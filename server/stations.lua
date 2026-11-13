-- ====================================================================
-- RESTAURANT MANAGER: SERVER STATIONS ENGINE
-- Zone-based Station Placement, Deletion, Validation & Client Sync
-- ====================================================================

-- Callback to Get All Stations for a Specific Restaurant
lib.callback.register('restaurant_manager:server:getStations', function(source, restaurantId)
    local stationList = {}
    if not restaurantId then
        for resId, stations in pairs(ServerCache.Stations or {}) do
            for _, st in pairs(stations) do
                table.insert(stationList, st)
            end
        end
        return stationList
    end

    local stations = ServerCache.Stations[restaurantId] or {}
    for _, st in pairs(stations) do
        table.insert(stationList, st)
    end
    -- Sort by ID ascending
    table.sort(stationList, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return stationList
end)

-- Callback to Get All Configured Stations (On Player Join)
lib.callback.register('restaurant_manager:server:getAllStations', function(source)
    return ServerCache.Stations or {}
end)

-- ====================================================================
-- SAVE NEW STATION (Owner Placement)
-- ====================================================================
local function SaveStationPlacement(src, payload)
    if not CheckRateLimit(src, 'saveStation', 1000) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    if EnsureDatabaseSchema then
        EnsureDatabaseSchema()
    end

    local restaurantId = payload.restaurantId
    local stationType = payload.stationType
    local rawCoords = payload.coords

    -- 1. Validate Manage Stations Permission (Admins bypass automatically inside HasPermission)
    if not HasPermission(src, restaurantId, 'manage_stations') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    -- 2. Validate Station Type Configuration
    local typeConfig = Config.StationTypes[stationType]
    if not typeConfig then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    -- 3. Check Maximum Station Limits
    local existingStations = ServerCache.Stations[restaurantId] or {}
    local currentTypeCount = 0
    for _, st in pairs(existingStations) do
        if st.station_type == stationType then
            currentTypeCount = currentTypeCount + 1
        end
    end

    local maxAllowed = typeConfig.maxPerRestaurant or 3
    if currentTypeCount >= maxAllowed then
        local limitMsg = _L('station_limit_reached', maxAllowed)
        Notify(src, 'error', limitMsg)
        return { ok = false, message = limitMsg }
    end

    -- 4. Validate Coordinates Sanity
    if type(rawCoords) ~= 'table' or not rawCoords.x or not rawCoords.y or not rawCoords.z then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    local sanitizedCoords = {
        x = tonumber(string.format('%.2f', rawCoords.x)),
        y = tonumber(string.format('%.2f', rawCoords.y)),
        z = tonumber(string.format('%.2f', rawCoords.z)),
        heading = tonumber(string.format('%.1f', rawCoords.heading or 0.0)),
        length = tonumber(rawCoords.length) or 1.2,
        width = tonumber(rawCoords.width) or 1.0,
        minZ = tonumber(string.format('%.2f', (rawCoords.z - 0.5))),
        maxZ = tonumber(string.format('%.2f', (rawCoords.z + 1.2)))
    }

    local citizenId = GetPlayerCitizenId(src) or 'UNKNOWN'
    local coordsJson = json.encode(sanitizedCoords)

    -- 5. Insert into Database
    local okInsert, stationId = pcall(MySQL.insert.await, [[
        INSERT INTO `rm_stations` (`restaurant_id`, `station_type`, `coords`, `created_by`) 
        VALUES (?, ?, ?, ?)
    ]], { restaurantId, stationType, coordsJson, citizenId })

    if not okInsert or not stationId then
        local dbErrMsg = 'Database error while saving zone! Please check server console.'
        print(string.format('^1[BurgerShot] Failed saving station (%s): %s^0', tostring(stationType), tostring(stationId)))
        Notify(src, 'error', dbErrMsg)
        return { ok = false, message = dbErrMsg }
    end

    -- 6. Update Cache
    local stationData = {
        id = stationId,
        restaurant_id = restaurantId,
        station_type = stationType,
        coords = sanitizedCoords,
        created_by = citizenId
    }

    ServerCache.Stations[restaurantId] = ServerCache.Stations[restaurantId] or {}
    ServerCache.Stations[restaurantId][stationId] = stationData

    -- Register ox_inventory stashes for trays and storages
    if exports.ox_inventory and exports.ox_inventory.RegisterStash then
        if stationType == 'tray' then
            exports.ox_inventory:RegisterStash(string.format('%s_tray_%d', restaurantId, stationId), 'Burger Shot - Food Tray', 15, 30000)
        elseif stationType == 'storage' then
            local resJob = (Config.Restaurants[restaurantId] and Config.Restaurants[restaurantId].job) or 'burgershot'
            exports.ox_inventory:RegisterStash(string.format('%s_storage_%d', restaurantId, stationId), 'Burger Shot - Storage', 60, 300000, nil, { [resJob] = 0 })
        end
    end

    -- 7. Broadcast to All Clients to Register ox_target Zone
    TriggerClientEvent('restaurant_manager:client:syncStation', -1, stationData)
    print(string.format('^2[BurgerShot] Station #%d (%s) placed by %s at (%.2f, %.2f, %.2f)^0', stationId, stationType, citizenId, sanitizedCoords.x, sanitizedCoords.y, sanitizedCoords.z))

    -- 8. Audit Log
    LogAction(restaurantId, src, 'STATION_CREATE', {
        station_id = stationId,
        station_type = stationType,
        coords = sanitizedCoords
    })

    Notify(src, 'success', _L('station_created', typeConfig.label or stationType))
    return { ok = true, station = stationData }
end

lib.callback.register('restaurant_manager:server:saveStation', function(source, payload)
    return SaveStationPlacement(source, payload)
end)

RegisterNetEvent('restaurant_manager:server:saveStation', function(payload)
    SaveStationPlacement(source, payload)
end)

-- ====================================================================
-- DELETE STATION (Owner Interaction)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:deleteStation', function(payload)
    local src = source
    if not CheckRateLimit(src, 'deleteStation', 1000) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local stationId = tonumber(payload.stationId)

    if not HasPermission(src, restaurantId, 'manage_stations') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    local existingStations = ServerCache.Stations[restaurantId]
    if not existingStations or not existingStations[stationId] then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local deletedStation = existingStations[stationId]

    -- Delete from Database
    MySQL.query('DELETE FROM `rm_stations` WHERE `id` = ? AND `restaurant_id` = ?', { stationId, restaurantId })

    -- Remove from Cache
    existingStations[stationId] = nil

    -- Broadcast Zone Removal to All Clients
    TriggerClientEvent('restaurant_manager:client:removeStation', -1, restaurantId, stationId)

    -- Audit Log
    LogAction(restaurantId, src, 'STATION_DELETE', {
        station_id = stationId,
        station_type = deletedStation.station_type
    })

    Notify(src, 'success', _L('station_deleted'))
end)

