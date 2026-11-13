-- ====================================================================
-- RESTAURANT MANAGER: SERVER ORDERS ENGINE
-- Flow: Pending > Accepted > Cooking > Ready > Delivered / Cancelled
-- ====================================================================

-- Count On-Duty Employees for Restaurant
local function GetOnDutyEmployeeCount(restaurantId)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return 0 end

    local count = 0
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ply = GetPlayer(src)
        if ply and ply.PlayerData and ply.PlayerData.job then
            if ply.PlayerData.job.name == resConfig.job and ply.PlayerData.job.onduty then
                count = count + 1
            end
        end
    end
    return count
end

-- Broadcast to All On-Duty Staff of a Restaurant
local function BroadcastToStaff(restaurantId, eventName, ...)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ply = GetPlayer(src)
        if ply and ply.PlayerData and ply.PlayerData.job then
            if ply.PlayerData.job.name == resConfig.job and (ply.PlayerData.job.onduty or IsRestaurantOwner(src, restaurantId)) then
                TriggerClientEvent(eventName, src, ...)
            end
        end
    end
end

-- ====================================================================
-- PLACE ORDER (Customer Interaction)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:placeOrder', function(payload)
    local src = source
    if not CheckRateLimit(src, 'placeOrder', 2000) then return end

    if type(payload) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local restaurantId = payload.restaurantId
    local rawCart = payload.cart
    local paymentMethod = payload.paymentMethod == 'bank' and 'bank' or 'cash'

    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        Notify(src, 'error', _L('restaurant_not_found'))
        return
    end

    -- 1. Distance Validation (Check placed counter stations and static config counters)
    local isNearCounter = false
    local placedStations = ServerCache.Stations[restaurantId] or {}
    local hasPlacedCounters = false
    for _, st in pairs(placedStations) do
        if st.station_type == 'counter' and st.coords then
            hasPlacedCounters = true
            if ValidatePlayerDistance(src, st.coords, 6.0) then
                isNearCounter = true
                break
            end
        end
    end

    if not hasPlacedCounters then
        if resConfig.orderingCounters and #resConfig.orderingCounters > 0 then
            for _, counter in ipairs(resConfig.orderingCounters) do
                if ValidatePlayerDistance(src, counter.coords, Config.MaxCounterDistance) then
                    isNearCounter = true
                    break
                end
            end
        else
            isNearCounter = true -- No static or dynamic counters defined, permit order
        end
    end

    if not isNearCounter then
        Notify(src, 'error', _L('too_far_away'))
        return
    end

    -- 2. Staff On-Duty Validation
    if Config.RequireOnDutyEmployeeToOrder then
        local onDutyCount = GetOnDutyEmployeeCount(restaurantId)
        if onDutyCount <= 0 then
            Notify(src, 'error', _L('no_staff_on_duty'))
            return
        end
    end

    -- 3. Cart & Stock Validation & Price Recalculation (Zero Client Trust!)
    if type(rawCart) ~= 'table' or #rawCart == 0 then
        Notify(src, 'error', _L('cart_empty'))
        return
    end

    local menuState = ServerCache.MenuState[restaurantId] or {}
    local validatedItems = {}
    local calculatedSubtotal = 0
    local stockDeductions = {}

    for _, cartItem in ipairs(rawCart) do
        local itemName = cartItem.item
        local count = math.floor(tonumber(cartItem.count) or 0)

        if count > 0 then
            local menuItem = menuState[itemName]
            if not menuItem then
                Notify(src, 'error', _L('invalid_data'))
                return
            end

            -- Check In-Stock status
            if not menuItem.in_stock then
                Notify(src, 'error', _L('item_out_of_stock', menuItem.label or itemName))
                return
            end

            -- Check Stock Count if tracked
            if menuItem.stock_count and menuItem.stock_count ~= -1 then
                if menuItem.stock_count < count then
                    Notify(src, 'error', _L('item_out_of_stock', menuItem.label or itemName))
                    return
                end
                stockDeductions[itemName] = (stockDeductions[itemName] or 0) + count
            end

            local itemPrice = tonumber(menuItem.price) or 0
            local lineTotal = itemPrice * count
            calculatedSubtotal = calculatedSubtotal + lineTotal

            table.insert(validatedItems, {
                item = itemName,
                label = menuItem.label or itemName,
                count = count,
                price = itemPrice,
                subtotal = lineTotal
            })
        end
    end

    if #validatedItems == 0 or calculatedSubtotal <= 0 then
        Notify(src, 'error', _L('cart_empty'))
        return
    end

    -- 3. Calculate Tax & Final Total
    local taxRate = GetRestaurantTaxRate(restaurantId)
    local taxAmount = math.floor((calculatedSubtotal * taxRate / 100) + 0.5)
    local calculatedTotal = calculatedSubtotal + taxAmount

    -- 4. Payment Deduction & 5. Deposit into Society Account
    if not DebitPlayerMoney(src, paymentMethod, calculatedTotal, 'restaurant-order-' .. restaurantId) then
        Notify(src, 'error', _L('insufficient_funds', paymentMethod, calculatedTotal))
        return
    end

    DepositSocietyMoney(resConfig.societyAccount, calculatedTotal, 'Customer Food Order')

    -- 6. Apply Stock Deductions in Cache and DB
    for itemName, deductedQty in pairs(stockDeductions) do
        local menuItem = menuState[itemName]
        if menuItem and menuItem.stock_count and menuItem.stock_count ~= -1 then
            menuItem.stock_count = math.max(0, menuItem.stock_count - deductedQty)
            if menuItem.stock_count == 0 then
                menuItem.in_stock = false
            end
            MySQL.update('UPDATE `rm_menu_state` SET `stock_count` = ?, `in_stock` = ? WHERE `restaurant_id` = ? AND `item_name` = ?',
                { menuItem.stock_count, menuItem.in_stock and 1 or 0, restaurantId, itemName })
        end
    end

    -- 7. Insert Order into Database
    if EnsureDatabaseSchema then
        EnsureDatabaseSchema()
    end

    local citizenId = GetPlayerCitizenId(src) or 'UNKNOWN'
    local customerName = GetPlayerFullName(src)
    local itemsJson = json.encode(validatedItems)

    local okOrder, orderId = pcall(MySQL.insert.await, [[
        INSERT INTO `rm_orders` 
        (`restaurant_id`, `customer_identifier`, `customer_name`, `items`, `total_price`, `tax_amount`, `payment_method`, `status`) 
        VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
    ]], { restaurantId, citizenId, customerName, itemsJson, calculatedTotal, taxAmount, paymentMethod })

    if not okOrder or not orderId then
        print(string.format('^1[BurgerShot] Failed inserting order for %s: %s^0', tostring(citizenId), tostring(orderId)))
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    -- 8. Add to In-Memory Cache
    local orderData = {
        id = orderId,
        restaurant_id = restaurantId,
        customer_identifier = citizenId,
        customer_source = src,
        customer_name = customerName,
        items = validatedItems,
        subtotal = calculatedSubtotal,
        tax_rate = taxRate,
        tax_amount = taxAmount,
        total_price = calculatedTotal,
        payment_method = paymentMethod,
        status = 'pending',
        claimed_by = nil,
        claimed_name = nil,
        created_at = os.date('%Y-%m-%d %H:%M:%S')
    }

    ServerCache.ActiveOrders[restaurantId] = ServerCache.ActiveOrders[restaurantId] or {}
    ServerCache.ActiveOrders[restaurantId][orderId] = orderData

    -- 9. Notify Customer & Broadcast to Employees
    print(string.format('^2[BurgerShot] Order #%d ($%d) placed by %s (%s)^0', orderId, calculatedTotal, customerName, citizenId))
    Notify(src, 'success', _L('order_placed', orderId, calculatedTotal))
    BroadcastToStaff(restaurantId, 'restaurant_manager:client:orderReceived', orderData)
