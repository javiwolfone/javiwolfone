local PlayerDataCache = {}
local PlayersLoading = {}

-- Función mejorada para sincronizar caché con todos los clientes
local function SyncCacheWithAllClients()
    Wait(100) -- Pequeña espera para asegurar consistencia
    TriggerClientEvent('tota_permid:client:updateCache', -1, PlayerDataCache)
    if Config.Debug then 
        local playerCount = 0
        for _ in pairs(PlayerDataCache) do playerCount = playerCount + 1 end
        print('[tota_permid]: Sincronizando caché con todos los clientes. Total jugadores en caché: ' .. playerCount)
    end
end

-- Función para sincronizar caché con un cliente específico
local function SyncCacheWithClient(source)
    TriggerClientEvent('tota_permid:client:updateCache', source, PlayerDataCache)
    if Config.Debug then 
        print(('[tota_permid]: Sincronizando caché específicamente con el jugador %s (%s)'):format(GetPlayerName(source), source))
    end
end

function HandleFinalPlayerData(source, license, discordId)
    local query = string.format('SELECT permid FROM `%s` WHERE `%s` = @license AND permid IS NOT NULL LIMIT 1', 
        Config.Database.UsersTable, Config.Database.LicenseColumn)
    
    MySQL.Async.fetchAll(query, {['@license'] = license}, function(result)
        if result[1] and result[1].permid then
            local existingPermId = result[1].permid
            if Config.Debug then print(('[tota_permid]: El jugador %s ya tiene un PermID existente: %s.'):format(GetPlayerName(source), existingPermId)) end
            
            local syncQuery = string.format('UPDATE `%s` SET permid = @permid, discord = @discord WHERE `%s` = @license AND permid IS NULL', 
                Config.Database.UsersTable, Config.Database.LicenseColumn)
            MySQL.Async.execute(syncQuery, {
                ['@permid'] = existingPermId, ['@discord'] = discordId, ['@license'] = license
            })
            
            LoadPlayerIntoCache(source, license, discordId, existingPermId)
        else
            if Config.Debug then print(('[tota_permid]: El jugador %s no tiene PermID. Generando uno nuevo...'):format(GetPlayerName(source))) end
            GenerateAndAssignNewPermId(source, license, discordId)
        end
    end)
end


AddEventHandler('playerJoining', function(oldId, reason)
    local source = source
    if Config.Debug then print(string.format('[DEBUG 1/3] Evento playerJoining para source %s.', source)) end

    local license, discordId
    local attempts = 0
    while not license and attempts < 10 do
        license = GetPlayerIdentifierByType(source, 'license')
        discordId = GetPlayerIdentifierByType(source, 'discord')
        if not license then Wait(200); attempts = attempts + 1 end
    end
    
    if not license then
        if Config.Debug then print(string.format('[DEBUG FALLED] No se pudo obtener la licencia para source %s en playerJoining.', source)) end
        return
    end

    if Config.Debug then print(string.format('[DEBUG 2/3] Licencia %s obtenida para %s. Guardando en PlayersLoading.', license, source)) end
    
    PlayersLoading[source] = {
        license = license,
        discord = discordId and discordId:gsub('discord:', '') or nil
    }
end)

local function OnPlayerFullyLoaded(source)
    if not PlayersLoading[source] then 
        if Config.Debug then print(string.format('[DEBUG WARNING] playerLoaded para %s, pero no hay datos en PlayersLoading. Probablemente un reinicio de script.', source)) end
        local license = GetPlayerIdentifierByType(source, 'license')
        local discordId = GetPlayerIdentifierByType(source, 'discord')
        if not license then return end
        PlayersLoading[source] = { license = license, discord = discordId and discordId:gsub('discord:', '') or nil }
    end

    if Config.Debug then print(string.format('[DEBUG 3/3] Evento playerLoaded para %s. Procesando datos finales...', source)) end

    local playerData = PlayersLoading[source]
    HandleFinalPlayerData(source, playerData.license, playerData.discord)

    PlayersLoading[source] = nil
end

if Config.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded')
    AddEventHandler('esx:playerLoaded', function(source, xPlayer) OnPlayerFullyLoaded(source) end)
elseif Config.Framework == 'qbcore' then
    RegisterNetEvent('QBCore:Server:OnPlayerLoaded')
    AddEventHandler('QBCore:Server:OnPlayerLoaded', function() OnPlayerFullyLoaded(source) end)
end

