-- ====================================================================
-- RESTAURANT MANAGER: SERVER RECIPES & COOKING ENGINE
-- Validates ingredients, station types, inventory limits, and ox_inventory items
-- ====================================================================

local function getSortedRecipeList(restaurantId)
    local resRecipes = ServerCache.Recipes[restaurantId] or {}
    local list = {}
    for _, rec in pairs(resRecipes) do
        if type(rec) == 'table' then
            table.insert(list, rec)
        end
    end
    table.sort(list, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    return list
end

-- Callback to Get Recipes for a Restaurant
lib.callback.register('restaurant_manager:server:getRecipes', function(source, restaurantId)
    return getSortedRecipeList(restaurantId or 'burgershot')
end)

-- Callback to Get Valid Items from ox_inventory for Recipe Editor
lib.callback.register('restaurant_manager:server:getOxInventoryItems', function(source)
    local items = {}
    if exports.ox_inventory and exports.ox_inventory.Items then
        local allItems = exports.ox_inventory:Items()
        for name, data in pairs(allItems) do
            table.insert(items, {
                name = name,
                label = data.label or name,
                weight = data.weight or 0,
                description = data.description or ''
            })
        end
        table.sort(items, function(a, b) return a.label < b.label end)
    end
    return items
end)

-- ====================================================================
-- START COOKING (Target Interaction)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:startCooking', function(payload)
    local src = source
    if not CheckRateLimit(src, 'startCooking', 1000) then return end

    if type(payload) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local restaurantId = payload.restaurantId
    local stationId = tonumber(payload.stationId)
    local recipeId = tonumber(payload.recipeId)

    -- 1. Validate Permission
    if not HasPermission(src, restaurantId, 'cook') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    -- 2. Validate Station & Distance
    local stations = ServerCache.Stations[restaurantId]
    local station = stations and stations[stationId]
    if not station then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    if not ValidatePlayerDistance(src, station.coords, Config.MaxStationDistance) then
        Notify(src, 'error', _L('too_far_away'))
        return
    end

    -- 3. Validate Recipe
    local recipes = ServerCache.Recipes[restaurantId]
    local recipe = recipes and recipes[recipeId]
    if not recipe or not recipe.enabled then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    -- 4. Station Type Matching Check
    if recipe.station_type ~= station.station_type then
        Notify(src, 'error', _L('wrong_station'))
        return
    end

    -- 5. Inventory Space Check for Output Item
    local amount = math.max(1, math.min(tonumber(payload.amount) or 1, 20))
    local baseOutputCount = recipe.output_count or 1
    local totalOutputCount = baseOutputCount * amount
    local outputItem = recipe.output_item

    if exports.ox_inventory and not exports.ox_inventory:CanCarryItem(src, outputItem, totalOutputCount) then
        Notify(src, 'error', _L('inventory_full'))
        return
    end

    -- 6. Ingredients Validation
    if type(recipe.ingredients) == 'table' then
        for _, ing in ipairs(recipe.ingredients) do
            local requiredTotal = (ing.count or 1) * amount
            local hasCount = exports.ox_inventory:GetItemCount(src, ing.item) or 0
            if hasCount < requiredTotal then
                Notify(src, 'error', _L('missing_ingredients'))
                return
            end
        end

        -- Deduct Ingredients
        for _, ing in ipairs(recipe.ingredients) do
            local requiredTotal = (ing.count or 1) * amount
            local removed = exports.ox_inventory:RemoveItem(src, ing.item, requiredTotal)
            if not removed then
                Notify(src, 'error', _L('missing_ingredients'))
                return
            end
        end
    end

    -- 7. Register Active Cooking Session
    local baseDuration = tonumber(recipe.cooking_time) or 5000
    local duration = math.floor(baseDuration * (1 + math.min(2.5, (amount - 1) * 0.3)))
    ServerCache.ActiveCooking[src] = {
        restaurantId = restaurantId,
        stationId = stationId,
        recipeId = recipeId,
        outputItem = outputItem,
        outputCount = totalOutputCount,
        amount = amount,
        ingredients = recipe.ingredients,
        finishTime = GetGameTimer() + duration
    }

    local stationConfig = Config.StationTypes[station.station_type] or {}

    -- 8. Trigger Client Progress
    local label = amount > 1 and string.format('Cooking %dx %s...', amount, recipe.recipe_name) or _L('cooking_started', recipe.recipe_name)
    TriggerClientEvent('restaurant_manager:client:startCookingProgress', src, {
        duration = duration,
        label = label,
        animDict = stationConfig.animDict or 'amb@prop_human_bbq@male@idle_a',
        animClip = stationConfig.animClip or 'idle_b'
    })
end)

