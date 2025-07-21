Config = {}

-- General Settings
Config.MaxFires = 50          -- Maximum number of simultaneous fires
Config.DefaultDimension = 0   -- Default dimension for fires
Config.UpdateInterval = 1000  -- Update interval in ms
Config.RenderDistance = 100.0 -- Distance to render fires
Config.DebugMode = true       -- Global debug mode

-- Fire Behavior
Config.Fire = {
    -- Lifetime settings
    DefaultLifetime = 300000, -- 5 minutes in ms (0 = infinite)
    MinLifetime = 30000,      -- Minimum 30 seconds
    MaxLifetime = 1800000,    -- Maximum 30 minutes

    -- Spreading settings
    EnableSpreading = true,
    SpreadChance = 0.15,    -- 15% chance per spread check
    SpreadInterval = 10000, -- Check for spreading every 10 seconds
    SpreadRadius = 8.0,     -- Maximum spread distance
    MaxSpreadCount = 3,     -- Maximum fires that can spawn from one fire

    -- Size and intensity
    DefaultRadius = 3.0,
    MinRadius = 1.0,
    MaxRadius = 15.0,

    -- Fire types
    Types = {
        small = { radius = 2.0, intensity = 0.3, spreadChance = 0.1 },
        medium = { radius = 5.0, intensity = 0.6, spreadChance = 0.15 },
        large = { radius = 10.0, intensity = 1.0, spreadChance = 0.25 }
    }
}

-- Effects Configuration
Config.Effects = {
    EnableParticles = true,
    EnableSmoke = true,
    EnableLight = true,
    EnableHeat = false, -- Heat damage (future feature)

    -- Particle settings
    ParticleDict = "core",
    ParticleName = "fire_wrecked_plane_cockpit",
    SmokeDict = "core",
    SmokeName = "exp_grd_bzgas_smoke",

    -- Light settings
    LightIntensity = 8.0,
    LightRange = 15.0,
    LightColor = { r = 255, g = 100, b = 0 }
}

-- Extinguishing Methods
Config.Extinguish = {
    EnableExtinguisher = true,
    EnableWater = true,
    EnableCommands = true,
    EnableVehicles = false, -- Future feature

    ExtinguisherRange = 8.0,
    ExtinguishTime = 3000, -- 3 seconds to extinguish
    WaterRange = 5.0
}

-- Performance Settings
Config.Performance = {
    MaxParticlesPerFire = 3,
    ReduceEffectsDistance = 50.0,   -- Reduce effects beyond this distance
    DisableEffectsDistance = 150.0, -- Disable effects beyond this distance
    ThreadSleepNear = 100,          -- Sleep time when near fires
    ThreadSleepFar = 500            -- Sleep time when far from fires
}

-- Commands & Permissions
Config.Commands = {
    StartFire = "startfire",
    StopFire = "stopfire",
    ClearFires = "clearfires",
    SetDimension = "setfiredimension",
    ToggleDebug = "togglefiredebug",
    ListFires = "listfires"
}

Config.Permissions = {
    RequireAcePermission = false,
    AcePermission = "smartfire.admin",
    AllowedGroups = { "admin", "moderator" }
}

-- Notifications
Config.Notifications = {
    FireStarted = "🔥 Feuer gestartet bei %s",
    FireStopped = "🚒 Feuer gelöscht: ID %s",
    FireExtinguished = "🚒 Feuer erfolgreich gelöscht!",
    AllFiresCleared = "🚒 Alle Feuer gelöscht (%s Feuer)",
    NoPermission = "❌ Keine Berechtigung für diesen Befehl",
    FireNotFound = "❌ Feuer mit ID %s nicht gefunden",
    MaxFiresReached = "❌ Maximum von %s Feuern erreicht",
    InvalidParameters = "❌ Ungültige Parameter. Verwendung: %s"
}
