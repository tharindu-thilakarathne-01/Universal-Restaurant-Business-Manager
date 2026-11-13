-- ====================================================================
-- RESTAURANT MANAGER: SERVER AUDIT LOGS ENGINE
-- Action Tracking, Owner Log View & Auto Database Cleanup
-- ====================================================================

local function SendDiscordWebhook(restaurantId, playerName, citizenId, action, details)
    if not Config.DiscordWebhook or not Config.DiscordWebhook.enabled or not Config.DiscordWebhook.url or Config.DiscordWebhook.url == '' then
        return
    end

    local embed = {
        {
            title = string.format('%s — %s', Config.DiscordWebhook.title or 'Restaurant Logs', string.upper(tostring(action))),
            description = string.format('**Staff:** %s (`%s`)\n**Restaurant:** `%s`\n**Action:** `%s`\n```json\n%s\n```',
                playerName, citizenId, restaurantId or 'burgershot', action, tostring(details)
            ),
            color = Config.DiscordWebhook.color or 16744192,
            footer = {
                text = 'Restaurant Manager • ' .. os.date('%Y-%m-%d %H:%M:%S')
            }
        }
    }

    PerformHttpRequest(Config.DiscordWebhook.url, function() end, 'POST', json.encode({
        username = 'Restaurant Manager',
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end

-- Global Action Logger
function LogAction(restaurantId, src, action, details)
    pcall(function()
        local citizenId = 'CONSOLE'
        local playerName = 'System'

        if src and src > 0 then
            citizenId = GetPlayerCitizenId(src) or 'UNKNOWN'
            playerName = GetPlayerFullName(src)
        end

        local detailsJson = '{}'
        if type(details) == 'table' then
            detailsJson = json.encode(details)
        elseif type(details) == 'string' then
            detailsJson = details
        end

        MySQL.insert([[
            INSERT INTO `rm_logs` (`restaurant_id`, `citizenid`, `player_name`, `action`, `details`) 
            VALUES (?, ?, ?, ?, ?)
        ]], { restaurantId or 'global', citizenId, playerName, action, detailsJson })

        SendDiscordWebhook(restaurantId, playerName, citizenId, action, detailsJson)
    end)
end

-- Callback to Get Audit Logs for Owner Tab
lib.callback.register('restaurant_manager:server:getLogs', function(source, restaurantId)
    local src = source

    if not HasPermission(src, restaurantId, 'view_logs') then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT `id`, `citizenid`, `player_name`, `action`, `details`, `created_at` 
        FROM `rm_logs` 
        WHERE `restaurant_id` = ? 
        ORDER BY `id` DESC 
        LIMIT 60
    ]], { restaurantId })

    if not rows then return {} end

    for _, row in ipairs(rows) do
        if row.details and row.details ~= '' then
            local success, decoded = pcall(json.decode, row.details)
            if success then
                row.details = decoded
            end
        end
    end

    return rows
end)

-- Auto-Clean Old Logs Routine (Cleans logs older than 14 days every 12 hours)
CreateThread(function()
    while true do
        Wait(12 * 60 * 60 * 1000) -- Every 12 hours
        pcall(function()
            local deleted = MySQL.query.await("DELETE FROM `rm_logs` WHERE `created_at` < NOW() - INTERVAL 14 DAY", {})
            if deleted and deleted.affectedRows and deleted.affectedRows > 0 then
                print(string.format('^2[restaurant_manager]^7 Auto-cleaned %d expired log records.', deleted.affectedRows))
            end
        end)
    end
end)
