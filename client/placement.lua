-- ====================================================================
-- RESTAURANT MANAGER: CLIENT STATION & ZONE PLACEMENT SYSTEM (Owner Mode)
-- High-Precision Raycasting with 3D Visualizer & Floating Labels
-- ====================================================================

local isPlacing = false

-- Convert Camera Rotation (Pitch, Roll, Yaw) to Normalized Forward Direction Vector
local function RotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- Raycast from Gameplay Camera into Game World
local function RaycastCamera(maxDistance)
    local camRot = GetGameplayCamRot(2)
    local camCoord = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)
    local dest = camCoord + (dir * maxDistance)

    -- Test world geometry, vehicles, and objects (1 | 2 | 16)
    local ray = StartShapeTestSweptSphere(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        0.15,
        1 | 2 | 16,
        PlayerPedId(),
        4
    )
    local _, hit, hitCoords, surfaceNormal = GetShapeTestResult(ray)

    if hit == 1 and hitCoords and hitCoords.x ~= 0.0 then
        return true, hitCoords, surfaceNormal
    end

    -- Secondary raycast fallback
    local ray2 = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        -1,
        PlayerPedId(),
        0
    )
    local _, hit2, hitCoords2 = GetShapeTestResult(ray2)
    if hit2 == 1 and hitCoords2 and hitCoords2.x ~= 0.0 then
        return true, hitCoords2, nil
    end

    -- Project 2.5 meters in front of the player if pointing into empty space
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local pedFwd = GetEntityForwardVector(ped)
    local fallbackCoords = pedCoords + (pedFwd * 2.5)
    return false, fallbackCoords, nil
end