-- ====================================================================
-- DELETE ALL STATIONS & ZONES (Owner / Reset)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:deleteAllStations', function(restaurantId)
    local src = source
    if not CheckRateLimit(src, 'deleteAllStations', 1000) then return end
    restaurantId = restaurantId or 'burgershot'

    if not HasPermission(src, restaurantId, 'manage_stations') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    MySQL.query('DELETE FROM `rm_stations` WHERE `restaurant_id` = ?', { restaurantId })
    ServerCache.Stations[restaurantId] = {}

    TriggerClientEvent('restaurant_manager:client:removeAllStations', -1, restaurantId)

    LogAction(restaurantId, src, 'STATIONS_RESET', {
        message = 'All stations and zones removed by owner'
    })

    Notify(src, 'success', 'All target zones and stations have been cleared!')
end)

-- Command to wipe all stations and reset for placement
RegisterCommand('bsresetstations', function(source)
    local src = source
    if src > 0 then
        if not HasPermission(src, 'burgershot', 'manage_stations') then
            Notify(src, 'error', 'Only Admins or authorized Burger Shot roles can execute this command!')
            return
        end
    end
    MySQL.query('DELETE FROM `rm_stations` WHERE `restaurant_id` = ?', { 'burgershot' })
    ServerCache.Stations['burgershot'] = {}
    TriggerClientEvent('restaurant_manager:client:removeAllStations', -1, 'burgershot')
    if src > 0 then
        Notify(src, 'success', 'All Burger Shot third-eye zones and stations have been cleared!')
    else
        print('^2[BurgerShot] All stations cleared from database and clients.^0')
    end
end, false)

