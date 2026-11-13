-- ====================================================================
-- RESTAURANT MANAGER: CLIENT MAIN & INITIALIZATION
-- Zero Idle CPU Usage, Blip Management & Cleanup Engine
-- ====================================================================

PlayerData = {}
CreatedBlips = {}

-- Safe Player Data Fetcher
function GetPlayerData()
    if exports['qbx_core'] and exports['qbx_core'].GetPlayerData then
        local data = exports['qbx_core']:GetPlayerData()
        if data and data.citizenid then return data end
    end
    if exports['qb-core'] and exports['qb-core'].GetCoreObject then
        local QBCore = exports['qb-core']:GetCoreObject()
        if QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData then
            local data = QBCore.Functions.GetPlayerData()
            if data and data.citizenid then return data end
        end
    end
    return PlayerData or {}
end

-- Create Blips for Configured Restaurants
local function SetupBlips()
    for resId, resConfig in pairs(Config.Restaurants) do
        if resConfig.blip and resConfig.blip.enabled and resConfig.blip.coords then
            local coords = resConfig.blip.coords
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, resConfig.blip.sprite or 106)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, resConfig.blip.scale or 0.8)
            SetBlipColour(blip, resConfig.blip.color or 1)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(resConfig.blip.name or resConfig.label or 'Restaurant')
            EndTextCommandSetBlipName(blip)

            table.insert(CreatedBlips, blip)
        end
    end
end

-- Framework Event Handlers
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = GetPlayerData()
    SetupBlips()
    TriggerEvent('restaurant_manager:client:loadStations')
    TriggerEvent('restaurant_manager:client:loadDoors')
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    PlayerData = GetPlayerData()
    SetupBlips()
    TriggerEvent('restaurant_manager:client:loadStations')
    TriggerEvent('restaurant_manager:client:loadDoors')
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
    TriggerEvent('restaurant_manager:client:rolesUpdated')
end)

RegisterNetEvent('qbx_core:client:jobUpdated', function(job)
    PlayerData.job = job
    TriggerEvent('restaurant_manager:client:rolesUpdated')
end)

-- Resource Start Initializer
CreateThread(function()
    PlayerData = GetPlayerData()
    SetupBlips()
    TriggerEvent('restaurant_manager:client:loadStations')
    TriggerEvent('restaurant_manager:client:loadDoors')
end)

-- Resource Stop Cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- 1. Remove Blips
    for _, blip in ipairs(CreatedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    CreatedBlips = {}

    -- 2. Remove Target Zones
    TriggerEvent('restaurant_manager:client:cleanupTargets')

    -- 3. Close NUI & Props
    if StopTabletAnimation then StopTabletAnimation() end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end)

-- ====================================================================
-- COOKING PROGRESS CIRCLE (ox_lib)
-- ====================================================================
RegisterNetEvent('restaurant_manager:client:startCookingProgress', function(data)
    if not data then return end

    local success = lib.progressCircle({
        duration = data.duration or 5000,
        label = data.label or 'Preparing Food...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
            mouse = false
        },
        anim = {
            dict = data.animDict or 'amb@prop_human_bbq@male@idle_a',
            clip = data.animClip or 'idle_b',
            flags = 49
        }
    })

    if success then
        TriggerServerEvent('restaurant_manager:server:finishCooking')
    else
        TriggerServerEvent('restaurant_manager:server:cancelCooking')
    end
end)

-- ====================================================================
-- LIVE ORDER NOTIFICATIONS & NUI SYNC
-- ====================================================================
RegisterNetEvent('restaurant_manager:client:orderReceived', function(orderData)
    -- Notify Employee
    lib.notify({
        title = 'Restaurant Manager',
        description = string.format('New Order #%s received! ($%s)', orderData.id, orderData.total_price),
        type = 'info',
        position = 'top-right',
        duration = 6000
    })

    -- Sync to Open NUI
    SendNUIMessage({
        action = 'orderReceived',
        order = orderData
    })
end)

RegisterNetEvent('restaurant_manager:client:orderUpdated', function(orderData)
    SendNUIMessage({
        action = 'orderUpdated',
        order = orderData
    })
end)

RegisterNetEvent('restaurant_manager:client:syncMenuState', function(restaurantId, itemName, state)
    SendNUIMessage({
        action = 'syncMenuState',
        restaurantId = restaurantId,
        itemName = itemName,
        state = state
    })
end)

RegisterNetEvent('restaurant_manager:client:syncPrice', function(restaurantId, itemName, newPrice)
    SendNUIMessage({
        action = 'syncPrice',
        restaurantId = restaurantId,
        itemName = itemName,
        price = newPrice
    })
end)

RegisterNetEvent('restaurant_manager:client:syncSettings', function(restaurantId, settings)
    SendNUIMessage({
        action = 'syncSettings',
        restaurantId = restaurantId,
        settings = settings
    })
end)
