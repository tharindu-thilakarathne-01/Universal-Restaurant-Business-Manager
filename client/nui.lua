-- ====================================================================
-- RESTAURANT MANAGER: CLIENT NUI CONTROLLER & CALLBACK ROUTER
-- Secure Bridge between NUI and Server Net Events / Callbacks
-- ====================================================================

local isUIOpen = false

-- Open Customer Menu (Counter Interaction)
function OpenCustomerMenu(restaurantId)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return end

    local menu = lib.callback.await('restaurant_manager:server:getMenuState', false, restaurantId) or {}
    local settings = lib.callback.await('restaurant_manager:server:getSettings', false, restaurantId) or { tax_rate = 10 }

    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openCustomer',
        restaurantId = restaurantId,
        restaurantLabel = resConfig.label,
        menu = menu,
        settings = settings
    })
end

local tabletProp = nil

local function PlayTabletAnimation()
    local ped = PlayerPedId()
    local animDict = 'amb@world_human_seat_wall_tablet@female@base'
    lib.requestAnimDict(animDict)
    TaskPlayAnim(ped, animDict, 'base', 3.0, 3.0, -1, 49, 0, false, false, false)

    local model = `prop_cs_tablet`
    lib.requestModel(model)
    if not tabletProp or not DoesEntityExist(tabletProp) then
        tabletProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
        AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 28422), -0.05, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
end

function StopTabletAnimation()
    local ped = PlayerPedId()
    StopAnimTask(ped, 'amb@world_human_seat_wall_tablet@female@base', 'base', 3.0)
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
        tabletProp = nil
    end
end

-- Open Customer Vending Machine UI (Vending Target Interaction)
function OpenVendingMenu(restaurantId)
    local resId = restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[resId]
    if not resConfig then return end

    local items = lib.callback.await('restaurant_manager:server:getVendingItems', false, resId) or {}
    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openVending',
        restaurantId = resId,
        restaurantLabel = resConfig.label,
        items = items
    })
end

