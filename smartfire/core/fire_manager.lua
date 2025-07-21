-- core/fire_manager.lua - Smart Fire System
FireManager = {}
FireManager.Version = "1.0.0"
FireManager.Initialized = false

-- Initialize fire manager
function FireManager.Initialize()
    if FireManager.Initialized then return end

    FireManager.Initialized = true
    Utils.DebugPrint("Fire Manager initialized - Version %s", FireManager.Version)
end

-- Get version
function FireManager.GetVersion()
    return FireManager.Version
end

-- Validate fire data integrity
function FireManager.ValidateFireData(fireData)
    if type(fireData) ~= "table" then
        return false, "Fire data must be a table"
    end

    local required = { "id", "x", "y", "z", "radius", "dimension", "createdAt" }

    for _, field in ipairs(required) do
        if fireData[field] == nil then
            return false, "Missing required field: " .. field
        end
    end

    -- Validate data types
    if type(fireData.id) ~= "string" then
        return false, "Field 'id' must be a string"
    end

    if type(fireData.x) ~= "number" or type(fireData.y) ~= "number" or type(fireData.z) ~= "number" then
        return false, "Coordinates must be numbers"
    end

    if type(fireData.radius) ~= "number" or fireData.radius <= 0 then
        return false, "Radius must be a positive number"
    end

    if type(fireData.dimension) ~= "number" or fireData.dimension < 0 then
        return false, "Dimension must be a non-negative number"
    end

    if type(fireData.createdAt) ~= "number" or fireData.createdAt <= 0 then
        return false, "CreatedAt must be a positive number (timestamp)"
    end

    -- Validate optional fields
    if fireData.lifetime and (type(fireData.lifetime) ~= "number" or fireData.lifetime < 0) then
        return false, "Lifetime must be a non-negative number"
    end

    if fireData.type and type(fireData.type) ~= "string" then
        return false, "Type must be a string"
    end

    if fireData.intensity and (type(fireData.intensity) ~= "number" or fireData.intensity <= 0) then
        return false, "Intensity must be a positive number"
    end

    return true
end

-- Calculate fire spread probability
function FireManager.CalculateSpreadProbability(fireData, targetPosition, environmentalFactors)
    local distance = Utils.GetDistance(fireData, targetPosition)
    local baseChance = fireData.spreadChance or Config.Fire.SpreadChance

    -- Reduce chance based on distance
    local distanceFactor = math.max(0, 1 - (distance / Config.Fire.SpreadRadius))

    -- Reduce chance based on fire age
    local age = GetGameTimer() - fireData.createdAt
    local ageFactor = math.max(0.1, 1 - (age / 300000)) -- Reduce over 5 minutes

    -- Apply fire type modifiers
    local typeFactor = 1.0
    if fireData.type and Config.Fire.Types[fireData.type] then
        typeFactor = Config.Fire.Types[fireData.type].spreadChance / Config.Fire.SpreadChance
    end

    -- Apply environmental factors (future feature)
    local envFactor = 1.0
    if environmentalFactors then
        -- Wind increases spread chance
        if environmentalFactors.windSpeed then
            envFactor = envFactor * (1.0 + environmentalFactors.windSpeed * 0.1)
        end

        -- Rain decreases spread chance
        if environmentalFactors.rainfall then
            envFactor = envFactor * (1.0 - environmentalFactors.rainfall * 0.5)
        end

        -- Humidity decreases spread chance
        if environmentalFactors.humidity then
            envFactor = envFactor * (1.0 - environmentalFactors.humidity * 0.3)
        end

        -- Temperature increases spread chance
        if environmentalFactors.temperature then
            local tempFactor = (environmentalFactors.temperature - 20) / 50 -- Normalize from 20°C
            envFactor = envFactor * (1.0 + math.max(0, tempFactor) * 0.2)
        end
    end

    local finalProbability = baseChance * distanceFactor * ageFactor * typeFactor * envFactor
    return math.max(0, math.min(1, finalProbability))
