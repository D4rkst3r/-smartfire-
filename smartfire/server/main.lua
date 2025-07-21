-- Server Main - Smart Fire System
local SmartFire = {}
SmartFire.Fires = {}
SmartFire.NextFireId = 1

-- Initialize system
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("^2[SmartFire]^7 System gestartet. Version 1.0.0")
        print("^2[SmartFire]^7 Maximale Feuer: " .. Config.MaxFires)

        -- Start spreading thread if enabled
        if Config.Fire.EnableSpreading then
            CreateThread(function()
                SmartFire.SpreadingLoop()
            end)
        end

        -- Start cleanup thread
        CreateThread(function()
            SmartFire.CleanupLoop()
        end)
    end
end)

-- Resource stop cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("^3[SmartFire]^7 System gestoppt. Alle Feuer gelöscht.")
        SmartFire.ClearAllFires()
    end
end)

-- Player joined - sync all fires
AddEventHandler('playerJoining', function()
    local source = source

    CreateThread(function()
        Wait(2000) -- Wait for player to fully load

        for fireId, fireData in pairs(SmartFire.Fires) do
            TriggerClientEvent('smartfire:syncFire', source, fireId, fireData)
        end

        Utils.DebugPrint("Synced %d fires to player %d",
            SmartFire.GetFireCount(), source)
    end)
end)

-- Create new fire
function SmartFire.CreateFire(x, y, z, radius, dimension, lifetime, fireType)
    -- Validate parameters
    local isValid, errors = Utils.ValidateFireParams(x, y, z, radius, dimension)
    if not isValid then
        return false, table.concat(errors, ", ")
    end

    -- Check fire limit
    if SmartFire.GetFireCount() >= Config.MaxFires then
        return false, string.format(Config.Notifications.MaxFiresReached, Config.MaxFires)
    end

    -- Generate fire data
    local fireId = "fire_" .. SmartFire.NextFireId
    SmartFire.NextFireId = SmartFire.NextFireId + 1

    -- Use server-compatible ground Z calculation
    local groundZ = z
    if Utils.GetEstimatedGroundLevel then
        groundZ = Utils.GetEstimatedGroundLevel(x, y, z)
    end

    local fireData = {
        id = fireId,
        x = x,
        y = y,
        z = groundZ,
        radius = radius or Config.Fire.DefaultRadius,
        dimension = dimension or Config.DefaultDimension,
        createdAt = GetGameTimer(),
        lifetime = lifetime or Config.Fire.DefaultLifetime,
        type = fireType or "medium",
        spreadCount = 0,
        lastSpreadCheck = GetGameTimer()
    }

    -- Apply fire type settings
    if Config.Fire.Types[fireType] then
        local typeData = Config.Fire.Types[fireType]
        fireData.radius = typeData.radius
        fireData.intensity = typeData.intensity
        fireData.spreadChance = typeData.spreadChance
    end

    -- Store fire
    SmartFire.Fires[fireId] = fireData

    -- Sync to all clients
    TriggerClientEvent('smartfire:syncFire', -1, fireId, fireData)

    Utils.DebugPrint("Fire created: %s at %s", fireId,
        Utils.CoordsToString(x, y, z))

    return true, fireId, fireData
end

-- Remove fire
function SmartFire.RemoveFire(fireId)
    if not SmartFire.Fires[fireId] then
        return false, Config.Notifications.FireNotFound:format(fireId)
    end

    SmartFire.Fires[fireId] = nil
    TriggerClientEvent('smartfire:removeFire', -1, fireId)

    Utils.DebugPrint("Fire removed: %s", fireId)
    return true
end

-- Clear all fires
function SmartFire.ClearAllFires()
    local count = SmartFire.GetFireCount()
    SmartFire.Fires = {}
    TriggerClientEvent('smartfire:clearAllFires', -1)

    Utils.DebugPrint("All fires cleared: %d fires", count)
    return count
end

