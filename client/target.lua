-- ====================================================================
-- RESTAURANT MANAGER: CLIENT OX_TARGET INTEGRATION
-- Purely Event-Driven (Zero Idle Loops), Dynamic Zone Lifecycle
-- ====================================================================

local ActiveTargetZones = {} -- [key] = zoneId
local ClientAccessCache = { isAdmin = false, canManageStations = false, canManageVending = false, canVendingFund = false, canDoorUnlock = false }

local function RefreshClientAccessCache()
    local ok, access = pcall(function()
        return lib.callback.await('restaurant_manager:server:getClientAccess', false, 'burgershot')
    end)
    if ok and type(access) == 'table' then
        ClientAccessCache.isAdmin = access.isAdmin == true
        ClientAccessCache.canManageStations = access.canManageStations == true
        ClientAccessCache.canManageVending = access.canManageVending == true
        ClientAccessCache.canVendingFund = access.canVendingFund == true
        ClientAccessCache.canDoorUnlock = access.canDoorUnlock == true
    end
end

function HasRestaurantDoorUnlockAccess()
    return ClientAccessCache.isAdmin == true or ClientAccessCache.canDoorUnlock == true
end

CreateThread(function()
    Wait(500)
    RefreshClientAccessCache()
end)

local function formatItemLabel(itemName, oxDef)
    if oxDef and oxDef.label and oxDef.label ~= '' and oxDef.label ~= itemName then
        return oxDef.label
    end
    local cleaned = tostring(itemName or 'Item'):gsub('^bs_', '')
    cleaned = cleaned:gsub('_', ' ')
    return (cleaned:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

RegisterNetEvent('restaurant_manager:client:rolesUpdated', function()
    CreateThread(RefreshClientAccessCache)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    CreateThread(RefreshClientAccessCache)
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    CreateThread(RefreshClientAccessCache)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    CreateThread(RefreshClientAccessCache)
end)

RegisterNetEvent('qbx_core:client:jobUpdated', function()
    CreateThread(RefreshClientAccessCache)
end)

-- Cleanup All Registered Target Zones
local function CleanupAllZones()
    for key, zoneId in pairs(ActiveTargetZones) do
        if zoneId then
            pcall(function()
                exports.ox_target:removeZone(zoneId)
            end)
        end
    end
    ActiveTargetZones = {}
end

RegisterNetEvent('restaurant_manager:client:cleanupTargets', CleanupAllZones)

-- Open Cooking Station Web UI
local function OpenCookingMenu(restaurantId, stationId, stationType)
    local pData = GetPlayerData()
    local resConfig = Config.Restaurants[restaurantId]
    local isAdminUser = ClientAccessCache.isAdmin
    if not resConfig then return end

    if not isAdminUser and (not pData.job or pData.job.name ~= resConfig.job) then
        lib.notify({
            title = 'Cooking Station',
            description = 'Access Denied: You are not employed at this restaurant!',
            type = 'error'
        })
        return
    end

    local grade = 0
    if pData and pData.job then
        if type(pData.job.grade) == 'table' then
            grade = tonumber(pData.job.grade.level) or 0
        elseif type(pData.job.grade) == 'number' then
            grade = pData.job.grade
        end
    end

    local isOwnerDutyBypass = isAdminUser or (grade == (resConfig.ownerGrade or 9)) or (grade == (resConfig.adminGrade or 10))
    if not isAdminUser and (not pData.job or (not pData.job.onduty and not isOwnerDutyBypass)) then
        lib.notify({
            title = 'Cooking Station',
            description = 'You must clock in (Duty ON) before using this cooking station!',
            type = 'warning'
        })
        return
    end

    RefreshClientAccessCache()
    local canDeleteStation = ClientAccessCache.isAdmin or ClientAccessCache.canManageStations

    local recipes = lib.callback.await('restaurant_manager:server:getRecipes', false, restaurantId) or {}
    local stationConfig = Config.StationTypes[stationType] or {}
    local matchingRecipes = {}
    local inventoryCounts = {}
    local itemDetails = {}

    local oxItems = (exports.ox_inventory and exports.ox_inventory:Items()) or {}

    for id, rec in pairs(recipes) do
        if rec.station_type == stationType and rec.enabled then
            table.insert(matchingRecipes, rec)

            -- Cache output item details
            if rec.output_item and not itemDetails[rec.output_item] then
                local it = oxItems[rec.output_item]
                itemDetails[rec.output_item] = {
                    label = formatItemLabel(rec.output_item, it),
                    name = rec.output_item
                }
            end

            -- Cache ingredient item counts and details
            if type(rec.ingredients) == 'table' then
                for _, ing in ipairs(rec.ingredients) do
                    if not inventoryCounts[ing.item] then
                        local c = 0
                        pcall(function()
                            c = exports.ox_inventory:Search('count', ing.item) or 0
                        end)
                        inventoryCounts[ing.item] = c
                    end
                    if not itemDetails[ing.item] then
                        local it = oxItems[ing.item]
                        itemDetails[ing.item] = {
                            label = formatItemLabel(ing.item, it),
                            name = ing.item
                        }
                    end
                end
            end
        end
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openStationCooking',
        restaurantId = restaurantId,
        stationId = stationId,
        stationType = stationType,
        stationLabel = stationConfig.label or 'Cooking Station',
        stationIcon = stationConfig.icon or 'fas fa-fire-burner',
        isOwner = canDeleteStation,
        recipes = matchingRecipes,
        inventoryCounts = inventoryCounts,
        itemDetails = itemDetails
    })
