-- client/commands.lua - Smart Fire System
local ClientCommands = {}

-- Client-side command handlers
RegisterNetEvent('smartfire:clientCommand')
AddEventHandler('smartfire:clientCommand', function(command, args)
    if command == "nearest" then
        ClientCommands.FindNearestFire()
    elseif command == "stats" then
        ClientCommands.ShowClientStats()
    elseif command == "dimension" then
        ClientCommands.ShowCurrentDimension()
    end
end)

-- Find nearest fire
function ClientCommands.FindNearestFire()
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
        local info = string.format(
            "🔥 Nächstes Feuer: %s\n📍 Entfernung: %.1fm\n📏 Radius: %.1f\n🌐 Dimension: %d",
            nearestFire.id,
            nearestFire.distance,
            nearestFire.data.radius,
            nearestFire.data.dimension
        )
        Utils.Notify(nil, info, 'info')

        -- Add waypoint if close enough
        if nearestFire.distance <= 100.0 then
            SetNewWaypoint(nearestFire.data.x, nearestFire.data.y)
            Utils.Notify(nil, "📍 Wegpunkt zum Feuer gesetzt", 'success')
        end
    else
        Utils.Notify(nil, "Keine Feuer in der Nähe gefunden", 'info')
    end
end

-- Show client statistics
function ClientCommands.ShowClientStats()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearbyFires = exports['smartfire']:GetNearbyFires()
    local renderStats = exports['smartfire']:GetRenderStatistics()

    local nearbyCount = 0
    local totalDistance = 0

    for fireId, fireData in pairs(nearbyFires) do
        nearbyCount = nearbyCount + 1
        totalDistance = totalDistance + Utils.GetDistance(playerCoords, fireData)
    end

    local avgDistance = nearbyCount > 0 and (totalDistance / nearbyCount) or 0

    local statsText = string.format(
        "📊 SmartFire Client Stats:\n" ..
        "🔥 Feuer in der Nähe: %d\n" ..
        "📏 Durchschnittliche Entfernung: %.1fm\n" ..
        "🎮 Render Queue: %d\n" ..
        "⚡ Performance Modus: %s\n" ..
        "🔄 Lösche gerade: %s",
        nearbyCount,
        avgDistance,
        renderStats.queueSize or 0,
        renderStats.performanceMode and "AN" or "AUS",
        exports['smartfire']:IsPlayerExtinguishing() and "JA" or "NEIN"
    )

    Utils.Notify(nil, statsText, 'info')
end

-- Show current dimension
function ClientCommands.ShowCurrentDimension()
    local dimension = GetPlayerRoutingBucket(PlayerId()) or 0
    Utils.Notify(nil, string.format("🌐 Aktuelle Dimension: %d", dimension), 'info')
end

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
        Utils.Notify(nil, "🚒 Lösche Feuer...", 'info')
    else
        Utils.Notify(nil, string.format("❌ Kein Feuer in Reichweite (%.1fm)", Config.Extinguish.ExtinguisherRange),
            'error')
    end
end, false)

-- Teleport to nearest fire (admin only)
RegisterCommand('tpfire', function(source, args, rawCommand)
    local fireId = args[1]

    if fireId then
        -- Teleport to specific fire
        local fireData = exports['smartfire']:GetFireById(fireId)
        if fireData then
            SetEntityCoords(PlayerPedId(), fireData.x, fireData.y, fireData.z + 1.0)
            Utils.Notify(nil, string.format("🔥 Teleportiert zu Feuer: %s", fireId), 'success')
        else
            Utils.Notify(nil, string.format("❌ Feuer %s nicht gefunden", fireId), 'error')
        end
    else
        -- Teleport to nearest fire
        local playerCoords = GetEntityCoords(PlayerPedId())
        local nearbyFires = exports['smartfire']:GetNearbyFires()

        local nearestFire = nil
        local nearestDistance = math.huge

        for fId, fData in pairs(nearbyFires) do
            local distance = Utils.GetDistance(playerCoords, fData)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestFire = fData
            end
        end

        if nearestFire then
            SetEntityCoords(PlayerPedId(), nearestFire.x, nearestFire.y, nearestFire.z + 1.0)
            Utils.Notify(nil, "🔥 Teleportiert zum nächsten Feuer", 'success')
        else
            Utils.Notify(nil, "❌ Keine Feuer gefunden", 'error')
        end
    end
end, false)