end

-- Get optimal fire position
function FireManager.GetOptimalFirePosition(x, y, z, checkWater, checkHeight)
    checkWater = checkWater ~= false   -- Default true
    checkHeight = checkHeight ~= false -- Default true

    local result = {
        x = x,
        y = y,
        z = z,
        adjusted = false,
        warnings = {}
    }

    -- Adjust to ground level if requested
    if checkHeight then
        local groundZ = Utils.GetGroundZ(x, y, z)
        if groundZ and math.abs(z - groundZ) > 2.0 then
            result.z = groundZ
            result.adjusted = true
            table.insert(result.warnings, "Position adjusted to ground level")
        end
    end

    -- Check for water if requested
    if checkWater then
        local waterHeight = GetWaterHeight(x, y, z)
        if waterHeight and waterHeight > result.z - 0.5 then
            table.insert(result.warnings, "Position is in or very close to water")
            return nil, "Cannot create fire in water"
        end
    end

    return result, nil
end

-- Calculate fire damage over time
function FireManager.CalculateFireDamage(fireData, target, deltaTime)
    if not target or not target.x then return 0 end

    local distance = Utils.GetDistance(fireData, target)
    local radius = fireData.radius
    local intensity = fireData.intensity or 1.0

    -- No damage outside fire radius
    if distance > radius then return 0 end

    -- Calculate damage based on proximity and intensity
    local proximityFactor = 1.0 - (distance / radius)
    local baseDamage = intensity * 10 -- Base damage per second
    local damage = baseDamage * proximityFactor * (deltaTime / 1000)

    return math.floor(damage)
end

