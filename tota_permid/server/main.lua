if not Config then
    print('^1[tota_permid] ^8ERROR: ^7config.lua has not been loaded. Please check your config file (bad config).')
    return
end

local PlayerDataCache = {}
local PlayersLoading = {}

local function dprint(fmt, ...)
    if Config.Debug then
        print(('[tota_permid][sv] ' .. tostring(fmt)):format(...))
    end
end

local function NormalizeKey(k) return tostring(k) end

local function GetIdentifierByPrefix(src, prefix)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, #prefix) == prefix then
            return id
        end
    end
    return nil
end

local function GetLicense(src)
    return GetIdentifierByPrefix(src, 'license:') or GetIdentifierByPrefix(src, 'steam:') or GetIdentifierByPrefix(src, 'license2:')
end

local function GetDiscord(src)
    local d = GetIdentifierByPrefix(src, 'discord:')
    if d then return d:gsub('discord:', '') end
    return nil
end

local function SyncCacheWithClient(targetSrc)
    TriggerClientEvent('tota:client:updateCache', targetSrc, PlayerDataCache)
end

local isSyncScheduled = false
local function SyncCacheWithAll()
    if isSyncScheduled then return end
    isSyncScheduled = true
    SetTimeout(1000, function()
        TriggerClientEvent('tota:client:updateCache', -1, PlayerDataCache)
        isSyncScheduled = false
        dprint('Sincronizando caché con todos.')
    end)
end

local function GenerateAndAssignNewPermId(source, license, discord, cb)
    cb = cb or function() end
    if Config.IdAssignmentMethod == 'increment' then
        local q = ("SELECT MAX(permid) FROM `%s`"):format(Config.Database.UsersTable)
        MySQL.scalar(q, {}, function(maxId)
            local newId = (tonumber(maxId) or 0) + 1
            local upd = ("UPDATE `%s` SET permid = ?, discord = ? WHERE `%s` = ?")
                :format(Config.Database.UsersTable, Config.Database.LicenseColumn)
            
            local function TryFinalUpdate(targetLicense)
                MySQL.update(upd, { newId, discord or '', targetLicense }, function(affected)
                    if affected > 0 then
                        dprint('Asignado PermID %s a %s', newId, tostring(source))
                        cb(true, newId)
                    else
                        if targetLicense == license then
                            local clean = license:gsub('license:', '')
                            if clean ~= license then
                                TryFinalUpdate(clean)
                                return
                            end
                        end
                        print(("^1[tota_permid] ERROR: No se encontró la fila para el license '%s' en la tabla '%s'.^7"):format(license, Config.Database.UsersTable))
                        cb(false, nil)
                    end
                end)
            end

            TryFinalUpdate(license)
        end)
    else
        local attempts = 0
        local function tryOnce()
            attempts = attempts + 1
            if attempts > 15 then cb(false, nil) return end
            local candidate = math.random(1, Config.MaxPermId)
            local check = ("SELECT permid FROM `%s` WHERE permid = ? LIMIT 1"):format(Config.Database.UsersTable)
            MySQL.scalar(check, { candidate }, function(exists)
                if exists then
                    tryOnce()
                else
                    local upd = ("UPDATE `%s` SET permid = ?, discord = ? WHERE `%s` = ?")
                        :format(Config.Database.UsersTable, Config.Database.LicenseColumn)
                    MySQL.update(upd, { candidate, discord or '', license }, function(aff)
                        if aff > 0 then cb(true, candidate) else tryOnce() end
                    end)
                end
            end)
        end
        tryOnce()
    end
end

local function EnsurePermId(source, license, discord, cb)
    cb = cb or function() end
    local q = ("SELECT permid FROM `%s` WHERE `%s` = ? LIMIT 1")
        :format(Config.Database.UsersTable, Config.Database.LicenseColumn)
    
    local function TryUpdate(finalLicense, pId)
        local upd = ("UPDATE `%s` SET discord = ? WHERE `%s` = ?")
            :format(Config.Database.UsersTable, Config.Database.LicenseColumn)
        MySQL.update(upd, { discord or '', finalLicense })
        cb(true, pId)
    end

    -- 1. Intentar con el formato original (con prefijo si lo tiene)
    MySQL.scalar(q, { license }, function(permId)
        if permId and permId ~= 0 then
            TryUpdate(license, tonumber(permId))
        else
            -- 2. Intentar sin el prefijo 'license:'
            local cleanLicense = license:gsub('license:', '')
            if cleanLicense ~= license then
                MySQL.scalar(q, { cleanLicense }, function(permId2)
                    if permId2 and permId2 ~= 0 then
                        TryUpdate(cleanLicense, tonumber(permId2))
                    else
                        GenerateAndAssignNewPermId(source, license, discord, cb)
                    end
                end)
            else
                GenerateAndAssignNewPermId(source, license, discord, cb)
            end
        end
    end)
