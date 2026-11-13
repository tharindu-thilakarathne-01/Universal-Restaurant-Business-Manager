-- ====================================================================
-- RESTAURANT MANAGER: SERVER ROLES & PERMISSIONS ENGINE
-- Granular Permission System with Owner Lockout Protection
-- ====================================================================

-- Callback to Get Roles for a Restaurant
lib.callback.register('restaurant_manager:server:getRoles', function(source, restaurantId)
    local roles = ServerCache.Roles[restaurantId] or {}
    local roleList = {}
    for grade, data in pairs(roles) do
        table.insert(roleList, {
            grade = grade,
            role_name = data.role_name,
            permissions = data.permissions,
            base_salary = tonumber(data.base_salary) or 0,
            is_owner = data.is_owner == true,
            is_admin = data.is_admin == true
        })
    end
    table.sort(roleList, function(a, b) return a.grade < b.grade end)
    return roleList
end)

-- Callback to Get Current Player Permissions and Role Information
-- Callback to Get Current Player Permissions and Role Information
lib.callback.register('restaurant_manager:server:getPlayerPermissions', function(source, restaurantId)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { isEmployee = false, onduty = false, permissions = {}, isOwner = false, isManager = false, isAdmin = false, canEditOwnerRole = false, grade = 0 }
    end

    local isAdminAccess = (HasRestaurantAdminAccess and HasRestaurantAdminAccess(source, restaurantId))
        or (IsServerAdmin and IsServerAdmin(source))
        or false

    local ply = GetPlayer(source)

    if ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == resConfig.job and SyncPlayerDutySession then
        SyncPlayerDutySession(source)
    end

    -- Server Admins & Restaurant Admin Role holders always receive full permissions
    if isAdminAccess then
        local allPerms = {}
        for _, perm in ipairs(Config.AllPermissions) do allPerms[perm.id] = true end
        local adminGrade = resConfig.adminGrade or 10
        local adminLabel = 'Server Admin'
        if ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == resConfig.job then
            adminGrade = ExtractJobGrade and ExtractJobGrade(ply.PlayerData.job) or adminGrade
            local roleEntry = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][adminGrade]
            local baseLabel = (roleEntry and roleEntry.role_name ~= '' and roleEntry.role_name)
                or (type(ply.PlayerData.job.grade) == 'table' and ply.PlayerData.job.grade.name)
                or 'Admin'
            if IsRoleAdminGrade and IsRoleAdminGrade(restaurantId, adminGrade) then
                adminLabel = baseLabel
            else
                adminLabel = string.format('%s • Admin', baseLabel)
            end
        end
        return {
            isEmployee = true,
            onduty = true,
            isAdmin = true,
            canEditOwnerRole = true,
            permissions = allPerms,
            isOwner = true,
            isManager = true,
            grade = adminGrade,
            gradeName = adminLabel,
            allPermissionsList = Config.AllPermissions
        }
    end

    if not ply or not ply.PlayerData or not ply.PlayerData.job or ply.PlayerData.job.name ~= resConfig.job then
        return { isEmployee = false, onduty = false, permissions = {}, isOwner = false, isManager = false, isAdmin = false, canEditOwnerRole = false, grade = 0 }
    end

    -- Non-admin permissions MUST strictly follow their configured Role in rm_roles (including Owner Grade 9)

    local grade = 0
    if type(ply.PlayerData.job.grade) == 'table' then
        grade = tonumber(ply.PlayerData.job.grade.level) or 0
    elseif type(ply.PlayerData.job.grade) == 'number' then
        grade = ply.PlayerData.job.grade
    end

    local isOwner = IsRoleOwnerGrade and IsRoleOwnerGrade(restaurantId, grade) or (grade == (resConfig.ownerGrade or 9))
    local isDuty = ply.PlayerData.job.onduty == true or isOwner

    local permissions = {}
    local roleCache = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][grade]
    if roleCache and type(roleCache.permissions) == 'table' then
        for _, p in ipairs(roleCache.permissions) do
            permissions[p] = true
        end
    end

    local isManager = (grade == (resConfig.managerGrade or 8)) or
        permissions['refund_orders'] == true or
        permissions['view_history'] == true or
        permissions['manage_menu'] == true or
        permissions['manage_stock'] == true or
        permissions['vending_manage'] == true or
        permissions['vending_fund'] == true

    local gradeName = 'Staff'
    if roleCache and roleCache.role_name and roleCache.role_name ~= '' then
        gradeName = roleCache.role_name
    elseif type(ply.PlayerData.job.grade) == 'table' and ply.PlayerData.job.grade.name then
        gradeName = ply.PlayerData.job.grade.name
    end

    return {
        isEmployee = true,
        onduty = isDuty,
        isAdmin = false,
        canEditOwnerRole = false,
        grade = grade,
        gradeName = gradeName,
        isOwner = isOwner,
        isManager = isManager,
        permissions = permissions,
        allPermissionsList = Config.AllPermissions
    }
