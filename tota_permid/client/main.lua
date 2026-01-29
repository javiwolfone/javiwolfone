if not Config then
    print('[tota_permid] ERROR: config.lua no cargado.')
    return
end

local PlayerCache = {}
local pendingPlayerRequests = {}
local lastCacheRequest = 0
local isOverheadIdVisible = false
local OverheadDrawDistance = 20.0
local isPlayerFrozen = false
local isSpectating, spectatingTarget = false, nil
local savedCoords = nil
local nuiOpen = false

local function dprint(fmt, ...)
    if Config.Debug then print(('[tota_permid][cl] ' .. tostring(fmt)):format(...)) end
end

local function NormalizeKey(k) 
    return tostring(k)
end

local function Notify(msg, t)
    if Framework and Framework.Notify then
        Framework.Notify(msg, t)
    else
        print('[tota_permid] '..tostring(msg))
    end
end

local function RequestServerCache()
    local now = GetGameTimer()
    if now - lastCacheRequest < 2000 then return end -- Throttling
    lastCacheRequest = now
    TriggerServerEvent('tota:server:requestCache')
end

RegisterNetEvent('tota:client:updateCache', function(serverCache)
    local newCache, count = {}, 0
    if serverCache then
        for k, v in pairs(serverCache) do
            newCache[NormalizeKey(k)] = v
            count = count + 1
        end
    end
    PlayerCache = newCache
    dprint('Caché actualizada: %d jugadores', count)

    for srvId, callbacks in pairs(pendingPlayerRequests) do
        local k = NormalizeKey(srvId)
        if PlayerCache[k] then
            for _, cb in ipairs(callbacks) do cb(PlayerCache[k]) end
            pendingPlayerRequests[srvId] = nil
        end
    end
end)

RegisterNetEvent('tota:client:receivePlayerData', function(serverId, playerData)
    local key = NormalizeKey(serverId)
    PlayerCache[key] = playerData
    if pendingPlayerRequests[serverId] then
        for _, cb in ipairs(pendingPlayerRequests[serverId]) do cb(playerData) end
        pendingPlayerRequests[serverId] = nil
    end
end)

local function GetPlayerData(serverId, callback)
    local key = NormalizeKey(serverId)
    if PlayerCache[key] then
        if callback then callback(PlayerCache[key]) end
        return PlayerCache[key]
    end
    if not pendingPlayerRequests[serverId] then pendingPlayerRequests[serverId] = {} end
    if callback then table.insert(pendingPlayerRequests[serverId], callback) end
    
    if #pendingPlayerRequests[serverId] <= 1 then
        TriggerServerEvent('tota:server:requestPlayerData', serverId)
    end
    return nil
end

local function onClientPlayerLoaded()
    Wait(1500)
    TriggerServerEvent('tota:server:clientIsReady')
    Wait(500)
    RequestServerCache()
end

if Framework and Framework.OnPlayerLoaded then
    Framework.OnPlayerLoaded(onClientPlayerLoaded)
else
    -- Fallback por si el bridge no está cargado aún
    CreateThread(function() Wait(2500) onClientPlayerLoaded() end)
end

-- =========================================================
-- Overhead ID (OPTIMIZADO)
-- =========================================================
local function GetRainbowColor(speed)
    local timer = GetGameTimer() * (speed or 0.002)
    local r = math.floor(math.sin(timer) * 127 + 128)
    local g = math.floor(math.sin(timer + 2) * 127 + 128)
    local b = math.floor(math.sin(timer + 4) * 127 + 128)
    return r, g, b
end

local function DrawTextSimple(x, y, text, scale, font, center, r, g, b, a)
    SetTextScale(scale, scale)
    SetTextFont(font or 0)
    SetTextProportional(1)
    SetTextCentre(center and true or false)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextOutline()
    
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function DrawOverheadLabel(worldX, worldY, worldZ, idLine, nameLine, distance)
    local onScreen, sx, sy = World3dToScreen2d(worldX, worldY, worldZ)
    if not onScreen then return end

    local maxScale, minScale = 0.38, 0.22
    local distClamp = math.max(1.0, math.min(distance, OverheadDrawDistance))
    local scale = maxScale - ((distClamp / OverheadDrawDistance) * (maxScale - minScale))
    if scale < minScale then scale = minScale end

    local idText   = tostring(idLine or '')
    local nameText = tostring(nameLine or '')

    local r, g, b = 255, 225, 120
    if Config.RainbowEffect then
        r, g, b = GetRainbowColor(Config.RainbowSpeed)
    end

    DrawTextSimple(sx, sy, idText, scale, 0, true, r, g, b, 255)

    if nameText ~= '' then
        local y2 = sy + 0.022
        DrawTextSimple(sx, y2, nameText, scale * 0.82, 0, true, r, g, b, 215)
    end