-- Eventos del framework para cuando un jugador está completamente cargado
if Config.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded')
    AddEventHandler('esx:playerLoaded', function(source, xPlayer)
        if PlayerDataCache[source] then
            if Config.Debug then 
                print(('[tota_permid]: ESX Player Loaded para %s. Sincronizando...'):format(GetPlayerName(source))) 
            end
            -- Enviar caché al jugador que acaba de cargar
            SyncCacheWithClient(source)
            -- Sincronizar con todos para que vean al nuevo jugador
            SyncCacheWithAllClients()
        end
    end)
elseif Config.Framework == 'qbcore' then
    RegisterNetEvent('QBCore:Server:OnPlayerLoaded')
    AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
        local source = source
        local player = Framework.GetPlayer(source)
        if player and PlayerDataCache[source] then
            if Config.Debug then 
                print(('[tota_permid]: QBCore Player Loaded para %s. Sincronizando...'):format(GetPlayerName(source))) 
            end
            -- Enviar caché al jugador que acaba de cargar
            SyncCacheWithClient(source)
            -- Sincronizar con todos para que vean al nuevo jugador
            SyncCacheWithAllClients()
        end
    end)
end

-- Al iniciar el resource, procesar jugadores existentes
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print('[tota_permid]: El script se ha iniciado. Sincronizando jugadores en línea...')
    Citizen.Wait(2000) 
    
    for _, playerId in ipairs(GetPlayers()) do
        OnPlayerFullyLoaded(playerId)
    end
end)

-- Cuando un jugador se conecta
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    deferrals.defer()
    Citizen.Wait(100)
    deferrals.update(string.format("Hola %s, verificando tu ID permanente...", name))
    
    CreateThread(function()
        HandlePlayerConnection(source)
    end)
    
    deferrals.done()
end)

-- Cuando un jugador se desconecta
AddEventHandler('playerDropped', function(reason)
    local source = source
    if PlayerDataCache[source] then
        if Config.Debug then print(('[tota_permid]: El jugador %s se ha desconectado.'):format(GetPlayerName(source))) end
        PlayerDataCache[source] = nil
        SyncCacheWithAllClients()
    end
    if PlayersLoading[source] then PlayersLoading[source] = nil end
end)

-- [[================================================================
-- LÓGICA CENTRAL DE ID PERMANENTE
-- ================================================================]]

function HandlePlayerConnection(source)
    local licenseIdentifier = GetPlayerIdentifierByType(source, 'license')
    if not licenseIdentifier then 
        print(('[tota_permid]: AVISO: No se pudo obtener la licencia para el jugador con ID de servidor %s. No se puede asignar PermID.'):format(source))
        return 
    end

    -- Comprobar si este jugador ya tiene un PermID
    local query = string.format('SELECT permid FROM `%s` WHERE `%s` = @license AND permid IS NOT NULL LIMIT 1', 
        Config.Database.UsersTable, Config.Database.LicenseColumn)
    
    MySQL.Async.fetchAll(query, {
        ['@license'] = licenseIdentifier
    }, function(result)
        if result[1] and result[1].permid then
            -- El jugador ya tiene un PermID
            local existingPermId = result[1].permid
            if Config.Debug then 
                print(('[tota_permid]: El jugador %s ya tiene un PermID existente: %s. Sincronizando personajes...'):format(
                    GetPlayerName(source), existingPermId
                )) 
            end
            
            -- Asegurar que TODOS los personajes tengan el mismo PermID
            local syncQuery = string.format('UPDATE `%s` SET permid = @permid WHERE `%s` = @license AND permid IS NULL', 
                Config.Database.UsersTable, Config.Database.LicenseColumn)
            MySQL.Async.execute(syncQuery, {
                ['@permid'] = existingPermId,
                ['@license'] = licenseIdentifier
            })
            
            LoadPlayerIntoCache(source, licenseIdentifier, existingPermId)
        else
            -- El jugador es nuevo, generar PermID
            if Config.Debug then 
                print(('[tota_permid]: El jugador %s no tiene PermID. Generando uno nuevo...'):format(GetPlayerName(source))) 
            end
            GenerateAndAssignNewPermId(source, licenseIdentifier)
        end
    end)
end