end)

-- Extract character full name from Qbox/QBCore charinfo JSON with safe fallback
local function extractCharacterName(charinfoRaw, fallbackName)
    if charinfoRaw and charinfoRaw ~= '' then
        local ok, char = pcall(json.decode, charinfoRaw)
        if ok and type(char) == 'table' then
            local full = string.format('%s %s', char.firstname or '', char.lastname or ''):gsub('^%s*(.-)%s*$', '%1')
            if full ~= '' then
                return full
            end
        end
    end
    return (fallbackName and fallbackName ~= '') and fallbackName or 'Unknown'
end

-- Callback to Get All Restaurant Staff (Online, Offline, Former) & Work Hours
lib.callback.register('restaurant_manager:server:getStaffList', function(source, restaurantId)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then return {} end

    if not HasPermission(source, restaurantId, 'view_history') and not IsRestaurantManager(source, restaurantId) then
        return {}
    end

    local byCid = {}

    local function upsertMember(cid, fields)
        if not cid or cid == '' then return end
        local rec = byCid[cid]
        if not rec then
            rec = {
                citizenid = cid,
                name = 'Unknown',
                grade = 0,
                gradeName = '',
                online = false,
                onduty = false,
                employed = false,
                workedSeconds = 0
            }
            byCid[cid] = rec
        end
        if fields.name and fields.name ~= '' and (rec.name == 'Unknown' or fields.preferName) then
            rec.name = fields.name
        end
        if fields.grade ~= nil and (fields.preferGrade or not rec.employed) then
            rec.grade = tonumber(fields.grade) or 0
        end
        if fields.gradeName and fields.gradeName ~= '' and (rec.gradeName == '' or fields.preferGrade) then
            rec.gradeName = fields.gradeName
        end
        if fields.employed then rec.employed = true end
        if fields.online then rec.online = true end
        if fields.onduty then rec.onduty = true end
        if fields.source then rec.source = fields.source end
    end

    -- 1. Seed with everyone who has cumulative work history or previously held this job
    local cachedHours = ServerCache.StaffHours[restaurantId] or {}
    for cid, entry in pairs(cachedHours) do
        upsertMember(cid, {
            name = entry.name,
            grade = entry.grade,
            gradeName = entry.gradeName
        })
    end

    -- 2. Include all Qbox job holders (online + offline + multijob) from player_groups
    local okGroups, groupRows = pcall(MySQL.query.await, [[
        SELECT pg.`citizenid`, pg.`grade`, p.`charinfo`, p.`name` AS `account_name`, p.`job`
        FROM `player_groups` pg
        LEFT JOIN `players` p ON p.`citizenid` = pg.`citizenid`
        WHERE pg.`group` = ? AND pg.`type` = 'job'
    ]], { resConfig.job })

    if okGroups and groupRows then
        for _, row in ipairs(groupRows) do
            local jobGradeName = ''
            if row.job and row.job ~= '' then
                local okJob, jobObj = pcall(json.decode, row.job)
                if okJob and type(jobObj) == 'table' and jobObj.name == resConfig.job and type(jobObj.grade) == 'table' then
                    jobGradeName = tostring(jobObj.grade.name or '')
                end
            end
            upsertMember(row.citizenid, {
                name = extractCharacterName(row.charinfo, row.account_name),
                grade = tonumber(row.grade) or 0,
                gradeName = jobGradeName,
                employed = true,
                preferName = true,
                preferGrade = true
            })
        end
    end

    -- 3. Fallback: players whose primary JSON job matches even if missing from player_groups
    local okPlayers, playerRows = pcall(MySQL.query.await, [[
        SELECT `citizenid`, `charinfo`, `name` AS `account_name`, `job`
        FROM `players`
        WHERE JSON_VALID(`job`) AND JSON_VALUE(`job`, '$.name') = ?
    ]], { resConfig.job })

    if okPlayers and playerRows then
        for _, row in ipairs(playerRows) do
            local g, gn = 0, ''
            if row.job and row.job ~= '' then
                local okJob, jobObj = pcall(json.decode, row.job)
                if okJob and type(jobObj) == 'table' then
                    g, gn = ExtractJobGrade(jobObj)
                end
            end
            upsertMember(row.citizenid, {
                name = extractCharacterName(row.charinfo, row.account_name),
                grade = g,
                gradeName = gn,
                employed = true,
                preferName = true,
                preferGrade = true
            })
        end
    end

    -- 4. Merge currently online players (live name, grade, multijob, and duty state)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local ply = GetPlayer(src)
        if ply and ply.PlayerData and ply.PlayerData.job then
            local isPrimary = (ply.PlayerData.job.name == resConfig.job)
            local multiGrade = type(ply.PlayerData.jobs) == 'table' and ply.PlayerData.jobs[resConfig.job] or nil
            if isPrimary or multiGrade ~= nil then
                local cid = ply.PlayerData.citizenid or GetPlayerCitizenId(src) or ('SRC_' .. tostring(src))
                local g, gn = 0, ''
                if isPrimary then
                    g, gn = ExtractJobGrade(ply.PlayerData.job)
                else
                    g = tonumber(multiGrade) or 0
                end
                upsertMember(cid, {
                    source = src,
                    name = GetPlayerFullName(src),
                    grade = g,
                    gradeName = gn,
                    online = true,
                    onduty = isPrimary and (ply.PlayerData.job.onduty == true),
                    employed = true,
                    preferName = true,
                    preferGrade = true
                })
            end
        end
    end

    -- 5. Compute live cumulative work seconds, role labels, status badges, and sort
    local staff = {}
    local statusOrder = { on_duty = 1, off_duty = 2, offline = 3, former = 4 }

    for cid, rec in pairs(byCid) do
        rec.workedSeconds = GetLiveWorkedSeconds and GetLiveWorkedSeconds(restaurantId, cid) or 0
        rec.gradeName = ResolveRoleLabel and ResolveRoleLabel(restaurantId, rec.grade, rec.gradeName) or rec.gradeName
        if rec.online and rec.onduty then
            rec.status = 'on_duty'
        elseif rec.online then
            rec.status = 'off_duty'
        elseif rec.employed then
            rec.status = 'offline'
        else
            rec.status = 'former'
        end
        table.insert(staff, rec)
    end

    table.sort(staff, function(a, b)
        local sa = statusOrder[a.status] or 9
        local sb = statusOrder[b.status] or 9
        if sa ~= sb then return sa < sb end
        if (a.grade or 0) ~= (b.grade or 0) then
            return (a.grade or 0) > (b.grade or 0)
        end
        if (a.workedSeconds or 0) ~= (b.workedSeconds or 0) then
            return (a.workedSeconds or 0) > (b.workedSeconds or 0)
        end
        return tostring(a.name or '') < tostring(b.name or '')
    end)

    return staff
end)

