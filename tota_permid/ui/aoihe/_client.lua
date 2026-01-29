local ESX, QBCore
if Config.Framework == 'esx' then
    ESX = exports["es_extended"]:getSharedObject()
elseif Config.Framework == 'qbcore' then
    QBCore = exports['qb-core']:GetCoreObject()
end

local isOverheadIdVisible = false
local PlayerCache = {}
local OverheadDrawDistance = 20.0
local LocalPlayerId = PlayerId()
local LocalPlayerPed = PlayerPedId()
local isPlayerFrozen = false
local isSpectating = false
local spectatingTarget = nil

-- Variables para el sistema de fallback
local pendingPlayerRequests = {}
local lastCacheRequest = 0

-- Función para solicitar caché del servidor
local function RequestServerCache()
    local currentTime = GetGameTimer()
    if currentTime - lastCacheRequest < 1000 then return end -- Evitar spam
    
    lastCacheRequest = currentTime
    TriggerServerEvent('tota_permid:server:requestCache')
    
    if Config.Debug then
        print('[tota_permid] Solicitando caché del servidor...')
    end
end

-- Actualizar variables cuando el resource se inicia
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    LocalPlayerId = PlayerId()
    LocalPlayerPed = PlayerPedId()
    
    -- Solicitar caché del servidor después de un breve delay
    Citizen.Wait(1000)
    RequestServerCache()
end)

-- =================================================================
-- SISTEMA DE CACHÉ Y SINCRONIZACIÓN MEJORADO
-- =================================================================

-- Receptor principal de caché del servidor
RegisterNetEvent('tota_permid:client:updateCache', function(serverCache)
    if Config.Debug then
        local playerCount = 0
        if serverCache then 
            for _ in pairs(serverCache) do playerCount = playerCount + 1 end 
        end
        print(('[tota_permid] Caché recibida/actualizada con %s jugadores.'):format(playerCount))
    end
    
    PlayerCache = serverCache or {}
    
    -- Resolver solicitudes pendientes
    for serverId, callbacks in pairs(pendingPlayerRequests) do
        if PlayerCache[tostring(serverId)] then
            for _, callback in ipairs(callbacks) do
                callback(PlayerCache[tostring(serverId)])
            end
            pendingPlayerRequests[serverId] = nil
        end
    end
end)

-- Receptor para datos específicos de jugador (fallback)
RegisterNetEvent('tota_permid:client:receivePlayerData', function(serverId, playerData)
    if Config.Debug then
        print(('[tota_permid] Recibidos datos fallback para jugador %s.'):format(serverId))
    end
    
    -- Actualizar caché local con los datos recibidos
    PlayerCache[tostring(serverId)] = playerData
    
    -- Resolver callbacks pendientes
    if pendingPlayerRequests[serverId] then
        for _, callback in ipairs(pendingPlayerRequests[serverId]) do
            callback(playerData)
        end
        pendingPlayerRequests[serverId] = nil
    end
end)

-- Función para obtener datos de jugador con fallback automático
local function GetPlayerData(serverId, callback)
    local serverIdStr = tostring(serverId)
    
    -- Si ya tenemos los datos, devolver inmediatamente
    if PlayerCache[serverIdStr] then
        if callback then callback(PlayerCache[serverIdStr]) end
        return PlayerCache[serverIdStr]
    end
    
    -- Si no tenemos los datos, solicitar al servidor
    if callback then
        -- Agregar callback a la lista de pendientes
        if not pendingPlayerRequests[serverId] then
            pendingPlayerRequests[serverId] = {}
        end
        table.insert(pendingPlayerRequests[serverId], callback)
        
        -- Solicitar datos al servidor (solo si no hay otras solicitudes pendientes)
        if #pendingPlayerRequests[serverId] == 1 then
            TriggerServerEvent('tota_permid:server:requestPlayerData', serverId)
            if Config.Debug then
                print(('[tota_permid] Solicitando datos fallback para jugador %s.'):format(serverId))
            end
        end
    end
    
    return nil
