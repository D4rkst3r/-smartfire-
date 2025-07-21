-- =============================================================================
-- client/fire_renderer.lua - Smart Fire System
-- =============================================================================

local FireRenderer = {}
FireRenderer.RenderQueue = {}
FireRenderer.LastRenderUpdate = 0

-- Main rendering loop
CreateThread(function()
    while true do
        local currentTime = GetGameTimer()

        if currentTime - FireRenderer.LastRenderUpdate > 100 then
            FireRenderer.ProcessRenderQueue()
            FireRenderer.LastRenderUpdate = currentTime
        end

        Wait(50)
    end
end)

-- Add fire to render queue
function FireRenderer.AddToRenderQueue(fireId, fireData, distance)
    FireRenderer.RenderQueue[fireId] = {
        data = fireData,
        distance = distance,
        priority = FireRenderer.GetRenderPriority(distance)
    }
end

-- Remove fire from render queue
function FireRenderer.RemoveFromRenderQueue(fireId)
    FireRenderer.RenderQueue[fireId] = nil
end

-- Get render priority based on distance
function FireRenderer.GetRenderPriority(distance)
    if distance <= 25.0 then
        return 1                          -- High priority
    elseif distance <= 50.0 then
        return 2                          -- Medium priority
    else
        return 3                          -- Low priority
    end
end

-- Process render queue
function FireRenderer.ProcessRenderQueue()
    -- Sort by priority
    local sortedFires = {}
    for fireId, renderData in pairs(FireRenderer.RenderQueue) do
        table.insert(sortedFires, { id = fireId, data = renderData })
    end

    table.sort(sortedFires, function(a, b)
        return a.data.priority < b.data.priority
    end)

    -- Render fires based on priority
    local renderedCount = 0
    local maxRender = Config.Performance.MaxParticlesPerFire * 5

    for _, fireEntry in ipairs(sortedFires) do
        if renderedCount >= maxRender then break end

        FireRenderer.RenderFire(fireEntry.data.data, fireEntry.data.distance)
        renderedCount = renderedCount + 1
    end
end

-- Render individual fire
function FireRenderer.RenderFire(fireData, distance)
    if distance > Config.Performance.DisableEffectsDistance then return end

    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius
    local intensity = fireData.intensity or 1.0

    -- Adjust intensity based on distance
    if distance > Config.Performance.ReduceEffectsDistance then
        intensity = intensity * 0.5
    end

    -- Render based on fire size
    if radius <= 3.0 then
        FireRenderer.RenderSmallFire(x, y, z, radius, intensity)
    elseif radius <= 7.0 then
        FireRenderer.RenderMediumFire(x, y, z, radius, intensity)
    else
        FireRenderer.RenderLargeFire(x, y, z, radius, intensity)
    end
end

-- Render small fire
function FireRenderer.RenderSmallFire(x, y, z, radius, intensity)
    UseParticleAsset("core")
    StartParticleFxLoopedAtCoord("fire_wrecked_plane_cockpit", x, y, z, 0.0, 0.0, 0.0, radius * intensity, false, false,
        false, false)
end

-- Render medium fire
function FireRenderer.RenderMediumFire(x, y, z, radius, intensity)
    UseParticleAsset("core")
    StartParticleFxLoopedAtCoord("fire_wrecked_plane_cockpit", x, y, z, 0.0, 0.0, 0.0, radius * intensity, false, false,
        false, false)
    StartParticleFxLoopedAtCoord("exp_grd_bzgas_smoke", x, y, z + 1, 0.0, 0.0, 0.0, radius * 0.7, false, false, false,
        false)
end

-- Render large fire
function FireRenderer.RenderLargeFire(x, y, z, radius, intensity)
    FireRenderer.RenderMediumFire(x, y, z, radius, intensity)

    UseParticleAsset("scr_trevor1")
    StartParticleFxLoopedAtCoord("scr_trev1_trailer_boosh", x, y, z, 0.0, 0.0, 0.0, radius * 0.8, false, false, false,
        false)
end

-- Export functions
exports('AddToRenderQueue', FireRenderer.AddToRenderQueue)
exports('RemoveFromRenderQueue', FireRenderer.RemoveFromRenderQueue)

-- =============================================================================
-- client/commands.lua - Smart Fire System
-- =============================================================================

-- Client-side command handlers
RegisterNetEvent('smartfire:clientCommand')
AddEventHandler('smartfire:clientCommand', function(command, args)
    if command == "nearest" then
        local playerCoords = GetEntityCoords(PlayerPedId())
        local nearestFire = nil
        local nearestDistance = math.huge

        local nearbyFires = exports['smartfire']:GetNearbyFires()

        for fireId, fireData in pairs(nearbyFires) do
            local distance = Utils.GetDistance(playerCoords, fireData)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestFire = { id = fireId, data = fireData, distance = distance }
            end
        end

        if nearestFire then
            Utils.Notify(nil, string.format("Nächstes Feuer: %s (%.1fm)", nearestFire.id, nearestFire.distance), 'info')
        else
            Utils.Notify(nil, "Keine Feuer in der Nähe", 'info')
        end
    end
end)