-- ====================================================================
-- ====================================================================
-- CREATE / EDIT / DELETE ROLES (Owner Only)
-- ====================================================================
local function SaveOrCreateRole(src, payload)
    if type(payload) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = payload.restaurantId
    local rawGrade = tonumber(payload.grade)
    local grade = rawGrade and math.floor(rawGrade) or nil
    local roleName = tostring(payload.role_name or ''):gsub('^%s*(.-)%s*$', '%1')
    local perms = payload.permissions
    local isNew = payload.isNew == true

    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig or not grade or rawGrade ~= grade or grade < 0 or grade > 99 then
        Notify(src, 'error', 'Invalid role grade (use 0 - 99).')
        return { ok = false, message = 'Invalid role grade (use 0 - 99).' }
    end

    if roleName == '' or #roleName > 50 then
        Notify(src, 'error', 'Role name must be between 1 and 50 characters.')
        return { ok = false, message = 'Role name must be between 1 and 50 characters.' }
    end

    -- 1. Validate Manage Roles Permission (Server Admins always pass HasPermission)
    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    -- 2. Admin Role is locked with Permanent Full Access; Owner Role is editable only by Admins
    local isAdminGrade = IsRoleAdminGrade and IsRoleAdminGrade(restaurantId, grade) or (grade == (resConfig.adminGrade or 10))
    if isAdminGrade then
        local msg = 'The Admin role permanently has Full Access and cannot be restricted.'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    local isOwnerGrade = IsRoleOwnerGrade and IsRoleOwnerGrade(restaurantId, grade) or (grade == (resConfig.ownerGrade or 9))
    local callerIsAdmin = HasRestaurantAdminAccess and HasRestaurantAdminAccess(src, restaurantId) or (IsServerAdmin and IsServerAdmin(src))
    if isOwnerGrade and not callerIsAdmin then
        local msg = 'Only Admins can modify the Owner role permissions.'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    ServerCache.Roles[restaurantId] = ServerCache.Roles[restaurantId] or {}
    local existingRole = ServerCache.Roles[restaurantId][grade]

    if isNew and existingRole then
        local msg = string.format('Grade %d (%s) already exists.', grade, existingRole.role_name or '')
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    -- 3. Sanitize Permissions
    local validPermsMap = {}
    for _, p in ipairs(Config.AllPermissions) do
        validPermsMap[p.id] = true
    end

    local sanitizedPerms = {}
    if type(perms) == 'table' then
        for _, p in ipairs(perms) do
            if validPermsMap[p] then
                table.insert(sanitizedPerms, p)
            end
        end
    end

    local permsJson = json.encode(sanitizedPerms)
    local baseSalary = existingRole and (tonumber(existingRole.base_salary) or 0) or 0
    if payload.base_salary ~= nil and tonumber(payload.base_salary) ~= nil then
        baseSalary = math.max(0, math.min(1000000, math.floor(tonumber(payload.base_salary))))
    end

    -- 4. Insert or Update in Database
    MySQL.insert.await([[
        INSERT INTO `rm_roles` (`restaurant_id`, `grade`, `role_name`, `permissions`, `base_salary`, `is_owner`, `is_admin`)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ON DUPLICATE KEY UPDATE `role_name` = VALUES(`role_name`), `permissions` = VALUES(`permissions`), `base_salary` = VALUES(`base_salary`)
    ]], { restaurantId, grade, roleName, permsJson, baseSalary, isOwnerGrade and 1 or 0 })

    -- Mark roles as initialized/customized so defaults do not re-seed over edits/deletes
    pcall(MySQL.insert.await, [[
        INSERT INTO `rm_settings` (`restaurant_id`, `setting_key`, `setting_value`)
        VALUES (?, 'roles_seeded', '1')
        ON DUPLICATE KEY UPDATE `setting_value` = '1'
    ]], { restaurantId })

    -- 5. Update Cache & Runtime Qbox/QBCore Job Definition
    local updatedRole = {
        role_name = roleName,
        permissions = sanitizedPerms,
        base_salary = baseSalary,
        is_owner = isOwnerGrade,
        is_admin = false
    }
    ServerCache.Roles[restaurantId][grade] = updatedRole

    if SyncRoleToCoreFramework then
        SyncRoleToCoreFramework(restaurantId, grade, updatedRole, false)
    end
    TriggerClientEvent('restaurant_manager:client:rolesUpdated', -1, restaurantId)

    -- Refresh online players currently holding this job grade
    for _, playerId in ipairs(GetPlayers()) do
        local pSrc = tonumber(playerId)
        local ply = GetPlayer(pSrc)
        if ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == resConfig.job then
            local g = ExtractJobGrade and ExtractJobGrade(ply.PlayerData.job) or nil
            if g == grade and SyncPlayerDutySession then
                SyncPlayerDutySession(pSrc)
            end
        end
    end

    -- 6. Audit Log
    local actionType = (isNew or not existingRole) and 'ROLE_CREATE' or 'ROLE_UPDATE'
    LogAction(restaurantId, src, actionType, {
        grade = grade,
        role_name = roleName,
        permissions = sanitizedPerms
    })

    local msg = isNew and string.format('Created role %s (Grade %d)!', roleName, grade) or _L('role_updated')
    Notify(src, 'success', msg)
    return { ok = true, message = msg }