end

-- =================================================================
-- HANDSHAKE: EL CLIENTE NOTIFICA AL SERVIDOR CUANDO ESTÁ LISTO
-- =================================================================

local function onClientPlayerLoaded()
    Citizen.Wait(1500) -- Esperar más tiempo para asegurar estabilidad
    if Config.Debug then 
        print('[tota_permid] Cliente completamente cargado. Notificando al servidor...') 
    end
    
    -- Notificar al servidor que estamos listos
    TriggerServerEvent('tota_permid:server:clientIsReady')
    
    -- También solicitar caché como backup
    Citizen.Wait(500)
    RequestServerCache()
end

if Config.Framework == 'esx' then
    AddEventHandler('esx:playerLoaded', onClientPlayerLoaded)
elseif Config.Framework == 'qbcore' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
    AddEventHandler('QBCore:Client:OnPlayerLoaded', onClientPlayerLoaded)
end

-- Backup para cuando no se dispara el evento del framework
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Esperar 5 segundos después del spawn
    if not next(PlayerCache) then -- Si no tenemos caché aún
        if Config.Debug then
            print('[tota_permid] Backup: Solicitando caché después de 5 segundos sin recibirla.')
        end
        RequestServerCache()
    end
end)

-- =================================================================
-- COMANDO PARA VER IDS Y BUCLE DE RENDERIZADO MEJORADO
-- =================================================================

RegisterCommand(Config.OverheadIdCommand, function()
    isOverheadIdVisible = not isOverheadIdVisible
    local status = isOverheadIdVisible and "activado" or "desactivado"
    
    if Config.Framework == 'esx' then 
        ESX.ShowNotification("IDs sobre la cabeza " .. status .. ".")
    elseif Config.Framework == 'qbcore' then 
        QBCore.Functions.Notify("IDs sobre la cabeza " .. status .. ".", "primary") 
    end
    
    if Config.Debug then
        print(('[tota_permid] IDs overhead %s. Jugadores en caché: %s'):format(status, GetTableLength(PlayerCache)))
    end
end, false)

-- Thread mejorado para renderizado de IDs
CreateThread(function()
    while true do
        if isOverheadIdVisible then
            local playerCoords = GetEntityCoords(LocalPlayerPed)
            local activePlayers = GetActivePlayers()
            local playersDrawn = 0
            
            for _, targetPlayerId in ipairs(activePlayers) do
                local targetServerId = GetPlayerServerId(targetPlayerId)
                local targetServerIdStr = tostring(targetServerId)
                
                -- Intentar obtener datos del jugador
                local data = PlayerCache[targetServerIdStr]
                
                if data then
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if DoesEntityExist(targetPed) then
                        local targetCoords = GetEntityCoords(targetPed)
                        local distance = #(playerCoords - targetCoords)
                        
                        if distance < OverheadDrawDistance then
                            local displayText = string.format("[%s | %s] %s", targetServerId, data.permId, data.name)
                            if targetPlayerId == LocalPlayerId then 
                                displayText = displayText .. " (Tú)" 
                            end
                            DrawText3D(targetCoords.x, targetCoords.y, targetCoords.z + 1.0, displayText)
                            playersDrawn = playersDrawn + 1
                        end
                    end
                else
                    -- Si no tenemos datos, solicitarlos automáticamente (fallback)
                    GetPlayerData(targetServerId, function(playerData)
                        if Config.Debug then
                            print(('[tota_permid] Datos fallback recibidos para %s: %s'):format(targetServerId, playerData.name))
                        end
                    end)
                end
            end
            
            Wait(5) -- Renderizado suave
        else
            Wait(500) -- Esperar más cuando no está visible
        end
    end
end)

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(_x, _y)
    
    local factor = (string.len(text)) / 370
    DrawRect(_x, _y + 0.0125, 0.005 + factor, 0.03, 41, 11, 41, 68)