-- Client-side pocket inventory reader (multi-source: ox_inventory GetPlayerItems, Search, Qbox/QBCore PlayerData.items)
local function readClientPocketInventory()
    local counts = {}
    local labels = {}
    local meta = { defsCount = 0, rawHits = 0, searchHits = 0, pdataHits = 0, rawErr = 'none' }

    local oxDefs = {}
    if exports.ox_inventory then
        if exports.ox_inventory.Items then
            local okDefs, defs = pcall(function() return exports.ox_inventory:Items() end)
            if okDefs and type(defs) == 'table' then
                oxDefs = defs
            elseif not okDefs then
                meta.rawErr = 'Items:' .. tostring(defs)
            end
        end
        if next(oxDefs) == nil and exports.ox_inventory.ItemList then
            local okList, listDefs = pcall(function() return exports.ox_inventory:ItemList() end)
            if okList and type(listDefs) == 'table' then oxDefs = listDefs end
        end
    end
    for _ in pairs(oxDefs) do meta.defsCount = meta.defsCount + 1 end

    local function findDef(name)
        if not name then return nil end
        return oxDefs[name] or oxDefs[string.lower(name)] or oxDefs[string.upper(name)]
    end

    local function addClientItem(name, qty, fallbackLabel)
        local n = tonumber(qty) or 0
        local lower = string.lower(tostring(name or ''))
        if lower == '' or lower == 'money' or lower == 'cash' or n <= 0 then return false end
        local def = findDef(name)
        local canonical = (def and def.name) or name
        counts[canonical] = (counts[canonical] or 0) + n
        labels[canonical] = (def and def.label) or fallbackLabel or labels[canonical] or canonical
        return true
    end

    -- 1. Try client ox_inventory:GetPlayerItems()
    if exports.ox_inventory and exports.ox_inventory.GetPlayerItems then
        local okRaw, rawItems = pcall(function() return exports.ox_inventory:GetPlayerItems() end)
        if not okRaw then
            meta.rawErr = 'GetPlayerItems:' .. tostring(rawItems)
        elseif type(rawItems) == 'table' then
            for _, slot in pairs(rawItems) do
                if type(slot) == 'table' and slot.name then
                    if addClientItem(slot.name, slot.count or slot.amount, slot.label) then
                        meta.rawHits = meta.rawHits + 1
                    end
                end
            end
        end
    end

    -- 2. Fallback: batched client ox_inventory:Search('count', batch)
    if next(counts) == nil and exports.ox_inventory and exports.ox_inventory.Search and next(oxDefs) ~= nil then
        local allNames = {}
        for itemName, _ in pairs(oxDefs) do
            if type(itemName) == 'string' then
                local lower = string.lower(itemName)
                if lower ~= '' and lower ~= 'money' and lower ~= 'cash' then
                    table.insert(allNames, itemName)
                end
            end
        end

        local chunkSize = 150
        for startIdx = 1, #allNames, chunkSize do
            local batch = {}
            for idx = startIdx, math.min(#allNames, startIdx + chunkSize - 1) do
                table.insert(batch, allNames[idx])
            end
            if #batch > 0 then
                local okSearch, res = pcall(function()
                    return exports.ox_inventory:Search('count', batch)
                end)
                if not okSearch then
                    meta.rawErr = 'Search:' .. tostring(res)
                elseif #batch == 1 and type(res) == 'number' then
                    if addClientItem(batch[1], res) then meta.searchHits = meta.searchHits + 1 end
                elseif type(res) == 'table' then
                    for itemName, qty in pairs(res) do
                        if addClientItem(itemName, qty) then meta.searchHits = meta.searchHits + 1 end
                    end
                end
            end
        end
    end

    -- 3. Fallback: Client Qbox/QBCore GetPlayerData().items
    if next(counts) == nil and GetPlayerData then
        local okPd, pd = pcall(GetPlayerData)
        if okPd and type(pd) == 'table' and type(pd.items) == 'table' then
            for _, slot in pairs(pd.items) do
                if type(slot) == 'table' and slot.name then
                    if addClientItem(slot.name, slot.count or slot.amount, slot.label) then
                        meta.pdataHits = meta.pdataHits + 1
                    end
                end
            end
        end
    end

    local list = {}
    for name, count in pairs(counts) do
        table.insert(list, {
            name = name,
            label = labels[name] or name,
            count = count
        })
    end
    table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return list, meta
end

local function mergeInventoryLists(primaryList, fallbackList)
    local byName = {}
    local merged = {}
    local function addList(srcList)
        if type(srcList) ~= 'table' then return end
        for _, entry in ipairs(srcList) do
            if type(entry) == 'table' and entry.name and (tonumber(entry.count) or 0) > 0 then
                local existing = byName[entry.name]
                if not existing then
                    local rec = {
                        name = entry.name,
                        label = entry.label or entry.name,
                        count = tonumber(entry.count) or 0
                    }
                    byName[entry.name] = rec
                    table.insert(merged, rec)
                elseif (tonumber(entry.count) or 0) > (tonumber(existing.count) or 0) then
                    existing.count = tonumber(entry.count) or existing.count
                end
            end
        end
    end
    addList(primaryList)
    addList(fallbackList)
    table.sort(merged, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return merged
end

-- Open Employee / Manager / Owner Management Terminal
function OpenManagementTerminal(restaurantId, preferredTab, preferredSubTab)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return end

    local permData = lib.callback.await('restaurant_manager:server:getPlayerPermissions', false, restaurantId)
    if not permData or not permData.isEmployee then
        lib.notify({
            title = 'Burgershot Terminal',
            description = 'Access Denied: Only authorized Burgershot personnel can access this terminal!',
            type = 'error'
        })
        return
    end

    if not permData.onduty and not permData.isAdmin and not permData.isOwner then
        lib.notify({
            title = 'Burgershot Tablet',
            description = 'Notice: Tablet opened while off-duty. Use [Duty Toggle] when handling customer orders.',
            type = 'info'
        })
    end

    if not permData.isAdmin and (type(permData.permissions) ~= 'table' or next(permData.permissions) == nil) then
        lib.notify({
            title = 'Restaurant Manager',
            description = 'No tablet permissions have been assigned to your role yet. Contact a Server Admin.',
            type = 'error'
        })
        return
    end

    local recipes = lib.callback.await('restaurant_manager:server:getRecipes', false, restaurantId) or {}
    local menu = lib.callback.await('restaurant_manager:server:getMenuState', false, restaurantId) or {}
    local stations = lib.callback.await('restaurant_manager:server:getStations', false, restaurantId) or {}
    local okDoors, doorsRes = pcall(lib.callback.await, 'restaurant_manager:server:getDoors', false, restaurantId)
    local doors = (okDoors and doorsRes) or {}
    local activeOrders = lib.callback.await('restaurant_manager:server:getActiveOrders', false, restaurantId) or {}
    local settings = lib.callback.await('restaurant_manager:server:getSettings', false, restaurantId) or { tax_rate = 10 }

    PlayTabletAnimation()
    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openManagement',
        restaurantId = restaurantId,
        restaurantLabel = resConfig.label,
        playerData = permData,
        recipes = recipes,
        menu = menu,
        stations = stations,
        doors = doors,
        activeOrders = activeOrders,
        settings = settings,
        stationTypes = Config.StationTypes,
        allPermissions = Config.AllPermissions,
        preferredTab = preferredTab,
        preferredSubTab = preferredSubTab
    })
