-- Client Main - Smart Fire System
local SmartFire = {}
SmartFire.Fires = {}
SmartFire.NearbyFires = {}
SmartFire.PlayerDimension = 0
SmartFire.IsExtinguishing = false
SmartFire.DebugMode = false

-- Initialize client
CreateThread(function()
    Wait(1000)
    
    -- Request sync from server
    TriggerServerEvent('smartfire:requestSync')
    
    -- Start main update loop
    SmartFire.MainLoop()
    
    -- Start extinguisher check loop
    SmartFire.ExtinguisherLoop()
    
    Utils.DebugPrint("Client initialized")
end)

-- Main update loop
function SmartFire.MainLoop()
    CreateThread(function()
        while true do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local sleepTime = Config.Performance.ThreadSleepFar
            
            -- Update nearby fires
            SmartFire.UpdateNearbyFires(playerCoords)
            
            -- Check if player is near any fires
            local nearFires = false
            for fireId, fireData in pairs(SmartFire.NearbyFires) do
                local distance = Utils.GetDistance(playerCoords, fireData)
                
                if distance <= Config.RenderDistance then
                    nearFires = true
                    sleepTime = Config.Performance.ThreadSleepNear
                    break
                end
            end
            
            -- Update effects for nearby fires
            if nearFires then
                SmartFire.UpdateFireEffects(playerCoords)
            end
            
            -- Debug rendering
            if SmartFire.DebugMode then
                SmartFire.RenderDebugInfo()
            end
            
            Wait(sleepTime)
        end
    end)
end

-- Update nearby fires list
function SmartFire.UpdateNearbyFires(playerCoords)
    SmartFire.NearbyFires = {}
    
    for fireId, fireData in pairs(SmartFire.Fires) do
        -- Check dimension
        if fireData.dimension == SmartFire.PlayerDimension then
            local distance = Utils.GetDistance(playerCoords, fireData)
            
            -- Only include fires within render distance + buffer
            if distance <= Config.RenderDistance + 20.0 then
                SmartFire.NearbyFires[fireId] = fireData
            end
        end
    end
end

-- Update fire effects
function SmartFire.UpdateFireEffects(playerCoords)
    for fireId, fireData in pairs(SmartFire.NearbyFires) do
        local distance = Utils.GetDistance(playerCoords, fireData)
        
        if distance <= Config.RenderDistance then
            -- Render fire effects based on distance
            if distance <= Config.Performance.ReduceEffectsDistance then
                SmartFire.RenderFullEffects(fireData)
            elseif distance <= Config.Performance.DisableEffectsDistance then
                SmartFire.RenderReducedEffects(fireData)
            end
        end
    end
end

-- Render full fire effects
function SmartFire.RenderFullEffects(fireData)
    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius
    
    -- Particle effects
    if Config.Effects.EnableParticles then
        UseParticleAsset(Config.Effects.ParticleDict)
        
        for i = 1, math.min(Config.Performance.MaxParticlesPerFire, math.ceil(radius / 2)) do
            local offsetX = math.random(-radius, radius) / 2
            local offsetY = math.random(-radius, radius) / 2
            
            StartParticleFxLoopedAtCoord(
                Config.Effects.ParticleName,
                x + offsetX, y + offsetY, z,
                0.0, 0.0, 0.0,
                radius / 3.0, false, false, false, false
            )
        end
    end
    
    -- Smoke effects
    if Config.Effects.EnableSmoke then
        UseParticleAsset(Config.Effects.SmokeDict)
        
        StartParticleFxLoopedAtCoord(
            Config.Effects.SmokeName,
            x, y, z + 1.0,
            0.0, 0.0, 0.0,
            radius / 2.0, false, false, false, false
        )
    end
    
    -- Light effects
    if Config.Effects.EnableLight then
        DrawLightWithRange(
            x, y, z + 1.0,
            Config.Effects.LightColor.r,
            Config.Effects.LightColor.g, 
            Config.Effects.LightColor.b,
            Config.Effects.LightRange * (radius / Config.Fire.DefaultRadius),
            Config.Effects.LightIntensity * (fireData.intensity or 1.0)
        )
    end
end

-- Render reduced fire effects (for distant fires)
function SmartFire.RenderReducedEffects(fireData)
    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius
    
    -- Only light and minimal particles for distant fires
    if Config.Effects.EnableLight then
        DrawLightWithRange(
            x, y, z + 1.0,
            Config.Effects.LightColor.r,
            Config.Effects.LightColor.g,
            Config.Effects.LightColor.b,
            Config.Effects.LightRange * 0.5,
            Config.Effects.LightIntensity * 0.5
        )
    end
    
    -- Single particle effect
    if Config.Effects.EnableParticles then
        UseParticleAsset(Config.Effects.ParticleDict)
        
        StartParticleFxLoopedAtCoord(
            Config.Effects.ParticleName,
            x, y, z,
            0.0, 0.0, 0.0,
            radius / 4.0, false, false, false, false
        )
    end
end

-- Extinguisher check loop
function SmartFire.ExtinguisherLoop()
    CreateThread(function()
        while true do
            Wait(500) -- Check every 500ms
            
            if Config.Extinguish.EnableExtinguisher then
                local playerPed = PlayerPedId()
                local weapon = GetSelectedPedWeapon(playerPed)
                
                -- Check if player has fire extinguisher
                if weapon == GetHashKey("WEAPON_FIREEXTINGUISHER") then
                    SmartFire.HandleExtinguisher()
                end
            end
        end
    end)
end