end

RegisterNetEvent('restaurant_manager:server:saveRole', function(payload)
    local src = source
    if not CheckRateLimit(src, 'saveRole', 1000) then return end
    SaveOrCreateRole(src, payload)
end)

lib.callback.register('restaurant_manager:server:saveRoleData', function(source, payload)
    if not CheckRateLimit(source, 'saveRoleData', 800) then
        return { ok = false, message = _L('rate_limited') }
    end
    return SaveOrCreateRole(source, payload)
end)

lib.callback.register('restaurant_manager:server:deleteRole', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'deleteRole', 1000) then
        return { ok = false, message = _L('rate_limited') }
    end

    if type(payload) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    local restaurantId = payload.restaurantId
    local grade = tonumber(payload.grade)
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig or not grade then
        Notify(src, 'error', _L('invalid_data'))
        return { ok = false, message = _L('invalid_data') }
    end

    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return { ok = false, message = _L('no_permission') }
    end

    if grade == 0 then
        local msg = 'Base Grade 0 cannot be deleted (you can still edit its name & permissions).'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    if (IsRoleAdminGrade and IsRoleAdminGrade(restaurantId, grade)) or grade == (resConfig.adminGrade or 10) then
        local msg = 'The Admin role cannot be deleted.'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    if (IsRoleOwnerGrade and IsRoleOwnerGrade(restaurantId, grade)) or grade == (resConfig.ownerGrade or 9) then
        local msg = 'The Owner role cannot be deleted (Admins can still edit its permissions).'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    ServerCache.Roles[restaurantId] = ServerCache.Roles[restaurantId] or {}
    local targetRole = ServerCache.Roles[restaurantId][grade]
    if not targetRole then
        local msg = 'Role does not exist.'
        Notify(src, 'error', msg)
        return { ok = false, message = msg }
    end

    local deletedName = targetRole.role_name or ('Grade ' .. grade)

    -- 1. Reassign online & DB employees holding this grade safely to Grade 0 before removing grade
    for _, playerId in ipairs(GetPlayers()) do
        local pSrc = tonumber(playerId)
        local ply = GetPlayer(pSrc)
        if ply and ply.PlayerData then
            local primaryMatches = ply.PlayerData.job and ply.PlayerData.job.name == resConfig.job
                and (ExtractJobGrade and ExtractJobGrade(ply.PlayerData.job) == grade)
            local multiMatches = type(ply.PlayerData.jobs) == 'table' and tonumber(ply.PlayerData.jobs[resConfig.job]) == grade
            if primaryMatches and exports['qbx_core'] and exports['qbx_core'].SetJob then
                pcall(function() exports['qbx_core']:SetJob(pSrc, resConfig.job, 0) end)
            elseif multiMatches and exports['qbx_core'] and exports['qbx_core'].AddPlayerToJob then
                pcall(function() exports['qbx_core']:AddPlayerToJob(ply.PlayerData.citizenid, resConfig.job, 0) end)
            end
        end
    end

    pcall(MySQL.update.await,
        'UPDATE `player_groups` SET `grade` = 0 WHERE `group` = ? AND `type` = ? AND `grade` = ?',
        { resConfig.job, 'job', grade }
    )
    pcall(MySQL.update.await,
        'UPDATE `rm_staff_hours` SET `grade` = 0 WHERE `restaurant_id` = ? AND `grade` = ?',
        { restaurantId, grade }
    )

    -- 2. Delete from rm_roles and ensure deleted roles stay deleted across restarts
    MySQL.query.await('DELETE FROM `rm_roles` WHERE `restaurant_id` = ? AND `grade` = ?', { restaurantId, grade })
    pcall(MySQL.insert.await, [[
        INSERT INTO `rm_settings` (`restaurant_id`, `setting_key`, `setting_value`)
        VALUES (?, 'roles_seeded', '1')
        ON DUPLICATE KEY UPDATE `setting_value` = '1'
    ]], { restaurantId })

    ServerCache.Roles[restaurantId][grade] = nil
    if SyncRoleToCoreFramework then
        SyncRoleToCoreFramework(restaurantId, grade, nil, true)
    end

    LogAction(restaurantId, src, 'ROLE_DELETE', {
        grade = grade,
        role_name = deletedName
    })

    local msg = string.format('Deleted role %s (Grade %d).', deletedName, grade)
    Notify(src, 'success', msg)
    return { ok = true, message = msg }