end

local function LoadPlayerIntoCache(source, license, permId)
    local key = NormalizeKey(source)
    local discord = GetDiscord(source) or 'N/A'
    PlayerDataCache[key] = {
        name = Framework.GetName(source),
        permId = tonumber(permId),
        license = license,
        discord = discord
    }

    dprint('Cargado en caché: src=%s perm=%s', key, tostring(permId))
    SyncCacheWithClient(source)
    SyncCacheWithAll()
end

local function HandleFinalPlayerData(source, license, discord)
    EnsurePermId(source, license, discord, function(ok, perm)
        if ok and perm then
            LoadPlayerIntoCache(source, license, perm)
        else
            dprint('Fallo al asegurar PermID para %s', tostring(source))
        end
    end)
end

AddEventHandler('playerJoining', function()
    local src = source
    local attempts, license, discord = 0, nil, nil
    while attempts < 10 and not license do
        license = GetLicense(src)
        discord = GetDiscord(src)
        if not license then attempts = attempts + 1 Wait(150) end
    end
    if not license then return end
    PlayersLoading[tostring(src)] = {
        license = license,
        discord = discord
    }
end)

local function OnPlayerFullyLoaded(src)
    local key = tostring(src)
    dprint('Intentando cargar jugador %s', key)
    
    if not PlayersLoading[key] then
        local identifier = Framework.GetIdentifier(src)
        if not identifier then 
            dprint('Fallo: No se pudo obtener identificador para src %s', key)
            return 
        end
        PlayersLoading[key] = { license = identifier, discord = GetDiscord(src) }
    end
    
    local pdata = PlayersLoading[key]
    dprint('Datos detectados para %s: Identifier=%s Discord=%s', key, pdata.license, tostring(pdata.discord))
    
    HandleFinalPlayerData(src, pdata.license, pdata.discord)
    PlayersLoading[key] = nil
end

RegisterNetEvent('tota:server:clientIsReady', function()
    OnPlayerFullyLoaded(source)
end)

if Config.Framework == 'esx' then
    dprint('Registrando evento esx:playerLoaded')
    AddEventHandler('esx:playerLoaded', function(src) OnPlayerFullyLoaded(src) end)
elseif Config.Framework == 'qbcore' then
    dprint('Registrando evento QBCore:Server:OnPlayerLoaded')
    AddEventHandler('QBCore:Server:OnPlayerLoaded', function() OnPlayerFullyLoaded(source) end)
end