end

-- ====================================================================
-- NUI CALLBACKS (From Web UI)
-- ====================================================================

-- Close UI
RegisterNUICallback('closeUI', function(data, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    StopTabletAnimation()
    cb('ok')
end)

-- Place Customer Order
RegisterNUICallback('placeOrder', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:placeOrder', data)
    cb('ok')
end)

-- Update Order Status (Employee Flow)
RegisterNUICallback('updateOrderStatus', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:updateOrderStatus', data)
    cb('ok')
end)

-- Cancel & Refund Order (Manager Flow)
RegisterNUICallback('cancelOrder', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:cancelOrder', data)
    cb('ok')
end)

-- Get Active Orders (Live Orders Tab Refresh)
RegisterNUICallback('getActiveOrders', function(data, cb)
    local activeOrders = lib.callback.await('restaurant_manager:server:getActiveOrders', false, data and data.restaurantId or 'burgershot') or {}
    cb(activeOrders)
end)

-- Get Order History (Manager Tab)
RegisterNUICallback('getOrderHistory', function(data, cb)
    local history = lib.callback.await('restaurant_manager:server:getOrderHistory', false, data.restaurantId) or {}
    cb(history)
end)

-- Get Online Staff List (Manager Tab)
RegisterNUICallback('getStaffList', function(data, cb)
    local staff = lib.callback.await('restaurant_manager:server:getStaffList', false, data.restaurantId) or {}
    cb(staff)
end)

-- Promote / Hire Staff by Server ID
RegisterNUICallback('promoteStaff', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:promoteStaff', false, data)
    if res and res.message then
        lib.notify({
            title = 'Burgershot Staff',
            description = res.message,
            type = res.ok and 'success' or 'error'
        })
    end
    cb(res or { ok = false, message = 'Failed to connect to server.' })
end)

-- Fire / Dismiss Staff by Server ID or Citizen ID
RegisterNUICallback('fireStaff', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:fireStaff', false, data)
    if res and res.message then
        lib.notify({
            title = 'Burgershot Staff',
            description = res.message,
            type = res.ok and 'success' or 'error'
        })
    end
    cb(res or { ok = false, message = 'Failed to connect to server.' })
end)

-- Give Burgershot Tablet to Player by Server ID
RegisterNUICallback('giveTablet', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:giveTablet', false, data)
    if res and res.message then
        lib.notify({
            title = 'Burgershot Tablet',
            description = res.message,
            type = res.ok and 'success' or 'error'
        })
    end
    cb(res or { ok = false, message = 'Failed to connect to server.' })
end)

-- Get Online Players List for Tablet Provisioning (Owner Tab)
RegisterNUICallback('getOnlinePlayers', function(data, cb)
    local players = lib.callback.await('restaurant_manager:server:getOnlinePlayersList', false, data.restaurantId) or {}
    cb(players)
end)

-- Update Menu Item Stock (Manager Tab)
RegisterNUICallback('updateStock', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:updateStock', data)
    cb('ok')
end)

-- Update Menu Item Price (Manager Tab)
RegisterNUICallback('updatePrice', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:updatePrice', data)
    cb('ok')
end)

-- Save Recipe (Owner Tab)
RegisterNUICallback('saveRecipe', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('restaurant_manager:server:saveRecipe', false, data)
    end)
    cb((ok and type(res) == 'table') and res or { ok = false, message = 'Failed to save recipe on server.' })
end)