end)

-- ====================================================================
-- SAVE PERIODIC BASE SALARIES PER ROLE (Owner Only)
-- ====================================================================
RegisterNetEvent('restaurant_manager:server:saveRoleSalaries', function(payload)
    local src = source
    if not CheckRateLimit(src, 'saveRoleSalaries', 1000) then return end

    if type(payload) ~= 'table' or type(payload.salaries) ~= 'table' then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    local restaurantId = payload.restaurantId
    if not Config.Restaurants[restaurantId] then
        Notify(src, 'error', _L('invalid_data'))
        return
    end

    if not HasPermission(src, restaurantId, 'manage_roles') then
        Notify(src, 'error', _L('no_permission'))
        return
    end

    if EnsureDatabaseSchema then
        EnsureDatabaseSchema()
    end

    ServerCache.Roles[restaurantId] = ServerCache.Roles[restaurantId] or {}
    local updatedMap = {}

    for _, entry in ipairs(payload.salaries) do
        local grade = type(entry) == 'table' and tonumber(entry.grade)
        local amount = type(entry) == 'table' and tonumber(entry.salary)
        if grade ~= nil and amount ~= nil then
            local cleanAmount = math.max(0, math.min(1000000, math.floor(amount)))
            if ServerCache.Roles[restaurantId][grade] then
                ServerCache.Roles[restaurantId][grade].base_salary = cleanAmount
            end
            pcall(MySQL.update.await,
                'UPDATE `rm_roles` SET `base_salary` = ? WHERE `restaurant_id` = ? AND `grade` = ?',
                { cleanAmount, restaurantId, grade }
            )
            updatedMap[tostring(grade)] = cleanAmount
        end
    end

    LogAction(restaurantId, src, 'ROLE_SALARIES_UPDATE', {
        salaries = updatedMap
    })

    Notify(src, 'success', 'Role base salaries updated successfully!')
end)

-- ====================================================================
-- STAFF HIRING, PROMOTION & TABLET DISTRIBUTION (Manager / Owner / Admin)
-- ====================================================================

local function CanManageStaff(src, restaurantId)
    if not src or src <= 0 then return true end
    if HasRestaurantAdminAccess and HasRestaurantAdminAccess(src, restaurantId) then return true end
    if IsServerAdmin and IsServerAdmin(src) then return true end
    if HasPermission and HasPermission(src, restaurantId, 'manage_staff') then return true end
    if HasPermission and HasPermission(src, restaurantId, 'manage_roles') then return true end
    if IsRestaurantManager and IsRestaurantManager(src, restaurantId) then return true end
    return false
