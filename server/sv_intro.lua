local QBCore = exports['qb-core']:GetCoreObject()
local introSessions = {}
local allocatedBuckets = {}
local pendingIntroQueue = {}
local queuedIntros = {}
local completedIntros = {}
local StartSession

local function StartNextQueuedIntro()
    while #pendingIntroQueue > 0 do
        local src = table.remove(pendingIntroQueue, 1)
        queuedIntros[src] = nil
        if QBCore.Functions.GetPlayer(src) then
            StartSession(src, true)
            return
        end
    end
end

local function DebugPrint(message)
    if Config.Debug or (Config.IntroFlow and Config.IntroFlow.Debug) then
        print("^5[DP-MultiCharacter:Intro] ^7" .. tostring(message))
    end
end

local function DescribeCoords(coords)
    if type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4" then
        return tostring(coords or "ninguna")
    end
    return ("%.2f %.2f %.2f"):format(
        tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
end

local function SetIntroStep(player, step)
    player.Functions.SetMetaData("introStep", step)
end

local function AllocateBucket()
    local start = math.max(1, tonumber(Config.IntroFlow.BucketStart) or 5000)
    local capacity = math.max(1, tonumber(Config.IntroFlow.MaxConcurrent) or 16)

    for bucket = start, start + capacity - 1 do
        if not allocatedBuckets[bucket] then
            allocatedBuckets[bucket] = true
            return bucket
        end
    end

    return nil
end

local function ReleaseSession(src, markDone, finalCoords)
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    if not session or not player then
        DebugPrint(("No se pudo liberar la sesión de %s (sesión: %s, jugador: %s)."):format(
            src, tostring(session ~= nil), tostring(player ~= nil)))
        return false
    end

    DebugPrint(("Liberando bucket %s de %s en fase %s; destino final %.2f %.2f %.2f."):format(
        session.bucket, src, tostring(session.phase),
        finalCoords and finalCoords.x or 0.0, finalCoords and finalCoords.y or 0.0,
        finalCoords and finalCoords.z or 0.0))
    SetPlayerRoutingBucket(src, 0)
    SetRoutingBucketPopulationEnabled(session.bucket, true)
    allocatedBuckets[session.bucket] = nil
    introSessions[src] = nil
    TriggerEvent('DP-MultiCharacter:server:bucketReleased', src)

    if markDone then
        completedIntros[src] = true
        SetIntroStep(player, "spawn")
    else
        SetIntroStep(player, "spawn")
    end

    TriggerClientEvent('DP-MultiCharacter:client:completeIntro', src, finalCoords, markDone)
    StartNextQueuedIntro()
    return true
end

local function ResolveDestination(coords)
    if type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4" then
        return nil
    end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then
        return nil
    end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -50 or z > 2000 then
        return nil
    end

    local closestKey, closest, closestDistance
    for key, destination in pairs(Config.IntroFlow.Destinations or {}) do
        local target = destination.coords
        local distance = #(vector2(x, y) - vector2(target.x, target.y))
        if not closestDistance or distance < closestDistance then
            closestKey, closest, closestDistance = key, destination, distance
        end
    end

    if closestDistance and closestDistance <= 150.0 then
        return closestKey, closest, closestDistance
    end

    return nil, nil, closestDistance
end

StartSession = function(src, resume)
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not Config.IntroFlow.Enabled then
        DebugPrint(("startIntro ignorado para %s (jugador: %s, intro activada: %s)."):format(
            src, tostring(player ~= nil), tostring(Config.IntroFlow.Enabled)))
        return
    end

    local metadata = player.PlayerData.metadata or {}
    if metadata.introDone ~= false then
        DebugPrint(("Intro no iniciada para %s: metadata.introDone=%s."):format(
            src, tostring(metadata.introDone)))
        return
    end

    if introSessions[src] or completedIntros[src] then
        DebugPrint(("Intro duplicada ignorada para %s (sesión activa o ya completada)."):format(src))
        return
    end

    local bucket = AllocateBucket()
    if not bucket then
        local queueLimit = math.max(0, tonumber(Config.IntroFlow.MaxQueue) or 64)
        if #pendingIntroQueue < queueLimit then
            if not queuedIntros[src] then
                queuedIntros[src] = true
                pendingIntroQueue[#pendingIntroQueue + 1] = src
                TriggerEvent('DP-MultiCharacter:server:bucketStarted', src)
                TriggerClientEvent('DP-MultiCharacter:client:introQueued', src)
                DebugPrint(("Jugador %s añadido a la cola de intro (%s en espera)."):format(src,
                    #pendingIntroQueue))
            end
            return
        end

        DebugPrint(("Cola de intro llena para %s; se usará el spawn normal."):format(src))
        player.Functions.SetMetaData("introDone", true)
        player.Functions.SetMetaData("introStep", nil)
        TriggerClientEvent('DP-MultiCharacter:client:introUnavailable', src)
        return
    end

    local step = resume and metadata.introStep or "tailor"
    if step ~= "cinematic" and step ~= "spawn" and step ~= "taxi" then
        step = "tailor"
    end
    if step == "taxi" then
        step = "spawn"
    end
    introSessions[src] = {
        bucket = bucket,
        phase = step,
        changes = 0,
        lastChange = 0,
        lastRushToggle = 0,
        rush = false,
        startedAt = os.time(),
        fareCharged = false
    }

    SetPlayerRoutingBucket(src, bucket)
    SetRoutingBucketPopulationEnabled(bucket, Config.IntroFlow.BucketPopulation == true)
    TriggerEvent('DP-MultiCharacter:server:bucketStarted', src)
    SetIntroStep(player, step)
    DebugPrint(("Intro iniciada para %s en bucket %s (fase %s)."):format(src, bucket, step))
    TriggerClientEvent('DP-MultiCharacter:client:introStarted', src, step)
end

RegisterNetEvent('DP-MultiCharacter:server:startIntro', function()
    StartSession(source, false)
end)

RegisterNetEvent('DP-MultiCharacter:server:resumeIntro', function()
    StartSession(source, true)
end)

RegisterNetEvent('DP-MultiCharacter:server:tailorFinished', function()
    local src = source
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    if not session or session.phase ~= "tailor" or not player then
        DebugPrint(("tailorFinished ignorado para %s (sesión: %s, fase: %s, jugador: %s)."):format(
            src, tostring(session ~= nil), session and tostring(session.phase) or "ninguna", tostring(player ~= nil)))
        return
    end

    DebugPrint(("Personalización confirmada por %s; comenzando cinemática."):format(src))
    session.phase = "cinematic"
    SetIntroStep(player, "cinematic")
    TriggerClientEvent('DP-MultiCharacter:client:beginIntroCinematic', src)
end)

RegisterNetEvent('DP-MultiCharacter:server:cinematicFinished', function()
    local src = source
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    if not session or session.phase ~= "cinematic" or not player then
        DebugPrint(("cinematicFinished ignorado para %s (sesión: %s, fase: %s, jugador: %s)."):format(
            src, tostring(session ~= nil), session and tostring(session.phase) or "ninguna", tostring(player ~= nil)))
        return
    end

    DebugPrint(("Cinemática terminada para %s; solicitando selector de spawn."):format(src))
    session.phase = "spawn"
    SetIntroStep(player, "spawn")
    TriggerClientEvent('DP-MultiCharacter:client:openIntroSpawnSelector', src)
end)

RegisterNetEvent('DP-MultiCharacter:server:confirmIntroSpawn', function(coords)
    local src = source
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    if not session or session.phase ~= "spawn" or not player then
        DebugPrint(("Selección de spawn ignorada para %s (sesión: %s, fase: %s, jugador: %s)."):format(
            src, tostring(session ~= nil), session and tostring(session.phase) or "ninguna", tostring(player ~= nil)))
        return
    end

    DebugPrint(("Spawn seleccionado por %s: %s."):format(src, DescribeCoords(coords)))
    local destinationKey, destination, distance = ResolveDestination(coords)
    if not destination then
        destinationKey = "airport"
        destination = Config.IntroFlow.Destinations.airport
        DebugPrint(("Spawn no reconocido para %s (distancia al blip más cercano: %s); se usa aeropuerto."):format(
            src, tostring(distance)))
    end
    if not destination then
        DebugPrint("No hay destino de aeropuerto configurado; no se puede continuar la intro.")
        TriggerClientEvent('QBCore:Notify', src, "No hay destinos configurados para la introducción.", "error")
        return
    end

    session.destination = destinationKey
    session.phase = destination.method == "taxi" and "taxi" or "walking"
    session.tripStartedAt = os.time()
    session.tripStart = Config.IntroFlow.TaxiStart
    SetIntroStep(player, session.phase == "taxi" and "taxi" or "spawn")
    DebugPrint(("Destino validado: %s (%s), método %s, distancia %.2fm; inicio del viaje %.2f %.2f %.2f."):format(
        tostring(destinationKey), tostring(destination.label), tostring(destination.method), distance or 0.0,
        session.tripStart.x, session.tripStart.y, session.tripStart.z))

    if destination.method == "taxi" then
        TriggerClientEvent('DP-MultiCharacter:client:startIntroTaxi', src, {
            destination = destinationKey,
            label = destination.label,
            coords = destination.coords,
            start = session.tripStart
        })
    else
        TriggerClientEvent('DP-MultiCharacter:client:startIntroWalk', src, destination.coords)
    end
end)

RegisterNetEvent('DP-MultiCharacter:server:requestTaxiDestination', function(destinationKey)
    local src = source
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    local taxi = Config.Taxi or {}
    local destination = Config.IntroFlow.Destinations[destinationKey]
    if not session or session.phase ~= "taxi" or not player or not destination or destination.method ~= "taxi" then
        DebugPrint(("Cambio de destino rechazado para %s (%s; fase %s)."):format(
            src, tostring(destinationKey), session and tostring(session.phase) or "sin sesión"))
        return
    end
    if destinationKey == session.destination or session.changes >= (tonumber(taxi.MaxDestinationChanges) or 2) then
        DebugPrint(("Cambio de destino de %s rechazado (destino actual o máximo de cambios alcanzado)."):format(src))
        return
    end
    local now = os.time()
    if now - session.lastChange < (tonumber(taxi.DestinationChangeCooldown) or 10) then
        DebugPrint(("Cambio de destino de %s rechazado por cooldown (%ss restantes)."):format(
            src, (tonumber(taxi.DestinationChangeCooldown) or 10) - (now - session.lastChange)))
        return
    end

    session.lastChange = now
    session.changes = session.changes + 1
    session.destination = destinationKey
    DebugPrint(("Destino del taxi cambiado por %s a %s (%s)."):format(src, destinationKey, destination.label))
    TriggerClientEvent('DP-MultiCharacter:client:updateIntroTaxiDestination', src, destinationKey, destination.label,
        destination.coords, session.changes)
end)

RegisterNetEvent('DP-MultiCharacter:server:toggleTaxiRush', function()
    local src = source
    local session = introSessions[src]
    if not session or session.phase ~= "taxi" then
        DebugPrint(("Toggle de prisa ignorado para %s: no está en fase taxi."):format(src))
        return
    end
    local now = os.time()
    if now - session.lastRushToggle < (tonumber(Config.Taxi.RushCooldown) or 3) then
        DebugPrint(("Cambio de prisa de %s rechazado por cooldown."):format(src))
        return
    end
    session.lastRushToggle = now
    session.rush = not session.rush
    DebugPrint(("Prisa del taxi para %s: %s."):format(src, tostring(session.rush)))
    TriggerClientEvent('DP-MultiCharacter:client:setIntroTaxiRush', src, session.rush)
end)

RegisterNetEvent('DP-MultiCharacter:server:requestTaxiStop', function()
    local src = source
    local session = introSessions[src]
    if not session or session.phase ~= "taxi" then
        DebugPrint(("Petición de parada ignorada para %s: no está en fase taxi."):format(src))
        return
    end
    if session.stopRequested then
        DebugPrint(("Petición de parada duplicada ignorada para %s."):format(src))
        return
    end
    if os.time() - (session.tripStartedAt or os.time()) < 5 then
        TriggerClientEvent('DP-MultiCharacter:client:taxiStopDenied', src)
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return
    end
    local position = GetEntityCoords(ped)
    session.stopRequested = true
    DebugPrint(("Parada solicitada por %s en %.2f %.2f %.2f."):format(src, position.x, position.y, position.z))
    TriggerClientEvent('DP-MultiCharacter:client:stopIntroTaxi', src, {
        x = position.x,
        y = position.y,
        z = position.z,
        heading = GetEntityHeading(ped)
    })
end)

local function ChargeFare(player, session, coords, stopped)
    if session.fareCharged then
        return 0
    end
    session.fareCharged = true

    local taxi = Config.Taxi or {}
    local destination = Config.IntroFlow.Destinations[session.destination]
    local totalDistance = #(vector3(session.tripStart.x, session.tripStart.y, session.tripStart.z) -
        vector3(destination.coords.x, destination.coords.y, destination.coords.z))
    local travelled = totalDistance

    if stopped and coords then
        travelled = #(vector3(session.tripStart.x, session.tripStart.y, session.tripStart.z) -
            vector3(coords.x, coords.y, coords.z))
    end

    local fare = (tonumber(taxi.BasePrice) or 0) + travelled * (tonumber(taxi.PricePerMeter) or 0)
    if session.rush then
        fare = fare + (tonumber(taxi.RushSurcharge) or 0)
    end
    fare = math.floor(math.max(tonumber(taxi.MinFare) or 0, math.min(tonumber(taxi.MaxFare) or fare, fare)))

    local paid = 0
    for _, account in ipairs(taxi.PayWith or { "cash", "bank" }) do
        local available = player.Functions.GetMoney(account) or 0
        local amount = math.min(available, fare - paid)
        if amount > 0 then
            player.Functions.RemoveMoney(account, amount, "DP-MultiCharacter taxi intro")
            paid = paid + amount
        end
        if paid >= fare then
            break
        end
    end

    if paid < fare then
        TriggerClientEvent('QBCore:Notify', player.PlayerData.source,
            ("No tienes suficiente dinero para la tarifa completa ($%s). Se han cobrado $%s."):format(fare, paid),
            "error")
    end
    return paid
end

RegisterNetEvent('DP-MultiCharacter:server:finishIntroTaxi', function(stopped)
    local src = source
    local session = introSessions[src]
    local player = QBCore.Functions.GetPlayer(src)
    local destination = session and Config.IntroFlow.Destinations[session.destination]
    if not session or session.phase ~= "taxi" or not player or not destination then
        DebugPrint(("finishIntroTaxi ignorado para %s (sesión: %s, fase: %s, destino: %s)."):format(
            src, tostring(session ~= nil), session and tostring(session.phase) or "ninguna",
            session and tostring(session.destination) or "ninguno"))
        return
    end

    local ped = GetPlayerPed(src)
    local position = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    local elapsed = os.time() - (session.tripStartedAt or os.time())
    local rescue = stopped == "rescue"
    local requestedStop = stopped == true
    if requestedStop and not session.stopRequested then
        DebugPrint(("Parada de taxi de %s ignorada: no existe petición de parada autorizada."):format(src))
        return
    end
    if rescue and elapsed < (tonumber(Config.Taxi.StuckTimeout) or 30) then
        DebugPrint(("Rescate de taxi de %s rechazado; solo han pasado %ss."):format(src, elapsed))
        return
    end
    if requestedStop and elapsed < 5 then
        DebugPrint(("Parada de taxi de %s rechazada; solo han pasado %ss."):format(src, elapsed))
        return
    end
    if not requestedStop and not rescue then
        if elapsed < 5 then
            DebugPrint(("Llegada de taxi de %s rechazada; solo han pasado %ss."):format(src, elapsed))
            return
        end
        if position and #(position - vector3(destination.coords.x, destination.coords.y, destination.coords.z)) > 250.0
            and elapsed < (tonumber(Config.Taxi.TripTimeout) or 900) then
            DebugPrint(("Llegada prematura de %s rechazada; jugador a %.2fm de %s tras %ss."):format(
                src, #(position - vector3(destination.coords.x, destination.coords.y, destination.coords.z)),
                destination.label, elapsed))
            return
        end
    end

    local finalCoords = destination.coords
    if requestedStop and position then
        finalCoords = vector4(position.x, position.y, position.z, GetEntityHeading(ped))
    end

    DebugPrint(("Viaje de taxi de %s finalizado (parada: %s, rescate: %s, duración: %ss)."):format(
        src, tostring(requestedStop), tostring(rescue), elapsed))
    ChargeFare(player, session, position, requestedStop)
    ReleaseSession(src, true, finalCoords)
end)

RegisterNetEvent('DP-MultiCharacter:server:finishIntroWalk', function()
    local src = source
    local session = introSessions[src]
    if not session or session.phase ~= "walking" or
        os.time() - (session.tripStartedAt or os.time()) < 5 then
        return
    end
    local destination = Config.IntroFlow.Destinations[session.destination]
    ReleaseSession(src, true, destination.coords)
end)

RegisterNetEvent('DP-MultiCharacter:server:confirmIntroComplete', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not completedIntros[src] then
        return
    end
    completedIntros[src] = nil
    player.Functions.SetMetaData("introDone", true)
    player.Functions.SetMetaData("introStep", nil)
end)

AddEventHandler('playerDropped', function()
    local src = source
    completedIntros[src] = nil
    if queuedIntros[src] then
        queuedIntros[src] = nil
        for index = #pendingIntroQueue, 1, -1 do
            if pendingIntroQueue[index] == src then
                table.remove(pendingIntroQueue, index)
                break
            end
        end
        TriggerEvent('DP-MultiCharacter:server:bucketReleased', src)
    end
    local session = introSessions[src]
    if session then
        SetPlayerRoutingBucket(src, 0)
        SetRoutingBucketPopulationEnabled(session.bucket, true)
        allocatedBuckets[session.bucket] = nil
        introSessions[src] = nil
        TriggerEvent('DP-MultiCharacter:server:bucketReleased', src)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    for src in pairs(queuedIntros) do
        SetPlayerRoutingBucket(src, 0)
        TriggerEvent('DP-MultiCharacter:server:bucketReleased', src)
        TriggerClientEvent('DP-MultiCharacter:client:cleanupIntro', src)
    end
    for src, session in pairs(introSessions) do
        SetPlayerRoutingBucket(src, 0)
        SetRoutingBucketPopulationEnabled(session.bucket, true)
        TriggerClientEvent('DP-MultiCharacter:client:cleanupIntro', src)
    end
    introSessions = {}
    allocatedBuckets = {}
    pendingIntroQueue = {}
    queuedIntros = {}
    completedIntros = {}
end)
