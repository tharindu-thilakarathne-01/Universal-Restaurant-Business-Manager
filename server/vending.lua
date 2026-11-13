-- ====================================================================
-- RESTAURANT MANAGER: VENDING MACHINE ENGINE
-- Inventory-Backed Staff Restocking, Price Controls & Customer Sales
-- ====================================================================

local function buildSortedVendingList(restaurantId)
    ServerCache.Vending[restaurantId] = ServerCache.Vending[restaurantId] or {}
    if next(ServerCache.Vending[restaurantId]) == nil then
        local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM `rm_vending_items` WHERE `restaurant_id` = ?', { restaurantId })
        if ok and rows then
            for _, v in ipairs(rows) do
                ServerCache.Vending[restaurantId][v.item_name] = {
                    item_name = v.item_name,
                    label = v.label or v.item_name,
                    price = tonumber(v.price) or 15,
                    stock = tonumber(v.stock) or 0
                }
            end
        end
    end

    local list = {}
    for _, item in pairs(ServerCache.Vending[restaurantId]) do
        table.insert(list, {
            item_name = item.item_name,
            label = item.label or item.item_name,
            price = tonumber(item.price) or 15,
            stock = tonumber(item.stock) or 0
        })
    end
    table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return list
end

local function isNearAnyVendingStation(src, restaurantId)
    if HasRestaurantAdminAccess and HasRestaurantAdminAccess(src, restaurantId) then
        return true
    end
    local stations = ServerCache.Stations[restaurantId] or {}
    local foundVending = false
    for _, st in pairs(stations) do
        if st.station_type == 'vending' and st.coords then
            foundVending = true
            if ValidatePlayerDistance(src, st.coords, 6.0) then
                return true
            end
        end
    end
    return not foundVending
end

-- Fetch vending machine catalog (accessible by customers & staff)
lib.callback.register('restaurant_manager:server:getVendingItems', function(source, restaurantId)
    local resId = restaurantId or 'burgershot'
    if not Config.Restaurants[resId] then return {} end
    return buildSortedVendingList(resId)
end)

-- Safe ox_inventory item definitions loader (Items + ItemList fallback)
local function getOxItemDefinitions()
    local defs = {}
    if not exports.ox_inventory then return defs end
    if exports.ox_inventory.Items then
        local ok, items = pcall(function() return exports.ox_inventory:Items() end)
        if ok and type(items) == 'table' and next(items) ~= nil then
            defs = items
        end
    end
    if next(defs) == nil and exports.ox_inventory.ItemList then
        local ok, items = pcall(function() return exports.ox_inventory:ItemList() end)
        if ok and type(items) == 'table' and next(items) ~= nil then
            defs = items
        end
    end
    return defs
end