-- ====================================================================
-- RESTAURANT MANAGER: SERVER DOOR LOCKS ENGINE
-- Persistent Single/Double Doors, Toggle Permission & Client Sync
-- ====================================================================
do
    local DoorAutoLockTokens = {}
    local AUTO_LOCK_DELAY_MS = 5000

    local function getDoorTokenKey(restaurantId, doorId)
        return string.format('%s_%s', tostring(restaurantId or 'burgershot'), tostring(doorId))
    end

    local function cancelAutoLock(restaurantId, doorId)
        local key = getDoorTokenKey(restaurantId, doorId)
        DoorAutoLockTokens[key] = (DoorAutoLockTokens[key] or 0) + 1
    end

    local function scheduleAutoLock(restaurantId, doorId)
        local key = getDoorTokenKey(restaurantId, doorId)
        local token = (DoorAutoLockTokens[key] or 0) + 1
        DoorAutoLockTokens[key] = token

        SetTimeout(AUTO_LOCK_DELAY_MS, function()
            if DoorAutoLockTokens[key] ~= token then return end
            local resDoors = ServerCache.Doors[restaurantId]
            local door = resDoors and resDoors[doorId]
            if not door or door.autoLock ~= true or door.locked == true then return end

            door.locked = true
            pcall(MySQL.update.await, 'UPDATE `rm_doors` SET `locked` = 1 WHERE `id` = ? AND `restaurant_id` = ?', {
                doorId, restaurantId
            })
            TriggerClientEvent('restaurant_manager:client:doorStateUpdated', -1, restaurantId, doorId, true)
        end)
    end

    lib.callback.register('restaurant_manager:server:getDoors', function(source, restaurantId)
        local resId = restaurantId or 'burgershot'
        local doors = ServerCache.Doors[resId] or {}
        local doorList = {}
        for _, door in pairs(doors) do
            table.insert(doorList, door)
        end
        table.sort(doorList, function(a, b) return (a.id or 0) < (b.id or 0) end)
        return doorList
    end)

    lib.callback.register('restaurant_manager:server:getAllDoors', function(source)
        return ServerCache.Doors or {}
    end)

    lib.callback.register('restaurant_manager:server:saveDoor', function(source, payload)
        local src = source
        if not CheckRateLimit(src, 'saveDoor', 800) then
            return { ok = false, message = _L('rate_limited') }
        end

        if type(payload) ~= 'table' then
            Notify(src, 'error', _L('invalid_data'))
            return { ok = false, message = _L('invalid_data') }
        end

        if EnsureDatabaseSchema then
            EnsureDatabaseSchema()
        end

        local restaurantId = payload.restaurantId or 'burgershot'
        if not Config.Restaurants[restaurantId] then
            Notify(src, 'error', _L('restaurant_not_found'))
            return { ok = false, message = _L('restaurant_not_found') }
        end

        if not HasPermission(src, restaurantId, 'manage_stations') then
            Notify(src, 'error', _L('no_permission'))
            return { ok = false, message = _L('no_permission') }
        end

        local rawLeaves = payload.leaves
        if type(rawLeaves) ~= 'table' or #rawLeaves < 1 or #rawLeaves > 2 then
            Notify(src, 'error', 'Invalid door selection.')
            return { ok = false, message = 'Invalid door selection.' }
        end

        local leaves = {}
        local sumX, sumY, sumZ = 0.0, 0.0, 0.0
        for _, leaf in ipairs(rawLeaves) do
            local model = tonumber(leaf.model)
            local c = leaf.coords
            if not model or model == 0 or type(c) ~= 'table' or not c.x or not c.y or not c.z then
                Notify(src, 'error', 'Invalid door model or coordinates.')
                return { ok = false, message = 'Invalid door model or coordinates.' }
            end
            local lx = tonumber(string.format('%.3f', c.x))
            local ly = tonumber(string.format('%.3f', c.y))
            local lz = tonumber(string.format('%.3f', c.z))
            sumX = sumX + lx
            sumY = sumY + ly
            sumZ = sumZ + lz
            table.insert(leaves, {
                model = model,
                coords = { x = lx, y = ly, z = lz }
            })
        end

        local leafCount = #leaves
        local centerCoords = {
            x = tonumber(string.format('%.3f', sumX / leafCount)),
            y = tonumber(string.format('%.3f', sumY / leafCount)),
            z = tonumber(string.format('%.3f', sumZ / leafCount))
        }

        local isDouble = leafCount > 1
        local existingCount = 0
        for _ in pairs(ServerCache.Doors[restaurantId] or {}) do
            existingCount = existingCount + 1
        end

        local rawLabel = tostring(payload.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if rawLabel == '' then
            rawLabel = string.format('Door #%d', existingCount + 1)
        end
        if #rawLabel > 60 then
            rawLabel = rawLabel:sub(1, 60)
        end

        local initialLocked = (payload.locked ~= false)
        local maxDistance = isDouble and 2.6 or 2.2
        local doorPayload = {
            coords = centerCoords,
            maxDistance = maxDistance,
            isDouble = isDouble,
            leaves = leaves,
            autoLock = false
        }

        local citizenId = GetPlayerCitizenId(src) or 'UNKNOWN'
        local doorJson = json.encode(doorPayload)

        local okInsert, doorId = pcall(MySQL.insert.await, [[
            INSERT INTO `rm_doors` (`restaurant_id`, `label`, `door_data`, `locked`, `created_by`)
            VALUES (?, ?, ?, ?, ?)
        ]], { restaurantId, rawLabel, doorJson, initialLocked and 1 or 0, citizenId })

        if not okInsert or not doorId then
            local dbErr = 'Database error while saving door lock!'
            Notify(src, 'error', dbErr)
            return { ok = false, message = dbErr }
        end

        local doorData = {
            id = doorId,
            restaurant_id = restaurantId,
            label = rawLabel,
            coords = centerCoords,
            maxDistance = maxDistance,
            isDouble = isDouble,
            leaves = leaves,
            locked = initialLocked,
            autoLock = false,
            created_by = citizenId
        }

        ServerCache.Doors[restaurantId] = ServerCache.Doors[restaurantId] or {}
        ServerCache.Doors[restaurantId][doorId] = doorData

        TriggerClientEvent('restaurant_manager:client:syncDoor', -1, doorData)

        LogAction(restaurantId, src, 'DOOR_PLACE', {
            door_id = doorId,
            label = rawLabel,
            is_double = isDouble,
            coords = centerCoords
        })

        Notify(src, 'success', string.format('%s (%s) saved and %s!', rawLabel, isDouble and 'Double Door' or 'Single Door', initialLocked and 'locked' or 'unlocked'))
        return { ok = true, door = doorData }
    end)

    lib.callback.register('restaurant_manager:server:toggleDoor', function(source, payload)
        local src = source
        if not CheckRateLimit(src, 'toggleDoor', 350) then
            return { ok = false, message = _L('rate_limited') }
        end

        local restaurantId = (type(payload) == 'table' and payload.restaurantId) or 'burgershot'
        local doorId = type(payload) == 'table' and tonumber(payload.doorId) or tonumber(payload)

        if not Config.Restaurants[restaurantId] or not doorId then
            return { ok = false, message = _L('invalid_data') }
        end

        if not HasPermission(src, restaurantId, 'door_unlock') then
            Notify(src, 'error', _L('no_permission'))
            return { ok = false, message = _L('no_permission') }
        end

        local resDoors = ServerCache.Doors[restaurantId]
        local door = resDoors and resDoors[doorId]
        if not door then
            return { ok = false, message = 'Door not found.' }
        end

        local newLocked = not (door.locked == true)
        door.locked = newLocked

        pcall(MySQL.update.await, 'UPDATE `rm_doors` SET `locked` = ? WHERE `id` = ? AND `restaurant_id` = ?', {
            newLocked and 1 or 0, doorId, restaurantId
        })

        if newLocked then
            cancelAutoLock(restaurantId, doorId)
        elseif door.autoLock == true then
            scheduleAutoLock(restaurantId, doorId)
        end

        TriggerClientEvent('restaurant_manager:client:doorStateUpdated', -1, restaurantId, doorId, newLocked)

        LogAction(restaurantId, src, 'DOOR_TOGGLE', {
            door_id = doorId,
            label = door.label,
            locked = newLocked
        })

        return { ok = true, doorId = doorId, locked = newLocked, autoLock = door.autoLock == true, label = door.label }
    end)

    lib.callback.register('restaurant_manager:server:toggleDoorAutoLock', function(source, payload)
        local src = source
        if not CheckRateLimit(src, 'toggleDoorAutoLock', 350) then
            return { ok = false, message = _L('rate_limited') }
        end

        local restaurantId = (type(payload) == 'table' and payload.restaurantId) or 'burgershot'
        local doorId = type(payload) == 'table' and tonumber(payload.doorId) or tonumber(payload)

        if not Config.Restaurants[restaurantId] or not doorId then
            return { ok = false, message = _L('invalid_data') }
        end

        if not HasPermission(src, restaurantId, 'manage_stations') then
            Notify(src, 'error', _L('no_permission'))
            return { ok = false, message = _L('no_permission') }
        end

        local resDoors = ServerCache.Doors[restaurantId]
        local door = resDoors and resDoors[doorId]
        if not door then
            return { ok = false, message = 'Door not found.' }
        end

        local newAutoLock = not (door.autoLock == true)
        door.autoLock = newAutoLock

        local updatedJson = json.encode({
            coords = door.coords,
            maxDistance = door.maxDistance,
            isDouble = door.isDouble,
            leaves = door.leaves,
            autoLock = newAutoLock
        })
        pcall(MySQL.update.await, 'UPDATE `rm_doors` SET `door_data` = ? WHERE `id` = ? AND `restaurant_id` = ?', {
            updatedJson, doorId, restaurantId
        })

        if newAutoLock then
            if door.locked ~= true then
                scheduleAutoLock(restaurantId, doorId)
            end
        else
            cancelAutoLock(restaurantId, doorId)
        end

        TriggerClientEvent('restaurant_manager:client:doorAutoLockUpdated', -1, restaurantId, doorId, newAutoLock)

        LogAction(restaurantId, src, 'DOOR_AUTOLOCK', {
            door_id = doorId,
            label = door.label,
            auto_lock = newAutoLock
        })

        Notify(src, 'info', string.format('%s Auto Lock %s.', door.label or ('Door #' .. doorId), newAutoLock and 'enabled (5s)' or 'disabled'))
        return { ok = true, doorId = doorId, autoLock = newAutoLock }
    end)

    RegisterNetEvent('restaurant_manager:server:deleteDoor', function(payload)
        local src = source
        if not CheckRateLimit(src, 'deleteDoor', 500) then return end
        if type(payload) ~= 'table' then return end

        local restaurantId = payload.restaurantId or 'burgershot'
        local doorId = tonumber(payload.doorId)
        if not Config.Restaurants[restaurantId] or not doorId then return end

        if not HasPermission(src, restaurantId, 'manage_stations') then
            Notify(src, 'error', _L('no_permission'))
            return
        end

        local resDoors = ServerCache.Doors[restaurantId]
        local targetDoor = resDoors and resDoors[doorId]
        if not targetDoor then return end

        cancelAutoLock(restaurantId, doorId)
        pcall(MySQL.query.await, 'DELETE FROM `rm_doors` WHERE `id` = ? AND `restaurant_id` = ?', { doorId, restaurantId })
        resDoors[doorId] = nil

        TriggerClientEvent('restaurant_manager:client:removeDoor', -1, restaurantId, doorId)

        LogAction(restaurantId, src, 'DOOR_DELETE', {
            door_id = doorId,
            label = targetDoor.label
        })

        Notify(src, 'info', string.format('Removed door lock: %s.', targetDoor.label or ('#' .. doorId)))
    end)

    RegisterNetEvent('restaurant_manager:server:deleteAllDoors', function(restaurantId)
        local src = source
        if not CheckRateLimit(src, 'deleteAllDoors', 1500) then return end

        local resId = restaurantId or 'burgershot'
        if not Config.Restaurants[resId] then return end

        if not HasPermission(src, resId, 'manage_stations') then
            Notify(src, 'error', _L('no_permission'))
            return
        end

        for dId, _ in pairs(ServerCache.Doors[resId] or {}) do
            cancelAutoLock(resId, dId)
        end
        pcall(MySQL.query.await, 'DELETE FROM `rm_doors` WHERE `restaurant_id` = ?', { resId })
        ServerCache.Doors[resId] = {}

        TriggerClientEvent('restaurant_manager:client:removeAllDoors', -1, resId)

        LogAction(resId, src, 'DOORS_CLEAR_ALL', { message = 'Cleared all door locks.' })
        Notify(src, 'info', 'All restaurant door locks have been removed.')
    end)
end