RegisterNetEvent('restaurant_manager:client:syncRecipes', function(restaurantId, recipes)
    SendNUIMessage({
        action = 'syncRecipes',
        restaurantId = restaurantId,
        recipes = recipes or {}
    })
end)

-- Delete Recipe (Owner Tab)
RegisterNUICallback('deleteRecipe', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:deleteRecipe', data)
    cb('ok')
end)

-- Get Valid ox_inventory Items for Recipe Editor
RegisterNUICallback('getOxItems', function(data, cb)
    local items = lib.callback.await('restaurant_manager:server:getOxInventoryItems', false) or {}
    cb(items)
end)

-- Get Roles & Permissions (Owner Tab)
RegisterNUICallback('getRoles', function(data, cb)
    local roles = lib.callback.await('restaurant_manager:server:getRoles', false, data.restaurantId) or {}
    cb(roles)
end)

-- Create / Update Role Permissions (Owner Tab)
RegisterNUICallback('saveRole', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:saveRoleData', false, data)
    cb(res or { ok = false })
end)

-- Delete Custom / Unused Role (Owner Tab)
RegisterNUICallback('deleteRole', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:deleteRole', false, data)
    cb(res or { ok = false })
end)

-- Get Audit Logs (Owner Tab)
RegisterNUICallback('getLogs', function(data, cb)
    local logs = lib.callback.await('restaurant_manager:server:getLogs', false, data.restaurantId) or {}
    cb(logs)
end)

-- Delete Station (Owner Tab)
RegisterNUICallback('deleteStation', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:deleteStation', data)
    cb('ok')
end)

-- Delete All Stations & Zones (Owner Tab)
RegisterNUICallback('deleteAllStations', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:deleteAllStations', data.restaurantId)
    cb('ok')
end)

-- Start Station Placement Mode (Owner Tab)
RegisterNUICallback('startPlacementMode', function(data, cb)
    -- Close NUI before entering 3D placement mode
    isUIOpen = false
    SetNuiFocus(false, false)
    StopTabletAnimation()
    SendNUIMessage({ action = 'close' })

    TriggerEvent('restaurant_manager:client:startPlacement', data.restaurantId, data.stationType)
    cb('ok')
end)

-- Start Door Lock Picker Mode (Owner Tab)
RegisterNUICallback('startDoorPlacementMode', function(data, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    StopTabletAnimation()
    SendNUIMessage({ action = 'close' })

    TriggerEvent('restaurant_manager:client:startDoorPlacement', data and data.restaurantId or 'burgershot', data and data.label or '')
    cb('ok')
end)

-- Toggle Door Lock State from Tablet (Owner Tab)
RegisterNUICallback('toggleDoorLock', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('restaurant_manager:server:toggleDoor', false, data)
    end)
    cb((ok and type(res) == 'table') and res or { ok = false })
end)

