-- server/fire_handler.lua - Smart Fire System
local FireHandler = {}

-- Initialize fire handler
function FireHandler.Initialize()
    print("^2[SmartFire]^7 Fire Handler initialized")
end

-- Validate fire creation
function FireHandler.ValidateFireCreation(x, y, z, radius, dimension)
    -- Check position bounds
    if not Utils.IsValidPosition(x, y, z) then
        return false, "Invalid position coordinates"
    end

    -- Check radius bounds
    if radius and (radius < Config.Fire.MinRadius or radius > Config.Fire.MaxRadius) then
        return false, string.format("Radius must be between %.1f and %.1f", Config.Fire.MinRadius, Config.Fire.MaxRadius)
    end

    -- Check dimension bounds
    if dimension and (dimension < 0 or dimension > 9999) then
        return false, "Dimension must be between 0 and 9999"
    end

    -- Check fire limit
    local currentCount = exports[GetCurrentResourceName()]:GetFireCount()
    if currentCount >= Config.MaxFires then
        return false, string.format("Maximum fire limit reached (%d)", Config.MaxFires)
    end

    return true
end

-- Check if position is safe for fire
function FireHandler.IsPositionSafe(x, y, z, radius)
    -- Check for water
    local waterHeight = GetWaterHeight(x, y, z)
    if waterHeight and waterHeight > z - 1.0 then
        return false, "Cannot create fire in water"
    end

    -- Check for existing fires too close
    local fires = exports[GetCurrentResourceName()]:GetFires()
    for fireId, fireData in pairs(fires) do
        local distance = Utils.GetDistance({ x = x, y = y, z = z }, fireData)
        if distance < (radius + fireData.radius) then
            return false, "Too close to existing fire"
        end
    end

    return true
end

-- Calculate fire intensity based on type and conditions
function FireHandler.CalculateFireIntensity(fireType, radius, conditions)
    local baseIntensity = 1.0

    -- Apply fire type modifiers
    if Config.Fire.Types[fireType] then
        baseIntensity = Config.Fire.Types[fireType].intensity or 1.0
    end

    -- Apply radius modifiers
    local radiusModifier = math.min(2.0, radius / Config.Fire.DefaultRadius)

    -- Apply environmental conditions (future feature)
    local conditionModifier = 1.0
    if conditions then
        if conditions.wind then conditionModifier = conditionModifier * 1.2 end
        if conditions.rain then conditionModifier = conditionModifier * 0.5 end
        if conditions.humidity then conditionModifier = conditionModifier * (1.0 - conditions.humidity * 0.3) end
    end

    return baseIntensity * radiusModifier * conditionModifier
end

-- Get fire statistics
function FireHandler.GetStatistics()
    local fires = exports[GetCurrentResourceName()]:GetFires()
    local stats = {
        total = 0,
        byType = { small = 0, medium = 0, large = 0 },
        byDimension = {},
        avgAge = 0,
        totalAge = 0,
        avgRadius = 0,
        totalRadius = 0,
        spreading = 0
    }

    local currentTime = GetGameTimer()

    for fireId, fireData in pairs(fires) do
        stats.total = stats.total + 1

        -- Count by type
        local fireType = fireData.type or "medium"
        stats.byType[fireType] = (stats.byType[fireType] or 0) + 1

        -- Count by dimension
        local dim = fireData.dimension or 0
        stats.byDimension[dim] = (stats.byDimension[dim] or 0) + 1

        -- Calculate age
        local age = currentTime - fireData.createdAt
        stats.totalAge = stats.totalAge + age

        -- Calculate radius
        stats.totalRadius = stats.totalRadius + fireData.radius

        -- Count spreading fires
        if fireData.spreadCount and fireData.spreadCount > 0 then
            stats.spreading = stats.spreading + 1
        end
    end

    if stats.total > 0 then
        stats.avgAge = math.floor(stats.totalAge / stats.total / 1000) -- Convert to seconds
        stats.avgRadius = Utils.Round(stats.totalRadius / stats.total, 1)
    end

    return stats
end