end

-- Promote or Hire Player by Server ID
lib.callback.register('restaurant_manager:server:promoteStaff', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'promoteStaff', 600) then
        return { ok = false, message = _L('rate_limited') or 'Please wait a moment.' }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = 'Invalid request parameters.' }
    end

    local restaurantId = payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = 'Invalid restaurant configuration.' }
    end

    if not CanManageStaff(src, restaurantId) then
        return { ok = false, message = 'Access Denied: You do not have permission to manage staff.' }
    end

    local targetId = tonumber(payload.targetId)
    local grade = tonumber(payload.grade)
    if not targetId or targetId <= 0 then
        return { ok = false, message = 'Please provide a valid online Server ID.' }
    end

    if grade == nil or grade < 0 then
        return { ok = false, message = 'Please select a valid job grade.' }
    end

    local targetPly = GetPlayer(targetId)
    if not targetPly then
        return { ok = false, message = string.format('Player with Server ID %d is not currently online.', targetId) }
    end

    -- Grade hierarchy protection: non-admins cannot assign a grade higher than or equal to their own
    local callerIsAdmin = (HasRestaurantAdminAccess and HasRestaurantAdminAccess(src, restaurantId))
        or (IsServerAdmin and IsServerAdmin(src))

    if not callerIsAdmin then
        local callerPly = GetPlayer(src)
        local callerGrade = 0
        if callerPly and callerPly.PlayerData and callerPly.PlayerData.job then
            callerGrade = ExtractJobGrade and ExtractJobGrade(callerPly.PlayerData.job) or 0
        end
        local isOwnerGrade = IsRoleOwnerGrade and IsRoleOwnerGrade(restaurantId, callerGrade)
        if not isOwnerGrade and grade >= callerGrade then
            return { ok = false, message = 'You cannot assign a grade equal to or higher than your own grade.' }
        end
    end

    -- Role name resolution
    local roleCache = ServerCache.Roles[restaurantId] and ServerCache.Roles[restaurantId][grade]
    local roleName = (roleCache and roleCache.role_name) or ('Grade ' .. tostring(grade))

    local jobSetSuccess = false
    if exports['qbx_core'] and exports['qbx_core'].SetJob then
        local ok = pcall(function()
            exports['qbx_core']:SetJob(targetId, resConfig.job, grade)
        end)
        jobSetSuccess = ok
    elseif targetPly.Functions and targetPly.Functions.SetJob then
        jobSetSuccess = targetPly.Functions.SetJob(resConfig.job, grade)
    end

    if jobSetSuccess then
        -- Also ensure multijob entry is updated in qbx_core
        if exports['qbx_core'] and exports['qbx_core'].AddPlayerToJob and targetPly.PlayerData and targetPly.PlayerData.citizenid then
            pcall(function()
                exports['qbx_core']:AddPlayerToJob(targetPly.PlayerData.citizenid, resConfig.job, grade)
            end)
        end

        local targetName = GetPlayerFullName(targetId)

        -- Notify target player
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = resConfig.label or 'Burgershot',
            description = string.format('Congratulations! You have been appointed as %s (Grade %d)!', roleName, grade),
            type = 'success',
            duration = 7500
        })

        local msg = string.format('Successfully promoted %s (ID %d) to %s (Grade %d).', targetName, targetId, roleName, grade)
        Notify(src, 'success', msg)

        LogAction(restaurantId, src, 'STAFF_PROMOTE', {
            targetId = targetId,
            targetName = targetName,
            citizenid = targetPly.PlayerData and targetPly.PlayerData.citizenid,
            grade = grade,
            role_name = roleName
        })

        return { ok = true, message = msg }
    else
        return { ok = false, message = 'Framework could not update the player job.' }
    end
end)