function GenerateAndAssignNewPermId(source, license, retries)
    if Config.IdAssignmentMethod == 'increment' then
        -- Método incremental
        local getMaxIdQuery = string.format('SELECT MAX(permid) as maxId FROM `%s`', Config.Database.UsersTable)
        
        MySQL.Async.fetchAll(getMaxIdQuery, {}, function(result)
            local highestId = (result and result[1] and result[1].maxId) or 0
            local newPermId = highestId + 1

            local updateQuery = string.format('UPDATE `%s` SET permid = @permid WHERE `%s` = @license', 
                Config.Database.UsersTable, Config.Database.LicenseColumn)
            MySQL.Async.execute(updateQuery, {
                ['@permid'] = newPermId,
                ['@license'] = license
            }, function(affectedRows)
                if affectedRows > 0 then
                    if Config.Debug then 
                        print(('[tota_permid]: Asignado nuevo PermID incremental %s al jugador %s.'):format(
                            newPermId, GetPlayerName(source)
                        )) 
                    end
                    LoadPlayerIntoCache(source, license, newPermId)
                else
                    print(('[tota_permid]: AVISO: La asignación de PermID incremental no afectó a ninguna fila para %s.'):format(
                        GetPlayerName(source)
                    ))
                end
            end)
        end)

    elseif Config.IdAssignmentMethod == 'random' then
        -- Método aleatorio con reintentos
        retries = retries or 0
        if retries >= 15 then
            print(('[tota_permid]: ERROR CRÍTICO! No se pudo asignar un PermID único al jugador %s tras 15 intentos.'):format(
                GetPlayerName(source)
            ))
            DropPlayer(source, "Error crítico al asignar ID de jugador. Por favor, contacta con un administrador.")
            return
        end

        local newPermId = math.random(1, Config.MaxPermId)

        local checkQuery = string.format('SELECT permid FROM `%s` WHERE permid = @permid LIMIT 1', Config.Database.UsersTable)
        MySQL.Async.fetchAll(checkQuery, {
            ['@permid'] = newPermId
        }, function(result)
            if result[1] then
                -- Colisión, reintentar
                if Config.Debug then 
                    print(('[tota_permid]: Colisión de PermID aleatorio (%s). Reintentando...'):format(newPermId)) 
                end
                GenerateAndAssignNewPermId(source, license, retries + 1)
            else
                -- ID libre, asignar
                local updateQuery = string.format('UPDATE `%s` SET permid = @permid WHERE `%s` = @license', 
                    Config.Database.UsersTable, Config.Database.LicenseColumn)
                MySQL.Async.execute(updateQuery, {
                    ['@permid'] = newPermId,
                    ['@license'] = license
                }, function(affectedRows)
                    if affectedRows > 0 then
                        if Config.Debug then 
                            print(('[tota_permid]: Se ha asignado el nuevo PermID %s al jugador %s y sus %s personajes.'):format(
                                newPermId, GetPlayerName(source), affectedRows
                            )) 
                        end
                        LoadPlayerIntoCache(source, license, newPermId)
                    else
                        if Config.Debug then 
                            print(('[tota_permid]: La asignación de PermID no afectó a ninguna fila para %s. Reintentando...'):format(
                                GetPlayerName(source)
                            )) 
                        end
                        Citizen.Wait(100)
                        GenerateAndAssignNewPermId(source, license, retries + 1)
                    end
                end)
            end
        end)
    else
        print('[tota_permid]: ERROR DE CONFIGURACIÓN! El valor de "Config.IdAssignmentMethod" es inválido.')
    end
end

function LoadPlayerIntoCache(source, license, permId)
    local discordIdentifier = GetPlayerIdentifierByType(source, 'discord')
    local discordId
    if discordIdentifier then
        discordId = discordIdentifier:gsub('discord:', '')
        local updateDiscordQuery = string.format('UPDATE `%s` SET discord = @discord WHERE `%s` = @license', 
            Config.Database.UsersTable, Config.Database.LicenseColumn)
        MySQL.Async.execute(updateDiscordQuery, {
            ['@discord'] = discordId,
            ['@license'] = license
        })
    end

    -- Cargar en caché
    PlayerDataCache[source] = {
        name = GetPlayerName(source),
        permId = permId,
        license = license,
        discord = discordId or 'N/A'
    }
    
    if Config.Debug then
        print(('[tota_permid]: Jugador %s (ID: %s, PermID: %s) cargado en la caché del servidor.'):format(
            GetPlayerName(source), source, permId
        ))
    end
    
    -- Sincronizar inmediatamente con el cliente
    SyncCacheWithClient(source)
end