end

local function ToggleOverhead()
    isOverheadIdVisible = not isOverheadIdVisible
    local status = isOverheadIdVisible and (Config.Translations.IDsOnHeadEnabled or 'IDs Activadas') or (Config.Translations.IDsOnHeadDisabled or 'IDs Desactivadas')
    Notify(status, 'primary')
    dprint('Overhead toggle: ' .. tostring(isOverheadIdVisible))
end

RegisterCommand(Config.OverheadIdCommand or 'ids', ToggleOverhead, false)
RegisterCommand('id', ToggleOverhead, false)

CreateThread(function()
    while true do
        local sleep = 1000
        if isOverheadIdVisible then
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)
            local players = GetActivePlayers()
            local drawnCount = 0

            for _, pid in ipairs(players) do
                local serverId = GetPlayerServerId(pid)
                local tgtPed = GetPlayerPed(pid)
                
                if DoesEntityExist(tgtPed) then
                    local coords = GetEntityCoords(tgtPed)
                    local dist = #(myCoords - coords)
                    
                    if dist < OverheadDrawDistance then
                        local data = PlayerCache[NormalizeKey(serverId)]
                        -- Si no hay data aún, intentamos pedirla (una vez)
                        if not data then GetPlayerData(serverId) end

                        if data and data.permId then
                            drawnCount = drawnCount + 1
                            sleep = 5
                            local namePart = (Config.ShowName and (data.name or '') or '')
                            local idLine = string.format('[%s | %s]', tostring(serverId), tostring(data.permId))
                            DrawOverheadLabel(coords.x, coords.y, coords.z + 1.1, idLine, namePart, dist)
                        end
                    end
                end
            end
            
            if drawnCount == 0 then sleep = 500 end
        end
        Wait(sleep)
    end
end)

-- =========================================================
-- Admin: TP / Freeze / Vehículo
-- =========================================================
RegisterNetEvent('tota:client:teleport', function(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    Notify(Config.Translations.TeleportedByAdmin, 'primary')
end)

RegisterNetEvent('tota:client:toggleFreeze', function()
    isPlayerFrozen = not isPlayerFrozen
    FreezeEntityPosition(PlayerPedId(), isPlayerFrozen)
    Notify((isPlayerFrozen and Config.Translations.FreezedMessage or Config.Translations.UnfreezedMessage), isPlayerFrozen and 'warning' or 'primary')
end)

RegisterNetEvent('tota:client:spawnVehicle', function(model)
    local modelHash = type(model) == "number" and model or GetHashKey(model)
    if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then
        Notify(Config.Translations.InvalidModel .. tostring(model), 'error')
        return
    end

    CreateThread(function()
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 100 do Wait(10) timeout = timeout + 1 end
        if not HasModelLoaded(modelHash) then
            Notify(Config.Translations.CouldNotLoadModel .. tostring(model), 'error')
            return
        end

        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local veh = CreateVehicle(modelHash, pCoords.x, pCoords.y, pCoords.z, heading, true, false)
        if DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            TaskWarpPedIntoVehicle(ped, veh, -1)
            Notify(Config.Translations.VehicleReceived, 'success')
        else
            Notify(Config.Translations.VehicleError, 'error')
        end
        SetModelAsNoLongerNeeded(modelHash)
    end)
end)

local function StartSpectating(targetPed)
    local ped = PlayerPedId()
    savedCoords = GetEntityCoords(ped)

    local tCoords = GetEntityCoords(targetPed)
    RequestCollisionAtCoord(tCoords.x, tCoords.y, tCoords.z)
    SetEntityVisible(ped, false, 0)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)

    SetEntityCoords(ped, tCoords.x, tCoords.y, tCoords.z + 5.0)
    Wait(250)
    NetworkSetInSpectatorMode(true, targetPed)

    isSpectating = true