-- Local fire extinguisher command
RegisterCommand('extinguish', function(source, args, rawCommand)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local nearbyFires = exports['smartfire']:GetNearbyFires()

    local nearestFire = nil
    local nearestDistance = Config.Extinguish.ExtinguisherRange + 1.0

    for fireId, fireData in pairs(nearbyFires) do
        local distance = Utils.GetDistance(playerCoords, fireData)
        if distance <= Config.Extinguish.ExtinguisherRange and distance < nearestDistance then
            nearestFire = fireId
            nearestDistance = distance
        end
    end

    if nearestFire then
        TriggerServerEvent('smartfire:extinguishFire', nearestFire)
    else
        Utils.Notify(nil, "Kein Feuer in Reichweite", 'error')
    end
end, false)

-- =============================================================================
-- server/fire_handler.lua - Smart Fire System
-- =============================================================================

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

-- Get fire statistics
function FireHandler.GetStatistics()
    local fires = exports[GetCurrentResourceName()]:GetFires()
    local stats = {
        total = 0,
        byType = { small = 0, medium = 0, large = 0 },
        byDimension = {},
        avgAge = 0,
        totalAge = 0
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
    end

    if stats.total > 0 then
        stats.avgAge = stats.totalAge / stats.total
    end

    return stats
end

-- Export functions
exports('ValidateFireCreation', FireHandler.ValidateFireCreation)
exports('GetFireStatistics', FireHandler.GetStatistics)

-- Initialize on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        FireHandler.Initialize()
    end
end)

-- =============================================================================
-- server/sync.lua - Smart Fire System
-- =============================================================================

local SyncManager = {}
SyncManager.PlayerDimensions = {}
SyncManager.LastSyncTime = {}

-- Track player dimensions
RegisterNetEvent('smartfire:updateDimension')
AddEventHandler('smartfire:updateDimension', function(dimension)
    local source = source
    SyncManager.PlayerDimensions[source] = dimension

    -- Resync fires for new dimension
    CreateThread(function()
        Wait(100) -- Brief delay
        SyncManager.SyncFiresForPlayer(source)
    end)
end)

-- Sync fires for specific player
function SyncManager.SyncFiresForPlayer(playerId)
    local playerDim = SyncManager.PlayerDimensions[playerId] or 0
    local fires = exports[GetCurrentResourceName()]:GetFires()

    for fireId, fireData in pairs(fires) do
        if fireData.dimension == playerDim then
            TriggerClientEvent('smartfire:syncFire', playerId, fireId, fireData)
        end
    end

    Utils.DebugPrint("Synced dimension %d fires to player %d", playerDim, playerId)
end

-- Bulk sync for dimension
function SyncManager.SyncDimension(dimension, excludePlayer)
    local fires = exports[GetCurrentResourceName()]:GetFires()

    for playerId, playerDim in pairs(SyncManager.PlayerDimensions) do
        if playerDim == dimension and playerId ~= excludePlayer then
            for fireId, fireData in pairs(fires) do
                if fireData.dimension == dimension then
                    TriggerClientEvent('smartfire:syncFire', playerId, fireId, fireData)
                end
            end
        end
    end
end

-- Cleanup disconnected players
AddEventHandler('playerDropped', function(reason)
    local source = source
    SyncManager.PlayerDimensions[source] = nil
    SyncManager.LastSyncTime[source] = nil
end)

-- Export functions
exports('SyncFiresForPlayer', SyncManager.SyncFiresForPlayer)
exports('SyncDimension', SyncManager.SyncDimension)

-- =============================================================================
-- core/fire_manager.lua - Smart Fire System
-- =============================================================================

local FireManager = {}
FireManager.Version = "1.0.0"

-- Core fire management functions
function FireManager.GetVersion()
    return FireManager.Version
end

-- Validate fire data integrity
function FireManager.ValidateFireData(fireData)
    local required = { "id", "x", "y", "z", "radius", "dimension", "createdAt" }

    for _, field in ipairs(required) do
        if fireData[field] == nil then
            return false, "Missing required field: " .. field
        end
    end

    return true
end

-- Calculate fire spread probability
function FireManager.CalculateSpreadProbability(fireData, targetPosition)
    local distance = Utils.GetDistance(fireData, targetPosition)
    local baseChance = fireData.spreadChance or Config.Fire.SpreadChance

    -- Reduce chance based on distance
    local distanceFactor = math.max(0, 1 - (distance / Config.Fire.SpreadRadius))

    -- Reduce chance based on fire age
    local age = GetGameTimer() - fireData.createdAt
    local ageFactor = math.max(0.1, 1 - (age / 300000)) -- Reduce over 5 minutes

    return baseChance * distanceFactor * ageFactor
end

-- Get optimal fire position
function FireManager.GetOptimalFirePosition(x, y, z)
    local groundZ = Utils.GetGroundZ(x, y, z)

    -- Check for water
    local waterHeight = GetWaterHeight(x, y, z)
    if waterHeight and waterHeight > groundZ then
        return nil, "Cannot create fire in water"
    end

    return { x = x, y = y, z = groundZ }, nil
end

-- Export core functions
if IsDuplicityVersion() then
    exports('ValidateFireData', FireManager.ValidateFireData)
    exports('CalculateSpreadProbability', FireManager.CalculateSpreadProbability)
    exports('GetOptimalFirePosition', FireManager.GetOptimalFirePosition)
    exports('GetFireManagerVersion', FireManager.GetVersion)
end