-- Evento cuando el cliente está listo para recibir datos
RegisterNetEvent('tota_permid:server:clientIsReady', function()
    local source = source
    if Config.Debug then 
        print(('[tota_permid]: Cliente %s (%s) reporta estar listo.'):format(GetPlayerName(source), source)) 
    end
    
    CreateThread(function()
        local attempts = 0
        local maxAttempts = 20
        
        while attempts < maxAttempts do
            if PlayerDataCache[source] then
                if Config.Debug then 
                    print(('[tota_permid]: Enviando caché al cliente %s (intento %s).'):format(source, attempts + 1)) 
                end
                SyncCacheWithClient(source)
                return
            end
            attempts = attempts + 1
            Wait(250)
        end
        
        if Config.Debug then 
            print(('[tota_permid]: FALLO: Cliente %s nunca tuvo datos en caché tras %s intentos.'):format(source, maxAttempts)) 
        end
    end)
end)

-- Evento para solicitar caché específica
RegisterNetEvent('tota_permid:server:requestCache', function()
    local source = source 
    SyncCacheWithClient(source)
    
    if Config.Debug then
        print(('[tota_permid]: El jugador %s (%s) ha solicitado la caché.'):format(GetPlayerName(source), source))
    end
end)

-- Evento para solicitar datos específicos de un jugador (fallback)
RegisterNetEvent('tota_permid:server:requestPlayerData', function(targetServerId)
    local source = source
    local targetId = tonumber(targetServerId)
    
    if not targetId or not PlayerDataCache[targetId] then
        if Config.Debug then
            print(('[tota_permid]: Solicitud de datos fallback para jugador %s - no encontrado en caché.'):format(targetId or 'nil'))
        end
        return
    end
    
    -- Enviar solo los datos del jugador solicitado
    TriggerClientEvent('tota_permid:client:receivePlayerData', source, targetId, PlayerDataCache[targetId])
    
    if Config.Debug then
        print(('[tota_permid]: Enviando datos fallback del jugador %s a %s.'):format(targetId, source))
    end
end)

-- [[================================================================
-- GESTOR DE ACCIONES DE ADMINISTRADOR
-- ================================================================]]

RegisterNetEvent('tota_permid:server:performAdminAction', function(data)
    local source = source
    if not Framework.HasPermission(source) then
        Framework.ShowNotification(source, "Error de permisos.")
        return
    end

    local targetId = tonumber(data.targetId)
    local action = data.action

    if Config.Debug then
        print('---[TOTA_PERMID] Admin Action Received ---')
        print(string.format('--> Admin Source: %s (%s)', GetPlayerName(source), source))
        print(string.format('--> Raw data.targetId: %s (type: %s)', tostring(data.targetId), type(data.targetId)))
        print(string.format('--> Processed targetId: %s (type: %s)', tostring(targetId), type(targetId)))
        print(string.format('--> Action: %s', tostring(action)))
        print('-----------------------------------------')
    end

    if not targetId or not PlayerDataCache[targetId] then
        Framework.ShowNotification(source, "El jugador no está en línea.")
        
        if Config.Debug then
            print('---[TOTA_PERMID] CACHE DUMP ON FAILURE ---')
            print(string.format('Lookup failed for key: %s (type: %s)', tostring(targetId), type(targetId)))
            print('Available keys in cache:')
            for k, v in pairs(PlayerDataCache) do
                print(string.format('--> Key: %s (type: %s) | Name: %s', tostring(k), type(k), v.name))
            end
            print('-------------------------------------------')
        end
        return
    end
    
    local targetName = GetPlayerName(targetId)
    local responseMessage = "Acción completada."

    if action == "kick" then
        DropPlayer(targetId, Config.KickMessage)
        responseMessage = "Jugador " .. targetName .. " expulsado."
    elseif action == "kill" then
        Config.KillPlayer(targetId)
        responseMessage = "Jugador " .. targetName .. " asesinado."
    elseif action == "revive" then
        Config.RevivePlayer(targetId)
        responseMessage = "Jugador " .. targetName .. " revivido."
    elseif action == "freeze" then
        TriggerClientEvent('tota_permid:client:toggleFreeze', targetId)
        responseMessage = "Estado de congelación de " .. targetName .. " cambiado."
    elseif action == "spectate" then
        TriggerClientEvent('tota_permid:client:spectatePlayer', source, targetId)
        responseMessage = "Iniciando modo espectador en " .. targetName .. "..."
    elseif action == "bring" then
        local adminCoords = GetEntityCoords(GetPlayerPed(source))
        TriggerClientEvent('tota_permid:client:teleport', targetId, adminCoords)
        responseMessage = "Has traído a " .. targetName .. " a tu posición."
    elseif action == "goto" then
        local targetCoords = GetEntityCoords(GetPlayerPed(targetId))
        TriggerClientEvent('tota_permid:client:teleport', source, targetCoords)
        responseMessage = "Has ido a la posición de " .. targetName .. "."
    elseif action == "giveCar" then
        local model = data.model
        if model and model ~= "" then
            TriggerClientEvent('tota_permid:client:spawnVehicle', targetId, model)
            responseMessage = "Vehículo " .. model .. " entregado a " .. targetName .. "."
        else
            responseMessage = "El modelo del vehículo no puede estar vacío."
        end
    elseif action == "sendToDiscord" then
        SendPlayerInfoToDiscord(source, targetId)
        responseMessage = "Información del jugador enviada a Discord."
    end
    
    Framework.ShowNotification(source, responseMessage)
end)