-- Show fires in range
RegisterCommand('firescan', function(source, args, rawCommand)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local scanRange = tonumber(args[1]) or 50.0
    local nearbyFires = exports['smartfire']:GetNearbyFires()

    local firesInRange = {}

    for fireId, fireData in pairs(nearbyFires) do
        local distance = Utils.GetDistance(playerCoords, fireData)
        if distance <= scanRange then
            table.insert(firesInRange, {
                id = fireId,
                data = fireData,
                distance = distance
            })
        end
    end

    -- Sort by distance
    table.sort(firesInRange, function(a, b)
        return a.distance < b.distance
    end)

    if #firesInRange > 0 then
        Utils.Notify(nil, string.format("🔍 Feuer-Scan (%.1fm Radius):", scanRange), 'info')

        for i, fire in ipairs(firesInRange) do
            if i <= 5 then -- Limit to 5 results
                local info = string.format(
                    "%d. %s | %.1fm | R:%.1f | Dim:%d",
                    i, fire.id, fire.distance, fire.data.radius, fire.data.dimension
                )
                Utils.Notify(nil, info, 'info')
            end
        end

        if #firesInRange > 5 then
            Utils.Notify(nil, string.format("... und %d weitere Feuer", #firesInRange - 5), 'info')
        end
    else
        Utils.Notify(nil, string.format("🔍 Keine Feuer im %.1fm Radius gefunden", scanRange), 'info')
    end
end, false)

-- Toggle fire notifications
local showFireNotifications = true
RegisterCommand('togglefirenotify', function(source, args, rawCommand)
    showFireNotifications = not showFireNotifications
    local status = showFireNotifications and "aktiviert" or "deaktiviert"
    Utils.Notify(nil, "🔔 Feuer-Benachrichtigungen " .. status, 'info')
end, false)

-- Show fire info
RegisterCommand('fireinfo', function(source, args, rawCommand)
    local fireId = args[1]

    if not fireId then
        Utils.Notify(nil, "❌ Verwendung: /fireinfo [fireId]", 'error')
        return
    end

    local fireData = exports['smartfire']:GetFireById(fireId)

    if fireData then
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = Utils.GetDistance(playerCoords, fireData)
        local currentTime = GetGameTimer()
        local age = math.floor((currentTime - fireData.createdAt) / 1000)

        local infoText = string.format(
            "🔥 Feuer Information: %s\n" ..
            "📍 Position: %.1f, %.1f, %.1f\n" ..
            "📏 Radius: %.1f | Typ: %s\n" ..
            "🌐 Dimension: %d\n" ..
            "⏱️ Alter: %ds | Entfernung: %.1fm\n" ..
            "🔥 Ausbreitungen: %d/%d",
            fireId,
            fireData.x, fireData.y, fireData.z,
            fireData.radius, fireData.type or "medium",
            fireData.dimension,
            age, distance,
            fireData.spreadCount or 0, Config.Fire.MaxSpreadCount
        )

        Utils.Notify(nil, infoText, 'info')

        -- Set waypoint if requested
        if args[2] and args[2]:lower() == "wp" then
            SetNewWaypoint(fireData.x, fireData.y)
            Utils.Notify(nil, "📍 Wegpunkt gesetzt", 'success')
        end
    else
        Utils.Notify(nil, string.format("❌ Feuer %s nicht gefunden", fireId), 'error')
    end
end, false)

-- Client help command
RegisterCommand('firefhelp', function(source, args, rawCommand)
    local helpText = {
        "🔥 SmartFire Client-Befehle:",
        "/extinguish - Nächstes Feuer löschen",
        "/tpfire [id] - Zu Feuer teleportieren",
        "/firescan [radius] - Feuer in Reichweite scannen",
        "/fireinfo [id] [wp] - Feuer-Informationen anzeigen",
        "/togglefirenotify - Benachrichtigungen umschalten",
        "/firefhelp - Diese Hilfe anzeigen"
    }

    for _, line in ipairs(helpText) do
        Utils.Notify(nil, line, 'info')
    end
end, false)

-- Handle fire notifications
RegisterNetEvent('smartfire:fireNotification')
AddEventHandler('smartfire:fireNotification', function(type, message, fireData)
    if not showFireNotifications then return end

    local notificationText = ""

    if type == "fireNearby" then
        notificationText = string.format("🔥 Feuer in der Nähe: %s (%.1fm)", message, fireData.distance or 0)
    elseif type == "fireExtinguished" then
        notificationText = "🚒 " .. message
    elseif type == "fireSpread" then
        notificationText = "🔥 " .. message
    end

    if notificationText ~= "" then
        Utils.Notify(nil, notificationText, type == "fireExtinguished" and 'success' or 'warning')
    end
end)

-- Auto-notify about nearby fires
CreateThread(function()
    local lastNotifyTime = 0
    local notifyInterval = 30000 -- 30 seconds

    while true do
        Wait(5000) -- Check every 5 seconds

        if showFireNotifications and GetGameTimer() - lastNotifyTime > notifyInterval then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local nearbyFires = exports['smartfire']:GetNearbyFires()

            local closeFireCount = 0
            for fireId, fireData in pairs(nearbyFires) do
                local distance = Utils.GetDistance(playerCoords, fireData)
                if distance <= 25.0 then -- Very close fires
                    closeFireCount = closeFireCount + 1
                end
            end

            if closeFireCount > 0 then
                TriggerEvent('smartfire:fireNotification', 'fireNearby',
                    string.format("%d Feuer", closeFireCount), { distance = 25.0 })
                lastNotifyTime = GetGameTimer()
            end
        end
    end
end)