end

local function StopSpectating()
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, 0)

    if savedCoords then
        RequestCollisionAtCoord(savedCoords.x, savedCoords.y, savedCoords.z)
        SetEntityCoords(ped, savedCoords.x, savedCoords.y, savedCoords.z)
        savedCoords = nil
    end

    isSpectating, spectatingTarget = false, nil
end

RegisterNetEvent('tota:client:spectatePlayer', function(targetId)
    if isSpectating and spectatingTarget == targetId then
        StopSpectating()
        Notify(Config.Translations.SpectateOff)
        return
    end

    if isSpectating then StopSpectating() end

    if targetId == GetPlayerServerId(PlayerId()) then
        Notify(Config.Translations.SpectateSelfError, "error")
        return
    end

    local targetPlayer = GetPlayerFromServerId(targetId)
    if targetPlayer == -1 then
        Notify(Config.Translations.SpectateUnavailable, "error")
        return
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if not DoesEntityExist(targetPed) then
        Notify(Config.Translations.SpectateUnavailable, "error")
        return
    end

    spectatingTarget = targetId
    StartSpectating(targetPed)
    local data = PlayerCache[NormalizeKey(targetId)]
    local name = (data and data.name) or GetPlayerName(targetPlayer)
    Notify(Config.Translations.SpectateOn:format(name))
end)

CreateThread(function()
    while true do
        local sleep = 500
        if isSpectating then
            sleep = 0
            if IsControlJustPressed(0, 73) then -- X
                StopSpectating()
                Notify(Config.Translations.SpectateOff)
            end
        end
        Wait(sleep)
    end
end)

RegisterCommand("spectateoff", function()
    if isSpectating then
        StopSpectating()
        Notify(Config.Translations.SpectateOff)
    end
end, false)

RegisterKeyMapping("spectateoff", "Salir del especteo", "keyboard", "X")

local function ClosePanel()
    SetNuiFocus(false, false)
    nuiOpen = false
    SendNUIMessage({ action = 'togglePanel', show = false })
end

RegisterNetEvent('tota:client:toggleAdminPanel', function(serverCache)
    if nuiOpen then
        ClosePanel()
    else
        PlayerCache = serverCache or PlayerCache
        SendNUIMessage({ action = 'togglePanel', show = true, players = PlayerCache })
        SetNuiFocus(true, true)
        nuiOpen = true
    end
end)

RegisterNUICallback('closePanel', function(_, cb)
    ClosePanel()
    cb('ok')
end)

RegisterNUICallback('performAdminAction', function(data, cb)
    TriggerServerEvent('tota:server:performAdminAction', data)
    cb('ok')
end)

RegisterNUICallback('requestPlayerData', function(data, cb)
    local id = tonumber(data.serverId)
    if not id then cb({ ok = false }) return end
    local info = GetPlayerData(id, function(p) cb({ ok = true, data = p }) end)
    if info then cb({ ok = true, data = info }) end
end)

AddEventHandler('onClientResourceStop', function(res)
    if GetCurrentResourceName() ~= res then return end
    PlayerCache, pendingPlayerRequests = {}, {}
    if nuiOpen then SetNuiFocus(false, false) nuiOpen = false end
    if isSpectating then StopSpectating() end
end)

exports('GetServerIdFromPermId', function(permId)
    if not permId then return false end
    for sid, data in pairs(PlayerCache) do
        if tonumber(data.permId) == tonumber(permId) then return tonumber(sid) end
    end
    return false
end)

exports('GetPlayerDataWithFallback', function(serverId, cb)
    return GetPlayerData(serverId, cb)
end)

exports('HasPlayerInCache', function(serverId)
    return PlayerCache[NormalizeKey(serverId)] ~= nil
end)

exports('GetPlayerCache', function() return PlayerCache end)

exports('SpectatePlayer', function(serverId)
    TriggerEvent('tota:client:spectatePlayer', tonumber(serverId))
end)

exports('IsSpectating', function()
    return isSpectating, spectatingTarget
end)

dprint('Cliente cargado y optimizado.')
