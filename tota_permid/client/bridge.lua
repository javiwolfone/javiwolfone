Framework = {}
_G.ESX = nil
_G.QBCore = nil

local function DetectFramework()
    if GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
        Config.Framework = 'qbcore'
        _G.QBCore = exports['qb-core']:GetCoreObject()
        return 'qbcore'
    elseif GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
        Config.Framework = 'esx'
        pcall(function()
            _G.ESX = exports['es_extended']:getSharedObject()
        end)
        if not _G.ESX then
            TriggerEvent('esx:getSharedObject', function(obj) _G.ESX = obj end)
        end
        return 'esx'
    end
    return nil
end

DetectFramework()

Framework.Notify = function(message, t)
    if _G.QBCore then
        _G.QBCore.Functions.Notify(message, t or "primary")
    elseif _G.ESX then
        _G.ESX.ShowNotification(message)
    else
        print("[CLIENT][Notify] " .. tostring(message))
    end
end

Framework.OnPlayerLoaded = function(cb)
    if _G.QBCore then
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() 
            cb(_G.QBCore.Functions.GetPlayerData()) 
        end)
        if _G.QBCore.Functions.GetPlayerData() and _G.QBCore.Functions.GetPlayerData().citizenid then
            cb(_G.QBCore.Functions.GetPlayerData())
        end
    elseif _G.ESX then
        RegisterNetEvent('esx:playerLoaded', function(xPlayer) 
            cb(xPlayer) 
        end)
        if _G.ESX.IsPlayerLoaded and _G.ESX.IsPlayerLoaded() then
            cb(_G.ESX.GetPlayerData())
        elseif _G.ESX.GetPlayerData and _G.ESX.GetPlayerData().identifier then
            cb(_G.ESX.GetPlayerData())
        end
    else
        CreateThread(function()
            Wait(2000)
            cb({})
        end)
    end
end

Framework.GetPlayerData = function()
    if _G.QBCore then
        return _G.QBCore.Functions.GetPlayerData()
    elseif _G.ESX then
        return _G.ESX.GetPlayerData()
    end
    return {}
end