-- Get fire count
function SmartFire.GetFireCount()
    local count = 0
    for _ in pairs(SmartFire.Fires) do
        count = count + 1
    end
    return count
end

-- Fire spreading logic
function SmartFire.SpreadingLoop()
    while true do
        Wait(Config.Fire.SpreadInterval)

        for fireId, fireData in pairs(SmartFire.Fires) do
            if SmartFire.ShouldFireSpread(fireData) then
                SmartFire.SpreadFire(fireData)
            end
        end
    end
end

-- Check if fire should spread
function SmartFire.ShouldFireSpread(fireData)
    if not Config.Fire.EnableSpreading then return false end
    if fireData.spreadCount >= Config.Fire.MaxSpreadCount then return false end
    if SmartFire.GetFireCount() >= Config.MaxFires then return false end

    local timeSinceLastCheck = GetGameTimer() - fireData.lastSpreadCheck
    if timeSinceLastCheck < Config.Fire.SpreadInterval then return false end

    local spreadChance = fireData.spreadChance or Config.Fire.SpreadChance
    return math.random() < spreadChance
end

-- Spread fire to nearby location
function SmartFire.SpreadFire(fireData)
    fireData.lastSpreadCheck = GetGameTimer()

    -- Get random position within spread radius
    local newPos = Utils.GetRandomPositionInRadius(
        { x = fireData.x, y = fireData.y, z = fireData.z },
        Config.Fire.SpreadRadius
    )

    -- Check if position is too close to existing fires
    for existingId, existingFire in pairs(SmartFire.Fires) do
        if existingFire.dimension == fireData.dimension then
            local distance = Utils.GetDistance(newPos, existingFire)
            if distance < (existingFire.radius + fireData.radius) * 0.5 then
                return -- Too close to existing fire
            end
        end
    end

    -- Create new fire
    local success, newFireId = SmartFire.CreateFire(
        newPos.x, newPos.y, newPos.z,
        fireData.radius * 0.8,   -- Slightly smaller
        fireData.dimension,
        fireData.lifetime * 0.7, -- Shorter lifetime
        fireData.type
    )

    if success then
        fireData.spreadCount = fireData.spreadCount + 1
        Utils.DebugPrint("Fire %s spread to %s", fireData.id, newFireId)
    end
end

-- Cleanup expired fires
function SmartFire.CleanupLoop()
    while true do
        Wait(Config.UpdateInterval * 10) -- Check every 10 update intervals

        local currentTime = GetGameTimer()
        local expiredFires = {}

        for fireId, fireData in pairs(SmartFire.Fires) do
            if fireData.lifetime > 0 then
                local age = currentTime - fireData.createdAt
                if age >= fireData.lifetime then
                    table.insert(expiredFires, fireId)
                end
            end
        end

        -- Remove expired fires
        for _, fireId in ipairs(expiredFires) do
            SmartFire.RemoveFire(fireId)
            Utils.DebugPrint("Fire expired: %s", fireId)
        end
    end
end

-- Event handlers
RegisterNetEvent('smartfire:extinguishFire')
AddEventHandler('smartfire:extinguishFire', function(fireId)
    local source = source

    if SmartFire.RemoveFire(fireId) then
        Utils.Notify(source, Config.Notifications.FireExtinguished, 'success')
    end
end)

RegisterNetEvent('smartfire:requestSync')
AddEventHandler('smartfire:requestSync', function()
    local source = source

    for fireId, fireData in pairs(SmartFire.Fires) do
        TriggerClientEvent('smartfire:syncFire', source, fireId, fireData)
    end
end)

-- Export functions for other resources
exports('CreateFire', function(x, y, z, radius, dimension, lifetime, fireType)
    return SmartFire.CreateFire(x, y, z, radius, dimension, lifetime, fireType)
end)

exports('RemoveFire', function(fireId)
    return SmartFire.RemoveFire(fireId)
end)

exports('GetFires', function()
    return SmartFire.Fires
end)

exports('GetFireCount', function()
    return SmartFire.GetFireCount()
end)
