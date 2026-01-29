Framework = {}
_G.ESX = nil
_G.QBCore = nil

local function DetectFramework()
    if GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
        Config.Framework = 'qbcore'
        Config.Database.UsersTable = 'players'
        Config.Database.LicenseColumn = 'license'
        _G.QBCore = exports['qb-core']:GetCoreObject()
        print('^2[tota_permid] QBCore Detectado Correctamente.^7')
        return 'qbcore'
    elseif GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
        Config.Framework = 'esx'
        Config.Database.UsersTable = 'users'
        Config.Database.LicenseColumn = 'identifier'
        
        -- Intento de obtener SharedObject vía export (Moderno)
        pcall(function()
            _G.ESX = exports['es_extended']:getSharedObject()
        end)
        
        -- Fallback vía Trigger (Antiguo/Legacy)
        if not _G.ESX then
            TriggerEvent('esx:getSharedObject', function(obj) _G.ESX = obj end)
        end
        
        print('^2[tota_permid] ESX Detectado Correctamente.^7')
        return 'esx'
    end
    return nil
end

-- Ejecutamos inmediatamente para evitar condiciones de carrera en main.lua
DetectFramework()

Framework.GetPlayer = function(source)
    if _G.QBCore then
        return _G.QBCore.Functions.GetPlayer(source)
    elseif _G.ESX then
        return _G.ESX.GetPlayerFromId(source)
    end
    return nil
end

Framework.GetIdentifier = function(source)
    local player = Framework.GetPlayer(source)
    
    if _G.QBCore then
        return (player and player.PlayerData.license) or GetLicense(source)
    elseif _G.ESX then
        return (player and player.identifier) or GetIdentifierByPrefix(source, 'steam:') or GetLicense(source)
    end

    return GetLicense(source)
end

Framework.HasPermission = function(source, permission)
    permission = permission or Config.AdminPermission
    local hasPerm = false

    if _G.QBCore then
        hasPerm = _G.QBCore.Functions.HasPermission(source, permission)
    elseif _G.ESX then
        local xPlayer = _G.ESX.GetPlayerFromId(source)
        hasPerm = xPlayer and (xPlayer.getGroup() == permission or xPlayer.getGroup() == 'superadmin')
    end

    if not hasPerm then
        hasPerm = IsPlayerAceAllowed(source, "command") or IsPlayerAceAllowed(source, "admin")
    end

    return hasPerm
end

Framework.GetName = function(source)
    local player = Framework.GetPlayer(source)
    if not player then return GetPlayerName(source) end

    if _G.QBCore then
        local charinfo = player.PlayerData.charinfo
        if charinfo then
            return ("%s %s"):format(charinfo.firstname or '', charinfo.lastname or '')
        end
    elseif _G.ESX then
        if player.getName then
            return player.getName()
        elseif player.get and player.get('firstName') then
            return ("%s %s"):format(player.get('firstName'), player.get('lastName'))
        end
    end
    return GetPlayerName(source)
end

Framework.ShowNotification = function(source, message)
    if _G.QBCore then
        TriggerClientEvent('QBCore:Notify', source, message)
    elseif _G.ESX then
        TriggerClientEvent('esx:showNotification', source, message)
    end
end