-- Draw 3D Placement Visualizer with Floor Ring, Sphere, Arrow & 3D Floating Label
local function DrawPlacementBox(coords, heading, length, width, height, r, g, b, a, label)
    local rad = math.rad(heading)
    local cosH = math.cos(rad)
    local sinH = math.sin(rad)

    -- 1. Outer Ground Cylinder Ring (Marker 1)
    DrawMarker(
        1,
        coords.x, coords.y, coords.z - 0.05,
        0.0, 0.0, 0.0,
        0.0, 0.0, heading,
        length, width, 0.25,
        r, g, b, a,
        false, false, 2, false, nil, nil, false
    )

    -- 2. Glowing Center Marker (Marker 28)
    DrawMarker(
        28,
        coords.x, coords.y, coords.z + 0.35,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.2, 0.2, 0.2,
        r, g, b, 220,
        false, false, 2, false, nil, nil, false
    )

    -- 3. Direction Pointer Arrow (Marker 2)
    local arrowX = coords.x + (-sinH * (length * 0.55))
    local arrowY = coords.y + (cosH * (length * 0.55))
    DrawMarker(
        2,
        arrowX, arrowY, coords.z + 0.35,
        0.0, 0.0, 0.0,
        0.0, 180.0, heading,
        0.35, 0.35, 0.35,
        r, g, b, 230,
        false, false, 2, false, nil, nil, false
    )

    -- 4. 3D Floating Text Label
    SetDrawOrigin(coords.x, coords.y, coords.z + 0.70, 0)
    BeginTextCommandDisplayText("STRING")
    SetTextScale(0.0, 0.36)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(r, g, b, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(1)
    AddTextComponentString(label or "Placement Zone")
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- ====================================================================
-- START PLACEMENT SESSION
-- ====================================================================
RegisterNetEvent('restaurant_manager:client:startPlacement', function(restaurantId, stationType)
    if isPlacing then return end

    local stationConfig = Config.StationTypes[stationType]
    if not stationConfig then return end

    isPlacing = true
    local heading = GetEntityHeading(PlayerPedId())
    local length = tonumber(stationConfig.length) or 1.2
    local width = tonumber(stationConfig.width) or 1.0
    local height = 0.8
    local label = stationConfig.label or 'Zone'

    lib.showTextUI(string.format('[E] Place %s  |  [Scroll / ← →] Rotate  |  [X] Cancel', label), {
        position = 'top-center',
        icon = stationConfig.icon or 'fas fa-arrows-up-down-left-right'
    })

    CreateThread(function()
        while isPlacing do
            Wait(0)

            -- Disable attack/combat controls so player does not punch while interacting
            DisableControlAction(0, 24, true)  -- Attack
            DisableControlAction(0, 25, true)  -- Aim
            DisableControlAction(0, 140, true) -- Light Melee

            local hit, hitCoords = RaycastCamera(20.0)
            local pCoords = GetEntityCoords(PlayerPedId())
            local isValid = false

            if hit and hitCoords and #(pCoords - hitCoords) <= 8.5 then
                isValid = true
            end

            -- Color: Vibrant Green if valid, Vibrant Red if out of range
            local r, g, b = 239, 68, 68
            if isValid then
                r, g, b = 34, 197, 94
            end

            if hitCoords then
                DrawPlacementBox(hitCoords, heading, length, width, height, r, g, b, 160, label)
            end

            -- Controls Handling
            -- Scroll Up / Right Arrow -> Rotate Right
            if IsControlJustPressed(0, 175) or IsControlJustPressed(0, 241) then
                heading = (heading + 5.0) % 360.0
            end

            -- Scroll Down / Left Arrow -> Rotate Left
            if IsControlJustPressed(0, 174) or IsControlJustPressed(0, 242) then
                heading = (heading - 5.0) % 360.0
            end

            -- [E] (Control 38) -> Confirm Placement
            if IsControlJustPressed(0, 38) then
                if isValid and hitCoords then
                    isPlacing = false
                    lib.hideTextUI()

                    local result = lib.callback.await('restaurant_manager:server:saveStation', false, {
                        restaurantId = restaurantId,
                        stationType = stationType,
                        coords = {
                            x = hitCoords.x,
                            y = hitCoords.y,
                            z = hitCoords.z,
                            heading = heading,
                            length = length,
                            width = width
                        }
                    })

                    if not result then
                        lib.notify({
                            title = 'Station Placement',
                            description = 'Server did not respond while saving zone!',
                            type = 'error'
                        })
                    end
                    break
                else
                    lib.notify({
                        title = 'Station Placement',
                        description = 'Placement location is invalid or too far away! Move closer to the surface.',
                        type = 'error'
                    })
                end
            end

            -- [X] (Control 73) or Backspace (Control 177) -> Cancel
            if IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177) then
                isPlacing = false
                lib.hideTextUI()
                lib.notify({
                    title = 'Station Placement',
                    description = 'Placement cancelled.',
                    type = 'info'
                })
                break
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName and isPlacing then
        isPlacing = false
        lib.hideTextUI()
    end
end)

-- ====================================================================
-- RESTAURANT MANAGER: CLIENT DOOR LOCKS & 3D DOOR PICKER
-- Handles Single/Double Doors, GTA DoorSystem State & [E] Interaction
-- ====================================================================
do
    local RegisteredDoors = {}
    local RegisteredHashes = {}
    local isPickingDoor = false
    local showingDoorUi = false
    local lastDoorUiText = nil
    local lastToggleAt = 0
    local lastLocalToneDoorKey = nil
    local lastLocalToneAt = 0

    local function triggerDoorTone(locked, volume)
        SendNUIMessage({
            action = 'playDoorTone',
            locked = locked == true,
            volume = tonumber(volume) or 1.0
        })
    end

    local function makeDoorKey(restaurantId, doorId)
        return string.format('%s_%s', tostring(restaurantId or 'burgershot'), tostring(doorId))
    end

    local function makeLeafHash(restaurantId, doorId, leafIdx)
        return GetHashKey(string.format('rm_door_%s_%s_%s', tostring(restaurantId or 'burgershot'), tostring(doorId), tostring(leafIdx)))
    end

    local function unregisterDoor(doorKey)
        local hashes = RegisteredHashes[doorKey]
        if type(hashes) == 'table' then
            for _, hash in ipairs(hashes) do
                if IsDoorRegisteredWithSystem(hash) then
                    DoorSystemSetDoorState(hash, 0, false, false)
                    RemoveDoorFromSystem(hash)
                end
            end
        end
        RegisteredHashes[doorKey] = nil
        RegisteredDoors[doorKey] = nil
    end

    local function applyDoorToSystem(door)
        if not door or not door.id or type(door.leaves) ~= 'table' or #door.leaves == 0 then return end
        local resId = door.restaurant_id or 'burgershot'
        local doorKey = makeDoorKey(resId, door.id)

        local c = door.coords or door.leaves[1].coords
        door.centerVec = vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
        door.restaurant_id = resId
        RegisteredDoors[doorKey] = door

        local hashes = RegisteredHashes[doorKey]
        if not hashes then
            hashes = {}
            for idx, leaf in ipairs(door.leaves) do
                local lc = leaf.coords
                local model = tonumber(leaf.model)
                if model and lc then
                    local hash = makeLeafHash(resId, door.id, idx)
                    AddDoorToSystem(hash, model, tonumber(lc.x) + 0.0, tonumber(lc.y) + 0.0, tonumber(lc.z) + 0.0, false, false, false)
                    DoorSystemSetDoorState(hash, 4, false, false)
                    DoorSystemSetAutomaticRate(hash, 10.0, false, false)
                    table.insert(hashes, hash)
                end
            end
            RegisteredHashes[doorKey] = hashes
        end

        local state = door.locked and 1 or 0
        for _, hash in ipairs(hashes) do
            DoorSystemSetDoorState(hash, state, false, false)
        end
    end

    local function clearAllDoorsForRestaurant(restaurantId)
        local prefix = tostring(restaurantId or 'burgershot') .. '_'
        for doorKey, _ in pairs(RegisteredDoors) do
            if string.sub(doorKey, 1, #prefix) == prefix then
                unregisterDoor(doorKey)
            end
        end
    end

    local function hideDoorTextUiIfShown()
        if showingDoorUi then
            showingDoorUi = false
            lastDoorUiText = nil
            lib.hideTextUI()
        end
    end

    RegisterNetEvent('restaurant_manager:client:loadDoors', function()
        local ok, allDoors = pcall(lib.callback.await, 'restaurant_manager:server:getAllDoors', false)
        if not ok or type(allDoors) ~= 'table' then return end
        for resId, doorList in pairs(allDoors) do
            if type(doorList) == 'table' then
                for _, door in pairs(doorList) do
                    door.restaurant_id = door.restaurant_id or resId
                    applyDoorToSystem(door)
                end
            end
        end
    end)

    RegisterNetEvent('restaurant_manager:client:syncDoor', function(doorData)
        if not doorData then return end
        applyDoorToSystem(doorData)
        SendNUIMessage({
            action = 'doorAdded',
            door = doorData
        })
    end)

    RegisterNetEvent('restaurant_manager:client:doorStateUpdated', function(restaurantId, doorId, locked)
        local doorKey = makeDoorKey(restaurantId, doorId)
        local door = RegisteredDoors[doorKey]
        local isLocked = locked == true
        if door then
            door.locked = isLocked
            applyDoorToSystem(door)

            local now = GetGameTimer()
            local recentlyPlayedLocally = (lastLocalToneDoorKey == doorKey) and ((now - lastLocalToneAt) < 1200)
            if not recentlyPlayedLocally and door.centerVec then
                local dist = #(GetEntityCoords(PlayerPedId()) - door.centerVec)
                if dist <= 8.5 then
                    local vol = math.max(0.25, math.min(1.0, 1.0 - (dist / 10.0)))
                    triggerDoorTone(isLocked, vol)
                end
            end
        end
        SendNUIMessage({
            action = 'doorStateUpdated',
            restaurantId = restaurantId,
            doorId = doorId,
            locked = isLocked
        })
    end)

    RegisterNetEvent('restaurant_manager:client:doorAutoLockUpdated', function(restaurantId, doorId, autoLock)
        local doorKey = makeDoorKey(restaurantId, doorId)
        local door = RegisteredDoors[doorKey]
        local isAuto = autoLock == true
        if door then
            door.autoLock = isAuto
        end
        SendNUIMessage({
            action = 'doorAutoLockUpdated',
            restaurantId = restaurantId,
            doorId = doorId,
            autoLock = isAuto
        })
    end)

    RegisterNetEvent('restaurant_manager:client:removeDoor', function(restaurantId, doorId)
        local doorKey = makeDoorKey(restaurantId, doorId)
        unregisterDoor(doorKey)
        hideDoorTextUiIfShown()
        SendNUIMessage({
            action = 'doorRemoved',
            restaurantId = restaurantId,
            doorId = doorId
        })
    end)

    RegisterNetEvent('restaurant_manager:client:removeAllDoors', function(restaurantId)
        clearAllDoorsForRestaurant(restaurantId)
        hideDoorTextUiIfShown()
        SendNUIMessage({
            action = 'allDoorsRemoved',
            restaurantId = restaurantId
        })
    end)

    CreateThread(function()
        while true do
            local sleep = 500
            if not isPickingDoor and next(RegisteredDoors) ~= nil then
                local ped = PlayerPedId()
                local pedCoords = GetEntityCoords(ped)
                local closestDoor = nil
                local closestDist = 999.0

                for _, door in pairs(RegisteredDoors) do
                    if door.centerVec then
                        local d = #(pedCoords - door.centerVec)
                        if d < closestDist then
                            closestDist = d
                            closestDoor = door
                        end
                    end
                end

                if closestDoor and closestDist <= 10.0 then
                    sleep = 150
                    local maxDist = tonumber(closestDoor.maxDistance) or (closestDoor.isDouble and 2.6 or 2.2)

                    if closestDist <= maxDist and not IsPauseMenuActive() and not IsPedInAnyVehicle(ped, false) then
                        sleep = 0
                        local hasKey = HasRestaurantDoorUnlockAccess and HasRestaurantDoorUnlockAccess()

                        if hasKey then
                            local prompt = closestDoor.locked
                                and ('[E] Unlock ' .. (closestDoor.label or 'Door'))
                                or ('[E] Lock ' .. (closestDoor.label or 'Door'))

                            if not showingDoorUi or lastDoorUiText ~= prompt then
                                showingDoorUi = true
                                lastDoorUiText = prompt
                                lib.showTextUI(prompt, {
                                    position = 'left-center',
                                    icon = closestDoor.locked and 'lock' or 'lock-open',
                                    iconColor = closestDoor.locked and '#ef4444' or '#22c55e'
                                })
                            end

                            if IsControlJustPressed(0, 38) then
                                local now = GetGameTimer()
                                if (now - lastToggleAt) >= 400 then
                                    lastToggleAt = now
                                    local res = lib.callback.await('restaurant_manager:server:toggleDoor', false, {
                                        restaurantId = closestDoor.restaurant_id or 'burgershot',
                                        doorId = closestDoor.id
                                    })
                                    if res and res.ok then
                                        lastLocalToneDoorKey = makeDoorKey(closestDoor.restaurant_id or 'burgershot', closestDoor.id)
                                        lastLocalToneAt = GetGameTimer()
                                        triggerDoorTone(res.locked == true, 1.0)
                                    end
                                end
                            end
                        elseif closestDoor.locked and closestDist <= 1.6 then
                            local prompt = 'Locked - ' .. (closestDoor.label or 'Door')
                            if not showingDoorUi or lastDoorUiText ~= prompt then
                                showingDoorUi = true
                                lastDoorUiText = prompt
                                lib.showTextUI(prompt, {
                                    position = 'left-center',
                                    icon = 'lock',
                                    iconColor = '#ef4444'
                                })
                            end
                        else
                            hideDoorTextUiIfShown()
                        end
                    else
                        hideDoorTextUiIfShown()
                    end
                else
                    hideDoorTextUiIfShown()
                end
            else
                hideDoorTextUiIfShown()
            end
            Wait(sleep)
        end
    end)

    local function rotToDirDoor(rot)
        local z = math.rad(rot.z)
        local x = math.rad(rot.x)
        local num = math.abs(math.cos(x))
        return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
    end

    local function DrawDoorMarkerLabel(coords, text, r, g, b)
        DrawMarker(28, coords.x, coords.y, coords.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.14, 0.14, 0.14, r, g, b, 220, false, false, 2, false, nil, nil, false)
        SetDrawOrigin(coords.x, coords.y, coords.z + 1.25, 0)
        BeginTextCommandDisplayText('STRING')
        SetTextScale(0.0, 0.34)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(r, g, b, 255)
        SetTextOutline()
        SetTextCentre(1)
        AddTextComponentString(text)
        EndTextCommandDisplayText(0.0, 0.0)
        ClearDrawOrigin()
    end

    local function RaycastDoorObject()
        local ped = PlayerPedId()
        local camCoord = GetGameplayCamCoord()
        local dir = rotToDirDoor(GetGameplayCamRot(2))
        local dest = camCoord + (dir * 12.0)

        local rayObj = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, 16, ped, 4)
        local _, hitObj, hitCoordsObj, _, entObj = GetShapeTestResult(rayObj)
        if hitObj == 1 and entObj and entObj ~= 0 and DoesEntityExist(entObj) and GetEntityType(entObj) == 3 then
            return entObj, hitCoordsObj
        end

        local rayAll = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, -1, ped, 4)
        local _, hitAll, hitCoordsAll, _, entAll = GetShapeTestResult(rayAll)
        if hitAll == 1 then
            if entAll and entAll ~= 0 and DoesEntityExist(entAll) and GetEntityType(entAll) == 3 then
                return entAll, hitCoordsAll
            end
            if hitCoordsAll and hitCoordsAll.x ~= 0.0 then
                local objects = GetGamePool('CObject')
                local bestEnt, bestDist = nil, 1.35
                for i = 1, #objects do
                    local obj = objects[i]
                    if DoesEntityExist(obj) and not IsEntityAttached(obj) then
                        local oc = GetEntityCoords(obj)
                        local d = #(hitCoordsAll - oc)
                        if d < bestDist then
                            bestDist = d
                            bestEnt = obj
                        end
                    end
                end
                if bestEnt then
                    return bestEnt, GetEntityCoords(bestEnt)
                end
            end
        end

        return nil, nil
    end

    RegisterNetEvent('restaurant_manager:client:startDoorPlacement', function(restaurantId, doorLabel)
        if isPickingDoor then return end
        isPickingDoor = true
        hideDoorTextUiIfShown()

        local resId = restaurantId or 'burgershot'
        local firstLeaf = nil
        lib.showTextUI('[E] Select Door (Aim at door)  |  [X] Cancel', { position = 'top-center', icon = 'door-closed' })

        CreateThread(function()
            while isPickingDoor do
                Wait(0)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)

                local ped = PlayerPedId()
                local pCoords = GetEntityCoords(ped)
                local aimedEnt, hitCoords = RaycastDoorObject()
                local isAimValid = false

                if aimedEnt and DoesEntityExist(aimedEnt) then
                    local entCoords = GetEntityCoords(aimedEnt)
                    if #(pCoords - entCoords) <= 8.5 then
                        if not firstLeaf or aimedEnt ~= firstLeaf.entity then
                            isAimValid = true
                            DrawDoorMarkerLabel(entCoords, firstLeaf and '2nd Door Leaf ([E] Select)' or 'Door Detected ([E] Select)', 34, 197, 94)
                        else
                            DrawDoorMarkerLabel(entCoords, 'Door #1 Selected', 59, 130, 246)
                        end
                    end
                elseif hitCoords then
                    DrawDoorMarkerLabel(hitCoords, 'Aim Closer at a Door Prop', 239, 68, 68)
                end

                if firstLeaf then
                    DrawDoorMarkerLabel(firstLeaf.vec, 'Door #1 Selected', 59, 130, 246)
                end

                if IsControlJustPressed(0, 38) then
                    if isAimValid and aimedEnt then
                        local entCoords = GetEntityCoords(aimedEnt)
                        local model = GetEntityModel(aimedEnt)
                        if not firstLeaf then
                            firstLeaf = {
                                entity = aimedEnt,
                                model = model,
                                vec = entCoords,
                                coords = { x = entCoords.x, y = entCoords.y, z = entCoords.z }
                            }
                            lib.showTextUI('[G] Save Single Door  |  [E] Select 2nd Door (Double)  |  [X] Cancel', {
                                position = 'top-center',
                                icon = 'door-open'
                            })
                        else
                            isPickingDoor = false
                            lib.hideTextUI()
                            local secondLeaf = {
                                model = model,
                                coords = { x = entCoords.x, y = entCoords.y, z = entCoords.z }
                            }
                            lib.callback.await('restaurant_manager:server:saveDoor', false, {
                                restaurantId = resId,
                                label = doorLabel,
                                locked = true,
                                leaves = {
                                    { model = firstLeaf.model, coords = firstLeaf.coords },
                                    secondLeaf
                                }
                            })
                            break
                        end
                    else
                        lib.notify({
                            title = 'Door Lock Placement',
                            description = firstLeaf
                                and 'Aim at the 2nd door leaf, or press [G] to save as a Single Door.'
                                or 'No door prop detected! Aim directly at the door within 8m.',
                            type = 'warning'
                        })
                    end
                end

                if firstLeaf and IsControlJustPressed(0, 47) then
                    isPickingDoor = false
                    lib.hideTextUI()
                    lib.callback.await('restaurant_manager:server:saveDoor', false, {
                        restaurantId = resId,
                        label = doorLabel,
                        locked = true,
                        leaves = {
                            { model = firstLeaf.model, coords = firstLeaf.coords }
                        }
                    })
                    break
                end

                if IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177) then
                    isPickingDoor = false
                    lib.hideTextUI()
                    lib.notify({
                        title = 'Door Lock Placement',
                        description = 'Door placement cancelled.',
                        type = 'info'
                    })
                    break
                end
            end
        end)
    end)

    AddEventHandler('onResourceStop', function(resourceName)
        if GetCurrentResourceName() ~= resourceName then return end
        if isPickingDoor then
            isPickingDoor = false
            lib.hideTextUI()
        end
        hideDoorTextUiIfShown()
        for doorKey, _ in pairs(RegisteredDoors) do
            unregisterDoor(doorKey)
        end
    end)
end