-- Toggle Door Auto Lock (5s) from Tablet (Owner Tab)
RegisterNUICallback('toggleDoorAutoLock', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('restaurant_manager:server:toggleDoorAutoLock', false, data)
    end)
    cb((ok and type(res) == 'table') and res or { ok = false })
end)

-- Delete Door Lock (Owner Tab)
RegisterNUICallback('deleteDoor', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:deleteDoor', data)
    cb('ok')
end)

-- Delete All Door Locks (Owner Tab)
RegisterNUICallback('deleteAllDoors', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:deleteAllDoors', data and data.restaurantId or 'burgershot')
    cb('ok')
end)

-- Save Tax Rate (Owner Tab)
RegisterNUICallback('saveTaxRate', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:saveTaxRate', data)
    cb('ok')
end)

-- Save Staff Order Salary Commission & Paycheck Schedule (Owner Tab)
RegisterNUICallback('saveSalarySettings', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:saveSalarySettings', data)
    cb('ok')
end)

-- Save Role Base Salaries (Owner Tab)
RegisterNUICallback('saveRoleSalaries', function(data, cb)
    TriggerServerEvent('restaurant_manager:server:saveRoleSalaries', data)
    cb('ok')
end)

-- Trigger Immediate Role Salary Payout (Owner Tab)
RegisterNUICallback('triggerSalaryPayout', function(data, cb)
    local res = lib.callback.await('restaurant_manager:server:triggerSalaryPayout', false, data and data.restaurantId or 'burgershot')
    cb(res or { ok = false })
end)

-- Vending Machine NUI Callbacks
RegisterNUICallback('getVendingData', function(data, cb)
    local resId = (data and data.restaurantId) or 'burgershot'
    local items = {}
    local inventory = {}

    local okItems, fetchedItems = pcall(function()
        return lib.callback.await('restaurant_manager:server:getVendingItems', false, resId)
    end)
    if okItems and type(fetchedItems) == 'table' then
        items = fetchedItems
    end

    if data and data.includeInventory then
        local srvInv = {}
        local okSrv, fetchedSrv = pcall(function()
            return lib.callback.await('restaurant_manager:server:getPlayerInventoryForVending', false, resId)
        end)
        if okSrv and type(fetchedSrv) == 'table' then
            srvInv = fetchedSrv
        end

        local cliInv, cliMeta = {}, nil
        local okCli, fetchedCli, fetchedMeta = pcall(readClientPocketInventory)
        if okCli and type(fetchedCli) == 'table' then
            cliInv = fetchedCli
            cliMeta = fetchedMeta
        elseif not okCli then
            cliMeta = { defsCount = -1, pdataHits = -1, searchHits = -1, rawErr = 'cliCrash:' .. tostring(fetchedCli) }
        end

        inventory = mergeInventoryLists(srvInv, cliInv)
        local sample = inventory[1] and (tostring(inventory[1].name) .. 'x' .. tostring(inventory[1].count)) or 'none'
        pcall(function()
            TriggerServerEvent('restaurant_manager:server:vendingDiag', {
                resId = resId,
                srvCount = type(srvInv) == 'table' and #srvInv or -1,
                cliCount = type(cliInv) == 'table' and #cliInv or -1,
                finalCount = #inventory,
                defsCount = cliMeta and cliMeta.defsCount or -1,
                pdataHits = cliMeta and cliMeta.pdataHits or -1,
                searchHits = cliMeta and cliMeta.searchHits or -1,
                rawErr = cliMeta and cliMeta.rawErr or (not okSrv and ('srvErr:' .. tostring(fetchedSrv)) or 'none'),
                sample = sample
            })
        end)
    end

    cb({ items = items, inventory = inventory })
end)