end

-- Register a Station Zone in ox_target
local function RegisterStationZone(station)
    if not station or not station.coords or not station.id then return end
    local restaurantId = station.restaurant_id or 'burgershot'
    local zoneKey = string.format('station_%s_%s', restaurantId, station.id)

    -- Remove old zone if existing
    if ActiveTargetZones[zoneKey] then
        pcall(function() exports.ox_target:removeZone(ActiveTargetZones[zoneKey]) end)
        ActiveTargetZones[zoneKey] = nil
    end

    local c = station.coords
    local stType = station.station_type
    local stationConfig = Config.StationTypes[stType] or {}
    local resConfig = Config.Restaurants[restaurantId]
    local targetOptions = {}

    -- Admin & Role-based target checks (synced via server IsServerAdmin / HasPermission)
    local function isAdmin()
        return ClientAccessCache.isAdmin == true
    end

    -- Staff status check helper
    local function isStaff()
        if isAdmin() then return true end
        local ply = GetPlayerData()
        if not ply or not ply.job or not resConfig then return false end
        return ply.job.name == resConfig.job
    end

    local function isOwnerOnly()
        return isAdmin() or ClientAccessCache.canManageStations == true
    end

    -- 1. Main Action Option per Station / Zone Type
    if stType == 'counter' then
        -- Customer Ordering Counter (Open to everyone)
        table.insert(targetOptions, {
            name = zoneKey .. '_order',
            icon = stationConfig.icon or 'fas fa-cash-register',
            label = stationConfig.label or 'Order Food',
            distance = 3.5,
            onSelect = function()
                OpenCustomerMenu(restaurantId)
            end
        })
    elseif stType == 'vending' then
        -- Vending Machine Purchase (Open to everyone) & Manage Option (Requires vending_manage)
        table.insert(targetOptions, {
            name = zoneKey .. '_vending_buy',
            icon = stationConfig.icon or 'fas fa-cart-shopping',
            label = 'Buy from Vending Machine',
            distance = 3.5,
            onSelect = function()
                OpenVendingMenu(restaurantId)
            end
        })
        table.insert(targetOptions, {
            name = zoneKey .. '_vending_manage',
            icon = 'fas fa-boxes-stacked',
            label = 'Manage Vending Machine',
            distance = 3.5,
            onSelect = function()
                OpenManagementTerminal(restaurantId, 'manager-tab', 'manager-vending')
            end,
            canInteract = function()
                return isAdmin() or ClientAccessCache.canManageVending == true or ClientAccessCache.canVendingFund == true
            end
        })
    elseif stType == 'duty' then
        -- Staff Clock In / Out
        table.insert(targetOptions, {
            name = zoneKey .. '_duty',
            icon = stationConfig.icon or 'fas fa-business-time',
            label = stationConfig.label or 'Toggle Duty (Clock In / Out)',
            distance = 3.5,
            onSelect = function()
                TriggerServerEvent('restaurant_manager:server:toggleDuty', restaurantId)
            end,
            canInteract = function()
                return isStaff()
            end
        })
    elseif stType == 'terminal' then
        -- Management Tablet Terminal
        table.insert(targetOptions, {
            name = zoneKey .. '_terminal',
            icon = stationConfig.icon or 'fas fa-laptop-code',
            label = stationConfig.label or 'Open Restaurant Management',
            distance = 3.5,
            onSelect = function()
                OpenManagementTerminal(restaurantId)
            end,
            canInteract = function()
                return isStaff()
            end
        })
    elseif stType == 'tray' then
        -- Food Counter / Tray (Open to staff and customers)
        table.insert(targetOptions, {
            name = zoneKey .. '_tray',
            icon = stationConfig.icon or 'fas fa-utensils',
            label = stationConfig.label or 'Open Food Tray',
            distance = 3.5,
            onSelect = function()
                exports.ox_inventory:openInventory('stash', string.format('%s_tray_%d', restaurantId, station.id))
            end
        })
    elseif stType == 'storage' then
        -- Ingredient Storage / Fridge (Staff & Admins)
        table.insert(targetOptions, {
            name = zoneKey .. '_storage',
            icon = stationConfig.icon or 'fas fa-box-archive',
            label = stationConfig.label or 'Open Ingredient Storage',
            distance = 3.5,
            onSelect = function()
                exports.ox_inventory:openInventory('stash', string.format('%s_storage_%d', restaurantId, station.id))
            end,
            canInteract = function()
                return isStaff()
            end
        })
    else
        -- Cooking Stations (grill, assembly, fry, drinks, coffee, etc.)
        table.insert(targetOptions, {
            name = zoneKey .. '_cook',
            icon = stationConfig.icon or 'fas fa-fire-burner',
            label = stationConfig.label or 'Cooking Station',
            distance = 3.5,
            onSelect = function()
                OpenCookingMenu(restaurantId, station.id, stType)
            end,
            canInteract = function()
                return isStaff()
            end
        })
    end

    -- 2. Owner Removal Option on Zone
    table.insert(targetOptions, {
        name = zoneKey .. '_delete',
        icon = 'fas fa-trash-can',
        label = string.format('Delete %s (Owner)', stationConfig.label or 'Zone'),
        distance = 3.5,
        onSelect = function()
            local confirm = lib.alertDialog({
                header = 'Delete Zone / Station?',
                content = string.format('Are you sure you want to permanently delete this %s?', stationConfig.label or 'zone'),
                centered = true,
                cancel = true
            })
            if confirm == 'confirm' then
                TriggerServerEvent('restaurant_manager:server:deleteStation', {
                    restaurantId = restaurantId,
                    stationId = station.id
                })
            end
        end,
        canInteract = function()
            return isOwnerOnly()
        end
    })

    -- Safe coordinate extraction
    local posX = tonumber(c.x) or 0.0
    local posY = tonumber(c.y) or 0.0
    local posZ = tonumber(c.z) or 0.0
    local rotHeading = tonumber(c.heading) or 0.0
    local boxLength = tonumber(c.length or stationConfig.length) or 1.2
    local boxWidth = tonumber(c.width or stationConfig.width) or 1.0

    -- Register Box Zone with ox_target
    local zoneId = exports.ox_target:addBoxZone({
        name = zoneKey,
        coords = vec3(posX, posY, posZ + 0.35),
        size = vec3(boxLength, boxWidth, 1.4),
        rotation = rotHeading,
        debug = Config.Debug,
        options = targetOptions
    })

    ActiveTargetZones[zoneKey] = zoneId
