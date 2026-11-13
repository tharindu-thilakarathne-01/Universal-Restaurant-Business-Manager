-- ====================================================================
-- RESTAURANT MANAGER: SERVER MAIN & CORE BRIDGE
-- Framework compatibility: Qbox (qbx_core) & QBCore (qb-core)
-- ====================================================================

ServerCache = {
    Roles = {},       -- [restaurantId] = { [grade] = { role_name, permissions, is_owner } }
    Recipes = {},     -- [restaurantId] = { [id] = recipeData }
    Stations = {},    -- [restaurantId] = { [id] = stationData }
    Doors = {},       -- [restaurantId] = { [id] = doorData }
    MenuState = {},   -- [restaurantId] = { [itemName] = itemData }
    ActiveOrders = {},-- [restaurantId] = { [orderId] = orderData }
    Settings = {},    -- [restaurantId] = { [key] = value }
    StaffHours = {},  -- [restaurantId] = { [citizenid] = { citizenid, name, grade, gradeName, workedSeconds, lastDutyAt } }
    Vending = {},     -- [restaurantId] = { [itemName] = { item_name, label, price, stock } }
    VendingFunds = {},-- [restaurantId] = number (accumulated vending cash fund)
    ActiveCooking = {}-- [src] = { restaurantId, recipeId, stationId, finishTime }
}

local RateLimits = {}
local ActiveDutySessions = {} -- [src] = { restaurantId, citizenid, name, grade, gradeName, startedAt }

-- Safe Qbox / QBCore Player Fetcher
function GetPlayer(src)
    if not src or src <= 0 then return nil end
    if exports['qbx_core'] and exports['qbx_core'].GetPlayer then
        local ply = exports['qbx_core']:GetPlayer(src)
        if ply then return ply end
    end
    if exports['qb-core'] and exports['qb-core'].GetCoreObject then
        local QBCore = exports['qb-core']:GetCoreObject()
        if QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
            return QBCore.Functions.GetPlayer(src)
        end
    end
    return nil
end

-- Get Player Identifier (Citizen ID)
function GetPlayerCitizenId(src)
    local ply = GetPlayer(src)
    if not ply then return nil end
    if ply.PlayerData and ply.PlayerData.citizenid then
        return ply.PlayerData.citizenid
    end
    return nil
end

-- Get Player Character Full Name
function GetPlayerFullName(src)
    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.charinfo then
        return GetPlayerName(src) or 'Unknown'
    end
    local char = ply.PlayerData.charinfo
    return string.format('%s %s', char.firstname or '', char.lastname or ''):gsub('^%s*(.-)%s*$', '%1')
end

-- Localization Helper
function _L(key, ...)
    local lang = Config.Locale or 'en'
    local str = (Locales[lang] and Locales[lang][key]) or (Locales['en'] and Locales['en'][key]) or key
    if select('#', ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

-- Server Notification Helper (ox_lib notify)
function Notify(src, msgType, message)
    if not src or src <= 0 then return end
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Restaurant Manager',
        description = message,
        type = msgType or 'info',
        position = 'top-right',
        duration = 5000
    })
end

-- Rate Limiting Helper (Anti-Spam)
function CheckRateLimit(src, action, limitMs)
    limitMs = limitMs or Config.RateLimitMs or 1000
    RateLimits[src] = RateLimits[src] or {}
    local now = GetGameTimer()
    if RateLimits[src][action] and (now - RateLimits[src][action]) < limitMs then
        Notify(src, 'error', _L('rate_limited'))
        return false
    end
    RateLimits[src][action] = now
    return true
end

-- Clean rate limits and flush active duty hours on player drop
AddEventHandler('playerDropped', function()
    local src = source
    if FlushDutySession then
        FlushDutySession(src, true, true)
    end
    RateLimits[src] = nil
    ServerCache.ActiveCooking[src] = nil
end)

-- Validate Distance Between Player and Target Coordinates
function ValidatePlayerDistance(src, targetCoords, maxDistance)
    if not targetCoords then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pCoords = GetEntityCoords(ped)
    local tCoords = type(targetCoords) == 'vector3' and targetCoords or vec3(targetCoords.x, targetCoords.y, targetCoords.z)
    return #(pCoords - tCoords) <= (maxDistance or Config.MaxStationDistance)
end

-- Determine whether a job grade is a Restaurant Admin role (Permanent Full Access)
function IsRoleAdminGrade(restaurantId, grade)
    local resConfig = Config.Restaurants[restaurantId]
    local g = tonumber(grade) or 0
    local adminGrade = (resConfig and resConfig.adminGrade) or 10
    if g == adminGrade then
        return true
    end
    local role = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][g]
    return role and role.is_admin == true or false
end

-- Determine whether a job grade is the Restaurant Owner role (Configurable by Admin)
function IsRoleOwnerGrade(restaurantId, grade)
    local resConfig = Config.Restaurants[restaurantId]
    local g = tonumber(grade) or 0
    local ownerGrade = (resConfig and resConfig.ownerGrade) or 9
    if g == ownerGrade then
        return true
    end
    if IsRoleAdminGrade(restaurantId, g) then
        return false
    end
    local role = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][g]
    if role then
        return role.is_owner == true
    end
    return false
end

-- Push a single role add/update/delete cleanly into live Qbox/QBCore job cache (without rewriting shared/jobs.lua)
function SyncRoleToCoreFramework(restaurantId, grade, roleData, isDelete)
    local resConfig = Config.Restaurants[restaurantId]
    local g = tonumber(grade)
    if not resConfig or not g then return end

    if exports['qbx_core'] then
        if isDelete then
            if exports['qbx_core'].RemoveJobGrade then
                pcall(function() exports['qbx_core']:RemoveJobGrade(resConfig.job, g, false) end)
            end
        elseif roleData and exports['qbx_core'].UpsertJobGrade then
            local isBoss = roleData.is_admin == true or roleData.is_owner == true or g == (resConfig.managerGrade or 8)
            local isBankAuth = roleData.is_admin == true or roleData.is_owner == true or g == (resConfig.ownerGrade or 9)
            pcall(function()
                exports['qbx_core']:UpsertJobGrade(resConfig.job, g, {
                    name = roleData.role_name or ('Grade ' .. g),
                    payment = 0,
                    isboss = isBoss,
                    bankAuth = isBankAuth
                }, false)
            end)
        end
    elseif exports['qb-core'] and exports['qb-core'].GetCoreObject then
        pcall(function()
            local QBCore = exports['qb-core']:GetCoreObject()
            local sharedJob = QBCore and QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[resConfig.job]
            if sharedJob and sharedJob.grades then
                local key = tostring(g)
                if isDelete then
                    sharedJob.grades[key] = nil
                    sharedJob.grades[g] = nil
                elseif roleData then
                    sharedJob.grades[key] = {
                        name = roleData.role_name or ('Grade ' .. g),
                        payment = 0,
                        isboss = roleData.is_admin == true or roleData.is_owner == true or g == (resConfig.managerGrade or 8)
                    }
                end
            end
        end)
    end