end)

-- Credit Money Helper (Qbox / QBCore / ox_inventory Cash Fallback + Renewed-Banking Log)
local function CreditPlayerMoney(src, account, amount, reason, txTitle, issuerLabel)
    amount = math.floor(tonumber(amount) or 0)
    if not src or src <= 0 or amount <= 0 then return false end
    local moneyType = (account == 'cash') and 'cash' or 'bank'
    local paidSuccess = false

    if exports['qbx_core'] and exports['qbx_core'].AddMoney then
        local ok, paid = pcall(function()
            return exports['qbx_core']:AddMoney(src, moneyType, amount, reason or 'restaurant-payout')
        end)
        if ok and paid then
            paidSuccess = true
        end
    end

    if not paidSuccess then
        local ply = GetPlayer(src)
        if ply and ply.Functions and ply.Functions.AddMoney then
            local ok, paid = pcall(function()
                return ply.Functions.AddMoney(moneyType, amount, reason or 'restaurant-payout')
            end)
            if ok and paid then
                paidSuccess = true
            end
        end
    end

    if not paidSuccess and moneyType == 'cash' and exports.ox_inventory then
        local ok, added = pcall(function()
            return exports.ox_inventory:AddItem(src, 'money', amount)
        end)
        if ok and added then
            paidSuccess = true
        end
    end

    if paidSuccess and moneyType == 'bank' and GetResourceState('Renewed-Banking') == 'started' and exports['Renewed-Banking'] and exports['Renewed-Banking'].handleTransaction then
        local citizenId = GetPlayerCitizenId(src)
        local playerName = GetPlayerFullName(src)
        if citizenId and citizenId ~= '' then
            pcall(function()
                exports['Renewed-Banking']:handleTransaction(
                    citizenId,
                    txTitle or 'Restaurant Payroll',
                    amount,
                    reason or 'Salary payout',
                    issuerLabel or 'Burger Shot',
                    playerName or 'Employee',
                    'deposit'
                )
            end)
        end
    end

    return paidSuccess