end

-- ====================================================================
-- STATIC RESTAURANT ZONES INITIALIZATION (Optional Fallback)
-- ====================================================================
local function SetupStaticRestaurantZones()
    for resId, resConfig in pairs(Config.Restaurants) do
        -- 1. Customer Ordering Counters (if any defined in config)
        if resConfig.orderingCounters and #resConfig.orderingCounters > 0 then
            for idx, counter in ipairs(resConfig.orderingCounters) do
                local key = string.format('counter_%s_%d', resId, idx)
                if not ActiveTargetZones[key] then
                    local zoneId = exports.ox_target:addBoxZone({
                        coords = counter.coords,
                        size = counter.size or vec3(1.2, 0.8, 1.0),
                        rotation = counter.rotation or 0.0,
                        debug = Config.Debug,
                        options = {
                            {
                                name = key,
                                icon = 'fas fa-utensils',
                                label = counter.label or 'Order Food',
                                distance = Config.MaxCounterDistance or 3.2,
                                onSelect = function()
                                    OpenCustomerMenu(resId)
                                end
                            }
                        }
                    })
                    ActiveTargetZones[key] = zoneId
                end
            end
        end

        -- 2. Staff Duty Clock In / Out (if defined in config)
        if resConfig.dutyTarget and resConfig.dutyTarget.coords then
            local key = 'duty_' .. resId
            if not ActiveTargetZones[key] then
                local dt = resConfig.dutyTarget
                local zoneId = exports.ox_target:addBoxZone({
                    coords = dt.coords,
                    size = dt.size or vec3(0.8, 0.8, 1.0),
                    rotation = dt.rotation or 0.0,
                    debug = Config.Debug,
                    options = {
                        {
                            name = key,
                            icon = 'fas fa-business-time',
                            label = dt.label or 'Clock In / Out',
                            distance = 2.0,
                            onSelect = function()
                                TriggerServerEvent('restaurant_manager:server:toggleDuty', resId)
                            end,
                            canInteract = function()
                                local ply = GetPlayerData()
                                return ply.job and ply.job.name == resConfig.job
                            end
                        }
                    }
                })
                ActiveTargetZones[key] = zoneId
            end
        end

        -- 3. Management Terminal (if defined in config)
        if resConfig.managementTerminal and resConfig.managementTerminal.coords then
            local key = 'terminal_' .. resId
            if not ActiveTargetZones[key] then
                local mt = resConfig.managementTerminal
                local zoneId = exports.ox_target:addBoxZone({
                    coords = mt.coords,
                    size = mt.size or vec3(0.8, 0.8, 1.0),
                    rotation = mt.rotation or 0.0,
                    debug = Config.Debug,
                    options = {
                        {
                            name = key,
                            icon = 'fas fa-laptop-code',
                            label = mt.label or 'Staff Management',
                            distance = 2.0,
                            onSelect = function()
                                OpenManagementTerminal(resId)
                            end,
                            canInteract = function()
                                if ClientAccessCache.isAdmin then return true end
                                local ply = GetPlayerData()
                                if not ply.job or ply.job.name ~= resConfig.job then return false end
                                local isOwner = (tonumber(ply.job.grade and ply.job.grade.level) or 0) >= (resConfig.ownerGrade or 9)
                                return ply.job.onduty or isOwner
                            end
                        }
                    }
                })
                ActiveTargetZones[key] = zoneId
            end
        end
    end
