-- ====================================================================
-- RESTAURANT MANAGER: SERVER DOOR LOCKS ENGINE
-- Persistent Single/Double Doors, Toggle Permission & Client Sync
-- ====================================================================

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

-- ====================================================================
-- SAVE NEW DOOR LOCK (Admin / Owner Manage Stations)
-- ====================================================================
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
        leaves = leaves
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

-- ====================================================================
-- TOGGLE DOOR LOCK STATE ([E] IN-WORLD OR TABLET)
-- ====================================================================
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

    TriggerClientEvent('restaurant_manager:client:doorStateUpdated', -1, restaurantId, doorId, newLocked)

    LogAction(restaurantId, src, 'DOOR_TOGGLE', {
        door_id = doorId,
        label = door.label,
        locked = newLocked
    })

    return { ok = true, doorId = doorId, locked = newLocked, label = door.label }
end)

-- ====================================================================
-- DELETE DOOR LOCK
-- ====================================================================
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

    pcall(MySQL.query.await, 'DELETE FROM `rm_doors` WHERE `id` = ? AND `restaurant_id` = ?', { doorId, restaurantId })
    resDoors[doorId] = nil

    TriggerClientEvent('restaurant_manager:client:removeDoor', -1, restaurantId, doorId)

    LogAction(restaurantId, src, 'DOOR_DELETE', {
        door_id = doorId,
        label = targetDoor.label
    })

    Notify(src, 'info', string.format('Removed door lock: %s.', targetDoor.label or ('#' .. doorId)))
end)

-- ====================================================================
-- CLEAR ALL DOOR LOCKS FOR A RESTAURANT
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:deleteAllDoors', function(restaurantId)
    local src = source
    if not CheckRateLimit(src, 'deleteAllDoors', 1500) then return end

    local resId = restaurantId or 'burgershot'
    if not Config.Restaurants[resId] then return end

    if not HasPermission(src, resId, 'manage_stations') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    pcall(MySQL.query.await, 'DELETE FROM `rm_doors` WHERE `restaurant_id` = ?', { resId })
    ServerCache.Doors[resId] = {}

    TriggerClientEvent('restaurant_manager:client:removeAllDoors', -1, resId)

    LogAction(resId, src, 'DOORS_CLEAR_ALL', { message = 'Cleared all door locks.' })
    Notify(src, 'info', 'All restaurant door locks have been removed.')
end)

