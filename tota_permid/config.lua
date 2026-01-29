Config = {}

-- MAIN CONFIG
Config.Framework = 'qbcore' -- 'esx' or 'qbcore'
Config.AdminPermission = 'admin'
Config.Debug = true

-- Método de asignación de PermID:
-- 'random'    = IDs aleatorios (rápido, menos predecible)
-- 'increment' = IDs secuenciales (1,2,3,...)
Config.IdAssignmentMethod = 'random'

-- ID OverHead
Config.MaxPermId = 50000
Config.OverheadIdCommand = 'ids'
Config.ShowName = true
Config.RainbowEffect = true -- Activa el efecto RGB cambiante
Config.RainbowSpeed = 0.002 -- Velocidad del cambio de color

-- Admin Panel
Config.AdminPanelCommand = 'idpanel'
Config.DiscordWebhook = ''
Config.ServerName = 'Mi Servidor'
Config.KickMessage = 'Has sido expulsado del servidor por un administrador.'

-- DB Config
Config.Database = {
    -- ESX: 'users' | QBCore: 'players'
    UsersTable = 'players',
    -- ESX: normalmente 'identifier' | QBCore: 'license'
    LicenseColumn = 'license'
}

Config.Translations = {
    -- Client
    IDsOnHeadEnabled   = 'Overhead IDs enabled.',
    IDsOnHeadDisabled  = 'Overhead IDs disabled.',
    TeleportedByAdmin  = 'You have been teleported by an admin.',
    FreezedMessage     = 'You have been frozen by an admin.',
    UnfreezedMessage   = 'You have been unfrozen by an admin.',
    InvalidModel       = 'Invalid vehicle model: ',
    CouldNotLoadModel  = 'Could not load the model: ',
    VehicleReceived    = 'You have received a vehicle from an admin.',
    VehicleError       = 'Error while spawning the vehicle.',
    SpectateOff        = 'Spectate mode disabled.',
    SpectateSelfError  = 'You cannot spectate yourself.',
    SpectateUnavailable= 'The target player is not available.',
    SpectateOn         = 'Now spectating %s. Press [X] to stop.',
    
    -- Server
    NoPermission       = 'You do not have permission to use this.',
    InvalidTarget      = 'Invalid target.',
    NotInCache         = 'Player is not in cache.',
    PlayerKicked       = 'Player %s has been kicked.',
    PlayerKilled       = 'Player %s has been killed.',
    PlayerRevived      = 'Player %s has been revived.',
    FreezeToggled      = 'Freeze toggled for %s.',
    SpectateStarted    = 'Started spectating %s.',
    PlayerBrought      = 'You brought %s to your location.',
    PlayerGoto         = 'You teleported to %s.',
    VehicleGiven       = 'Vehicle %s given to %s.',
    ModelInvalid       = 'Invalid vehicle model.',
    UnknownAction      = 'Unknown action.',
    PanelResynced      = 'Admin panel resynced.',
    InfoSentDiscord    = 'Information sent to Discord.',
    WebhookNotSet      = 'Discord webhook not configured.'
}

Config.RevivePlayer = function(playerId)
    if Config.Framework == 'esx' then
        TriggerClientEvent('esx_ambulancejob:revive', playerId)
    elseif Config.Framework == 'qbcore' then
        TriggerClientEvent('hospital:client:Revive', playerId)
    end
end

Config.KillPlayer = function(playerId)
    if Config.Framework == 'esx' then
        TriggerClientEvent('esx:killPlayer', playerId)
    elseif Config.Framework == 'qbcore' then
        TriggerClientEvent('QBCore:Client:SetDead', playerId, true)
    end
end