local function DatabaseInitialization()
    local table = Config.Database.UsersTable
    local columns = {
        { name = 'permid', type = 'INT(11) NULL DEFAULT NULL' },
        { name = 'discord', type = 'VARCHAR(50) NULL DEFAULT NULL' }
    }

    for _, col in ipairs(columns) do
        local check = ("SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '%s' AND COLUMN_NAME = '%s'"):format(table, col.name)
        MySQL.scalar(check, {}, function(exists)
            if exists == 0 then
                local sql = ("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(table, col.name, col.type)
                MySQL.update(sql, {}, function(affected)
                    if affected then
                        print(("^2[tota_permid] Columna '%s' añadida automáticamente a la tabla '%s'.^7"):format(col.name, table))
                    end
                end)
            end
        end)
    end
end

AddEventHandler('onResourceStart', function(resName)
    if GetCurrentResourceName() ~= resName then return end
    Wait(1000)
    DatabaseInitialization()
    for _, pid in ipairs(GetPlayers()) do
        OnPlayerFullyLoaded(tonumber(pid))
    end
end)

AddEventHandler('playerDropped', function()
    local key = NormalizeKey(source)
    if PlayerDataCache[key] then
        PlayerDataCache[key] = nil
        SyncCacheWithAll()
    end
    if PlayersLoading[key] then PlayersLoading[key] = nil end
end)

RegisterNetEvent('tota:server:requestCache', function()
    SyncCacheWithClient(source)
end)

RegisterNetEvent('tota:server:requestPlayerData', function(targetServerId)
    local src = source
    local key = NormalizeKey(tonumber(targetServerId) or targetServerId)
    if PlayerDataCache[key] then
        TriggerClientEvent('tota:client:receivePlayerData', src, tonumber(targetServerId), PlayerDataCache[key])
    end
end)

RegisterNetEvent('tota:server:performAdminAction', function(data)
    local src = source
    if not Framework.HasPermission(src) then
        Framework.ShowNotification(src, Config.Translations.NoPermission)
        return
    end

    local targetId = tonumber(data.targetId)
    local action = tostring(data.action or '')
    if not targetId then Framework.ShowNotification(src, Config.Translations.InvalidTarget) return end

    local key = NormalizeKey(targetId)
    if not PlayerDataCache[key] then Framework.ShowNotification(src, Config.Translations.NotInCache) return end

    local targetName = Framework.GetName(targetId)

    if action == 'kick' then
        DropPlayer(targetId, Config.KickMessage or 'Expulsado por admin.')
        Framework.ShowNotification(src, Config.Translations.PlayerKicked:format(targetName))
    elseif action == 'kill' then
        Config.KillPlayer(targetId)
        Framework.ShowNotification(src, Config.Translations.PlayerKilled:format(targetName))
    elseif action == 'revive' then
        Config.RevivePlayer(targetId)
        Framework.ShowNotification(src, Config.Translations.PlayerRevived:format(targetName))
    elseif action == 'freeze' then
        TriggerClientEvent('tota:client:toggleFreeze', targetId)
        Framework.ShowNotification(src, Config.Translations.FreezeToggled:format(targetName))
    elseif action == 'spectate' then
        TriggerClientEvent('tota:client:spectatePlayer', src, targetId)
        Framework.ShowNotification(src, Config.Translations.SpectateStarted:format(targetName))
    elseif action == 'bring' then
        local coords = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent('tota:client:teleport', targetId, coords)
        Framework.ShowNotification(src, Config.Translations.PlayerBrought:format(targetName))
    elseif action == 'goto' then
        local targetPed = GetPlayerPed(targetId)
        if DoesEntityExist(targetPed) then
            local coords = GetEntityCoords(targetPed)
            TriggerClientEvent('tota:client:teleport', src, coords)
            Framework.ShowNotification(src, Config.Translations.PlayerGoto:format(targetName))
        end
    elseif action == 'giveCar' then
        local model = tostring(data.model or '')
        if model ~= '' then
            TriggerClientEvent('tota:client:spawnVehicle', targetId, model)
            Framework.ShowNotification(src, Config.Translations.VehicleGiven:format(model, targetName))
        else Framework.ShowNotification(src, Config.Translations.ModelInvalid) end
    else
        Framework.ShowNotification(src, Config.Translations.UnknownAction)
    end
end)

RegisterCommand(Config.AdminPanelCommand or 'idpanel', function(src)
    if not Framework.HasPermission(src) then
        Framework.ShowNotification(src, Config.Translations.NoPermission)
        return
    end
    TriggerClientEvent('tota:client:toggleAdminPanel', src, PlayerDataCache)
end, false)

RegisterCommand('resyncpanel', function(src)
    if not Framework.HasPermission(src) then return end
    TriggerClientEvent('tota:client:toggleAdminPanel', src, PlayerDataCache)
    Wait(200)
    TriggerClientEvent('tota:client:toggleAdminPanel', src, PlayerDataCache)
    Framework.ShowNotification(src, Config.Translations.PanelResynced)
end, false)

exports('GetSourceFromPermId', function(permId)
    permId = tonumber(permId)
    if not permId then return false end
    for sid, data in pairs(PlayerDataCache) do
        if tonumber(data.permId) == permId then
            return tonumber(sid)
        end
    end
    return false
end)

dprint('Servidor cargado y optimizado.')