end

-- Unified Server Admin Detector (ACE, Qbox, CityAdmin, QBCore)
function IsServerAdmin(src)
    if not src or src <= 0 then return false end

    if GetResourceState('cityadmin') == 'started' and exports['cityadmin'] then
        local okBase, baseRole = pcall(function() return exports['cityadmin']:GetBaseRole(src) end)
        local okDuty, isDuty = pcall(function() return exports['cityadmin']:IsAdminDuty(src) end)
        if okBase and baseRole and baseRole ~= 'none' and okDuty and isDuty == false then
            return false
        end
    end

    local srcStr = tostring(src)
    if IsPlayerAceAllowed(srcStr, 'command')
        or IsPlayerAceAllowed(srcStr, 'admin')
        or IsPlayerAceAllowed(srcStr, 'god')
        or IsPlayerAceAllowed(srcStr, 'group.admin')
        or IsPlayerAceAllowed(srcStr, 'city.admin.owner')
        or IsPlayerAceAllowed(srcStr, 'city.admin.superadmin')
        or IsPlayerAceAllowed(srcStr, 'city.admin.admin')
    then
        return true
    end

    if exports['qbx_core'] and exports['qbx_core'].HasPermission then
        for _, grp in ipairs({ 'god', 'owner', 'superadmin', 'admin' }) do
            local ok, has = pcall(function() return exports['qbx_core']:HasPermission(src, grp) end)
            if ok and has then return true end
        end
    end

    if exports['qb-core'] and exports['qb-core'].GetCoreObject then
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
            if QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god') then
                return true
            end
        end
    end

    return false
end

-- True when player is a FiveM Server Admin OR holds the restaurant's Admin role
function HasRestaurantAdminAccess(src, restaurantId)
    if IsServerAdmin(src) then
        return true
    end
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return false end

    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.job or ply.PlayerData.job.name ~= resConfig.job then
        return false
    end

    local grade = 0
    if type(ply.PlayerData.job.grade) == 'table' then
        grade = tonumber(ply.PlayerData.job.grade.level) or 0
    elseif type(ply.PlayerData.job.grade) == 'number' then
        grade = ply.PlayerData.job.grade
    end
    return IsRoleAdminGrade(restaurantId, grade)
end

-- Validate Player Employment, Duty & Granular Role Permission
function HasPermission(src, restaurantId, permissionId)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return false end

    -- Server Admins and Restaurant Admin Role holders always have full permissions
    if HasRestaurantAdminAccess(src, restaurantId) then
        return true
    end

    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.job then
        return false
    end

    if ply.PlayerData.job.name ~= resConfig.job then
        return false
    end

    -- Evaluate strictly against the assigned Role Permissions in rm_roles (for ALL non-admin grades, including Owner)
    local grade = 0
    if type(ply.PlayerData.job.grade) == 'table' then
        grade = tonumber(ply.PlayerData.job.grade.level) or 0
    elseif type(ply.PlayerData.job.grade) == 'number' then
        grade = ply.PlayerData.job.grade
    end

    local isOwnerGrade = IsRoleOwnerGrade(restaurantId, grade)
    if not isOwnerGrade and not ply.PlayerData.job.onduty then
        return false
    end

    local roles = ServerCache.Roles[restaurantId]
    if roles and roles[grade] then
        local perms = roles[grade].permissions
        if type(perms) == 'table' then
            for _, p in ipairs(perms) do
                if p == permissionId then
                    return true
                end
            end
        end
    end

    return false
end

-- Shared player debit & society deposit helpers (used by Orders & Vending)
function DebitPlayerMoney(src, paymentMethod, amount, reason)
    local cleanAmount = math.max(0, math.floor(tonumber(amount) or 0))
    if cleanAmount <= 0 then return true end
    local acct = (paymentMethod == 'cash') and 'cash' or 'bank'
    local ply = GetPlayer(src)
    if not ply then return false end

    local playerMoney = 0
    if exports['qbx_core'] and exports['qbx_core'].GetMoney then
        playerMoney = tonumber(exports['qbx_core']:GetMoney(src, acct)) or 0
    elseif ply.Functions and ply.Functions.GetMoney then
        playerMoney = tonumber(ply.Functions.GetMoney(acct)) or 0
    elseif exports.ox_inventory and acct == 'cash' then
        playerMoney = tonumber(exports.ox_inventory:GetItemCount(src, 'money')) or 0
    end

    if playerMoney <= 0 and acct == 'cash' and exports.ox_inventory then
        playerMoney = tonumber(exports.ox_inventory:GetItemCount(src, 'money')) or 0
    end

    if playerMoney < cleanAmount then
        return false
    end

    local paymentSuccess = false
    if exports['qbx_core'] and exports['qbx_core'].RemoveMoney then
        paymentSuccess = exports['qbx_core']:RemoveMoney(src, acct, cleanAmount, reason or 'restaurant-purchase')
    elseif ply.Functions and ply.Functions.RemoveMoney then
        paymentSuccess = ply.Functions.RemoveMoney(acct, cleanAmount, reason or 'restaurant-purchase')
    end

    if not paymentSuccess and acct == 'cash' and exports.ox_inventory then
        paymentSuccess = exports.ox_inventory:RemoveItem(src, 'money', cleanAmount)
    end

    return paymentSuccess == true
end

function DepositSocietyMoney(accountName, amount, reason)
    local cleanAmount = math.max(0, math.floor(tonumber(amount) or 0))
    if not accountName or accountName == '' or cleanAmount <= 0 then return false end
    pcall(function()
        if exports['qbx_management'] and exports['qbx_management'].AddMoney then
            exports['qbx_management']:AddMoney(accountName, cleanAmount)
        elseif exports['Renewed-Banking'] and exports['Renewed-Banking'].addAccountMoney then
            exports['Renewed-Banking']:addAccountMoney(accountName, cleanAmount)
        elseif exports['qb-banking'] and exports['qb-banking'].AddMoney then
            exports['qb-banking']:AddMoney(accountName, cleanAmount, reason or 'Restaurant Income')
        end
    end)
    return true
end

-- Client target interaction helper (Admin, Station & Vending Manage access without per-frame latency)
lib.callback.register('restaurant_manager:server:getClientAccess', function(source, restaurantId)
    local resId = restaurantId or 'burgershot'
    return {
        isAdmin = HasRestaurantAdminAccess(source, resId),
        canManageStations = HasPermission(source, resId, 'manage_stations'),
        canManageVending = HasPermission(source, resId, 'vending_manage'),
        canVendingFund = HasPermission(source, resId, 'vending_fund'),
        canDoorUnlock = HasPermission(source, resId, 'door_unlock')
    }
end)

