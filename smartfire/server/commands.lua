-- Server Commands - Smart Fire System

-- Start fire command
RegisterCommand(Config.Commands.StartFire, function(source, args, rawCommand)
    if source == 0 then return end -- Console protection

    if not Utils.HasPermission(source, Config.Commands.StartFire) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local x, y, z, radius, dimension = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]),
        tonumber(args[4]), tonumber(args[5])

    if not x or not y or not z then
        local ped = GetPlayerPed(source)
        local coords = GetEntityCoords(ped)
        x, y, z = coords.x, coords.y, coords.z
    end

    radius = radius or Config.Fire.DefaultRadius
    dimension = dimension or Config.DefaultDimension

    local success, result, fireData = exports[GetCurrentResourceName()]:CreateFire(x, y, z, radius, dimension)

    if success then
        local message = Config.Notifications.FireStarted:format(Utils.CoordsToString(x, y, z))
        Utils.Notify(source, message .. " (ID: " .. result .. ")", 'success')
    else
        Utils.Notify(source, result, 'error')
    end
end, false)

-- Stop specific fire command
RegisterCommand(Config.Commands.StopFire, function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, Config.Commands.StopFire) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local fireId = args[1]
    if not fireId then
        Utils.Notify(source,
            Config.Notifications.InvalidParameters:format("/" .. Config.Commands.StopFire .. " [fireId]"), 'error')
        return
    end

    local success, message = exports[GetCurrentResourceName()]:RemoveFire(fireId)

    if success then
        Utils.Notify(source, Config.Notifications.FireStopped:format(fireId), 'success')
    else
        Utils.Notify(source, message, 'error')
    end
end, false)

-- Clear all fires command
RegisterCommand(Config.Commands.ClearFires, function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, Config.Commands.ClearFires) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local fireCount = exports[GetCurrentResourceName()]:GetFireCount()

    if fireCount == 0 then
        Utils.Notify(source, "Keine aktiven Feuer gefunden", 'info')
        return
    end

    TriggerEvent('smartfire:clearAllFires')
    exports[GetCurrentResourceName()]:GetFires() -- Clear the fires table
    for fireId, _ in pairs(exports[GetCurrentResourceName()]:GetFires()) do
        exports[GetCurrentResourceName()]:RemoveFire(fireId)
    end

    local message = Config.Notifications.AllFiresCleared:format(fireCount)
    Utils.Notify(source, message, 'success')
end, false)

-- Set fire dimension command
RegisterCommand(Config.Commands.SetDimension, function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, Config.Commands.SetDimension) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local fireId = args[1]
    local dimension = tonumber(args[2])

    if not fireId or not dimension then
        Utils.Notify(source,
            Config.Notifications.InvalidParameters:format("/" .. Config.Commands.SetDimension .. " [fireId] [dimension]"),
            'error')
        return
    end

    local fires = exports[GetCurrentResourceName()]:GetFires()

    if not fires[fireId] then
        Utils.Notify(source, Config.Notifications.FireNotFound:format(fireId), 'error')
        return
    end

    fires[fireId].dimension = dimension
    TriggerClientEvent('smartfire:syncFire', -1, fireId, fires[fireId])

    Utils.Notify(source, string.format("Feuer %s wurde in Dimension %d verschoben", fireId, dimension), 'success')
end, false)

-- Toggle debug mode command
RegisterCommand(Config.Commands.ToggleDebug, function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, Config.Commands.ToggleDebug) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    Config.DebugMode = not Config.DebugMode
    TriggerClientEvent('smartfire:toggleDebug', -1, Config.DebugMode)

    local status = Config.DebugMode and "aktiviert" or "deaktiviert"
    Utils.Notify(source, "Debug-Modus " .. status, 'info')
end, false)