end

-- ====================================================================
-- UPDATE ORDER STATUS (Employee Flow)
-- Flow: Pending > Accepted > Cooking > Ready > Delivered
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:updateOrderStatus', function(payload)
    local src = source
    if not CheckRateLimit(src, 'updateOrder', 500) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local orderId = tonumber(payload.orderId)
    local nextStatus = payload.status

    if not HasPermission(src, restaurantId, 'view_orders') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    local activeOrders = ServerCache.ActiveOrders[restaurantId]
    if not activeOrders or not activeOrders[orderId] then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local order = activeOrders[orderId]
    if order.status == 'delivered' or order.status == 'cancelled' then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local citizenId = GetPlayerCitizenId(src)
    local employeeName = GetPlayerFullName(src)

    -- Double-Claim Protection on Pending Orders
    if nextStatus == 'accepted' then
        if order.status ~= 'pending' then
            Notify(src, 'error', _L('order_already_claimed'))
            return
        end
        order.claimed_by = citizenId
        order.claimed_name = employeeName
    elseif nextStatus == 'cooking' or nextStatus == 'ready' or nextStatus == 'delivered' then
        if not order.claimed_by then
            order.claimed_by = citizenId
            order.claimed_name = employeeName
        end
    else
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    order.status = nextStatus

    -- Clean delivered orders synchronously before async DB/payout calls to block duplicate payouts
    if nextStatus == 'delivered' then
        activeOrders[orderId] = nil
    end

    -- Update Database
    MySQL.update([[
        UPDATE `rm_orders` 
        SET `status` = ?, `claimed_by` = ?, `claimed_name` = ? 
        WHERE `id` = ? AND `restaurant_id` = ?
    ]], { nextStatus, order.claimed_by, order.claimed_name, orderId, restaurantId })

    -- Broadcast to Staff
    BroadcastToStaff(restaurantId, 'restaurant_manager:client:orderUpdated', order)

    -- Notify Customer if Online
    if order.customer_source and GetPlayer(order.customer_source) then
        Notify(order.customer_source, 'info', _L('order_status_updated', orderId, nextStatus:upper()))
    end

    -- Pay Order Completion Salary Commission to the Employee Finishing the Order
    if nextStatus == 'delivered' and GetRestaurantSalarySettings then
        local salaryPercent, salaryAccount = GetRestaurantSalarySettings(restaurantId)
        local orderTotal = tonumber(order.total_price) or 0
        if salaryPercent > 0 and orderTotal > 0 then
            local commission = math.floor(((orderTotal * salaryPercent) / 100) + 0.5)
            if commission > 0 then
                local resLabel = (Config.Restaurants[restaurantId] and Config.Restaurants[restaurantId].label) or 'Burger Shot'
                local paid = CreditPlayerMoney(
                    src,
                    salaryAccount,
                    commission,
                    string.format('Order #%d Commission (%d%%)', orderId, salaryPercent),
                    resLabel .. ' Commission',
                    resLabel
                )
                if paid then
                    print(string.format('^2[BurgerShot] Order #%d commission paid: $%d (%d%%) to %s -> %s^0', orderId, commission, salaryPercent, employeeName, salaryAccount:upper()))
                    LogAction(restaurantId, src, 'ORDER_SALARY', {
                        order_id = orderId,
                        order_total = orderTotal,
                        salary_percent = salaryPercent,
                        salary_amount = commission,
                        account = salaryAccount
                    })
                    Notify(src, 'success', string.format('Order #%d finished! Earned $%d salary (%d%% -> %s).', orderId, commission, salaryPercent, salaryAccount:upper()))
                end
            end
        end
    end