-- Fetch caller's pocket items available to deposit into the vending machine
lib.callback.register('restaurant_manager:server:getPlayerInventoryForVending', function(source, restaurantId)
    local src = tonumber(source) or source
    local resId = restaurantId or 'burgershot'
    local hasPerm = HasPermission(src, resId, 'vending_manage')
    if not hasPerm then
        print(('[BurgerShot][Vending] Permission denied for inventory fetch | src=%s resId=%s'):format(tostring(src), tostring(resId)))
        return {}
    end

    local counts = {}
    local labels = {}
    local oxDefs = getOxItemDefinitions()
    local defCount = 0
    for _ in pairs(oxDefs) do
        defCount = defCount + 1
    end

    local function findDef(name)
        if not name then return nil end
        return oxDefs[name] or oxDefs[string.lower(name)] or oxDefs[string.upper(name)]
    end

    local function isExcludedAccount(name)
        local lower = string.lower(tostring(name or ''))
        return lower == '' or lower == 'money' or lower == 'cash'
    end

    local function addItemCount(name, qty, fallbackLabel)
        local n = tonumber(qty) or 0
        if not name or isExcludedAccount(name) or n <= 0 then return false end
        local def = findDef(name)
        local canonical = (def and def.name) or name
        counts[canonical] = (counts[canonical] or 0) + n
        labels[canonical] = (def and def.label) or fallbackLabel or labels[canonical] or canonical
        return true
    end

    local function collectSlot(slot)
        if type(slot) == 'table' and slot.name then
            return addItemCount(slot.name, slot.count, slot.label)
        end
        return false
    end

    local slotHits, searchHits, pdataHits, rawHits = 0, 0, 0, 0
    local firstErr = nil

    -- 1. Primary: Per-slot GetSlot (normal slots 1..60 + utility slots 101..110; plain table, no sparse truncation)
    if exports.ox_inventory and exports.ox_inventory.GetSlot then
        local function scanSlot(slotIdx)
            local okSlot, slot = pcall(function() return exports.ox_inventory:GetSlot(src, slotIdx) end)
            if not okSlot and not firstErr then
                firstErr = 'GetSlot:' .. tostring(slot)
            elseif okSlot and slot and collectSlot(slot) then
                slotHits = slotHits + 1
            end
        end
        for slotIdx = 1, 60 do
            scanSlot(slotIdx)
        end
        for slotIdx = 101, 110 do
            scanSlot(slotIdx)
        end
    end

    -- 2. Fallback: Query ox_inventory:Search('count', batch) (covers custom slot numbers > 60)
    if next(counts) == nil and exports.ox_inventory and exports.ox_inventory.Search and next(oxDefs) ~= nil then
        local allNames = {}
        for itemName, _ in pairs(oxDefs) do
            if type(itemName) == 'string' and not isExcludedAccount(itemName) then
                table.insert(allNames, itemName)
            end
        end

        local chunkSize = 150
        for startIdx = 1, #allNames, chunkSize do
            local batch = {}
            for idx = startIdx, math.min(#allNames, startIdx + chunkSize - 1) do
                table.insert(batch, allNames[idx])
            end
            if #batch > 0 then
                local okSearch, result = pcall(function()
                    return exports.ox_inventory:Search(src, 'count', batch)
                end)
                if not okSearch then
                    if not firstErr then firstErr = 'Search:' .. tostring(result) end
                elseif #batch == 1 and type(result) == 'number' then
                    if addItemCount(batch[1], result) then searchHits = searchHits + 1 end
                elseif type(result) == 'table' then
                    for itemName, qty in pairs(result) do
                        if addItemCount(itemName, qty) then searchHits = searchHits + 1 end
                    end
                end
            end
        end
    end

    -- 3. Fallback: Qbox/QBCore PlayerData.items
    if next(counts) == nil then
        local ply = GetPlayer(src)
        if ply and ply.PlayerData and type(ply.PlayerData.items) == 'table' then
            for _, slot in pairs(ply.PlayerData.items) do
                if collectSlot(slot) then pdataHits = pdataHits + 1 end
            end
        end
    end

    -- 4. Fallback: ox_inventory:GetInventoryItems
    if next(counts) == nil and exports.ox_inventory and exports.ox_inventory.GetInventoryItems then
        local okRaw, inv = pcall(function() return exports.ox_inventory:GetInventoryItems(src) end)
        if not okRaw then
            if not firstErr then firstErr = 'GetInventoryItems:' .. tostring(inv) end
        elseif type(inv) == 'table' then
            for _, slot in pairs(inv) do
                if collectSlot(slot) then rawHits = rawHits + 1 end
            end
        end
    end

    local items = {}
    for name, count in pairs(counts) do
        table.insert(items, {
            name = name,
            label = labels[name] or name,
            count = count
        })
    end
    table.sort(items, function(a, b) return tostring(a.label) < tostring(b.label) end)

    local sample = items[1] and (tostring(items[1].name) .. 'x' .. tostring(items[1].count)) or 'none'
    print(('[BurgerShot][Vending] Server scan | src=%s resId=%s perm=%s defs=%d total=%d (slots=%d search=%d pdata=%d raw=%d) err=%s sample=%s'):format(
        tostring(src), tostring(resId), tostring(hasPerm), defCount, #items, slotHits, searchHits, pdataHits, rawHits, tostring(firstErr), sample
    ))

    return items
end)

RegisterNetEvent('restaurant_manager:server:vendingDiag', function(info)
    local src = source
    if type(info) ~= 'table' then return end
    if not CheckRateLimit(src, 'vendingDiag', 500) then return end
    print(('[BurgerShot][Vending] Client NUI bridge | src=%s resId=%s srv=%s cli=%s final=%s defs=%s pdata=%s search=%s rawErr=%s sample=%s'):format(
        tostring(src),
        tostring(info.resId),
        tostring(info.srvCount),
        tostring(info.cliCount),
        tostring(info.finalCount),
        tostring(info.defsCount),
        tostring(info.pdataHits),
        tostring(info.searchHits),
        tostring(info.rawErr),
        tostring(info.sample)
    ))
end)

local vendingTableReady = false
local function ensureVendingTable()
    if vendingTableReady then return true end
    if EnsureDatabaseSchema then
        pcall(EnsureDatabaseSchema)
    end
    local ok = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS `rm_vending_items` (
            `restaurant_id` VARCHAR(50) NOT NULL,
            `item_name` VARCHAR(60) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `price` INT NOT NULL DEFAULT 15,
            `stock` INT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`restaurant_id`, `item_name`),
            INDEX `idx_rm_vending_res` (`restaurant_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})
    if ok then
        vendingTableReady = true
    end
    return ok
end

-- Add stock or update sale price (requires vending_manage permission)
lib.callback.register('restaurant_manager:server:upsertVendingItem', function(source, payload)
    local src = tonumber(source) or source
    local okRun, resOrErr = pcall(function()
        if not CheckRateLimit(src, 'upsertVendingItem', 500) then
            return { ok = false, message = _L('rate_limited') }
        end

        if type(payload) ~= 'table' then
            return { ok = false, message = _L('invalid_data') }
        end

        local restaurantId = (type(payload.restaurantId) == 'string' and payload.restaurantId ~= '') and payload.restaurantId or 'burgershot'
        if not Config.Restaurants[restaurantId] then
            return { ok = false, message = _L('invalid_data') }
        end

        if not HasPermission(src, restaurantId, 'vending_manage') then
            Notify(src, 'error', _L('no_permission'))
            return { ok = false, message = _L('no_permission') }
        end

        ensureVendingTable()

        local rawItemName = tostring(payload.item_name or ''):gsub('^%s*(.-)%s*$', '%1')
        local addStock = math.max(0, math.min(500, math.floor(tonumber(payload.add_stock) or 0)))
        local price = math.max(1, math.min(50000, math.floor(tonumber(payload.price) or 15)))

        local oxDefs = getOxItemDefinitions()
        local itemDef = oxDefs[rawItemName] or oxDefs[string.lower(rawItemName)] or oxDefs[string.upper(rawItemName)]
        if not itemDef and exports.ox_inventory and exports.ox_inventory.Items then
            local okSingle, singleDef = pcall(function() return exports.ox_inventory:Items(rawItemName) end)
            if okSingle and type(singleDef) == 'table' then itemDef = singleDef end
            if not itemDef then
                local okLower, lowerDef = pcall(function() return exports.ox_inventory:Items(string.lower(rawItemName)) end)
                if okLower and type(lowerDef) == 'table' then itemDef = lowerDef end
            end
        end
        if not itemDef and rawItemName ~= '' and exports.ox_inventory and exports.ox_inventory.GetSlot then
            local rawLower = string.lower(rawItemName)
            local function findInSlots(fromSlot, toSlot)
                for slotIdx = fromSlot, toSlot do
                    local okSlot, slot = pcall(function() return exports.ox_inventory:GetSlot(src, slotIdx) end)
                    if okSlot and type(slot) == 'table' and slot.name and string.lower(tostring(slot.name)) == rawLower then
                        return { name = slot.name, label = slot.label or slot.name }
                    end
                end
                return nil
            end
            itemDef = findInSlots(1, 60) or findInSlots(101, 110)
        end

        local lowerName = string.lower(rawItemName)
        if rawItemName == '' or lowerName == 'money' or lowerName == 'cash' or not itemDef then
            local msg = 'Invalid item selected for vending machine.'
            Notify(src, 'error', msg)
            print(('[BurgerShot][Vending] upsertVendingItem invalid item | src=%s raw=%s'):format(tostring(src), tostring(rawItemName)))
            return { ok = false, message = msg }
        end
        local itemName = itemDef.name or rawItemName

        if addStock > 0 then
            local hasCount = 0
            if exports.ox_inventory and exports.ox_inventory.GetItemCount then
                local okCnt, cnt = pcall(function() return exports.ox_inventory:GetItemCount(src, itemName) end)
                if okCnt then hasCount = tonumber(cnt) or 0 end
            end
            if hasCount < addStock and exports.ox_inventory and exports.ox_inventory.Search then
                local okSch, sch = pcall(function() return exports.ox_inventory:Search(src, 'count', itemName) end)
                if okSch and type(sch) == 'number' and sch > hasCount then
                    hasCount = sch
                end
            end
            if hasCount < addStock then
                local msg = string.format('You only have %dx %s in your inventory.', hasCount, itemDef.label or itemName)
                Notify(src, 'error', msg)
                print(('[BurgerShot][Vending] upsertVendingItem insufficient | src=%s item=%s has=%s need=%s'):format(tostring(src), tostring(itemName), tostring(hasCount), tostring(addStock)))
                return { ok = false, message = msg }
            end
            local okCallRem, removed, remErr = pcall(function()
                return exports.ox_inventory:RemoveItem(src, itemName, addStock)
            end)
            if not okCallRem or not removed then
                local msg = 'Failed to remove item from your inventory.'
                Notify(src, 'error', msg)
                print(('[BurgerShot][Vending] upsertVendingItem remove failed | src=%s item=%s qty=%s err=%s'):format(tostring(src), tostring(itemName), tostring(addStock), tostring(remErr or removed)))
                return { ok = false, message = msg }
            end
        end

        local label = itemDef.label or itemName
        local okDb, dbErr = pcall(MySQL.query.await, [[
            INSERT INTO `rm_vending_items` (`restaurant_id`, `item_name`, `label`, `price`, `stock`)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `label` = VALUES(`label`),
                `price` = VALUES(`price`),
                `stock` = `stock` + VALUES(`stock`)
        ]], { restaurantId, itemName, label, price, addStock })

        if not okDb then
            if addStock > 0 and exports.ox_inventory and exports.ox_inventory.AddItem then
                pcall(function() exports.ox_inventory:AddItem(src, itemName, addStock) end)
            end
            local msg = 'Failed saving vending item to database.'
            Notify(src, 'error', msg)
            print(('[BurgerShot][Vending] upsertVendingItem DB error | src=%s item=%s err=%s'):format(tostring(src), tostring(itemName), tostring(dbErr)))
            return { ok = false, message = msg }
        end

        ServerCache.Vending[restaurantId] = ServerCache.Vending[restaurantId] or {}
        local existing = ServerCache.Vending[restaurantId][itemName]
        local newStock = (existing and (tonumber(existing.stock) or 0) or 0) + addStock
        ServerCache.Vending[restaurantId][itemName] = {
            item_name = itemName,
            label = label,
            price = price,
            stock = newStock
        }

        local list = buildSortedVendingList(restaurantId)
        TriggerClientEvent('restaurant_manager:client:syncVending', -1, restaurantId, list)

        LogAction(restaurantId, src, addStock > 0 and 'VENDING_RESTOCK' or 'VENDING_PRICE', {
            item = itemName,
            added = addStock,
            price = price,
            stock = newStock
        })

        local msg = addStock > 0
            and string.format('Stocked %dx %s at $%d each!', addStock, label, price)
            or string.format('Updated price for %s to $%d!', label, price)
        Notify(src, 'success', msg)
        print(('[BurgerShot][Vending] upsertVendingItem OK | src=%s item=%s added=%s price=%s stock=%s'):format(tostring(src), tostring(itemName), tostring(addStock), tostring(price), tostring(newStock)))
        return { ok = true, message = msg, items = list }
    end)

    if not okRun then
        print(('[BurgerShot][Vending] upsertVendingItem CRASH | src=%s err=%s'):format(tostring(src), tostring(resOrErr)))
        Notify(src, 'error', 'Failed to restock item.')
        return { ok = false, message = 'Failed to restock item.' }
    end
    return resOrErr
end)

-- Withdraw items back to pockets or remove vending item listing (requires vending_manage)
lib.callback.register('restaurant_manager:server:withdrawVendingItem', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'withdrawVendingItem', 500) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = payload.restaurantId or 'burgershot'
    if not Config.Restaurants[restaurantId] then
        return { ok = false, message = _L('invalid_data') }
    end

    if not HasPermission(src, restaurantId, 'vending_manage') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    local itemName = tostring(payload.item_name or '')
    local removeListing = payload.remove_listing == true
    ServerCache.Vending[restaurantId] = ServerCache.Vending[restaurantId] or {}
    local entry = ServerCache.Vending[restaurantId][itemName]
    if not entry then
        return { ok = false, message = 'Item not found in vending machine.' }
    end

    local currentStock = tonumber(entry.stock) or 0
    local qty = removeListing and currentStock or math.max(1, math.min(currentStock, math.floor(tonumber(payload.qty) or 1)))
    local isAdmin = HasRestaurantAdminAccess and HasRestaurantAdminAccess(src, restaurantId)
    local discardStock = (payload.discard_stock == true) and isAdmin

    if qty > 0 and not discardStock then
        if not exports.ox_inventory or not exports.ox_inventory:CanCarryItem(src, itemName, qty) then
            return { ok = false, message = _L('inventory_full') }
        end
    end

    local remaining = currentStock - qty
    if remaining < 0 then remaining = 0 end

    if removeListing then
        ServerCache.Vending[restaurantId][itemName] = nil
        MySQL.query.await('DELETE FROM `rm_vending_items` WHERE `restaurant_id` = ? AND `item_name` = ?', { restaurantId, itemName })
    else
        entry.stock = remaining
        MySQL.update.await('UPDATE `rm_vending_items` SET `stock` = ? WHERE `restaurant_id` = ? AND `item_name` = ?', { remaining, restaurantId, itemName })
    end

    if qty > 0 and not discardStock then
        if not exports.ox_inventory:AddItem(src, itemName, qty) then
            -- Restore DB & cache on unexpected AddItem failure
            ServerCache.Vending[restaurantId][itemName] = {
                item_name = itemName,
                label = entry.label,
                price = entry.price,
                stock = currentStock
            }
            pcall(MySQL.query.await, [[
                INSERT INTO `rm_vending_items` (`restaurant_id`, `item_name`, `label`, `price`, `stock`)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE `stock` = VALUES(`stock`)
            ]], { restaurantId, itemName, entry.label, entry.price, currentStock })
            return { ok = false, message = _L('inventory_full') }
        end
    end

    local list = buildSortedVendingList(restaurantId)
    TriggerClientEvent('restaurant_manager:client:syncVending', -1, restaurantId, list)

    LogAction(restaurantId, src, removeListing and 'VENDING_REMOVE' or 'VENDING_WITHDRAW', {
        item = itemName,
        qty = qty,
        discarded = discardStock
    })

    local msg = removeListing
        and string.format('Removed %s from vending machine.', entry.label or itemName)
        or string.format('Withdrew %dx %s from vending machine.', qty, entry.label or itemName)
    return { ok = true, message = msg, items = list }
end)

local function givePlayerMoney(src, accountType, amount, reason)
    local cleanAmount = math.max(0, math.floor(tonumber(amount) or 0))
    if cleanAmount <= 0 then return false end
    local acct = (accountType == 'cash') and 'cash' or 'bank'

    if exports['qbx_core'] and exports['qbx_core'].AddMoney then
        local ok, res = pcall(function() return exports['qbx_core']:AddMoney(src, acct, cleanAmount, reason or 'vending-payout') end)
        if ok and res ~= false then return true end
    end
    local ply = GetPlayer(src)
    if ply and ply.Functions and ply.Functions.AddMoney then
        local ok, res = pcall(function() return ply.Functions.AddMoney(acct, cleanAmount, reason or 'vending-payout') end)
        if ok and res ~= false then return true end
    end
    if acct == 'cash' and exports.ox_inventory and exports.ox_inventory.AddItem then
        local ok, res = pcall(function() return exports.ox_inventory:AddItem(src, 'money', cleanAmount) end)
        if ok and res then return true end
    end
    return false
end

local function refundPlayerMoney(src, paymentMethod, amount, reason)
    givePlayerMoney(src, paymentMethod, amount, reason or 'vending-refund')
end

local function getVendingFundBalance(restaurantId)
    local resId = (type(restaurantId) == 'string' and restaurantId ~= '') and restaurantId or 'burgershot'
    if ServerCache.VendingFunds and ServerCache.VendingFunds[resId] ~= nil then
        return math.max(0, math.floor(tonumber(ServerCache.VendingFunds[resId]) or 0))
    end

    local ok, rowBalance = pcall(MySQL.scalar.await, 'SELECT `balance` FROM `rm_vending_funds` WHERE `restaurant_id` = ?', { resId })
    local balance = ok and math.max(0, math.floor(tonumber(rowBalance) or 0)) or 0
    if ServerCache.VendingFunds then
        ServerCache.VendingFunds[resId] = balance
    end
    return balance
end

local function addVendingFund(restaurantId, amount)
    local resId = (type(restaurantId) == 'string' and restaurantId ~= '') and restaurantId or 'burgershot'
    local addAmount = math.max(0, math.floor(tonumber(amount) or 0))
    if addAmount <= 0 then
        return getVendingFundBalance(resId)
    end

    MySQL.insert.await(
        'INSERT INTO `rm_vending_funds` (`restaurant_id`, `balance`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `balance` = `balance` + VALUES(`balance`)',
        { resId, addAmount }
    )
    local rowBalance = MySQL.scalar.await('SELECT `balance` FROM `rm_vending_funds` WHERE `restaurant_id` = ?', { resId })
    local newBalance = math.max(0, math.floor(tonumber(rowBalance) or 0))
    if ServerCache.VendingFunds then
        ServerCache.VendingFunds[resId] = newBalance
    end
    TriggerClientEvent('restaurant_manager:client:syncVendingFund', -1, resId, newBalance)
    return newBalance
end

-- Customer purchases an item from a placed vending machine
lib.callback.register('restaurant_manager:server:buyVendingItem', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'buyVendingItem', 500) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = _L('invalid_data') }
    end

    if not isNearAnyVendingStation(src, restaurantId) then
        return { ok = false, message = _L('too_far_away') }
    end

    local itemName = tostring(payload.item_name or '')
    local qty = math.max(1, math.min(20, math.floor(tonumber(payload.qty) or 1)))
    local paymentMethod = (payload.paymentMethod == 'bank') and 'bank' or 'cash'

    ServerCache.Vending[restaurantId] = ServerCache.Vending[restaurantId] or {}
    local entry = ServerCache.Vending[restaurantId][itemName]
    if not entry or (tonumber(entry.stock) or 0) < qty then
        return { ok = false, message = 'Requested item is out of stock in the vending machine.' }
    end

    if not exports.ox_inventory or not exports.ox_inventory:CanCarryItem(src, itemName, qty) then
        return { ok = false, message = _L('inventory_full') }
    end

    local totalCost = math.max(1, math.floor(tonumber(entry.price) or 15)) * qty

    -- Reserve stock optimistically BEFORE payment/inventory awaits to prevent race-condition overselling
    entry.stock = (tonumber(entry.stock) or 0) - qty

    if not DebitPlayerMoney(src, paymentMethod, totalCost, 'vending-' .. restaurantId) then
        entry.stock = entry.stock + qty
        return { ok = false, message = _L('insufficient_funds', paymentMethod, totalCost) }
    end

    if not exports.ox_inventory:AddItem(src, itemName, qty) then
        entry.stock = entry.stock + qty
        refundPlayerMoney(src, paymentMethod, totalCost, 'vending-refund')
        return { ok = false, message = _L('inventory_full') }
    end

    MySQL.update.await(
        'UPDATE `rm_vending_items` SET `stock` = ? WHERE `restaurant_id` = ? AND `item_name` = ?',
        { entry.stock, restaurantId, itemName }
    )

    addVendingFund(restaurantId, totalCost)

    local list = buildSortedVendingList(restaurantId)
    TriggerClientEvent('restaurant_manager:client:syncVending', -1, restaurantId, list)

    LogAction(restaurantId, src, 'VENDING_PURCHASE', {
        item = itemName,
        qty = qty,
        total = totalCost,
        payment = paymentMethod
    })

    return {
        ok = true,
        message = string.format('Purchased %dx %s for $%d (%s)!', qty, entry.label or itemName, totalCost, paymentMethod:upper()),
        items = list
    }
end)

-- Customer purchases full cart from a placed vending machine
lib.callback.register('restaurant_manager:server:buyVendingCart', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'buyVendingCart', 500) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' or type(payload.items) ~= 'table' then
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = (type(payload.restaurantId) == 'string' and payload.restaurantId ~= '') and payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = _L('invalid_data') }
    end

    if not isNearAnyVendingStation(src, restaurantId) then
        return { ok = false, message = _L('too_far_away') }
    end

    if not exports.ox_inventory then
        return { ok = false, message = 'Inventory system unavailable.' }
    end

    local orderList = {}
    local byName = {}
    for _, req in ipairs(payload.items) do
        if type(req) == 'table' then
            local itemName = tostring(req.item_name or '')
            local qty = math.max(0, math.min(50, math.floor(tonumber(req.qty) or 0)))
            if itemName ~= '' and qty > 0 then
                if byName[itemName] then
                    byName[itemName].qty = math.min(50, byName[itemName].qty + qty)
                else
                    local entryReq = { item_name = itemName, qty = qty }
                    byName[itemName] = entryReq
                    table.insert(orderList, entryReq)
                    if #orderList >= 50 then break end
                end
            end
        end
    end

    if #orderList == 0 then
        return { ok = false, message = 'Your vending cart is empty.' }
    end

    local paymentMethod = (payload.paymentMethod == 'bank') and 'bank' or 'cash'
    ServerCache.Vending[restaurantId] = ServerCache.Vending[restaurantId] or {}

    local totalCost = 0
    local totalUnits = 0
    for _, req in ipairs(orderList) do
        local entry = ServerCache.Vending[restaurantId][req.item_name]
        if not entry or (tonumber(entry.stock) or 0) < req.qty then
            local label = (entry and entry.label) or req.item_name
            return { ok = false, message = string.format('Insufficient stock for %s.', label) }
        end
        if not exports.ox_inventory:CanCarryItem(src, req.item_name, req.qty) then
            return { ok = false, message = _L('inventory_full') }
        end
        local unitPrice = math.max(1, math.floor(tonumber(entry.price) or 15))
        req.label = entry.label or req.item_name
        req.lineTotal = unitPrice * req.qty
        totalCost = totalCost + req.lineTotal
        totalUnits = totalUnits + req.qty
    end

    -- Reserve all requested quantities optimistically before payment
    for _, req in ipairs(orderList) do
        local entry = ServerCache.Vending[restaurantId][req.item_name]
        entry.stock = (tonumber(entry.stock) or 0) - req.qty
    end

    local function rollbackStocks()
        for _, req in ipairs(orderList) do
            local entry = ServerCache.Vending[restaurantId][req.item_name]
            if entry then
                entry.stock = (tonumber(entry.stock) or 0) + req.qty
            end
        end
    end

    if not DebitPlayerMoney(src, paymentMethod, totalCost, 'vending-' .. restaurantId) then
        rollbackStocks()
        return { ok = false, message = _L('insufficient_funds', paymentMethod, totalCost) }
    end

    local given = {}
    for _, req in ipairs(orderList) do
        if not exports.ox_inventory:AddItem(src, req.item_name, req.qty) then
            for _, g in ipairs(given) do
                pcall(function() exports.ox_inventory:RemoveItem(src, g.item_name, g.qty) end)
            end
            refundPlayerMoney(src, paymentMethod, totalCost, 'vending-refund')
            rollbackStocks()
            return { ok = false, message = _L('inventory_full') }
        end
        table.insert(given, req)
    end

    local summary = {}
    for _, req in ipairs(orderList) do
        MySQL.update.await(
            'UPDATE `rm_vending_items` SET `stock` = GREATEST(0, `stock` - ?) WHERE `restaurant_id` = ? AND `item_name` = ?',
            { req.qty, restaurantId, req.item_name }
        )
        table.insert(summary, { item = req.item_name, qty = req.qty, total = req.lineTotal })
    end

    addVendingFund(restaurantId, totalCost)

    local list = buildSortedVendingList(restaurantId)
    TriggerClientEvent('restaurant_manager:client:syncVending', -1, restaurantId, list)

    LogAction(restaurantId, src, 'VENDING_PURCHASE', {
        cart = true,
        items = summary,
        total = totalCost,
        payment = paymentMethod
    })

    return {
        ok = true,
        message = string.format('Purchased %d item(s) for $%d (%s)!', totalUnits, totalCost, paymentMethod:upper()),
        items = list
    }
end)

-- Fetch accumulated vending machine fund balance
lib.callback.register('restaurant_manager:server:getVendingFund', function(source, restaurantId)
    local src = source
    local resId = (type(restaurantId) == 'string' and restaurantId ~= '') and restaurantId or 'burgershot'
    if not Config.Restaurants[resId] then
        return { ok = false, message = _L('invalid_data'), balance = 0 }
    end
    if not HasPermission(src, resId, 'vending_fund') then
        return { ok = false, message = _L('no_permission'), balance = 0 }
    end
    return {
        ok = true,
        balance = getVendingFundBalance(resId)
    }
end)

-- Withdraw accumulated vending machine revenue (requires vending_fund permission)
lib.callback.register('restaurant_manager:server:withdrawVendingFund', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'withdrawVendingFund', 500) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = (type(payload.restaurantId) == 'string' and payload.restaurantId ~= '') and payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = _L('invalid_data') }
    end

    if not HasPermission(src, restaurantId, 'vending_fund') then
        return { ok = false, message = _L('no_permission') }
    end

    local destination = 'cash'
    if payload.destination == 'bank' then
        destination = 'bank'
    elseif payload.destination == 'society' then
        destination = 'society'
    end

    local withdrawAll = payload.withdrawAll == true
    local currentRow = MySQL.scalar.await('SELECT `balance` FROM `rm_vending_funds` WHERE `restaurant_id` = ?', { restaurantId })
    local currentBalance = math.max(0, math.floor(tonumber(currentRow) or 0))
    if currentBalance <= 0 then
        if ServerCache.VendingFunds then ServerCache.VendingFunds[restaurantId] = 0 end
        return { ok = false, message = 'Vending fund balance is empty ($0).', balance = 0 }
    end

    local withdrawAmount = withdrawAll and currentBalance or math.floor(tonumber(payload.amount) or 0)
    if withdrawAmount <= 0 then
        return { ok = false, message = 'Enter a valid withdrawal amount greater than $0.', balance = currentBalance }
    end
    if withdrawAmount > currentBalance then
        return { ok = false, message = string.format('Requested amount ($%d) exceeds available vending fund ($%d).', withdrawAmount, currentBalance), balance = currentBalance }
    end

    -- Atomic conditional deduction prevents concurrent double-withdraw race conditions
    local affected = MySQL.update.await(
        'UPDATE `rm_vending_funds` SET `balance` = `balance` - ? WHERE `restaurant_id` = ? AND `balance` >= ?',
        { withdrawAmount, restaurantId, withdrawAmount }
    )
    if not affected or affected < 1 then
        local latest = getVendingFundBalance(restaurantId)
        return { ok = false, message = 'Fund balance changed. Please try again.', balance = latest }
    end

    local paid = false
    if destination == 'society' then
        if resConfig.societyAccount and resConfig.societyAccount ~= '' then
            DepositSocietyMoney(resConfig.societyAccount, withdrawAmount, 'Vending Machine Fund Transfer')
            paid = true
        end
    else
        paid = givePlayerMoney(src, destination, withdrawAmount, 'vending-fund-withdraw')
    end

    if not paid then
        -- Roll back deduction cleanly if payout failed
        MySQL.update.await(
            'UPDATE `rm_vending_funds` SET `balance` = `balance` + ? WHERE `restaurant_id` = ?',
            { withdrawAmount, restaurantId }
        )
        local restored = MySQL.scalar.await('SELECT `balance` FROM `rm_vending_funds` WHERE `restaurant_id` = ?', { restaurantId })
        local restoredBal = math.max(0, math.floor(tonumber(restored) or 0))
        if ServerCache.VendingFunds then ServerCache.VendingFunds[restaurantId] = restoredBal end
        return { ok = false, message = 'Failed to deliver withdrawn funds.', balance = restoredBal }
    end

    local afterRow = MySQL.scalar.await('SELECT `balance` FROM `rm_vending_funds` WHERE `restaurant_id` = ?', { restaurantId })
    local newBalance = math.max(0, math.floor(tonumber(afterRow) or 0))
    if ServerCache.VendingFunds then
        ServerCache.VendingFunds[restaurantId] = newBalance
    end
    TriggerClientEvent('restaurant_manager:client:syncVendingFund', -1, restaurantId, newBalance)

    LogAction(restaurantId, src, 'VENDING_FUND_WITHDRAW', {
        amount = withdrawAmount,
        destination = destination,
        remainingBalance = newBalance
    })

    local destLabel = (destination == 'society') and 'Company Account' or destination:upper()
    return {
        ok = true,
        amount = withdrawAmount,
        balance = newBalance,
        destination = destination,
        message = string.format('Withdrew $%d from Vending Fund to %s!', withdrawAmount, destLabel)
    }
end)

