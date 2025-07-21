Utils = {}

-- Distance calculation
function Utils.GetDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Check if position is valid
function Utils.IsValidPosition(x, y, z)
    return type(x) == "number" and type(y) == "number" and type(z) == "number" and
        x >= -4000 and x <= 4000 and y >= -4000 and y <= 4000 and z >= -1000 and z <= 1000
end

-- Generate unique fire ID
function Utils.GenerateFireId()
    return "fire_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(GetGameTimer())
end

-- Clamp value between min and max
function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Round number to decimals
function Utils.Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Convert coordinates to string
function Utils.CoordsToString(x, y, z)
    return string.format("%.2f, %.2f, %.2f", x, y, z)
end

-- Debug print function
function Utils.DebugPrint(message, ...)
    if Config.DebugMode then
        print(string.format("[SmartFire DEBUG] " .. message, ...))
    end
end

-- Get random position within radius
function Utils.GetRandomPositionInRadius(center, radius)
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * radius

    return {
        x = center.x + math.cos(angle) * distance,
        y = center.y + math.sin(angle) * distance,
        z = center.z
    }
end

-- Check if player has permission
function Utils.HasPermission(source, command)
    if not Config.Permissions.RequireAcePermission then
        return true
    end

    if IsPlayerAceAllowed(source, Config.Permissions.AcePermission) then
        return true
    end

    -- Check group permissions (if using a framework)
    local playerGroup = GetPlayerGroup and GetPlayerGroup(source)
    if playerGroup then
        for _, group in ipairs(Config.Permissions.AllowedGroups) do
            if playerGroup == group then
                return true
            end
        end
    end

    return false
end

-- Send notification to player
function Utils.Notify(source, message, type)
    if IsDuplicityVersion() then -- Server side
        TriggerClientEvent('smartfire:notify', source, message, type or 'info')
    else                         -- Client side
        -- Here you can integrate with your notification system
        -- For now, using basic chat message
        TriggerEvent('chat:addMessage', {
            color = type == 'error' and { 255, 0, 0 } or type == 'success' and { 0, 255, 0 } or { 255, 255, 255 },
            multiline = false,
            args = { "SmartFire", message }
        })
    end
end

-- Validate fire parameters
function Utils.ValidateFireParams(x, y, z, radius, dimension)
    local errors = {}

    if not Utils.IsValidPosition(x, y, z) then
        table.insert(errors, "Ungültige Position")
    end

    if radius and (radius < Config.Fire.MinRadius or radius > Config.Fire.MaxRadius) then
        table.insert(errors, string.format("Radius muss zwischen %.1f und %.1f liegen",
            Config.Fire.MinRadius, Config.Fire.MaxRadius))
    end

    if dimension and (dimension < 0 or dimension > 9999) then
        table.insert(errors, "Dimension muss zwischen 0 und 9999 liegen")
    end

    return #errors == 0, errors
end

-- Get ground Z coordinate - Client/Server compatible
function Utils.GetGroundZ(x, y, z)
    if IsDuplicityVersion() then
        -- Server side - just return the provided Z or a reasonable ground level
        return z or 30.0
    else
        -- Client side - use native function
        local retval, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
        return retval and groundZ or z
    end
end

-- Server-specific utilities
if IsDuplicityVersion() then
    -- Check for water on server side (simplified)
    function Utils.IsInWater(x, y, z)
        -- This is a simplified check - in a real implementation you might want to
        -- maintain a list of known water areas or use a more sophisticated method
        -- For now, we'll assume areas below sea level might be water
        return z < 0.0
    end

    -- Get a reasonable ground level for server-side calculations
    function Utils.GetEstimatedGroundLevel(x, y, z)
        -- For most of the GTA map, ground level is around 30-50
        -- This is a fallback when we can't get precise ground coordinates
        local mapCenterDistance = math.sqrt(x * x + y * y)

        if mapCenterDistance < 2000 then
            return 30.0  -- City area
        elseif mapCenterDistance < 3000 then
            return 50.0  -- Suburban/hills
        else
            return 100.0 -- Mountains/far areas
        end
    end
end