end)

-- ====================================================================
-- CANCEL & REFUND ORDER (Manager / Owner)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:cancelOrder', function(payload)
    local src = source
    if not CheckRateLimit(src, 'cancelOrder', 1000) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local orderId = tonumber(payload.orderId)
    local reason = payload.reason or 'Cancelled by staff'

    if not HasPermission(src, restaurantId, 'refund_orders') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    local activeOrders = ServerCache.ActiveOrders[restaurantId]
    local order = activeOrders and activeOrders[orderId]

    if not order then
        -- Check Database if order not in active cache
        local dbOrder = MySQL.single.await('SELECT * FROM `rm_orders` WHERE `id` = ? AND `restaurant_id` = ?', { orderId, restaurantId })
        if dbOrder then
            local decodedItems = {}
            pcall(function() decodedItems = json.decode(dbOrder.items) end)
            order = dbOrder
            order.items = decodedItems
        end
    end

    if not order or order.status == 'cancelled' or order.status == 'delivered' then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    -- Process Refund
    if Config.RefundOnCancel and order.total_price and order.total_price > 0 then
        local customerFound = false
        for _, pId in ipairs(GetPlayers()) do
            local pSrc = tonumber(pId)
            local cid = GetPlayerCitizenId(pSrc)
            if cid and cid == order.customer_identifier then
                local ply = GetPlayer(pSrc)
                if ply and ply.Functions and ply.Functions.AddMoney then
                    ply.Functions.AddMoney(order.payment_method or 'cash', order.total_price, 'order-refund-' .. orderId)
                    Notify(pSrc, 'info', _L('order_refunded', orderId, order.total_price))
                    customerFound = true
                elseif exports.ox_inventory and (order.payment_method or 'cash') == 'cash' then
                    exports.ox_inventory:AddItem(pSrc, 'money', order.total_price)
                    Notify(pSrc, 'info', _L('order_refunded', orderId, order.total_price))
                    customerFound = true
                end
                break
            end
        end

        -- If customer is offline, deduct from society or flag in logs
        LogAction(restaurantId, src, 'ORDER_REFUND', {
            order_id = orderId,
            customer_identifier = order.customer_identifier,
            amount = order.total_price,
            customer_online = customerFound,
            reason = reason
        })
    end

    -- Update Order in DB
    order.status = 'cancelled'
    MySQL.update('UPDATE `rm_orders` SET `status` = ? WHERE `id` = ?', { 'cancelled', orderId })

    -- Remove from In-Memory Active Cache
    if activeOrders then
        activeOrders[orderId] = nil
    end

    -- Broadcast Update
    BroadcastToStaff(restaurantId, 'restaurant_manager:client:orderUpdated', order)
    Notify(src, 'success', _L('order_cancelled', orderId))