-- Check If Player has Admin access or Holds Restaurant Owner Grade
function IsRestaurantOwner(src, restaurantId)
    if HasRestaurantAdminAccess(src, restaurantId) then return true end
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return false end

    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.job then
        return false
    end

    if ply.PlayerData.job.name ~= resConfig.job then
        return false
    end

    local grade = 0
    if type(ply.PlayerData.job.grade) == 'table' then
        grade = tonumber(ply.PlayerData.job.grade.level) or 0
    elseif type(ply.PlayerData.job.grade) == 'number' then
        grade = ply.PlayerData.job.grade
    end
    return IsRoleOwnerGrade(restaurantId, grade)
end

-- Check If Player has Admin access or Manager Grade
function IsRestaurantManager(src, restaurantId)
    if HasRestaurantAdminAccess(src, restaurantId) then return true end
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return false end
    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.job then return false end
    if ply.PlayerData.job.name ~= resConfig.job then return false end

    local grade = 0
    if type(ply.PlayerData.job.grade) == 'table' then
        grade = tonumber(ply.PlayerData.job.grade.level) or 0
    elseif type(ply.PlayerData.job.grade) == 'number' then
        grade = ply.PlayerData.job.grade
    end
    local managerGrade = resConfig.managerGrade or 8
    local role = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][grade]
    if role then
        return grade == managerGrade
    end
    return grade >= managerGrade
end

-- ====================================================================
-- AUTOMATIC DATABASE SCHEMA MIGRATION & CACHE INITIALIZATION
-- ====================================================================
local schemaInitialized = false

