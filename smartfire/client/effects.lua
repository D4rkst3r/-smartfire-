-- Client Effects - Smart Fire System
local Effects = {}
Effects.ActiveParticles = {}
Effects.ParticleAssets = {}

-- Initialize particle assets
CreateThread(function()
    Effects.LoadParticleAssets()
end)

-- Load particle assets
function Effects.LoadParticleAssets()
    local assets = {
        Config.Effects.ParticleDict,
        Config.Effects.SmokeDict,
        "scr_trevor1",
        "scr_ornate_heist",
        "scr_solomon3"
    }

    for _, asset in ipairs(assets) do
        if not Effects.ParticleAssets[asset] then
            RequestNamedPtfxAsset(asset)

            local timeout = 0
            while not HasNamedPtfxAssetLoaded(asset) and timeout < 5000 do
                Wait(10)
                timeout = timeout + 10
            end

            if HasNamedPtfxAssetLoaded(asset) then
                Effects.ParticleAssets[asset] = true
                Utils.DebugPrint("Loaded particle asset: %s", asset)
            else
                Utils.DebugPrint("Failed to load particle asset: %s", asset)
            end
        end
    end
end

-- Create fire effect
function Effects.CreateFireEffect(fireData)
    if not Config.Effects.EnableParticles then return end

    local fireId = fireData.id
    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius
    local intensity = fireData.intensity or 1.0

    -- Clean up existing effects for this fire
    Effects.CleanupFireEffect(fireId)

    Effects.ActiveParticles[fireId] = {}

    -- Main fire particles
    UseParticleAsset(Config.Effects.ParticleDict)

    local particleCount = math.min(
        Config.Performance.MaxParticlesPerFire,
        math.max(1, math.ceil(radius / 1.5))
    )

    for i = 1, particleCount do
        local offsetX = (math.random() - 0.5) * radius
        local offsetY = (math.random() - 0.5) * radius
        local offsetZ = math.random() * (radius * 0.3)

        local particle = StartParticleFxLoopedAtCoord(
            Config.Effects.ParticleName,
            x + offsetX, y + offsetY, z + offsetZ,
            0.0, 0.0, 0.0,
            radius * intensity * 0.8, false, false, false, false
        )

        if particle ~= 0 then
            table.insert(Effects.ActiveParticles[fireId], particle)
        end
    end

    -- Additional flame effects for larger fires
    if radius > 5.0 then
        UseParticleAsset("scr_trevor1")

        local bigFlame = StartParticleFxLoopedAtCoord(
            "scr_trev1_trailer_boosh",
            x, y, z,
            0.0, 0.0, 0.0,
            radius * 0.6, false, false, false, false
        )

        if bigFlame ~= 0 then
            table.insert(Effects.ActiveParticles[fireId], bigFlame)
        end
    end
end

-- Create smoke effect
function Effects.CreateSmokeEffect(fireData)
    if not Config.Effects.EnableSmoke then return end

    local fireId = fireData.id
    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius

    UseParticleAsset(Config.Effects.SmokeDict)

    -- Main smoke column
    local smoke = StartParticleFxLoopedAtCoord(
        Config.Effects.SmokeName,
        x, y, z + 1.0,
        0.0, 0.0, 0.0,
        radius * 0.8, false, false, false, false
    )

    if smoke ~= 0 then
        if not Effects.ActiveParticles[fireId] then
            Effects.ActiveParticles[fireId] = {}
        end
        table.insert(Effects.ActiveParticles[fireId], smoke)
    end

    -- Additional smoke for larger fires
    if radius > 3.0 then
        UseParticleAsset("scr_solomon3")

        local heavySmoke = StartParticleFxLoopedAtCoord(
            "scr_solomon3_trail",
            x, y, z + 2.0,
            0.0, 0.0, 0.0,
            radius * 0.5, false, false, false, false
        )

        if heavySmoke ~= 0 then
            table.insert(Effects.ActiveParticles[fireId], heavySmoke)
        end
    end
end

-- Create light effect
function Effects.CreateLightEffect(fireData)
    if not Config.Effects.EnableLight then return end

    -- Light is drawn in main loop, not created as persistent object
    return true
end

-- Create heat shimmer effect (advanced)
function Effects.CreateHeatEffect(fireData)
    if not Config.Effects.EnableHeat then return end

    local fireId = fireData.id
    local x, y, z = fireData.x, fireData.y, fireData.z
    local radius = fireData.radius

    -- Create heat distortion using particle effects
    UseParticleAsset("scr_ornate_heist")

    local heatEffect = StartParticleFxLoopedAtCoord(
        "scr_heist_ornate_thermal_burn",
        x, y, z,
        0.0, 0.0, 0.0,
        radius * 1.2, false, false, false, false
    )

    if heatEffect ~= 0 then
        if not Effects.ActiveParticles[fireId] then
            Effects.ActiveParticles[fireId] = {}
        end
        table.insert(Effects.ActiveParticles[fireId], heatEffect)
    end
end