end

-- ====================================================================
-- DYNAMIC STATIONS SYNC
-- ====================================================================
RegisterNetEvent('restaurant_manager:client:loadStations', function()
    CreateThread(RefreshClientAccessCache)
    SetupStaticRestaurantZones()

    local allStations = lib.callback.await('restaurant_manager:server:getAllStations', false) or {}
    for resId, stationList in pairs(allStations) do
        for sId, station in pairs(stationList) do
            station.restaurant_id = station.restaurant_id or resId
            RegisterStationZone(station)
        end
    end
end)

RegisterNetEvent('restaurant_manager:client:syncStation', function(stationData)
    RegisterStationZone(stationData)
    SendNUIMessage({
        action = 'stationAdded',
        station = stationData
    })
end)

RegisterNetEvent('restaurant_manager:client:removeStation', function(restaurantId, stationId)
    local zoneKey = string.format('station_%s_%s', restaurantId, stationId)
    if ActiveTargetZones[zoneKey] then
        pcall(function()
            exports.ox_target:removeZone(ActiveTargetZones[zoneKey])
        end)
        ActiveTargetZones[zoneKey] = nil
    end
    SendNUIMessage({
        action = 'stationRemoved',
        stationId = stationId
    })
end)

RegisterNetEvent('restaurant_manager:client:removeAllStations', function(restaurantId)
    for zoneKey, zoneId in pairs(ActiveTargetZones) do
        if string.find(zoneKey, 'station_' .. restaurantId) then
            pcall(function()
                exports.ox_target:removeZone(zoneId)
            end)
            ActiveTargetZones[zoneKey] = nil
        end
    end
    SendNUIMessage({
        action = 'allStationsRemoved'
    })
end)

-- Debug Command to visually inspect all registered Target Zones
RegisterCommand('bsdebug', function()
    Config.Debug = not Config.Debug
    lib.notify({
        title = 'Burger Shot Target Debug',
        description = 'Zone Wireframe Debug: ' .. (Config.Debug and 'ENABLED' or 'DISABLED'),
        type = Config.Debug and 'success' or 'info'
    })
    TriggerEvent('restaurant_manager:client:loadStations')
end, false)