end

-- =================================================================
-- EVENTOS DE ACCIONES DE ADMINISTRADOR MEJORADOS
-- =================================================================

RegisterNetEvent('tota_permid:client:teleport', function(coords)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, true)
    
    if Config.Framework == 'esx' then 
        ESX.ShowNotification("Has sido teletransportado por un administrador.")
    elseif Config.Framework == 'qbcore' then
        QBCore.Functions.Notify("Has sido teletransportado por un administrador.", "primary")
    end
end)

RegisterNetEvent('tota_permid:client:toggleFreeze', function()
    isPlayerFrozen = not isPlayerFrozen
    FreezeEntityPosition(PlayerPedId(), isPlayerFrozen)
    local status = isPlayerFrozen and "congelado" or "descongelado"

    if Config.Framework == 'esx' then 
        ESX.ShowNotification("Has sido " .. status .. " por un admin.")
    elseif Config.Framework == 'qbcore' then
        QBCore.Functions.Notify("Has sido " .. status .. " por un admin.", "warning")
    end
end)

RegisterNetEvent('tota_permid:client:spawnVehicle', function(model)
    local modelHash = GetHashKey(model)
    if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then
        if Config.Framework == 'esx' then 
            ESX.ShowNotification("Modelo de vehículo inválido: " .. model) 
        elseif Config.Framework == 'qbcore' then
            QBCore.Functions.Notify("Modelo de vehículo inválido: " .. model, "error")
        end
        return
    end

    if Config.Framework == 'esx' then
        ESX.Game.SpawnVehicle(model, GetEntityCoords(PlayerPedId()), 90.0, function(vehicle)
            TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
            ESX.ShowNotification("Has recibido un vehículo de un administrador.")
        end)
    elseif Config.Framework == 'qbcore' then
        QBCore.Functions.SpawnVehicle(model, function(vehicle)
            TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
            QBCore.Functions.Notify("Has recibido un vehículo de un administrador.", "success")
        end, GetEntityCoords(PlayerPedId()), true)
    end
end)

-- =================================================================
-- SISTEMA DE ESPECTEO COMPLETAMENTE REHECHO
-- =================================================================

RegisterNetEvent('tota_permid:client:spectatePlayer', function(targetId)
    local targetPlayerId = GetPlayerFromServerId(targetId)
    
    if targetPlayerId == -1 or not DoesEntityExist(GetPlayerPed(targetPlayerId)) then
        if Config.Framework == 'esx' then 
            ESX.ShowNotification("El jugador objetivo no está disponible.")
        elseif Config.Framework == 'qbcore' then
            QBCore.Functions.Notify("El jugador objetivo no está disponible.", "error")
        end
        return
    end
    
    local targetPed = GetPlayerPed(targetPlayerId)
    
    if isSpectating then
        -- Salir del modo espectador
        StopSpectating()
    else
        -- Entrar en modo espectador
        StartSpectating(targetPed, targetId)
    end
end)

function StartSpectating(targetPed, targetId)
    if not DoesEntityExist(targetPed) then return end
    
    isSpectating = true
    spectatingTarget = targetId
    
    -- Hacer invisible al jugador actual
    SetEntityVisible(PlayerPedId(), false, false)
    SetEntityCollision(PlayerPedId(), false, false)
    FreezeEntityPosition(PlayerPedId(), true)
    
    -- Configurar la cámara de espectador
    NetworkSetInSpectatorMode(true, targetPed)
    
    if Config.Framework == 'esx' then 
        ESX.ShowNotification("Modo espectador activado. Presiona [X] para salir.")
    elseif Config.Framework == 'qbcore' then
        QBCore.Functions.Notify("Modo espectador activado. Presiona [X] para salir.", "primary")
    end
    
    if Config.Debug then
        print(('[tota_permid] Iniciando especteo del jugador %s'):format(targetId))
    end