end)

-- ====================================================================
-- FETCH ORDER HISTORY (ox_lib callback)
-- ====================================================================
lib.callback.register('restaurant_manager:server:getOrderHistory', function(source, restaurantId)
    local src = source
    if not HasPermission(src, restaurantId, 'view_history') then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT `id`, `customer_name`, `items`, `total_price`, `payment_method`, `status`, `claimed_name`, `created_at` 
        FROM `rm_orders` 
        WHERE `restaurant_id` = ? 
        ORDER BY `id` DESC 
        LIMIT 50
    ]], { restaurantId })

    if not rows then return {} end

    for _, row in ipairs(rows) do
        if row.items and row.items ~= '' then
            local success, decoded = pcall(json.decode, row.items)
            if success then
                row.items = decoded
            end
        end
    end

    return rows
end)

-- ====================================================================
-- FETCH ACTIVE ORDERS (ox_lib callback)
-- ====================================================================
lib.callback.register('restaurant_manager:server:getActiveOrders', function(source, restaurantId)
    local src = source
    if not HasPermission(src, restaurantId, 'view_orders') then
        return {}
    end

    ServerCache.ActiveOrders[restaurantId] = ServerCache.ActiveOrders[restaurantId] or {}

    -- Direct DB query to ensure 100% data consistency even after server/resource restarts
    local orders = MySQL.query.await("SELECT * FROM `rm_orders` WHERE `restaurant_id` = ? AND `status` IN ('pending', 'accepted', 'cooking', 'ready') ORDER BY `id` DESC", { restaurantId })
    local orderList = {}
    if orders then
        for _, ord in ipairs(orders) do
            local decodedItems = {}
            if ord.items and ord.items ~= '' then
                local success, result = pcall(json.decode, ord.items)
                if success and type(result) == 'table' then
                    decodedItems = result
                end
            end
            local orderData = {
                id = ord.id,
                restaurant_id = ord.restaurant_id,
                customer_identifier = ord.customer_identifier,
                customer_name = ord.customer_name,
                items = decodedItems,
                total_price = ord.total_price,
                payment_method = ord.payment_method,
                status = ord.status,
                claimed_by = ord.claimed_by,
                claimed_name = ord.claimed_name,
                created_at = ord.created_at
            }
            ServerCache.ActiveOrders[restaurantId][ord.id] = orderData
            table.insert(orderList, orderData)
        end
    end

    return orderList
end)

-- ====================================================================
-- RESTAURANT SETTINGS, TAX & SALARY MANAGEMENT (Owner Controls)
-- ====================================================================
local function UpsertRestaurantSetting(restaurantId, key, value)
    ServerCache.Settings[restaurantId] = ServerCache.Settings[restaurantId] or {}
    ServerCache.Settings[restaurantId][key] = value
    MySQL.query([[
        INSERT INTO `rm_settings` (`restaurant_id`, `setting_key`, `setting_value`)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE `setting_value` = ?
    ]], { restaurantId, key, tostring(value), tostring(value) })
end

local LastSalaryPayoutAt = {}

lib.callback.register('restaurant_manager:server:getSettings', function(source, restaurantId)
    local taxRate = GetRestaurantTaxRate(restaurantId)
    local salaryPercent, salaryAccount = GetRestaurantSalarySettings(restaurantId)
    local scheduleEnabled, intervalMinutes, onDutyOnly = GetRestaurantSalarySchedule(restaurantId)
    return {
        tax_rate = taxRate,
        salary_percent = salaryPercent,
        salary_account = salaryAccount,
        salary_schedule_enabled = scheduleEnabled,
        salary_interval_minutes = intervalMinutes,
        salary_on_duty_only = onDutyOnly
    }
end)