local function safeVendingCallback(eventName, payload)
    local ok, res = pcall(function()
        return lib.callback.await(eventName, false, payload)
    end)
    if ok and type(res) == 'table' then
        return res
    end
    return { ok = false, message = 'Action failed cleanly. Please try again.' }
end

RegisterNUICallback('upsertVendingItem', function(data, cb)
    cb(safeVendingCallback('restaurant_manager:server:upsertVendingItem', data))
end)

RegisterNUICallback('withdrawVendingItem', function(data, cb)
    cb(safeVendingCallback('restaurant_manager:server:withdrawVendingItem', data))
end)

RegisterNUICallback('buyVendingItem', function(data, cb)
    cb(safeVendingCallback('restaurant_manager:server:buyVendingItem', data))
end)

RegisterNUICallback('buyVendingCart', function(data, cb)
    cb(safeVendingCallback('restaurant_manager:server:buyVendingCart', data))
end)

RegisterNUICallback('getVendingFund', function(data, cb)
    local resId = (data and data.restaurantId) or 'burgershot'
    cb(safeVendingCallback('restaurant_manager:server:getVendingFund', resId))
end)

RegisterNUICallback('withdrawVendingFund', function(data, cb)
    cb(safeVendingCallback('restaurant_manager:server:withdrawVendingFund', data))
end)

RegisterNetEvent('restaurant_manager:client:syncVending', function(restaurantId, items)
    SendNUIMessage({
        action = 'syncVending',
        restaurantId = restaurantId,
        items = items or {}
    })
end)

RegisterNetEvent('restaurant_manager:client:syncVendingFund', function(restaurantId, balance)
    SendNUIMessage({
        action = 'syncVendingFund',
        restaurantId = restaurantId,
        balance = tonumber(balance) or 0
    })
end)

-- Start Cooking Batch (Station Cooking UI)
RegisterNUICallback('startCooking', function(data, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    StopTabletAnimation()
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('restaurant_manager:server:startCooking', {
        restaurantId = data.restaurantId,
        stationId = data.stationId,
        recipeId = data.recipeId,
        amount = tonumber(data.amount) or 1
    })
    cb('ok')
end)

-- ====================================================================
-- TABLET EXPORTS & NET EVENTS
-- ====================================================================
exports('openTablet', function(data, slot)
    OpenManagementTerminal('burgershot', nil)
end)

exports('burgershot_tablet', function(data, slot)
    OpenManagementTerminal('burgershot', nil)
end)

RegisterNetEvent('burgershot:client:useTablet', function()
    OpenManagementTerminal('burgershot', nil)
end)

exports('openOwnerTablet', function(data, slot)
    OpenManagementTerminal('burgershot', 'owner-tab')
end)

exports('openManagerTablet', function(data, slot)
    OpenManagementTerminal('burgershot', 'manager-tab')
end)

exports('openEmployeeTablet', function(data, slot)
    OpenManagementTerminal('burgershot', 'employee-tab')
end)

RegisterNetEvent('restaurant_manager:client:openTablet', function(restaurantId, tab)
    OpenManagementTerminal(restaurantId or 'burgershot', tab)
end)

-- ====================================================================
-- CONVENIENCE COMMANDS
-- ====================================================================
RegisterCommand('bsmenu', function()
    OpenManagementTerminal('burgershot')
end, false)

RegisterCommand('burgershot', function()
    OpenManagementTerminal('burgershot')
end, false)

RegisterCommand('bstablet', function()
    OpenManagementTerminal('burgershot')
end, false)

RegisterCommand('bsduty', function()
    TriggerServerEvent('restaurant_manager:server:toggleDuty', 'burgershot')
end, false)

-- Cleanup on resource stop/restart
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if isUIOpen then
            isUIOpen = false
            SetNuiFocus(false, false)
            StopTabletAnimation()
        end
    end
end)


