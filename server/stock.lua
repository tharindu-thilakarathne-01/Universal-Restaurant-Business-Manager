-- ====================================================================
-- RESTAURANT MANAGER: SERVER STOCK & MENU MANAGEMENT
-- In-Stock / Out-of-Stock toggles, Stock count limits, and Price controls
-- ====================================================================

-- Callback to Get Current Menu & Stock State
-- Callback to Get Current Menu & Stock State
lib.callback.register('restaurant_manager:server:getMenuState', function(source, restaurantId)
    -- If cache not yet loaded or empty for this restaurant, load directly from DB
    if not ServerCache.MenuState[restaurantId] or next(ServerCache.MenuState[restaurantId]) == nil then
        ServerCache.MenuState[restaurantId] = ServerCache.MenuState[restaurantId] or {}
        local dbMenu = MySQL.query.await('SELECT * FROM `rm_menu_state` WHERE `restaurant_id` = ?', { restaurantId })
        if dbMenu then
            for _, m in ipairs(dbMenu) do
                ServerCache.MenuState[restaurantId][m.item_name] = {
                    item_name = m.item_name,
                    label = m.label,
                    price = m.price,
                    in_stock = (m.in_stock == 1 or m.in_stock == true),
                    stock_count = tonumber(m.stock_count) or -1,
                    category = m.category
                }
            end
        end
    end

    local menu = ServerCache.MenuState[restaurantId] or {}
    local menuList = {}
    for itemName, data in pairs(menu) do
        local isInStock = (data.in_stock == true or data.in_stock == 1)
        table.insert(menuList, {
            item = itemName,
            item_name = itemName,
            label = data.label or itemName,
            price = data.price or 0,
            in_stock = isInStock,
            stock_count = tonumber(data.stock_count) or -1,
            category = data.category or 'food'
        })
    end
    table.sort(menuList, function(a, b) return a.label < b.label end)
    return menuList
end)

-- ====================================================================
-- UPDATE STOCK AVAILABILITY (Manager / Owner)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:updateStock', function(payload)
    local src = source
    if not CheckRateLimit(src, 'updateStock', 500) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local itemName = payload.item_name or payload.item
    local inStock = (payload.in_stock == true or payload.in_stock == 1 or payload.in_stock == 'true')
    local stockCount = tonumber(payload.stock_count)
    if not stockCount then stockCount = -1 end

    -- Auto out-of-stock if stock count is set to 0
    if stockCount == 0 then
        inStock = false
    end

    -- 1. Validate Permission
    if not HasPermission(src, restaurantId, 'manage_stock') and not IsRestaurantManager(src, restaurantId) then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    ServerCache.MenuState[restaurantId] = ServerCache.MenuState[restaurantId] or {}
    local menu = ServerCache.MenuState[restaurantId]
    if not menu[itemName] then
        local dbItem = MySQL.single.await('SELECT * FROM `rm_menu_state` WHERE `restaurant_id` = ? AND `item_name` = ?', { restaurantId, itemName })
        if dbItem then
            menu[itemName] = {
                item_name = dbItem.item_name,
                label = dbItem.label,
                price = dbItem.price,
                in_stock = (dbItem.in_stock == 1 or dbItem.in_stock == true),
                stock_count = tonumber(dbItem.stock_count) or -1,
                category = dbItem.category
            }
        else
            Notify(src, 'error', _L('invalid_data'))
            return
        end
    end

    local oldState = {
        in_stock = menu[itemName].in_stock,
        stock_count = menu[itemName].stock_count
    }

    -- 2. Update Cache
    menu[itemName].in_stock = inStock
    menu[itemName].stock_count = stockCount

    -- 3. Update Database
    MySQL.update([[
        UPDATE `rm_menu_state` 
        SET `in_stock` = ?, `stock_count` = ? 
        WHERE `restaurant_id` = ? AND `item_name` = ?
    ]], { inStock and 1 or 0, stockCount, restaurantId, itemName })

    -- 4. Broadcast Menu Update to All Clients
    TriggerClientEvent('restaurant_manager:client:syncMenuState', -1, restaurantId, itemName, {
        in_stock = inStock,
        stock_count = stockCount
    })

    -- 5. Audit Log
    LogAction(restaurantId, src, 'STOCK_UPDATE', {
        item = itemName,
        old_state = oldState,
        new_state = { in_stock = inStock, stock_count = stockCount }
    })

    Notify(src, 'success', _L('stock_updated', menu[itemName].label or itemName))
end)

-- ====================================================================
-- UPDATE MENU PRICE (Manager / Owner)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:updatePrice', function(payload)
    local src = source
    if not CheckRateLimit(src, 'updatePrice', 500) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local itemName = payload.item_name or payload.item
    local newPrice = math.max(1, math.min(5000, tonumber(payload.price) or 10))

    -- 1. Validate Permission
    if not HasPermission(src, restaurantId, 'manage_menu') and not IsRestaurantManager(src, restaurantId) then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    ServerCache.MenuState[restaurantId] = ServerCache.MenuState[restaurantId] or {}
    local menu = ServerCache.MenuState[restaurantId]
    if not menu[itemName] then
        local dbItem = MySQL.single.await('SELECT * FROM `rm_menu_state` WHERE `restaurant_id` = ? AND `item_name` = ?', { restaurantId, itemName })
        if dbItem then
            menu[itemName] = {
                item_name = dbItem.item_name,
                label = dbItem.label,
                price = dbItem.price,
                in_stock = (dbItem.in_stock == 1 or dbItem.in_stock == true),
                stock_count = tonumber(dbItem.stock_count) or -1,
                category = dbItem.category
            }
        else
            Notify(src, 'error', _L('invalid_data'))
            return
        end
    end

    local oldPrice = menu[itemName].price

    -- 2. Update Cache
    menu[itemName].price = newPrice

    -- 3. Update Database
    MySQL.update([[
        UPDATE `rm_menu_state` 
        SET `price` = ? 
        WHERE `restaurant_id` = ? AND `item_name` = ?
    ]], { newPrice, restaurantId, itemName })

    -- 4. Broadcast Price Update
    TriggerClientEvent('restaurant_manager:client:syncPrice', -1, restaurantId, itemName, newPrice)

    -- 5. Audit Log
    LogAction(restaurantId, src, 'PRICE_UPDATE', {
        item = itemName,
        old_price = oldPrice,
        new_price = newPrice
    })

    Notify(src, 'success', string.format('Price for %s updated to $%d.', menu[itemName].label or itemName, newPrice))
end)