RegisterCommand(Config.AdminPanelCommand, function(source, args, rawCommand)
    -- if not Framework.HasPermission(source) then
    --     Framework.ShowNotification(source, 'No tienes permiso máquina')
    --     return
    -- end
    TriggerClientEvent('tota_permid:client:toggleAdminPanel', source, PlayerDataCache)
end, false)

function SendPlayerInfoToDiscord(adminSource, targetSource)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" then return end
    
    local adminPlayer = Framework.GetPlayer(adminSource)
    local targetPlayer = Framework.GetPlayer(targetSource)
    local targetCache = PlayerDataCache[targetSource]

    if not targetPlayer or not targetCache then return end

    local adminDiscordId = GetPlayerIdentifierByType(adminSource, 'discord')
    if adminDiscordId then
        adminDiscordId = adminDiscordId:gsub("discord:", "")
    else
        adminDiscordId = "N/A"
    end
    
    local identifiers = {}
    for i = 0, GetNumPlayerIdentifiers(targetSource) - 1 do
        table.insert(identifiers, GetPlayerIdentifier(targetSource, i))
    end

    local jobLabel = "N/A"
    local money = { bank = "N/A", cash = "N/A" }
    
    if Config.Framework == 'esx' then
        jobLabel = targetPlayer.getJob().label
        money.bank = targetPlayer.getAccount('bank').money
        money.cash = targetPlayer.getAccount('black_money').money + targetPlayer.getAccount('money').money
    elseif Config.Framework == 'qbcore' then
        jobLabel = targetPlayer.PlayerData.job.label
        money.bank = targetPlayer.PlayerData.money.bank
        money.cash = targetPlayer.PlayerData.money.cash
    end

    local embed = {
        {
            ["color"] = 15844367,
            ["title"] = "Informe de Jugador - " .. targetCache.name,
            ["description"] = string.format("Información solicitada por <@%s>", adminDiscordId),
            ["fields"] = {
                {
                    ["name"] = "IDs",
                    ["value"] = string.format("```\nServer ID: %s\nPerm ID: %s\n```", targetSource, targetCache.permId),
                    ["inline"] = true
                },
                {
                    ["name"] = "Información",
                    ["value"] = string.format("```\nTrabajo: %s\nBanco: $%s\nEfectivo: $%s\n```", jobLabel, money.bank, money.cash),
                    ["inline"] = true
                },
                {
                    ["name"] = "Identificadores",
                    ["value"] = "```\n" .. table.concat(identifiers, "\n") .. "\n```"
                }
            },
            ["footer"] = {
                ["text"] = Config.ServerName .. " - " .. os.date('%Y-%m-%d %H:%M:%S')
            }
        }
    }

    PerformHttpRequest(Config.DiscordWebhook, function(err, text, headers) end, 'POST', json.encode({ embeds = embed }), { ['Content-Type'] = 'application/json' })
end

exports('GetSourceFromPermId', function(permId)
    if not permId or not PlayerDataCache then
        return false
    end
    
    for source, data in pairs(PlayerDataCache) do
        if data.permId == tonumber(permId) then
            return source
        end
    end

    return false
end)

RegisterCommand('resyncpanel', function(source)
    if not Framework.HasPermission(source) then return end
    
    TriggerClientEvent('tota_permid:client:toggleAdminPanel', source, PlayerDataCache)
    Wait(200)
    TriggerClientEvent('tota_permid:client:toggleAdminPanel', source, PlayerDataCache)
    Framework.ShowNotification(source, "Panel resincronizado con el servidor.")
end, false)