-- Get fire spread candidates
function FireManager.GetSpreadCandidates(fireData, existingFires, maxCandidates)
    maxCandidates = maxCandidates or 10
    local candidates = {}

    -- Generate potential spread positions
    for i = 1, maxCandidates * 2 do
        local angle = math.random() * 2 * math.pi
        local distance = math.random() * Config.Fire.SpreadRadius

        local candidate = {
            x = fireData.x + math.cos(angle) * distance,
            y = fireData.y + math.sin(angle) * distance,
            z = fireData.z,
            distance = distance,
            angle = angle
        }

        -- Check if position is valid
        if Utils.IsValidPosition(candidate.x, candidate.y, candidate.z) then
            -- Check distance from existing fires
            local tooClose = false
            for existingId, existingFire in pairs(existingFires) do
                if existingFire.dimension == fireData.dimension then
                    local distToExisting = Utils.GetDistance(candidate, existingFire)
                    if distToExisting < (existingFire.radius + fireData.radius) * 0.7 then
                        tooClose = true
                        break
                    end
                end
            end

            if not tooClose then
                candidate.probability = FireManager.CalculateSpreadProbability(fireData, candidate)
                table.insert(candidates, candidate)
            end
        end
    end

    -- Sort by probability
    table.sort(candidates, function(a, b)
        return a.probability > b.probability
    end)

    -- Return top candidates
    local result = {}
    for i = 1, math.min(maxCandidates, #candidates) do
        table.insert(result, candidates[i])
    end

    return result
end

-- Calculate fire interaction effects
function FireManager.CalculateFireInteraction(fire1, fire2)
    local distance = Utils.GetDistance(fire1, fire2)
    local combinedRadius = fire1.radius + fire2.radius

    local interaction = {
        distance = distance,
        overlapping = distance < combinedRadius,
        intensityBoost = 0,
        spreadBoost = 0,
        mergeCandidate = false
    }

    if interaction.overlapping then
        -- Calculate interaction strength
        local overlapFactor = math.max(0, 1 - (distance / combinedRadius))

        -- Boost intensity for both fires
        interaction.intensityBoost = overlapFactor * 0.3

        -- Boost spread chance
        interaction.spreadBoost = overlapFactor * 0.2

        -- Check if fires should merge
        if distance < math.min(fire1.radius, fire2.radius) * 0.5 then
            interaction.mergeCandidate = true
        end
    end

    return interaction
end

-- Merge two fires into one
function FireManager.MergeFires(fire1, fire2)
    -- Calculate merged properties
    local totalMass = fire1.radius * fire1.radius + fire2.radius * fire2.radius
    local newRadius = math.sqrt(totalMass)

    -- Average position weighted by radius
    local weight1 = fire1.radius / (fire1.radius + fire2.radius)
    local weight2 = fire2.radius / (fire1.radius + fire2.radius)

    local mergedFire = {
        id = Utils.GenerateFireId(),
        x = fire1.x * weight1 + fire2.x * weight2,
        y = fire1.y * weight1 + fire2.y * weight2,
        z = fire1.z * weight1 + fire2.z * weight2,
        radius = math.min(newRadius, Config.Fire.MaxRadius),
        dimension = fire1.dimension,
        createdAt = math.min(fire1.createdAt, fire2.createdAt),
        type = fire1.radius > fire2.radius and fire1.type or fire2.type,
        intensity = math.min(2.0, (fire1.intensity or 1.0) + (fire2.intensity or 1.0) * 0.5),
        spreadCount = math.max(fire1.spreadCount or 0, fire2.spreadCount or 0),
        mergedFrom = { fire1.id, fire2.id }
    }

    -- Set lifetime to the longer of the two
    if fire1.lifetime and fire2.lifetime then
        mergedFire.lifetime = math.max(fire1.lifetime, fire2.lifetime)
    elseif fire1.lifetime or fire2.lifetime then
        mergedFire.lifetime = fire1.lifetime or fire2.lifetime
    end

    return mergedFire
end

-- Get fire extinguish effectiveness
function FireManager.GetExtinguishEffectiveness(fireData, extinguishMethod, extinguishPower)
    local baseEffectiveness = {
        extinguisher = 0.8,
        water = 1.0,
        foam = 1.2,
        sand = 0.4,
        command = 1.0
    }

    local effectiveness = baseEffectiveness[extinguishMethod] or 0.5
    effectiveness = effectiveness * (extinguishPower or 1.0)

    -- Larger fires are harder to extinguish
    local sizeFactor = math.max(0.1, 1.0 - (fireData.radius - Config.Fire.DefaultRadius) * 0.1)
    effectiveness = effectiveness * sizeFactor

    -- Older fires are easier to extinguish (burned out material)
    local age = GetGameTimer() - fireData.createdAt
    local ageFactor = 1.0 + math.min(0.5, age / 600000) -- Max 50% bonus after 10 minutes
    effectiveness = effectiveness * ageFactor

    return math.max(0.1, math.min(2.0, effectiveness))
end

-- Initialize when file is loaded
CreateThread(function()
    Wait(100)
    FireManager.Initialize()
end)

-- Export functions (available to both client and server)
if IsDuplicityVersion() then
    -- Server exports
    exports('ValidateFireData', FireManager.ValidateFireData)
    exports('CalculateSpreadProbability', FireManager.CalculateSpreadProbability)
    exports('GetOptimalFirePosition', FireManager.GetOptimalFirePosition)
    exports('CalculateFireDamage', FireManager.CalculateFireDamage)
    exports('GetSpreadCandidates', FireManager.GetSpreadCandidates)
    exports('CalculateFireInteraction', FireManager.CalculateFireInteraction)
    exports('MergeFires', FireManager.MergeFires)
    exports('GetExtinguishEffectiveness', FireManager.GetExtinguishEffectiveness)
    exports('GetFireManagerVersion', FireManager.GetVersion)
else
    exports('ValidateFireData', FireManager.ValidateFireData)
    exports('CalculateFireDamage', FireManager.CalculateFireDamage)
    exports('GetFireManagerVersion', FireManager.GetVersion)
end