-- Handle fire extinguisher logic
function SmartFire.HandleExtinguisher()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Check if player is shooting extinguisher
    if IsPedShooting(playerPed) then
        -- Find nearest fire within extinguisher range
        local nearestFire = nil
        local nearestDistance = Config.Extinguish.ExtinguisherRange + 1.0
        
        for fireId, fireData in pairs(SmartFire.NearbyFires) do
            local distance = Utils.GetDistance(playerCoords, fireData)
            
            if distance <= Config.Extinguish.ExtinguisherRange and distance < nearestDistance then
                nearestFire = fireId
                nearestDistance = distance
            end
        end
        
        -- Start extinguishing process
        if nearestFire and not SmartFire.IsExtinguishing then
            SmartFire.StartExtinguishing(nearestFire)
        end
    else
        -- Stop extinguishing if not shooting
        if SmartFire.IsExtinguishing then
            SmartFire.StopExtinguishing()
        end
    end
end

-- Start extinguishing fire
function SmartFire.StartExtinguishing(fireId)
    SmartFire.IsExtinguishing = true
    local startTime = GetGameTimer()
    
    CreateThread(function()
        while SmartFire.IsExtinguishing and GetGameTimer() - startTime < Config.Extinguish.ExtinguishTime do
            -- Show progress (you can add progress bar here)
            local progress = (GetGameTimer() - startTime) / Config.Extinguish.ExtinguishTime
            
            -- Add some visual feedback
            if SmartFire.DebugMode then
                local fireData = SmartFire.Fires[fireId]
                if fireData then
                    DrawText3D(fireData.x, fireData.y, fireData.z + 2.0, 
                        string.format("Löschvorgang: %.0f%%", progress * 100))
                end
            end
            
            Wait(100)
        end
        
        -- Fire extinguished
        if SmartFire.IsExtinguishing then
            TriggerServerEvent('smartfire:extinguishFire', fireId)
            SmartFire.IsExtinguishing = false
        end
    end)
end

-- Stop extinguishing
function SmartFire.StopExtinguishing()
    SmartFire.IsExtinguishing = false
end

-- Render debug information
function SmartFire.RenderDebugInfo()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    -- Draw fire markers and info
    for fireId, fireData in pairs(SmartFire.NearbyFires) do
        local x, y, z = fireData.x, fireData.y, fireData.z
        local distance = Utils.GetDistance(playerCoords, fireData)
        
        -- Draw marker
        DrawMarker(1, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, 
            fireData.radius * 2, fireData.radius * 2, 1.0,
            255, 0, 0, 100, false, true, 2, false, nil, nil, false)
        
        -- Draw info text
        local infoText = string.format(
            "ID: %s\nRadius: %.1f\nDist: %.1fm\nDim: %d",
            fireId, fireData.radius, distance, fireData.dimension
        )
        
        DrawText3D(x, y, z + 3.0, infoText)
    end
    
    -- Draw HUD info
    local fireCount = 0
    for _ in pairs(SmartFire.Fires) do fireCount = fireCount + 1 end
    
    local nearbyCount = 0
    for _ in pairs(SmartFire.NearbyFires) do nearbyCount = nearbyCount + 1 end
    
    local debugText = string.format(
        "SmartFire Debug\nTotal: %d | Nearby: %d | Dim: %d\nExtinguishing: %s",
        fireCount, nearbyCount, SmartFire.PlayerDimension,
        SmartFire.IsExtinguishing and "Yes" or "No"
    )
    
    DrawText2D(0.01, 0.3, debugText, 0.3, {255, 255, 255, 255})
end

-- Helper function to draw 3D text
function DrawText3D(x, y, z, text)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if onScreen then
        local scale = 0.35
        local px, py, pz = table.unpack(GetGameplayCamCoords())
        local dist = GetDistanceBetweenCoords(px, py, pz, x, y, z, 1)
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov / (dist * 2)
        
        SetTextScale(0.0, scale)
        SetTextFont(0)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(screenX, screenY)
    end
end

-- Helper function to draw 2D text
function DrawText2D(x, y, text, scale, color)
    SetTextFont(4)
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Event handlers
RegisterNetEvent('smartfire:syncFire')
AddEventHandler('smartfire:syncFire', function(fireId, fireData)
    SmartFire.Fires[fireId] = fireData
    Utils.DebugPrint("Fire synced: %s", fireId)
end)

RegisterNetEvent('smartfire:removeFire')
AddEventHandler('smartfire:removeFire', function(fireId)
    SmartFire.Fires[fireId] = nil
    SmartFire.NearbyFires[fireId] = nil
    Utils.DebugPrint("Fire removed: %s", fireId)
end)

RegisterNetEvent('smartfire:clearAllFires')
AddEventHandler('smartfire:clearAllFires', function()
    SmartFire.Fires = {}
    SmartFire.NearbyFires = {}
    SmartFire.IsExtinguishing = false
    Utils.DebugPrint("All fires cleared")
end)

RegisterNetEvent('smartfire:toggleDebug')
AddEventHandler('smartfire:toggleDebug', function(enabled)
    SmartFire.DebugMode = enabled
    Utils.DebugPrint("Debug mode: %s", enabled and "enabled" or "disabled")
end)

RegisterNetEvent('smartfire:notify')
AddEventHandler('smartfire:notify', function(message, type)
    Utils.Notify(nil, message, type)
end)

-- Export functions
exports('GetNearbyFires', function()
    return SmartFire.NearbyFires
end)

exports('IsPlayerExtinguishing', function()
    return SmartFire.IsExtinguishing
end)

exports('GetFireById', function(fireId)
    return SmartFire.Fires[fireId]
end)