-- ====================================================================
-- FINISH COOKING (Award Prepared Food)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:finishCooking', function()
    local src = source
    local session = ServerCache.ActiveCooking[src]
    if not session then return end

    -- Anti-Speedhack Check: Must have elapsed the required duration (-500ms grace period)
    if GetGameTimer() < (session.finishTime - 500) then
        ServerCache.ActiveCooking[src] = nil
        Notify(src, 'error', _L('cooking_cancelled'))
        return
    end

    -- Validate Distance to Station
    local stations = ServerCache.Stations[session.restaurantId]
    local station = stations and stations[session.stationId]
    if not station or not ValidatePlayerDistance(src, station.coords, Config.MaxStationDistance + 1.0) then
        ServerCache.ActiveCooking[src] = nil
        Notify(src, 'error', _L('too_far_away'))
        return
    end

    -- Add Output Item to Inventory
    local success, response = exports.ox_inventory:AddItem(src, session.outputItem, session.outputCount)
    if success then
        local itemData = exports.ox_inventory:Items()[session.outputItem]
        local itemLabel = (itemData and itemData.label) or session.outputItem
        Notify(src, 'success', _L('cooking_success', string.format('%dx %s', session.outputCount, itemLabel)))
    else
        Notify(src, 'error', _L('inventory_full'))
    end

    ServerCache.ActiveCooking[src] = nil
end)

-- ====================================================================
-- CANCEL COOKING (Refund Ingredients)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:cancelCooking', function()
    local src = source
    local session = ServerCache.ActiveCooking[src]
    if not session then return end

    -- Return consumed ingredients back to player
    local amount = session.amount or 1
    if type(session.ingredients) == 'table' then
        for _, ing in ipairs(session.ingredients) do
            exports.ox_inventory:AddItem(src, ing.item, (ing.count or 1) * amount)
        end
    end

    ServerCache.ActiveCooking[src] = nil
    Notify(src, 'info', _L('cooking_cancelled'))
end)