-- Fire / Dismiss Staff Member
lib.callback.register('restaurant_manager:server:fireStaff', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'fireStaff', 600) then
        return { ok = false, message = _L('rate_limited') or 'Please wait a moment.' }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = 'Invalid request parameters.' }
    end

    local restaurantId = payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = 'Invalid restaurant configuration.' }
    end

    if not CanManageStaff(src, restaurantId) then
        return { ok = false, message = 'Access Denied: You do not have permission to manage staff.' }
    end

    local targetId = tonumber(payload.targetId)
    local citizenid = payload.citizenid

    -- 1. If target is online, dismiss via active session
    if targetId and targetId > 0 then
        local targetPly = GetPlayer(targetId)
        if targetPly then
            local targetName = GetPlayerFullName(targetId)
            if exports['qbx_core'] and exports['qbx_core'].SetJob then
                pcall(function() exports['qbx_core']:SetJob(targetId, 'unemployed', 0) end)
            elseif targetPly.Functions and targetPly.Functions.SetJob then
                targetPly.Functions.SetJob('unemployed', 0)
            end

            if exports['qbx_core'] and exports['qbx_core'].RemovePlayerFromJob and targetPly.PlayerData and targetPly.PlayerData.citizenid then
                pcall(function() exports['qbx_core']:RemovePlayerFromJob(targetPly.PlayerData.citizenid, resConfig.job) end)
            end

            TriggerClientEvent('ox_lib:notify', targetId, {
                title = resConfig.label or 'Burgershot',
                description = 'Your employment at Burgershot has been terminated.',
                type = 'info',
                duration = 7000
            })

            local msg = string.format('Dismissed %s (ID %d) from Burgershot.', targetName, targetId)
            Notify(src, 'success', msg)
            LogAction(restaurantId, src, 'STAFF_DISMISS', { targetId = targetId, targetName = targetName })
            return { ok = true, message = msg }
        end
    end

    -- 2. If target is offline, update database tables by citizenid
    if citizenid and citizenid ~= '' then
        pcall(MySQL.update.await, 'DELETE FROM `player_groups` WHERE `citizenid` = ? AND `group` = ? AND `type` = "job"', { citizenid, resConfig.job })
        pcall(MySQL.update.await, 'UPDATE `players` SET `job` = JSON_SET(`job`, "$.name", "unemployed", "$.grade", JSON_OBJECT("level", 0, "name", "Unemployed")) WHERE `citizenid` = ? AND JSON_VALUE(`job`, "$.name") = ?', { citizenid, resConfig.job })
        local msg = string.format('Removed offline staff (%s) from Burgershot.', citizenid)
        Notify(src, 'success', msg)
        LogAction(restaurantId, src, 'STAFF_DISMISS_OFFLINE', { citizenid = citizenid })
        return { ok = true, message = msg }
    end

    return { ok = false, message = 'Staff member not found or invalid citizen ID.' }
end)

-- Delivery helper for Burgershot Tablet with ox_inventory reload fallback
local function DeliverBurgershotTablet(targetId)
    local tabletDef = {
        name = 'burgershot_tablet',
        label = 'Burgershot Tablet',
        weight = 1000,
        stack = false,
        close = true,
        description = 'Official Burgershot management tablet for orders, kitchen recipes, stock control, staff promotions and administration.',
        client = {
            event = 'burgershot:client:useTablet'
        }
    }

    local targetPly = GetPlayer(targetId)
    if not targetPly then
        return false, string.format('Player with Server ID %d is not online.', targetId)
    end

    local addSuccess = false
    local addErr = 'unknown'

    -- 1. Try ox_inventory AddItem as item name string
    if exports.ox_inventory then
        local ok1, success1, response1 = pcall(function()
            return exports.ox_inventory:AddItem(targetId, 'burgershot_tablet', 1)
        end)
        if ok1 and success1 then
            addSuccess = true
        else
            addErr = tostring(response1 or success1 or 'ox_failed')
        end

        -- 2. If item is not in loaded ox_inventory cache, try passing the full item table definition
        if not addSuccess then
            local ok2, success2, response2 = pcall(function()
                return exports.ox_inventory:AddItem(targetId, tabletDef, 1)
            end)
            if ok2 and success2 then
                addSuccess = true
            else
                addErr = tostring(response2 or success2 or addErr)
            end
        end

        -- 3. If ox_inventory reported invalid_item, restart ox_inventory to reload data/items.lua from disk
        if not addSuccess and (addErr == 'invalid_item' or string.find(string.lower(addErr), 'invalid')) then
            print('^3[Burgershot] Item "burgershot_tablet" is not yet loaded into ox_inventory memory. Reloading ox_inventory...^0')
            pcall(ExecuteCommand, 'restart ox_inventory')
            Wait(1000)
            local okRetry, successRetry, responseRetry = pcall(function()
                return exports.ox_inventory:AddItem(targetId, 'burgershot_tablet', 1)
            end)
            if okRetry and successRetry then
                addSuccess = true
            else
                addErr = tostring(responseRetry or successRetry or addErr)
            end
        end
    end

    -- 4. Try Framework Player AddItem fallback
    if not addSuccess and targetPly.Functions and targetPly.Functions.AddItem then
        local okF, successF = pcall(function()
            return targetPly.Functions.AddItem('burgershot_tablet', 1)
        end)
        if okF and successF then
            addSuccess = true
        end
    end

    if addSuccess then
        local targetName = GetPlayerFullName(targetId)
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'Burgershot Tablet',
            description = 'You have received an official Burgershot Management Tablet!',
            type = 'success',
            duration = 7500
        })
        return true, targetName
    end

    return false, addErr
end