-- List all fires command
RegisterCommand(Config.Commands.ListFires, function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, Config.Commands.ListFires) then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local fires = exports[GetCurrentResourceName()]:GetFires()
    local fireCount = exports[GetCurrentResourceName()]:GetFireCount()

    if fireCount == 0 then
        Utils.Notify(source, "Keine aktiven Feuer gefunden", 'info')
        return
    end

    Utils.Notify(source, string.format("🔥 Aktive Feuer: %d/%d", fireCount, Config.MaxFires), 'info')

    local count = 0
    for fireId, fireData in pairs(fires) do
        count = count + 1
        if count <= 10 then -- Limit to first 10 fires to avoid spam
            local coords = Utils.CoordsToString(fireData.x, fireData.y, fireData.z)
            local age = math.floor((GetGameTimer() - fireData.createdAt) / 1000)
            local info = string.format("%s | %s | Radius: %.1f | Alter: %ds | Dim: %d",
                fireId, coords, fireData.radius, age, fireData.dimension)
            Utils.Notify(source, info, 'info')
        end
    end

    if fireCount > 10 then
        Utils.Notify(source, string.format("... und %d weitere Feuer", fireCount - 10), 'info')
    end
end, false)

-- Admin fire command (quick fire at player position)
RegisterCommand('adminfire', function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, 'adminfire') then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local fireType = args[1] or "medium"

    if not Config.Fire.Types[fireType] then
        fireType = "medium"
    end

    local success, fireId = exports[GetCurrentResourceName()]:CreateFire(
        coords.x, coords.y, coords.z, nil, nil, nil, fireType
    )

    if success then
        Utils.Notify(source, string.format("🔥 %s Feuer erstellt: %s", fireType, fireId), 'success')
    else
        Utils.Notify(source, "❌ Fehler beim Erstellen des Feuers", 'error')
    end
end, false)

-- Help command
RegisterCommand('smartfire', function(source, args, rawCommand)
    if source == 0 then return end

    if not Utils.HasPermission(source, 'smartfire') then
        Utils.Notify(source, Config.Notifications.NoPermission, 'error')
        return
    end

    local helpText = {
        "🔥 SmartFire System - Befehle:",
        "/" .. Config.Commands.StartFire .. " [x] [y] [z] [radius] [dimension] - Feuer starten",
        "/" .. Config.Commands.StopFire .. " [fireId] - Feuer löschen",
        "/" .. Config.Commands.ClearFires .. " - Alle Feuer löschen",
        "/" .. Config.Commands.ListFires .. " - Feuer auflisten",
        "/" .. Config.Commands.SetDimension .. " [fireId] [dimension] - Dimension ändern",
        "/" .. Config.Commands.ToggleDebug .. " - Debug-Modus umschalten",
        "/adminfire [small/medium/large] - Feuer an deiner Position"
    }

    for _, line in ipairs(helpText) do
        Utils.Notify(source, line, 'info')
    end
end, false)

-- Console commands for server admins
if IsDuplicityVersion() then
    RegisterCommand('sf_stats', function(source, args, rawCommand)
        if source ~= 0 then return end -- Console only

        local fireCount = exports[GetCurrentResourceName()]:GetFireCount()
        print(string.format("^2[SmartFire Stats]^7"))
        print(string.format("Active Fires: %d/%d", fireCount, Config.MaxFires))
        print(string.format("Spreading: %s", Config.Fire.EnableSpreading and "Enabled" or "Disabled"))
        print(string.format("Debug Mode: %s", Config.DebugMode and "Enabled" or "Disabled"))
    end, true)

    RegisterCommand('sf_clear', function(source, args, rawCommand)
        if source ~= 0 then return end -- Console only

        local fireCount = exports[GetCurrentResourceName()]:GetFireCount()
        if fireCount > 0 then
            TriggerEvent('smartfire:clearAllFires')
            print(string.format("^3[SmartFire]^7 Cleared %d fires from console", fireCount))
        else
            print("^3[SmartFire]^7 No active fires to clear")
        end
    end, true)
end