-- Update fire properties
function FireHandler.UpdateFireProperties(fireId, properties)
    local fires = exports[GetCurrentResourceName()]:GetFires()
    local fireData = fires[fireId]

    if not fireData then
        return false, "Fire not found"
    end

    -- Update allowed properties
    local allowedProps = { "radius", "intensity", "type", "lifetime", "dimension" }
    local updated = false

    for _, prop in ipairs(allowedProps) do
        if properties[prop] ~= nil then
            fireData[prop] = properties[prop]
            updated = true
        end
    end

    if updated then
        -- Sync updated fire to all clients
        TriggerClientEvent('smartfire:syncFire', -1, fireId, fireData)
        Utils.DebugPrint("Updated fire %s properties", fireId)
    end

    return updated
end

-- Check fire health/status
function FireHandler.CheckFireHealth(fireData)
    local currentTime = GetGameTimer()
    local age = currentTime - fireData.createdAt

    local health = {
        age = age,
        agePercent = fireData.lifetime > 0 and (age / fireData.lifetime) * 100 or 0,
        isExpiring = fireData.lifetime > 0 and age >= fireData.lifetime * 0.9,
        isExpired = fireData.lifetime > 0 and age >= fireData.lifetime,
        spreadCount = fireData.spreadCount or 0,
        maxSpreadReached = (fireData.spreadCount or 0) >= Config.Fire.MaxSpreadCount
    }

    return health
end

-- Get fires by criteria
function FireHandler.GetFiresByCriteria(criteria)
    local fires = exports[GetCurrentResourceName()]:GetFires()
    local results = {}

    for fireId, fireData in pairs(fires) do
        local matches = true

        if criteria.dimension and fireData.dimension ~= criteria.dimension then
            matches = false
        end

        if criteria.type and fireData.type ~= criteria.type then
            matches = false
        end

        if criteria.minRadius and fireData.radius < criteria.minRadius then
            matches = false
        end

        if criteria.maxRadius and fireData.radius > criteria.maxRadius then
            matches = false
        end

        if criteria.position and criteria.maxDistance then
            local distance = Utils.GetDistance(fireData, criteria.position)
            if distance > criteria.maxDistance then
                matches = false
            end
        end

        if criteria.maxAge then
            local age = GetGameTimer() - fireData.createdAt
            if age > criteria.maxAge then
                matches = false
            end
        end

        if matches then
            results[fireId] = fireData
        end
    end

    return results
end

-- Cleanup expired and invalid fires
function FireHandler.CleanupInvalidFires()
    local fires = exports[GetCurrentResourceName()]:GetFires()
    local currentTime = GetGameTimer()
    local cleanupCount = 0

    for fireId, fireData in pairs(fires) do
        local shouldRemove = false
        local reason = ""

        -- Check if expired
        if fireData.lifetime > 0 then
            local age = currentTime - fireData.createdAt
            if age >= fireData.lifetime then
                shouldRemove = true
                reason = "expired"
            end
        end

        -- Check if data is corrupted
        local isValid, error = FireManager.ValidateFireData(fireData)
        if not isValid then
            shouldRemove = true
            reason = "invalid data: " .. error
        end

        -- Check if position is still valid
        if not Utils.IsValidPosition(fireData.x, fireData.y, fireData.z) then
            shouldRemove = true
            reason = "invalid position"
        end

        if shouldRemove then
            exports[GetCurrentResourceName()]:RemoveFire(fireId)
            cleanupCount = cleanupCount + 1
            Utils.DebugPrint("Cleaned up fire %s: %s", fireId, reason)
        end
    end

    return cleanupCount
end

-- Export functions
exports('ValidateFireCreation', FireHandler.ValidateFireCreation)
exports('IsPositionSafe', FireHandler.IsPositionSafe)
exports('CalculateFireIntensity', FireHandler.CalculateFireIntensity)
exports('GetFireStatistics', FireHandler.GetStatistics)
exports('UpdateFireProperties', FireHandler.UpdateFireProperties)
exports('CheckFireHealth', FireHandler.CheckFireHealth)
exports('GetFiresByCriteria', FireHandler.GetFiresByCriteria)
exports('CleanupInvalidFires', FireHandler.CleanupInvalidFires)

-- Initialize on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        FireHandler.Initialize()

        -- Start cleanup thread
        CreateThread(function()
            while true do
                Wait(60000) -- Check every minute
                FireHandler.CleanupInvalidFires()
            end
        end)
    end
end)