-- Give Burgershot Tablet by Server ID
lib.callback.register('restaurant_manager:server:giveTablet', function(source, payload)
    local src = source
    if not CheckRateLimit(src, 'giveTablet', 600) then
        return { ok = false, message = _L('rate_limited') or 'Please wait a moment.' }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = 'Invalid request parameters.' }
    end

    local restaurantId = payload.restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[restaurantId]
    if not resConfig then
        return { ok = false, message = 'Invalid restaurant configuration.' }
    end

    if not CanManageStaff(src, restaurantId) then
        return { ok = false, message = 'Access Denied: Only managers and admins can issue official tablets.' }
    end

    local rawId = tonumber(payload.targetId)
    local targetId = (rawId and rawId > 0) and rawId or src

    local success, result = DeliverBurgershotTablet(targetId)
    if success then
        local targetName = result
        local msg = (targetId == src)
            and 'Burgershot Tablet added to your inventory.'
            or string.format('Issued Burgershot Tablet to %s (ID %d).', targetName, targetId)

        if targetId ~= src then
            Notify(src, 'success', msg)
        end

        LogAction(restaurantId, src, 'GIVE_TABLET', {
            targetId = targetId,
            targetName = targetName
        })

        return { ok = true, message = msg }
    else
        return { ok = false, message = string.format('Could not add tablet to inventory (%s).', tostring(result)) }
    end
end)

-- Command: /givebstab [id] and /givebstablet [id]
local function HandleGiveTabletCommand(src, args)
    local rawId = tonumber(args[1])
    local targetId = (rawId and rawId > 0) and rawId or src
    local restaurantId = 'burgershot'

    if not CanManageStaff(src, restaurantId) then
        if src > 0 then
            Notify(src, 'error', 'Access Denied: Only Burgershot Managers and Admins can issue tablets.')
        end
        return
    end

    local success, result = DeliverBurgershotTablet(targetId)
    if success then
        local targetName = result
        local msg = (targetId == src)
            and 'Burgershot Tablet added to your inventory.'
            or string.format('Issued Burgershot Tablet to %s (ID %d).', targetName, targetId)

        if src > 0 then
            Notify(src, 'success', msg)
        else
            print('[Burgershot] ' .. msg)
        end
    else
        local err = string.format('Failed to give tablet: %s', tostring(result))
        if src > 0 then
            Notify(src, 'error', err)
        else
            print('[Burgershot] ' .. err)
        end
    end
end

RegisterCommand('givebstab', function(src, args)
    HandleGiveTabletCommand(src, args)
end, false)

RegisterCommand('givebstablet', function(src, args)
    HandleGiveTabletCommand(src, args)
end, false)

-- Callback to Get All Currently Online Players for Tablet Provisioning
lib.callback.register('restaurant_manager:server:getOnlinePlayersList', function(source, restaurantId)
    local src = source
    local resId = restaurantId or 'burgershot'
    local resConfig = Config.Restaurants[resId]
    if not resConfig then return {} end

    if not CanManageStaff(src, resId) then
        return {}
    end

    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pSrc = tonumber(playerId)
        local ply = GetPlayer(pSrc)
        if ply and ply.PlayerData then
            local pJob = ply.PlayerData.job or {}
            local isBurgershot = (pJob.name == resConfig.job)
            local gradeNum = 0
            local gradeLabel = ''
            if type(pJob.grade) == 'table' then
                gradeNum = tonumber(pJob.grade.level) or 0
                gradeLabel = tostring(pJob.grade.name or '')
            elseif type(pJob.grade) == 'number' then
                gradeNum = pJob.grade
            end

            local resolvedGradeName = gradeLabel
            if isBurgershot then
                resolvedGradeName = ResolveRoleLabel and ResolveRoleLabel(resId, gradeNum, gradeLabel) or gradeLabel
                if resolvedGradeName == '' then resolvedGradeName = 'Staff' end
            end

            local jobDisplay = isBurgershot
                and string.format('Burgershot • %s (G%d)', resolvedGradeName, gradeNum)
                or string.format('%s (G%d)', tostring(pJob.label or pJob.name or 'Unemployed'), gradeNum)

            table.insert(list, {
                source = pSrc,
                citizenid = ply.PlayerData.citizenid or ('SRC_' .. pSrc),
                name = GetPlayerFullName(pSrc),
                jobName = pJob.name or 'unemployed',
                jobLabel = jobDisplay,
                isStaff = isBurgershot,
                grade = gradeNum,
                gradeName = resolvedGradeName,
                onduty = isBurgershot and (pJob.onduty == true)
            })
        end
    end

    table.sort(list, function(a, b)
        if a.isStaff ~= b.isStaff then
            return a.isStaff == true
        end
        return (a.source or 0) < (b.source or 0)
    end)

    return list
end)