end

function StopSpectating()
    if not isSpectating then return end
    
    isSpectating = false
    spectatingTarget = nil
    
    -- Restaurar el jugador
    NetworkSetInSpectatorMode(false, PlayerPedId())
    SetEntityVisible(PlayerPedId(), true, false)
    SetEntityCollision(PlayerPedId(), true, true)
    FreezeEntityPosition(PlayerPedId(), false)
    
    if Config.Framework == 'esx' then 
        ESX.ShowNotification("Modo espectador desactivado.")
    elseif Config.Framework == 'qbcore' then
        QBCore.Functions.Notify("Modo espectador desactivado.", "primary")
    end
    
    if Config.Debug then
        print('[tota_permid] Especteo desactivado.')
    end
end

-- Thread para controlar la salida del modo espectador
CreateThread(function()
    while true do
        if isSpectating then
            -- Comprobar si se presiona X para salir
            if IsControlJustPressed(0, 73) then -- 73 es la tecla X
                StopSpectating()
            end
            
            -- Verificar si el objetivo sigue existiendo
            if spectatingTarget then
                local targetPlayerId = GetPlayerFromServerId(spectatingTarget)
                if targetPlayerId == -1 or not DoesEntityExist(GetPlayerPed(targetPlayerId)) then
                    if Config.Framework == 'esx' then 
                        ESX.ShowNotification("El jugador objetivo se ha desconectado.")
                    elseif Config.Framework == 'qbcore' then
                        QBCore.Functions.Notify("El jugador objetivo se ha desconectado.", "warning")
                    end
                    StopSpectating()
                end
            end
            
            Wait(100)
        else
            Wait(1000)
        end
    end
end)

-- Asegurar que el especteo se desactive si el resource se reinicia
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isSpectating then
        StopSpectating()
    end
end)

-- =================================================================
-- EXPORTS Y FUNCIONES DE UTILIDAD
-- =================================================================

-- Export mejorado para obtener Server ID desde Perm ID
exports('GetServerIdFromPermId', function(permId)
    if not permId or not PlayerCache then
        return false
    end

    for serverId, data in pairs(PlayerCache) do
        if data.permId == tonumber(permId) then
            return tonumber(serverId)
        end
    end

    return false
end)

-- Export para obtener datos de jugador con fallback
exports('GetPlayerDataWithFallback', function(serverId, callback)
    return GetPlayerData(serverId, callback)
end)

-- Export para verificar si tenemos datos en caché
exports('HasPlayerInCache', function(serverId)
    return PlayerCache[tostring(serverId)] ~= nil
end)

-- Export para obtener toda la caché actual
exports('GetPlayerCache', function()
    return PlayerCache
end)

-- Comando de debug para administradores
RegisterCommand('debugcache', function()
    if Config.Debug then
        print('=== TOTA_PERMID DEBUG CACHE ===')
        print(('Cache contains %s players:'):format(GetTableLength(PlayerCache)))
        for serverId, data in pairs(PlayerCache) do
            print(('  [%s] %s (PermID: %s)'):format(serverId, data.name, data.permId))
        end
        print('==============================')
    end
end, false)

-- Función helper para contar elementos en tabla
function GetTableLength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- =================================================================
-- EVENTOS ADICIONALES Y LIMPIEZA
-- =================================================================

-- Limpiar variables al cambiar de personaje (para multicharacter)
AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Limpiar estados
    isOverheadIdVisible = false
    isPlayerFrozen = false
    if isSpectating then
        StopSpectating()
    end
    
    -- Limpiar caché
    PlayerCache = {}
    pendingPlayerRequests = {}
end)

-- Actualizar LocalPlayerPed periódicamente por si cambia
CreateThread(function()
    while true do
        LocalPlayerPed = PlayerPedId()
        LocalPlayerId = PlayerId()
        Wait(1000)
    end
end)