RegisterNetEvent('restaurant_manager:server:saveTaxRate', function(payload)
    local src = source
    if not CheckRateLimit(src, 'saveTaxRate', 1000) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local rawTax = tonumber(payload.taxRate) or 0
    local taxRate = math.max(0, math.min(50, rawTax))

    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    UpsertRestaurantSetting(restaurantId, 'tax_rate', taxRate)

    TriggerClientEvent('restaurant_manager:client:syncSettings', -1, restaurantId, {
        tax_rate = taxRate
    })

    LogAction(restaurantId, src, 'TAX_UPDATE', {
        tax_rate = taxRate
    })

    Notify(src, 'success', string.format('Sales tax rate updated to %d%%!', taxRate))
end)

-- Shared helper to execute a role base salary payout cycle for a restaurant
local function RunSalaryPayoutForRestaurant(resId, onDutyOnlyOverride, isManual)
    local resConfig = Config.Restaurants[resId]
    if not resConfig then return 0, 0 end

    local _, salaryAccount = GetRestaurantSalarySettings(resId)
    local _, intervalMinutes, onDutyOnly = GetRestaurantSalarySchedule(resId)
    if onDutyOnlyOverride ~= nil then
        onDutyOnly = onDutyOnlyOverride
    end

    local roles = ServerCache.Roles[resId] or {}
    local resLabel = resConfig.label or 'Burger Shot'
    local paidCount = 0
    local totalPaid = 0

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ply = GetPlayer(src)
        if ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == resConfig.job then
            local grade = 0
            if type(ply.PlayerData.job.grade) == 'table' then
                grade = tonumber(ply.PlayerData.job.grade.level) or 0
            elseif type(ply.PlayerData.job.grade) == 'number' then
                grade = ply.PlayerData.job.grade
            end

            -- Owners and Admins can receive base salary without punching the clock; regular staff follow onDutyOnly
            local isExemptDuty = (IsRoleOwnerGrade and IsRoleOwnerGrade(resId, grade))
                or (IsRoleAdminGrade and IsRoleAdminGrade(resId, grade))
                or (grade == (resConfig.ownerGrade or 9))
                or (grade == (resConfig.adminGrade or 10))
            local isEffectiveDuty = (ply.PlayerData.job.onduty == true) or isExemptDuty

            if not onDutyOnly or isEffectiveDuty then
                local roleData = roles[grade]
                local baseAmount = math.floor(tonumber(roleData and roleData.base_salary) or 0)
                if baseAmount > 0 then
                    local roleName = (roleData and roleData.role_name) or ('Grade ' .. grade)
                    local playerName = GetPlayerFullName(src)
                    local reason = string.format('%s Paycheck (%s)', resLabel, roleName)
                    local paid = CreditPlayerMoney(src, salaryAccount, baseAmount, reason, resLabel .. ' Paycheck', resLabel)
                    if paid then
                        paidCount = paidCount + 1
                        totalPaid = totalPaid + baseAmount
                        print(string.format('^2[BurgerShot] Role salary paid: $%d to %s (%s) -> %s^0', baseAmount, playerName, roleName, salaryAccount:upper()))
                        LogAction(resId, src, 'ROLE_SALARY', {
                            grade = grade,
                            role_name = roleName,
                            amount = baseAmount,
                            account = salaryAccount,
                            interval_minutes = intervalMinutes,
                            manual = isManual == true
                        })
                        Notify(src, 'success', string.format('%s Paycheck: Received $%d (%s) to %s.', resLabel, baseAmount, roleName, salaryAccount:upper()))
                    else
                        print(string.format('^1[BurgerShot] Failed crediting $%d salary to %s (%s) via %s^0', baseAmount, playerName, roleName, salaryAccount:upper()))
                    end
                end
            end
        end
    end

    return paidCount, totalPaid
end