-- Create complete fire effects
function Effects.CreateCompleteFireEffect(fireData)
    Effects.CreateFireEffect(fireData)
    Effects.CreateSmokeEffect(fireData)
    Effects.CreateHeatEffect(fireData)

    Utils.DebugPrint("Created complete fire effect for: %s", fireData.id)
end

-- Cleanup fire effect
function Effects.CleanupFireEffect(fireId)
    if Effects.ActiveParticles[fireId] then
        for _, particle in ipairs(Effects.ActiveParticles[fireId]) do
            if DoesParticleFxLoopedExist(particle) then
                StopParticleFxLooped(particle, false)
            end
        end
        Effects.ActiveParticles[fireId] = nil

        Utils.DebugPrint("Cleaned up fire effect: %s", fireId)
    end
end

-- Cleanup all effects
function Effects.CleanupAllEffects()
    for fireId, particles in pairs(Effects.ActiveParticles) do
        for _, particle in ipairs(particles) do
            if DoesParticleFxLoopedExist(particle) then
                StopParticleFxLooped(particle, false)
            end
        end
    end
    Effects.ActiveParticles = {}

    Utils.DebugPrint("Cleaned up all fire effects")
end

-- Update particle intensity based on distance
function Effects.UpdateParticleIntensity(fireId, distance)
    if not Effects.ActiveParticles[fireId] then return end

    local intensity = 1.0

    -- Reduce intensity based on distance
    if distance > Config.Performance.ReduceEffectsDistance then
        intensity = 0.5
    elseif distance > Config.Performance.DisableEffectsDistance then
        intensity = 0.0
    end

    -- Apply intensity to particles
    for _, particle in ipairs(Effects.ActiveParticles[fireId]) do
        if DoesParticleFxLoopedExist(particle) then
            SetParticleFxLoopedAlpha(particle, intensity)
        end
    end
end

-- Create extinguishing effect
function Effects.CreateExtinguishEffect(x, y, z)
    UseParticleAsset("core")

    -- Steam/water effect
    StartParticleFxNonLoopedAtCoord(
        "water_splash_ped_out",
        x, y, z + 1.0,
        0.0, 0.0, 0.0,
        2.0, false, false, false
    )

    -- Smoke puff when extinguished
    StartParticleFxNonLoopedAtCoord(
        "exp_grd_bzgas_smoke",
        x, y, z + 0.5,
        0.0, 0.0, 0.0,
        1.5, false, false, false
    )

    Utils.DebugPrint("Created extinguish effect at: %.2f, %.2f, %.2f", x, y, z)
end

-- Create spreading effect (when fire spreads)
function Effects.CreateSpreadEffect(fromFire, toFire)
    local fromX, fromY, fromZ = fromFire.x, fromFire.y, fromFire.z
    local toX, toY, toZ = toFire.x, toFire.y, toFire.z

    -- Create a trail of small fire particles between the two fires
    local steps = 10
    for i = 1, steps do
        local progress = i / steps
        local x = fromX + (toX - fromX) * progress
        local y = fromY + (toY - fromY) * progress
        local z = fromZ + (toZ - fromZ) * progress

        CreateThread(function()
            Wait(i * 100) -- Delay for trail effect

            UseParticleAsset("core")
            StartParticleFxNonLoopedAtCoord(
                "fire_wrecked_plane_cockpit",
                x, y, z,
                0.0, 0.0, 0.0,
                0.8, false, false, false
            )
        end)
    end

    Utils.DebugPrint("Created spread effect from %s to %s", fromFire.id, toFire.id)
end

-- Use particle asset with error handling
function UseParticleAsset(assetName)
    if not Effects.ParticleAssets[assetName] then
        RequestNamedPtfxAsset(assetName)

        local timeout = 0
        while not HasNamedPtfxAssetLoaded(assetName) and timeout < 1000 do
            Wait(10)
            timeout = timeout + 10
        end

        if HasNamedPtfxAssetLoaded(assetName) then
            Effects.ParticleAssets[assetName] = true
        else
            Utils.DebugPrint("Failed to load particle asset: %s", assetName)
            return false
        end
    end

    UseParticleFxAssetNextCall(assetName)
    return true
end

-- Event handlers
RegisterNetEvent('smartfire:createEffect')
AddEventHandler('smartfire:createEffect', function(fireData)
    Effects.CreateCompleteFireEffect(fireData)
end)

RegisterNetEvent('smartfire:removeEffect')
AddEventHandler('smartfire:removeEffect', function(fireId)
    Effects.CleanupFireEffect(fireId)
end)

RegisterNetEvent('smartfire:extinguishEffect')
AddEventHandler('smartfire:extinguishEffect', function(x, y, z)
    Effects.CreateExtinguishEffect(x, y, z)
end)

RegisterNetEvent('smartfire:spreadEffect')
AddEventHandler('smartfire:spreadEffect', function(fromFire, toFire)
    Effects.CreateSpreadEffect(fromFire, toFire)
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Effects.CleanupAllEffects()
    end
end)

-- Export functions
exports('CreateFireEffect', Effects.CreateCompleteFireEffect)
exports('CleanupFireEffect', Effects.CleanupFireEffect)
exports('CreateExtinguishEffect', Effects.CreateExtinguishEffect)