-- ====================================================================
-- SAVE / CREATE RECIPE (Owner Recipe Editor)
-- ====================================================================
local function SaveRecipeHandler(src, payload)
    if not CheckRateLimit(src, 'saveRecipe', 800) then
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

    local recipeId = payload.id and tonumber(payload.id)
    local recipeName = tostring(payload.recipe_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local stationType = payload.station_type
    local ingredients = payload.ingredients
    local outputItem = payload.output_item
    local outputCount = math.max(1, math.min(50, tonumber(payload.output_count) or 1))
    local cookingTime = math.max(1000, math.min(120000, tonumber(payload.cooking_time) or 5000))
    local enabled = payload.enabled ~= false

    -- 1. Validate Manage Recipes Permission
    if not HasPermission(src, restaurantId, 'manage_recipes') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    if recipeName == '' then
        Notify(src, 'error', 'Recipe display name cannot be empty!')
        return { ok = false, message = 'Recipe display name cannot be empty!' }
    end

    if not stationType or not Config.StationTypes[stationType] then
        Notify(src, 'error', 'Invalid cooking station type!')
        return { ok = false, message = 'Invalid cooking station type!' }
    end

    -- 2. Validate Items Against ox_inventory
    local oxItems = exports.ox_inventory and exports.ox_inventory:Items()
    if not oxItems then
        Notify(src, 'error', 'ox_inventory items unavailable.')
        return { ok = false, message = 'ox_inventory items unavailable.' }
    end

    if not outputItem or not oxItems[outputItem] then
        local msg = string.format('Output item "%s" does not exist in ox_inventory!', tostring(outputItem))
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    if type(ingredients) ~= 'table' or #ingredients == 0 then
        Notify(src, 'error', 'Recipe must have at least one ingredient!')
        return { ok = false, message = 'Recipe must have at least one ingredient!' }
    end

    local sanitizedIngredients = {}
    for _, ing in ipairs(ingredients) do
        local ingItem = ing and ing.item
        local ingCount = math.max(1, math.min(50, tonumber(ing and ing.count) or 1))
        if not ingItem or not oxItems[ingItem] then
            local msg = string.format('Ingredient "%s" does not exist in ox_inventory!', tostring(ingItem))
            Notify(src, 'error', msg)
            return { ok = false, message = msg }
        end
        table.insert(sanitizedIngredients, { item = ingItem, count = ingCount })
    end

    local ingredientsJson = json.encode(sanitizedIngredients)

    -- 3. Insert or Update Database
    if recipeId and recipeId > 0 then
        local okUpd, errUpd = pcall(MySQL.update.await, [[
            UPDATE `rm_recipes`
            SET `recipe_name` = ?, `station_type` = ?, `ingredients` = ?, `output_item` = ?, `output_count` = ?, `cooking_time` = ?, `enabled` = ?
            WHERE `id` = ? AND `restaurant_id` = ?
        ]], { recipeName, stationType, ingredientsJson, outputItem, outputCount, cookingTime, enabled and 1 or 0, recipeId, restaurantId })
        if not okUpd then
            print(string.format('^1[BurgerShot] saveRecipe update failed: %s^0', tostring(errUpd)))
            Notify(src, 'error', 'Database error while updating recipe!')
            return { ok = false, message = 'Database error while updating recipe!' }
        end
    else
        local okIns, newId = pcall(MySQL.insert.await, [[
            INSERT INTO `rm_recipes`
            (`restaurant_id`, `recipe_name`, `station_type`, `ingredients`, `output_item`, `output_count`, `cooking_time`, `enabled`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { restaurantId, recipeName, stationType, ingredientsJson, outputItem, outputCount, cookingTime, enabled and 1 or 0 })
        if not okIns or not newId then
            print(string.format('^1[BurgerShot] saveRecipe insert failed: %s^0', tostring(newId)))
            Notify(src, 'error', 'Database error while saving recipe!')
            return { ok = false, message = 'Database error while saving recipe!' }
        end
        recipeId = newId
    end

    -- 4. Update Cache
    local savedRecipe = {
        id = recipeId,
        restaurant_id = restaurantId,
        recipe_name = recipeName,
        station_type = stationType,
        ingredients = sanitizedIngredients,
        output_item = outputItem,
        output_count = outputCount,
        cooking_time = cookingTime,
        enabled = enabled
    }
    ServerCache.Recipes[restaurantId] = ServerCache.Recipes[restaurantId] or {}
    ServerCache.Recipes[restaurantId][recipeId] = savedRecipe

    local recipeList = getSortedRecipeList(restaurantId)
    TriggerClientEvent('restaurant_manager:client:syncRecipes', -1, restaurantId, recipeList)

    -- 5. Audit Log
    LogAction(restaurantId, src, 'RECIPE_SAVE', {
        recipe_id = recipeId,
        name = recipeName,
        station = stationType,
        output = outputItem
    })

    Notify(src, 'success', _L('recipe_saved', recipeName))
    return { ok = true, recipe = savedRecipe, recipes = recipeList }
end

lib.callback.register('restaurant_manager:server:saveRecipe', function(source, payload)
    return SaveRecipeHandler(source, payload)
end)

RegisterNetEvent('restaurant_manager:server:saveRecipe', function(payload)
    SaveRecipeHandler(source, payload)
end)

-- ====================================================================
-- DELETE RECIPE (Owner Interaction)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:deleteRecipe', function(payload)
    local src = source
    if not CheckRateLimit(src, 'deleteRecipe', 1000) then return end

    if type(payload) ~= 'table' then return end
    local restaurantId = payload.restaurantId
    local recipeId = tonumber(payload.recipeId)

    if not HasPermission(src, restaurantId, 'manage_recipes') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    local existing = ServerCache.Recipes[restaurantId]
    if not existing or not existing[recipeId] then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local deleted = existing[recipeId]
    pcall(MySQL.query.await, 'DELETE FROM `rm_recipes` WHERE `id` = ? AND `restaurant_id` = ?', { recipeId, restaurantId })
    existing[recipeId] = nil

    TriggerClientEvent('restaurant_manager:client:syncRecipes', -1, restaurantId, getSortedRecipeList(restaurantId))

    LogAction(restaurantId, src, 'RECIPE_DELETE', {
        recipe_id = recipeId,
        name = deleted.recipe_name
    })

    Notify(src, 'success', _L('recipe_deleted'))
end)