RegisterNetEvent('restaurant_manager:server:saveSalarySettings', function(payload)
    local src = source
    if not CheckRateLimit(src, 'saveSalarySettings', 1000) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    if not Config.Restaurants[restaurantId] then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    local wasEnabled = GetRestaurantSalarySchedule(restaurantId)

    local rawPercent = tonumber(payload.salaryPercent) or 0
    local salaryPercent = math.max(0, math.min(100, math.floor(rawPercent)))
    local salaryAccount = (payload.salaryAccount == 'cash') and 'cash' or 'bank'

    local scheduleEnabled = payload.salaryScheduleEnabled ~= false and payload.salaryScheduleEnabled ~= 0 and payload.salaryScheduleEnabled ~= '0'
    local rawInterval = tonumber(payload.salaryIntervalMinutes) or 15
    local intervalMinutes = math.max(1, math.min(240, math.floor(rawInterval)))
    local onDutyOnly = payload.salaryOnDutyOnly ~= false and payload.salaryOnDutyOnly ~= 0 and payload.salaryOnDutyOnly ~= '0'

    UpsertRestaurantSetting(restaurantId, 'salary_percent', salaryPercent)
    UpsertRestaurantSetting(restaurantId, 'salary_account', salaryAccount)
    UpsertRestaurantSetting(restaurantId, 'salary_schedule_enabled', scheduleEnabled and '1' or '0')
    UpsertRestaurantSetting(restaurantId, 'salary_interval_minutes', intervalMinutes)
    UpsertRestaurantSetting(restaurantId, 'salary_on_duty_only', onDutyOnly and '1' or '0')

    -- Reset countdown only when newly enabling schedule so shortening an active interval pays promptly
    if scheduleEnabled and not wasEnabled then
        LastSalaryPayoutAt[restaurantId] = os.time()
    else
        LastSalaryPayoutAt[restaurantId] = LastSalaryPayoutAt[restaurantId] or os.time()
    end

    TriggerClientEvent('restaurant_manager:client:syncSettings', -1, restaurantId, {
        salary_percent = salaryPercent,
        salary_account = salaryAccount,
        salary_schedule_enabled = scheduleEnabled,
        salary_interval_minutes = intervalMinutes,
        salary_on_duty_only = onDutyOnly
    })

    LogAction(restaurantId, src, 'SALARY_UPDATE', {
        salary_percent = salaryPercent,
        salary_account = salaryAccount,
        schedule_enabled = scheduleEnabled,
        interval_minutes = intervalMinutes,
        on_duty_only = onDutyOnly
    })

    Notify(src, 'success', string.format('Salary settings saved! Order: %d%%, Paycheck: %s.', salaryPercent, scheduleEnabled and ('Every ' .. intervalMinutes .. 'm') or 'Disabled'))
end)

-- Manual Payroll Trigger (Owner Button)
lib.callback.register('restaurant_manager:server:triggerSalaryPayout', function(source, restaurantId)
    local src = source
    if not CheckRateLimit(src, 'triggerSalaryPayout', 3000) then
        return { ok = false, message = _L('rate_limited') }
    end

    if not Config.Restaurants[restaurantId] then
        return { ok = false, message = _L('invalid_data') }
    end

    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    local paidCount, totalPaid = RunSalaryPayoutForRestaurant(restaurantId, nil, true)
    LastSalaryPayoutAt[restaurantId] = os.time()
    return { ok = true, paidCount = paidCount, totalPaid = totalPaid }
end)

-- ====================================================================
-- PERIODIC ROLE BASE SALARY PAYOUT SCHEDULER
-- ====================================================================
CreateThread(function()
    while true do
        Wait(5000)

        if IsDatabaseSchemaReady and IsDatabaseSchemaReady() then
            local now = os.time()
            for resId in pairs(Config.Restaurants or {}) do
                local enabled, intervalMinutes = GetRestaurantSalarySchedule(resId)
                if not LastSalaryPayoutAt[resId] then
                    LastSalaryPayoutAt[resId] = now
                end

                if enabled and intervalMinutes >= 1 and (now - LastSalaryPayoutAt[resId]) >= (intervalMinutes * 60) then
                    LastSalaryPayoutAt[resId] = now
                    RunSalaryPayoutForRestaurant(resId, nil, false)
                end
            end
        end
    end
end)