function EnsureDatabaseSchema()
    if schemaInitialized then return true end

    local queries = {
        [[
            CREATE TABLE IF NOT EXISTS `rm_stations` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `station_type` VARCHAR(50) NOT NULL,
                `coords` LONGTEXT NOT NULL,
                `created_by` VARCHAR(60) NOT NULL,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX `idx_rm_stations_res` (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_roles` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `grade` INT NOT NULL,
                `role_name` VARCHAR(50) NOT NULL,
                `permissions` LONGTEXT NOT NULL,
                `base_salary` INT NOT NULL DEFAULT 0,
                `is_owner` TINYINT(1) DEFAULT 0,
                `is_admin` TINYINT(1) DEFAULT 0,
                UNIQUE KEY `uk_res_grade` (`restaurant_id`, `grade`),
                INDEX `idx_rm_roles_res` (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_recipes` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `recipe_name` VARCHAR(100) NOT NULL,
                `station_type` VARCHAR(50) NOT NULL,
                `ingredients` LONGTEXT NOT NULL,
                `output_item` VARCHAR(60) NOT NULL,
                `output_count` INT NOT NULL DEFAULT 1,
                `cooking_time` INT NOT NULL DEFAULT 5000,
                `enabled` TINYINT(1) NOT NULL DEFAULT 1,
                INDEX `idx_rm_recipes_res_station` (`restaurant_id`, `station_type`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_orders` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `customer_identifier` VARCHAR(60) NOT NULL,
                `customer_name` VARCHAR(100) NOT NULL,
                `items` LONGTEXT NOT NULL,
                `total_price` INT NOT NULL,
                `tax_amount` INT NOT NULL DEFAULT 0,
                `payment_method` VARCHAR(20) NOT NULL DEFAULT 'cash',
                `status` ENUM('pending', 'accepted', 'cooking', 'ready', 'delivered', 'cancelled') NOT NULL DEFAULT 'pending',
                `claimed_by` VARCHAR(60) DEFAULT NULL,
                `claimed_name` VARCHAR(100) DEFAULT NULL,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX `idx_rm_orders_res_status` (`restaurant_id`, `status`),
                INDEX `idx_rm_orders_created` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_menu_state` (
                `restaurant_id` VARCHAR(50) NOT NULL,
                `item_name` VARCHAR(60) NOT NULL,
                `label` VARCHAR(100) NOT NULL,
                `price` INT NOT NULL DEFAULT 10,
                `in_stock` TINYINT(1) NOT NULL DEFAULT 1,
                `stock_count` INT NOT NULL DEFAULT -1,
                `category` VARCHAR(50) NOT NULL DEFAULT 'food',
                PRIMARY KEY (`restaurant_id`, `item_name`),
                INDEX `idx_rm_menu_res` (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_logs` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `citizenid` VARCHAR(60) NOT NULL,
                `player_name` VARCHAR(100) NOT NULL,
                `action` VARCHAR(50) NOT NULL,
                `details` LONGTEXT NOT NULL,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX `idx_rm_logs_res_time` (`restaurant_id`, `created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_settings` (
                `restaurant_id` VARCHAR(50) NOT NULL,
                `setting_key` VARCHAR(50) NOT NULL,
                `setting_value` LONGTEXT NOT NULL,
                PRIMARY KEY (`restaurant_id`, `setting_key`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_staff_hours` (
                `restaurant_id` VARCHAR(50) NOT NULL,
                `citizenid` VARCHAR(60) NOT NULL,
                `player_name` VARCHAR(100) NOT NULL DEFAULT 'Unknown',
                `grade` INT NOT NULL DEFAULT 0,
                `grade_name` VARCHAR(80) NOT NULL DEFAULT '',
                `worked_seconds` BIGINT NOT NULL DEFAULT 0,
                `last_duty_at` TIMESTAMP NULL DEFAULT NULL,
                `first_seen_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`restaurant_id`, `citizenid`),
                INDEX `idx_rm_staff_hours_res` (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
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
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_vending_funds` (
                `restaurant_id` VARCHAR(50) NOT NULL,
                `balance` INT NOT NULL DEFAULT 0,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]],
        [[
            CREATE TABLE IF NOT EXISTS `rm_doors` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `restaurant_id` VARCHAR(50) NOT NULL,
                `label` VARCHAR(100) NOT NULL,
                `door_data` LONGTEXT NOT NULL,
                `locked` TINYINT(1) NOT NULL DEFAULT 1,
                `created_by` VARCHAR(60) NOT NULL,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX `idx_rm_doors_res` (`restaurant_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]]
    }

    for _, ddl in ipairs(queries) do
        local ok, err = pcall(MySQL.query.await, ddl, {})
        if not ok then
            print(string.format('^1[restaurant_manager]^7 Failed creating DB table: %s', tostring(err)))
            return false
        end
    end

    -- Upgrade existing rm_roles table cleanly if created without base_salary or is_admin columns
    local okCol, colRow = pcall(MySQL.single.await, "SHOW COLUMNS FROM `rm_roles` LIKE 'base_salary'", {})
    if okCol and not colRow then
        pcall(MySQL.query.await, 'ALTER TABLE `rm_roles` ADD COLUMN `base_salary` INT NOT NULL DEFAULT 0 AFTER `permissions`', {})
    end

    local okAdmCol, admColRow = pcall(MySQL.single.await, "SHOW COLUMNS FROM `rm_roles` LIKE 'is_admin'", {})
    if okAdmCol and not admColRow then
        pcall(MySQL.query.await, 'ALTER TABLE `rm_roles` ADD COLUMN `is_admin` TINYINT(1) NOT NULL DEFAULT 0 AFTER `is_owner`', {})
    end

    -- Build full permissions JSON cleanly from Config.AllPermissions
    local allPermIds = {}
    for _, p in ipairs(Config.AllPermissions or {}) do
        table.insert(allPermIds, p.id)
    end
    local allPermsJson = json.encode(allPermIds)

    -- Seed default roles (all standard grades 0-9) ONLY on first setup so deleted roles stay deleted
    local okRoleCount, roleCount = pcall(MySQL.scalar.await, "SELECT COUNT(*) FROM `rm_roles` WHERE `restaurant_id` = 'burgershot'", {})
    local okSeedFlag, seedFlagRow = pcall(MySQL.single.await, "SELECT `setting_value` FROM `rm_settings` WHERE `restaurant_id` = 'burgershot' AND `setting_key` = 'roles_seeded'", {})
    local alreadySeeded = okSeedFlag and seedFlagRow and seedFlagRow.setting_value == '1'
    if (not alreadySeeded) and okRoleCount and (tonumber(roleCount) or 0) == 0 then
        pcall(MySQL.query.await, [[
            INSERT IGNORE INTO `rm_roles` (`restaurant_id`, `grade`, `role_name`, `permissions`, `is_owner`, `is_admin`)
            VALUES
            ('burgershot', 10, 'Admin', ?, 0, 1),
            ('burgershot', 9, 'Owner', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock","manage_stations","manage_recipes","manage_roles","view_logs"]', 1, 0),
            ('burgershot', 8, 'Manager', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock"]', 0, 0),
            ('burgershot', 7, 'Assistant Manager', '["view_orders","cook","refund_orders","view_history","manage_menu","manage_stock"]', 0, 0),
            ('burgershot', 6, 'Supervisor', '["view_orders","cook","view_history","manage_stock"]', 0, 0),
            ('burgershot', 5, 'Shift Lead', '["view_orders","cook","view_history"]', 0, 0),
            ('burgershot', 4, 'Cashier', '["view_orders","cook"]', 0, 0),
            ('burgershot', 3, 'Senior Cook', '["view_orders","cook"]', 0, 0),
            ('burgershot', 2, 'Cook', '["view_orders","cook"]', 0, 0),
            ('burgershot', 1, 'Crew Member', '["view_orders","cook"]', 0, 0),
            ('burgershot', 0, 'Trainee', '["view_orders","cook"]', 0, 0)
        ]], { allPermsJson })
    end

    -- Ensure Admin Role (adminGrade = 10) exists & stays Full Access even on already-seeded DBs
    for resId, resConfig in pairs(Config.Restaurants or {}) do
        local adminGrade = tonumber(resConfig.adminGrade) or 10
        pcall(MySQL.query.await, [[
            INSERT IGNORE INTO `rm_roles` (`restaurant_id`, `grade`, `role_name`, `permissions`, `is_owner`, `is_admin`)
            VALUES (?, ?, 'Admin', ?, 0, 1)
        ]], { resId, adminGrade, allPermsJson })
        pcall(MySQL.update.await, [[
            UPDATE `rm_roles`
            SET `permissions` = ?, `is_owner` = 0, `is_admin` = 1
            WHERE `restaurant_id` = ? AND `grade` = ?
        ]], { allPermsJson, resId, adminGrade })
    end

    pcall(MySQL.query.await, [[
        INSERT IGNORE INTO `rm_menu_state` (`restaurant_id`, `item_name`, `label`, `price`, `in_stock`, `stock_count`, `category`)
        VALUES
        ('burgershot', 'bs_cheese_chilli_burger', 'Cheese And Chilli Burger', 18, 1, -1, 'food'),
        ('burgershot', 'bs_bbq_burger', 'BBQ Burger', 20, 1, -1, 'food'),
        ('burgershot', 'bs_ecola', 'E-Cola', 5, 1, -1, 'drinks'),
        ('burgershot', 'bs_bubble_tea', 'Bubble tea', 8, 1, -1, 'drinks')
    ]], {})

    pcall(MySQL.query.await, [[
        INSERT IGNORE INTO `rm_settings` (`restaurant_id`, `setting_key`, `setting_value`)
        VALUES
        ('burgershot', 'tax_rate', '10'),
        ('burgershot', 'salary_percent', '10'),
        ('burgershot', 'salary_account', 'bank'),
        ('burgershot', 'salary_schedule_enabled', '1'),
        ('burgershot', 'salary_interval_minutes', '15'),
        ('burgershot', 'salary_on_duty_only', '1')
    ]], {})

    local okCount, recipeCount = pcall(MySQL.scalar.await, "SELECT COUNT(*) FROM `rm_recipes` WHERE `restaurant_id` = 'burgershot'", {})
    if okCount and (tonumber(recipeCount) or 0) == 0 then
        pcall(MySQL.query.await, [[
            INSERT INTO `rm_recipes` (`restaurant_id`, `recipe_name`, `station_type`, `ingredients`, `output_item`, `output_count`, `cooking_time`, `enabled`)
            VALUES
            ('burgershot', 'Cheese And Chilli Burger', 'assembly', '[{"item":"bs_meat_pattie","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_cheese","count":1},{"item":"bs_pepper","count":1},{"item":"bs_tomato_lettuce","count":1}]', 'bs_cheese_chilli_burger', 1, 6000, 1),
            ('burgershot', 'BBQ Burger', 'assembly', '[{"item":"bs_bbq_sauce","count":1},{"item":"bs_cheese","count":1},{"item":"bs_tomato_lettuce","count":1},{"item":"bs_onion_rings","count":1},{"item":"bs_burger_bun","count":1},{"item":"bs_bacon","count":1}]', 'bs_bbq_burger', 1, 7000, 1),
            ('burgershot', 'E-Cola', 'drinks', '[{"item":"bs_ice_cubes","count":1},{"item":"bs_cola_syrup","count":1},{"item":"bs_carbonated_water","count":1}]', 'bs_ecola', 1, 3500, 1),
            ('burgershot', 'Bubble tea', 'drinks', '[{"item":"bs_bubbles","count":1},{"item":"bs_ice_cubes","count":1},{"item":"bs_sugar_cubes","count":1},{"item":"bs_milk","count":1}]', 'bs_bubble_tea', 1, 4000, 1)
        ]], {})
    end

    schemaInitialized = true
    return true
end

MySQL.ready(function()
    print('^2[restaurant_manager]^7 Ensuring database tables and preloading server cache...')
    EnsureDatabaseSchema()

    -- 1. Load Roles
    local allPermsList = {}
    for _, p in ipairs(Config.AllPermissions or {}) do
        table.insert(allPermsList, p.id)
    end

    local roles = MySQL.query.await('SELECT * FROM `rm_roles`', {})
    if roles then
        for _, r in ipairs(roles) do
            local gradeNum = tonumber(r.grade)
            if gradeNum then
                local resCfg = Config.Restaurants[r.restaurant_id]
                local isAdminGrade = (r.is_admin == 1 or r.is_admin == true) or (resCfg and gradeNum == (resCfg.adminGrade or 10))
                local isOwnerGrade = (not isAdminGrade) and ((r.is_owner == 1 or r.is_owner == true) or (resCfg and gradeNum == (resCfg.ownerGrade or 9)))
                ServerCache.Roles[r.restaurant_id] = ServerCache.Roles[r.restaurant_id] or {}
                local decodedPerms = {}
                if isAdminGrade then
                    decodedPerms = allPermsList
                elseif r.permissions and r.permissions ~= '' then
                    local success, result = pcall(json.decode, r.permissions)
                    if success and type(result) == 'table' then
                        decodedPerms = result
                    end
                end
                ServerCache.Roles[r.restaurant_id][gradeNum] = {
                    id = r.id,
                    role_name = r.role_name,
                    permissions = decodedPerms,
                    base_salary = tonumber(r.base_salary) or 0,
                    is_owner = isOwnerGrade,
                    is_admin = isAdminGrade
                }
            end
        end
    end

    -- Sync roles between rm_roles (source of truth after initial seed) and Qbox/QBCore runtime jobs
    for resId, resConfig in pairs(Config.Restaurants or {}) do
        ServerCache.Roles[resId] = ServerCache.Roles[resId] or {}

        local okFlag, flagRow = pcall(MySQL.single.await,
            'SELECT `setting_value` FROM `rm_settings` WHERE `restaurant_id` = ? AND `setting_key` = ?',
            { resId, 'roles_seeded' }
        )
        local rolesAlreadySeeded = (okFlag and flagRow and flagRow.setting_value == '1')

        local jobDef = nil
        if exports['qbx_core'] and exports['qbx_core'].GetJob then
            local ok, res = pcall(function() return exports['qbx_core']:GetJob(resConfig.job) end)
            if ok then jobDef = res end
        elseif exports['qb-core'] and exports['qb-core'].GetCoreObject then
            local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok and QBCore and QBCore.Shared and QBCore.Shared.Jobs then
                jobDef = QBCore.Shared.Jobs[resConfig.job]
            end
        end

        if jobDef and type(jobDef.grades) == 'table' then
            for rawGrade, gInfo in pairs(jobDef.grades) do
                local gNum = tonumber(rawGrade)
                if gNum and not ServerCache.Roles[resId][gNum] then
                    local adminGrade = resConfig.adminGrade or 10
                    local ownerGrade = resConfig.ownerGrade or 9
                    local isProtectedGrade = (gNum == 0 or gNum == ownerGrade or gNum == adminGrade)
                    if (not rolesAlreadySeeded) or isProtectedGrade then
                        local isAdminGrade = (gNum == adminGrade)
                        local isOwnerGrade = (not isAdminGrade) and (gNum == ownerGrade)
                        local defaultPerms = { 'view_orders', 'cook' }
                        if isAdminGrade or isOwnerGrade then
                            defaultPerms = allPermsList
                        elseif gNum == (resConfig.managerGrade or 8) then
                            defaultPerms = { 'view_orders', 'cook', 'refund_orders', 'view_history', 'manage_menu', 'manage_stock' }
                        end
                        local roleName = (type(gInfo) == 'table' and gInfo.name) or ('Grade ' .. gNum)
                        pcall(MySQL.query.await, [[
                            INSERT IGNORE INTO `rm_roles` (`restaurant_id`, `grade`, `role_name`, `permissions`, `is_owner`, `is_admin`)
                            VALUES (?, ?, ?, ?, ?, ?)
                        ]], { resId, gNum, roleName, json.encode(defaultPerms), isOwnerGrade and 1 or 0, isAdminGrade and 1 or 0 })

                        ServerCache.Roles[resId][gNum] = {
                            role_name = roleName,
                            permissions = defaultPerms,
                            base_salary = 0,
                            is_owner = isOwnerGrade,
                            is_admin = isAdminGrade
                        }
                    else
                        -- Deleted custom/default grade stays removed in runtime framework memory
                        SyncRoleToCoreFramework(resId, gNum, nil, true)
                    end
                end
            end
        end

        -- Push all roles saved in rm_roles (custom grades, renamed roles) to runtime Qbox/QBCore
        for gNum, roleData in pairs(ServerCache.Roles[resId]) do
            SyncRoleToCoreFramework(resId, gNum, roleData, false)
        end

        if not rolesAlreadySeeded then
            pcall(MySQL.insert.await, [[
                INSERT INTO `rm_settings` (`restaurant_id`, `setting_key`, `setting_value`)
                VALUES (?, 'roles_seeded', '1')
                ON DUPLICATE KEY UPDATE `setting_value` = '1'
            ]], { resId })
        end
    end

    -- 2. Load Recipes
    local recipes = MySQL.query.await('SELECT * FROM `rm_recipes` WHERE `enabled` = 1', {})
    if recipes then
        for _, rec in ipairs(recipes) do
            ServerCache.Recipes[rec.restaurant_id] = ServerCache.Recipes[rec.restaurant_id] or {}
            local decodedIngs = {}
            if rec.ingredients and rec.ingredients ~= '' then
                local success, result = pcall(json.decode, rec.ingredients)
                if success and type(result) == 'table' then
                    decodedIngs = result
                end
            end
            ServerCache.Recipes[rec.restaurant_id][rec.id] = {
                id = rec.id,
                recipe_name = rec.recipe_name,
                station_type = rec.station_type,
                ingredients = decodedIngs,
                output_item = rec.output_item,
                output_count = rec.output_count,
                cooking_time = rec.cooking_time,
                enabled = (rec.enabled == 1 or rec.enabled == true)
            }
        end
    end

    -- 3. Load Stations
    local stations = MySQL.query.await('SELECT * FROM `rm_stations`', {})
    if stations then
        for _, st in ipairs(stations) do
            ServerCache.Stations[st.restaurant_id] = ServerCache.Stations[st.restaurant_id] or {}
            local decodedCoords = nil
            if st.coords and st.coords ~= '' then
                local success, result = pcall(json.decode, st.coords)
                if success and type(result) == 'table' then
                    decodedCoords = result
                end
            end
            if decodedCoords then
                ServerCache.Stations[st.restaurant_id][st.id] = {
                    id = st.id,
                    restaurant_id = st.restaurant_id,
                    station_type = st.station_type,
                    coords = decodedCoords,
                    created_by = st.created_by
                }

                -- Register ox_inventory stash on resource start
                if exports.ox_inventory and exports.ox_inventory.RegisterStash then
                    if st.station_type == 'tray' then
                        exports.ox_inventory:RegisterStash(string.format('%s_tray_%d', st.restaurant_id, st.id), 'Burger Shot - Food Tray', 15, 30000)
                    elseif st.station_type == 'storage' then
                        local resJob = (Config.Restaurants[st.restaurant_id] and Config.Restaurants[st.restaurant_id].job) or 'burgershot'
                        exports.ox_inventory:RegisterStash(string.format('%s_storage_%d', st.restaurant_id, st.id), 'Burger Shot - Storage', 60, 300000, nil, { [resJob] = 0 })
                    end
                end
            end
        end
    end

    -- 3b. Load Doors
    local okDoors, doorRows = pcall(MySQL.query.await, 'SELECT * FROM `rm_doors`', {})
    if okDoors and doorRows then
        for _, d in ipairs(doorRows) do
            ServerCache.Doors[d.restaurant_id] = ServerCache.Doors[d.restaurant_id] or {}
            local decodedData = nil
            if d.door_data and d.door_data ~= '' then
                local success, result = pcall(json.decode, d.door_data)
                if success and type(result) == 'table' then
                    decodedData = result
                end
            end
            if decodedData and type(decodedData.leaves) == 'table' and #decodedData.leaves > 0 then
                ServerCache.Doors[d.restaurant_id][d.id] = {
                    id = d.id,
                    restaurant_id = d.restaurant_id,
                    label = d.label or ('Door #' .. tostring(d.id)),
                    coords = decodedData.coords,
                    maxDistance = tonumber(decodedData.maxDistance) or 2.4,
                    isDouble = decodedData.isDouble == true or #decodedData.leaves > 1,
                    leaves = decodedData.leaves,
                    locked = (d.locked == 1 or d.locked == true),
                    autoLock = (decodedData.autoLock == true),
                    created_by = d.created_by
                }
            end
        end
    end

    -- 4. Load Menu & Stock State
    local menu = MySQL.query.await('SELECT * FROM `rm_menu_state`', {})
    if menu then
        for _, m in ipairs(menu) do
            ServerCache.MenuState[m.restaurant_id] = ServerCache.MenuState[m.restaurant_id] or {}
            ServerCache.MenuState[m.restaurant_id][m.item_name] = {
                item_name = m.item_name,
                label = m.label,
                price = m.price,
                in_stock = (m.in_stock == 1 or m.in_stock == true),
                stock_count = tonumber(m.stock_count) or -1,
                category = m.category
            }
        end
    end

    -- 4b. Load Vending Machine Inventory
    local okVending, vendingRows = pcall(MySQL.query.await, 'SELECT * FROM `rm_vending_items`', {})
    if okVending and vendingRows then
        for _, v in ipairs(vendingRows) do
            ServerCache.Vending[v.restaurant_id] = ServerCache.Vending[v.restaurant_id] or {}
            ServerCache.Vending[v.restaurant_id][v.item_name] = {
                item_name = v.item_name,
                label = v.label or v.item_name,
                price = tonumber(v.price) or 15,
                stock = tonumber(v.stock) or 0
            }
        end
    end

    -- 5. Load Active Orders (pending, accepted, cooking, ready)
    local orders = MySQL.query.await("SELECT * FROM `rm_orders` WHERE `status` IN ('pending', 'accepted', 'cooking', 'ready')", {})
    if orders then
        for _, ord in ipairs(orders) do
            ServerCache.ActiveOrders[ord.restaurant_id] = ServerCache.ActiveOrders[ord.restaurant_id] or {}
            local decodedItems = {}
            if ord.items and ord.items ~= '' then
                local success, result = pcall(json.decode, ord.items)
                if success and type(result) == 'table' then
                    decodedItems = result
                end
            end
            ServerCache.ActiveOrders[ord.restaurant_id][ord.id] = {
                id = ord.id,
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
        end
    end

    -- 6. Load Restaurant Settings (Tax Rate, etc.)
    local settings = MySQL.query.await('SELECT * FROM `rm_settings`', {})
    if settings then
        for _, s in ipairs(settings) do
            ServerCache.Settings[s.restaurant_id] = ServerCache.Settings[s.restaurant_id] or {}
            ServerCache.Settings[s.restaurant_id][s.setting_key] = s.setting_value
        end
    end

    -- 7. Load Cumulative Staff Work Hours & Sync Already-Online Duty Sessions
    local okHours, staffHourRows = pcall(MySQL.query.await, 'SELECT * FROM `rm_staff_hours`', {})
    if okHours and staffHourRows then
        for _, row in ipairs(staffHourRows) do
            ServerCache.StaffHours[row.restaurant_id] = ServerCache.StaffHours[row.restaurant_id] or {}
            ServerCache.StaffHours[row.restaurant_id][row.citizenid] = {
                citizenid = row.citizenid,
                name = row.player_name or 'Unknown',
                grade = tonumber(row.grade) or 0,
                gradeName = row.grade_name or '',
                workedSeconds = tonumber(row.worked_seconds) or 0,
                lastDutyAt = row.last_duty_at and tostring(row.last_duty_at) or nil
            }
        end
    end

    if SyncPlayerDutySession then
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src then
                SyncPlayerDutySession(src)
            end
        end
    end

    print('^2[restaurant_manager]^7 Cache loaded successfully!')
    -- Broadcast loaded station zones and refreshed role access to all online clients
    TriggerClientEvent('restaurant_manager:client:loadStations', -1)
    TriggerClientEvent('restaurant_manager:client:rolesUpdated', -1)
end)

-- Shared Helper to Fetch a Cached / Database Restaurant Setting
function GetRestaurantSetting(restaurantId, key, defaultValue)
    if ServerCache.Settings[restaurantId] and ServerCache.Settings[restaurantId][key] ~= nil then
        return ServerCache.Settings[restaurantId][key]
    end

    local ok, row = pcall(MySQL.single.await,
        'SELECT `setting_value` FROM `rm_settings` WHERE `restaurant_id` = ? AND `setting_key` = ?',
        { restaurantId, key }
    )
    if ok and row and row.setting_value ~= nil then
        ServerCache.Settings[restaurantId] = ServerCache.Settings[restaurantId] or {}
        ServerCache.Settings[restaurantId][key] = row.setting_value
        return row.setting_value
    end

    return defaultValue
end

-- Helper to Get Restaurant Tax Rate (in percent, e.g. 10)
function GetRestaurantTaxRate(restaurantId)
    return tonumber(GetRestaurantSetting(restaurantId, 'tax_rate', 10)) or 0
end

-- Helper to Get Staff Order Completion Commission Percentage & Account
function GetRestaurantSalarySettings(restaurantId)
    local percent = tonumber(GetRestaurantSetting(restaurantId, 'salary_percent', 10)) or 0
    percent = math.max(0, math.min(100, math.floor(percent)))
    local rawAccount = tostring(GetRestaurantSetting(restaurantId, 'salary_account', 'bank'))
    local account = (rawAccount == 'cash') and 'cash' or 'bank'
    return percent, account
end

-- Helper to Get Periodic Role Paycheck Schedule Settings
function GetRestaurantSalarySchedule(restaurantId)
    local rawEnabled = tostring(GetRestaurantSetting(restaurantId, 'salary_schedule_enabled', '1'))
    local enabled = (rawEnabled == '1' or rawEnabled == 'true')
    local intervalMinutes = tonumber(GetRestaurantSetting(restaurantId, 'salary_interval_minutes', 15)) or 15
    intervalMinutes = math.max(1, math.min(240, math.floor(intervalMinutes)))
    local rawDuty = tostring(GetRestaurantSetting(restaurantId, 'salary_on_duty_only', '1'))
    local onDutyOnly = (rawDuty ~= '0' and rawDuty ~= 'false')
    return enabled, intervalMinutes, onDutyOnly
end

function IsDatabaseSchemaReady()
    return schemaInitialized
end

-- ====================================================================
-- STAFF PRESENCE & CUMULATIVE WORK HOURS TRACKER
-- ====================================================================
function ResolveRestaurantForJob(jobName)
    if not jobName or jobName == '' then return nil, nil end
    for resId, resCfg in pairs(Config.Restaurants or {}) do
        if resCfg.job == jobName then
            return resId, resCfg
        end
    end
    return nil, nil
end

function ExtractJobGrade(jobData)
    if type(jobData) ~= 'table' then return 0, '' end
    if type(jobData.grade) == 'table' then
        return tonumber(jobData.grade.level) or 0, tostring(jobData.grade.name or '')
    end
    return tonumber(jobData.grade) or 0, ''
end

function ResolveRoleLabel(restaurantId, grade, fallbackName)
    local g = tonumber(grade) or 0
    local cachedRole = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][g]
    if cachedRole and cachedRole.role_name and cachedRole.role_name ~= '' then
        return cachedRole.role_name
    end
    if fallbackName and fallbackName ~= '' then
        return fallbackName
    end
    return string.format('Grade %d', g)
end

local function PersistStaffHoursDelta(restaurantId, citizenid, name, grade, gradeName, deltaSeconds, updateLastDuty, fireAndForget)
    if not schemaInitialized then return end
    if not restaurantId or not citizenid or citizenid == '' then return end
    local cleanDelta = math.max(0, math.floor(tonumber(deltaSeconds) or 0))

    local query
    if updateLastDuty then
        query = [[
            INSERT INTO `rm_staff_hours` (`restaurant_id`, `citizenid`, `player_name`, `grade`, `grade_name`, `worked_seconds`, `last_duty_at`)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
                `player_name` = VALUES(`player_name`),
                `grade` = VALUES(`grade`),
                `grade_name` = VALUES(`grade_name`),
                `worked_seconds` = `worked_seconds` + VALUES(`worked_seconds`),
                `last_duty_at` = NOW()
        ]]
    else
        query = [[
            INSERT INTO `rm_staff_hours` (`restaurant_id`, `citizenid`, `player_name`, `grade`, `grade_name`, `worked_seconds`)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `player_name` = VALUES(`player_name`),
                `grade` = VALUES(`grade`),
                `grade_name` = VALUES(`grade_name`),
                `worked_seconds` = `worked_seconds` + VALUES(`worked_seconds`)
        ]]
    end

    local params = {
        restaurantId,
        citizenid,
        name or 'Unknown',
        tonumber(grade) or 0,
        gradeName or '',
        cleanDelta
    }

    if fireAndForget then
        pcall(MySQL.insert, query, params)
    else
        pcall(MySQL.insert.await, query, params)
    end
end

function EnsureStaffHoursEntry(restaurantId, citizenid, name, grade, gradeName, persistToDb)
    if not restaurantId or not citizenid or citizenid == '' then return nil end
    ServerCache.StaffHours[restaurantId] = ServerCache.StaffHours[restaurantId] or {}
    local entry = ServerCache.StaffHours[restaurantId][citizenid]
    local resolvedGrade = tonumber(grade) or (entry and entry.grade) or 0
    local resolvedName = (name and name ~= '') and name or (entry and entry.name) or 'Unknown'
    local resolvedRole = ResolveRoleLabel(restaurantId, resolvedGrade, gradeName or (entry and entry.gradeName))

    local changed = not entry
        or entry.name ~= resolvedName
        or entry.grade ~= resolvedGrade
        or entry.gradeName ~= resolvedRole

    if not entry then
        entry = {
            citizenid = citizenid,
            name = resolvedName,
            grade = resolvedGrade,
            gradeName = resolvedRole,
            workedSeconds = 0,
            lastDutyAt = nil
        }
        ServerCache.StaffHours[restaurantId][citizenid] = entry
    else
        entry.name = resolvedName
        entry.grade = resolvedGrade
        entry.gradeName = resolvedRole
    end

    if persistToDb and changed then
        CreateThread(function()
            PersistStaffHoursDelta(restaurantId, citizenid, resolvedName, resolvedGrade, resolvedRole, 0, false)
        end)
    end
    return entry
end

function FlushDutySession(src, stopSession, syncAwait)
    local sess = ActiveDutySessions[src]
    if not sess then return 0 end

    local now = os.time()
    local elapsed = math.max(0, now - (sess.startedAt or now))
    sess.startedAt = now

    local ply = GetPlayer(src)
    if ply and ply.PlayerData and ply.PlayerData.job then
        local jobResId = ResolveRestaurantForJob(ply.PlayerData.job.name)
        if jobResId == sess.restaurantId then
            local g, gn = ExtractJobGrade(ply.PlayerData.job)
            sess.name = GetPlayerFullName(src)
            sess.grade = g
            sess.gradeName = ResolveRoleLabel(sess.restaurantId, g, gn)
        end
    end

    local entry = EnsureStaffHoursEntry(sess.restaurantId, sess.citizenid, sess.name, sess.grade, sess.gradeName, false)
    if entry and elapsed > 0 then
        entry.workedSeconds = (entry.workedSeconds or 0) + elapsed
        entry.lastDutyAt = os.date('%Y-%m-%d %H:%M:%S', now)
    end

    if stopSession then
        ActiveDutySessions[src] = nil
    end

    if elapsed > 0 or stopSession then
        if syncAwait == 'fire' then
            PersistStaffHoursDelta(sess.restaurantId, sess.citizenid, sess.name, sess.grade, sess.gradeName, elapsed, true, true)
        elseif syncAwait then
            PersistStaffHoursDelta(sess.restaurantId, sess.citizenid, sess.name, sess.grade, sess.gradeName, elapsed, true, false)
        else
            CreateThread(function()
                PersistStaffHoursDelta(sess.restaurantId, sess.citizenid, sess.name, sess.grade, sess.gradeName, elapsed, true, false)
            end)
        end
    end
    return elapsed
end

function SyncPlayerDutySession(src)
    if not src or src <= 0 then return end
    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData then
        if ActiveDutySessions[src] then
            FlushDutySession(src, true, false)
        end
        return
    end

    local cid = ply.PlayerData.citizenid
    if not cid or cid == '' then return end

    local fullName = GetPlayerFullName(src)
    local primaryJob = ply.PlayerData.job
    local activeResId = primaryJob and ResolveRestaurantForJob(primaryJob.name) or nil

    -- Record any multi-job holdings for restaurants even if not currently primary
    if type(ply.PlayerData.jobs) == 'table' then
        for jobName, jobGrade in pairs(ply.PlayerData.jobs) do
            local rId = ResolveRestaurantForJob(jobName)
            if rId and rId ~= activeResId then
                EnsureStaffHoursEntry(rId, cid, fullName, tonumber(jobGrade) or 0, nil, true)
            end
        end
    end

    local existingSess = ActiveDutySessions[src]
    local isOnDutyPrimary = activeResId ~= nil and primaryJob.onduty == true

    if existingSess and (not isOnDutyPrimary or existingSess.restaurantId ~= activeResId or existingSess.citizenid ~= cid) then
        FlushDutySession(src, true, false)
        existingSess = nil
    end

    if not activeResId then return end

    local grade, gradeName = ExtractJobGrade(primaryJob)
    local roleLabel = ResolveRoleLabel(activeResId, grade, gradeName)
    EnsureStaffHoursEntry(activeResId, cid, fullName, grade, roleLabel, true)

    if isOnDutyPrimary then
        if not existingSess then
            ActiveDutySessions[src] = {
                restaurantId = activeResId,
                citizenid = cid,
                name = fullName,
                grade = grade,
                gradeName = roleLabel,
                startedAt = os.time()
            }
        else
            existingSess.name = fullName
            existingSess.grade = grade
            existingSess.gradeName = roleLabel
        end
    end
end

function GetLiveWorkedSeconds(restaurantId, citizenid)
    local cached = ServerCache.StaffHours[restaurantId] and ServerCache.StaffHours[restaurantId][citizenid]
    local total = cached and (tonumber(cached.workedSeconds) or 0) or 0
    local now = os.time()
    for _, sess in pairs(ActiveDutySessions) do
        if sess.restaurantId == restaurantId and sess.citizenid == citizenid then
            total = total + math.max(0, now - (sess.startedAt or now))
        end
    end
    return total
end

AddEventHandler('QBCore:Server:SetDuty', function(src)
    if src then SyncPlayerDutySession(src) end
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    if src then SyncPlayerDutySession(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    CreateThread(function()
        Wait(250)
        SyncPlayerDutySession(src)
    end)
end)

AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    if src then FlushDutySession(src, true, true) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if src then FlushDutySession(src, true, true) end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for src in pairs(ActiveDutySessions) do
        FlushDutySession(src, true, 'fire')
    end
end)

-- Periodically flush active duty work sessions to MySQL
CreateThread(function()
    while true do
        Wait(30000)
        for src in pairs(ActiveDutySessions) do
            FlushDutySession(src, false, false)
        end
    end
end)

-- Duty Toggle Event
RegisterNetEvent('restaurant_manager:server:toggleDuty', function(restaurantId)
    local src = source
    if not CheckRateLimit(src, 'toggleDuty', 2000) then return end

    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return end

    local ply = GetPlayer(src)
    if not ply or not ply.PlayerData or not ply.PlayerData.job then return end
    if ply.PlayerData.job.name ~= resConfig.job then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    -- Distance check to duty station (Owner can toggle from anywhere in restaurant)
    if not IsRestaurantOwner(src, restaurantId) and resConfig.dutyTarget and resConfig.dutyTarget.coords then
        if not ValidatePlayerDistance(src, resConfig.dutyTarget.coords, 3.5) then
            Notify(src, 'error', _L('too_far_away'))
            return
        end
    end

    local currentDuty = ply.PlayerData.job.onduty
    local newDuty = not currentDuty

    if ply.Functions and ply.Functions.SetJobDuty then
        ply.Functions.SetJobDuty(newDuty)
    elseif exports['qbx_core'] and exports['qbx_core'].SetJobDuty then
        exports['qbx_core']:SetJobDuty(src, newDuty)
    end

    SyncPlayerDutySession(src)

    if newDuty then
        Notify(src, 'success', _L('duty_on', resConfig.label))
    else
        Notify(src, 'info', _L('duty_off'))
    end
end)

-- ====================================================================
-- USABLE TABLET ITEMS REGISTRATION
-- ====================================================================
local tabletMap = {
    ['bs_tablet'] = nil,
    ['bs_owner_tablet'] = 'owner-tab',
    ['bs_manager_tablet'] = 'manager-tab',
    ['bs_employee_tablet'] = 'employee-tab'
}

CreateThread(function()
    Wait(1000)
    for itemName, targetTab in pairs(tabletMap) do
        -- Register with qbx_core
        if exports['qbx_core'] and exports['qbx_core'].CreateUseableItem then
            exports['qbx_core']:CreateUseableItem(itemName, function(source, item)
                TriggerClientEvent('restaurant_manager:client:openTablet', source, 'burgershot', targetTab)
            end)
        end
    end
end)

-- ox_inventory Usable Item Exports (Return false so the tablet is not consumed)
exports('bs_tablet', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        TriggerClientEvent('restaurant_manager:client:openTablet', inventory.player.source, 'burgershot', nil)
        return false
    end
end)

exports('bs_owner_tablet', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        TriggerClientEvent('restaurant_manager:client:openTablet', inventory.player.source, 'burgershot', 'owner-tab')
        return false
    end
end)

exports('bs_manager_tablet', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        TriggerClientEvent('restaurant_manager:client:openTablet', inventory.player.source, 'burgershot', 'manager-tab')
        return false
    end
end)

exports('bs_employee_tablet', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        TriggerClientEvent('restaurant_manager:client:openTablet', inventory.player.source, 'burgershot', 'employee-tab')
        return false
    end
end)

