local QBCore = exports['qb-core']:GetCoreObject()
local introActive = false
local introVehicle = nil
local introDriver = nil
local introDestination = nil
local introDestinationKey = nil
local introTaxiStartedAt = 0
local introRush = false
local introChanges = 0
local taxiFinishing = false
local taxiStopping = false
local taxiDepartureRequested = false
local pinnedTailorInterior = 0

function IsMultiCharacterIntroActive()
    return introActive
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

local function SetIntroPlayerState(enabled)
    local ped = PlayerPedId()
    introActive = enabled
    SetEntityInvincible(ped, enabled)
    SetEntityVisible(ped, not enabled, false)
    FreezeEntityPosition(ped, enabled)
    DisplayHud(not enabled)
    DisplayRadar(not enabled)
    if enabled then
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetPedArmour(ped, 100)
    end
    if not enabled then
        SetPlayerControl(PlayerId(), true, 0)
    end
end

local function StreamTeleport(ped, coords, heading)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    local interior = GetInteriorAtCoords(coords.x, coords.y, coords.z)
    if interior ~= 0 then
        pinnedTailorInterior = interior
        PinInteriorInMemory(interior)
        LoadInterior(interior)
        local interiorTimeout = GetGameTimer() + 10000
        while not IsInteriorReady(interior) and GetGameTimer() < interiorTimeout do
            Wait(100)
        end
        RefreshInterior(interior)
        DebugPrint(("Interior de personalización %s (listo: %s)."):format(
            interior, tostring(IsInteriorReady(interior))))
    else
        DebugPrint("El Tailor Room está en el mundo exterior; no requiere carga de interior.")
    end

    -- Keep the player blacked out and stream only a bounded scene around the destination.
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    NewLoadSceneStart(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, 60.0, 0)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z + 1.0, false, false, false, true)
    SetEntityHeading(ped, heading or coords.w or 0.0)
    SetEntityCollision(ped, true, true)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local startedAt = GetGameTimer()
    local timeout = startedAt + 30000
    while (not IsNewLoadSceneLoaded() or not HasCollisionLoadedAroundEntity(ped)) and GetGameTimer() < timeout do
        Wait(100)
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    end

    local sceneLoaded = IsNewLoadSceneLoaded()
    local collisionLoaded = HasCollisionLoadedAroundEntity(ped)
    NewLoadSceneStop()
    ClearFocus()
    if not sceneLoaded or not collisionLoaded then
        DebugPrint(("No se abrirá qb-clothing: escena cargada=%s, colisión cargada=%s en %.2f %.2f %.2f."):format(
            tostring(sceneLoaded), tostring(collisionLoaded), coords.x, coords.y, coords.z))
        return false
    end

    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    if interior ~= 0 and not IsInteriorReady(interior) then
        DebugPrint(("El interior %s no quedó listo antes de abrir la personalización."):format(interior))
    end
    DebugPrint(("Escena del destino: %s; colisión: %s; posición %.2f %.2f %.2f (interior %s)."):format(
        tostring(sceneLoaded), tostring(collisionLoaded), coords.x, coords.y, coords.z, tostring(interior)))
    return sceneLoaded and collisionLoaded
end

local function ReleaseTailorInterior()
    if pinnedTailorInterior ~= 0 then
        UnpinInterior(pinnedTailorInterior)
        pinnedTailorInterior = 0
    end
end

local function LoadIntroModel(model)
    local hash = type(model) == "number" and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not HasModelLoaded(hash) then
        return nil
    end
    return hash
end

local function UpdateTaxiHud(show, label, status)
    SendNUIMessage({
        action = "introTaxiHud",
        show = show == true,
        destination = label,
        status = status
    })
end

local function CleanupTaxi()
    UpdateTaxiHud(false)
    SetWaypointOff()
    local ped = PlayerPedId()
    if introVehicle and DoesEntityExist(introVehicle) then
        if IsPedInVehicle(ped, introVehicle, false) then
            TaskLeaveVehicle(ped, introVehicle, 16)
            Wait(500)
        end
        SetEntityAsMissionEntity(introVehicle, true, true)
        DeleteVehicle(introVehicle)
    end
    if introDriver and DoesEntityExist(introDriver) then
        SetEntityAsMissionEntity(introDriver, true, true)
        DeletePed(introDriver)
    end
    introVehicle = nil
    introDriver = nil
end

local function StartTaxiDeparture()
    UpdateTaxiHud(false)
    SetWaypointOff()
    if not introVehicle or not DoesEntityExist(introVehicle) then
        CleanupTaxi()
        return
    end

    SetEntityInvincible(introVehicle, false)
    SetVehicleHandbrake(introVehicle, false)
    SetVehicleEngineOn(introVehicle, true, true, false)
    if introDriver and DoesEntityExist(introDriver) then
        SetEntityInvincible(introDriver, false)
        SetBlockingOfNonTemporaryEvents(introDriver, false)
        TaskVehicleDriveWander(introDriver, introVehicle, 18.0, 786603)
    end

    local vehicle = introVehicle
    local driver = introDriver
    introVehicle = nil
    introDriver = nil
    CreateThread(function()
        Wait(10000)
        if vehicle and DoesEntityExist(vehicle) then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
        end
        if driver and DoesEntityExist(driver) then
            SetEntityAsMissionEntity(driver, true, true)
            DeletePed(driver)
        end
    end)
end

local function CompleteTaxi(stopped, rescue)
    if not introActive or taxiFinishing then
        DebugPrint(("Fin de taxi ignorado (intro activa: %s, finalizando: %s)."):format(
            tostring(introActive), tostring(taxiFinishing)))
        return
    end
    taxiFinishing = true
    DebugPrint(("Solicitando fin del taxi (parada: %s, rescate: %s)."):format(
        tostring(stopped), tostring(rescue)))
    if not rescue and stopped ~= true and GetGameTimer() - introTaxiStartedAt < 5000 then
        local minimumTripWait = 5000 - (GetGameTimer() - introTaxiStartedAt)
        DebugPrint(("Esperando %sms para cumplir el tiempo mínimo del servidor."):format(minimumTripWait))
        Wait(minimumTripWait)
    end
    if introVehicle and DoesEntityExist(introVehicle) and introDriver and DoesEntityExist(introDriver) then
        TaskVehicleTempAction(introDriver, introVehicle, 27, 1500)
        Wait(700)
    end
    if rescue then
        local rescueDelay = math.max(0, (Config.Taxi.StuckTimeout * 1000) -
            (GetGameTimer() - introTaxiStartedAt))
        CreateThread(function()
            Wait(rescueDelay)
            TriggerServerEvent('DP-MultiCharacter:server:finishIntroTaxi', "rescue")
        end)
    else
        TriggerServerEvent('DP-MultiCharacter:server:finishIntroTaxi', stopped == true)
    end
end

local function BeginTaxiDrive()
    if not introVehicle or not DoesEntityExist(introVehicle) or not introDriver or not DoesEntityExist(introDriver) or
        not introDestination then
        DebugPrint("No se inicia la conducción: falta taxi, conductor o destino.")
        CompleteTaxi(false, true)
        return
    end

    local style = 786603
    local speed = introRush and 24.0 or 16.0
    DebugPrint(("Taxista conduciendo hacia %s, %.2f %.2f %.2f (prisa: %s)."):format(
        tostring(introDestinationKey), introDestination.x, introDestination.y, introDestination.z, tostring(introRush)))
    SetDriveTaskDrivingStyle(introDriver, style)
    SetDriveTaskMaxCruiseSpeed(introDriver, speed)
    SetNewWaypoint(introDestination.x, introDestination.y)
    TaskVehicleDriveToCoordLongrange(introDriver, introVehicle, introDestination.x, introDestination.y,
        introDestination.z, speed, style, 12.0)
end

local function HandleTaxiInput(action)
    if not introActive or not introVehicle or not DoesEntityExist(introVehicle) then
        return
    end

    if action == "talk" then
        DebugPrint("Comando de conversación (G) recibido.")
        QBCore.Functions.Notify("Taxista: Bienvenido a Los Santos. ¿Es tu primera vez por aquí?", "primary")
    elseif action == "rush" then
        DebugPrint("Comando de prisa (R) recibido.")
        TriggerServerEvent('DP-MultiCharacter:server:toggleTaxiRush')
    elseif action == "change" then
        local destinationKeys = {}
        for key, destination in pairs(Config.IntroFlow.Destinations) do
            if destination.method == "taxi" and key ~= introDestinationKey then
                destinationKeys[#destinationKeys + 1] = key
            end
        end
        table.sort(destinationKeys)
        if #destinationKeys > 0 then
            local choice = destinationKeys[(introChanges % #destinationKeys) + 1]
            DebugPrint(("Comando de cambio de destino (E) recibido; destino %s."):format(choice))
            TriggerServerEvent('DP-MultiCharacter:server:requestTaxiDestination', choice)
        else
            DebugPrint("Comando de cambio de destino recibido, pero no hay destinos alternativos.")
        end
    elseif action == "stop" then
        DebugPrint("Comando de parada (Backspace) recibido.")
        TriggerServerEvent('DP-MultiCharacter:server:requestTaxiStop')
    end
end

RegisterCommand('+dpIntroTaxiTalk', function()
    HandleTaxiInput("talk")
end, false)
RegisterCommand('-dpIntroTaxiTalk', function() end, false)
RegisterKeyMapping('+dpIntroTaxiTalk', 'DP-MultiCharacter: hablar con el taxista', 'keyboard', 'G')

RegisterCommand('+dpIntroTaxiRush', function()
    HandleTaxiInput("rush")
end, false)
RegisterCommand('-dpIntroTaxiRush', function() end, false)
RegisterKeyMapping('+dpIntroTaxiRush', 'DP-MultiCharacter: pedir prisa al taxista', 'keyboard', 'R')

RegisterCommand('+dpIntroTaxiChange', function()
    HandleTaxiInput("change")
end, false)
RegisterCommand('-dpIntroTaxiChange', function() end, false)
RegisterKeyMapping('+dpIntroTaxiChange', 'DP-MultiCharacter: cambiar destino del taxi', 'keyboard', 'E')

RegisterCommand('+dpIntroTaxiStop', function()
    HandleTaxiInput("stop")
end, false)
RegisterCommand('-dpIntroTaxiStop', function() end, false)
RegisterKeyMapping('+dpIntroTaxiStop', 'DP-MultiCharacter: solicitar parada del taxi', 'keyboard', 'BACK')

local function StartTaxi(data)
    introTaxiStartedAt = GetGameTimer()
    taxiFinishing = false
    taxiStopping = false
    taxiDepartureRequested = false
    DebugPrint(("startIntroTaxi recibido (destino: %s; inicio: %s; destino: %s)."):format(
        tostring(data and data.destination), DescribeCoords(data and data.start), DescribeCoords(data and data.coords)))
    if type(data) ~= "table" or not data.start or not data.coords then
        DebugPrint("Datos incompletos para iniciar el taxi; se solicita rescate.")
        CompleteTaxi(false, true)
        return
    end

    CleanupTaxi()
    introDestinationKey = data.destination
    introDestination = data.coords
    introChanges = 0
    introRush = false

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    local ped = PlayerPedId()
    SetPlayerControl(PlayerId(), false, 0)
    local collisionLoaded = StreamTeleport(ped, data.start, data.start.w)
    if not collisionLoaded then
        DebugPrint("Las colisiones del punto de recogida del taxi no cargaron en 8 s; se intentará continuar y se registrará si falla el vehículo.")
    end
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    RequestCollisionAtCoord(data.start.x, data.start.y, data.start.z)
    Wait(300)

    local models = Config.Taxi.Models or { { model = "taxi", chance = 1 } }
    local totalChance = 0
    for _, entry in ipairs(models) do
        totalChance = totalChance + math.max(0, tonumber(entry.chance) or 0)
    end
    local roll = math.random() * math.max(totalChance, 1)
    local selectedModel = models[1].model
    for _, entry in ipairs(models) do
        roll = roll - math.max(0, tonumber(entry.chance) or 0)
        if roll <= 0 then
            selectedModel = entry.model
            break
        end
    end

    local vehicleHash = LoadIntroModel(selectedModel)
    local driverHash = LoadIntroModel(Config.Taxi.DriverModel or "s_m_m_gentransport")
    if not vehicleHash or not driverHash then
        DebugPrint(("No se pudieron cargar los modelos del taxi/conductor (taxi: %s, conductor: %s)."):format(
            tostring(vehicleHash ~= nil), tostring(driverHash ~= nil)))
        if vehicleHash then
            SetModelAsNoLongerNeeded(vehicleHash)
        end
        if driverHash then
            SetModelAsNoLongerNeeded(driverHash)
        end
        CompleteTaxi(false, true)
        return
    end

    local foundNode, vehicleCoords, vehicleHeading = GetClosestVehicleNodeWithHeading(
        data.start.x + 10.0, data.start.y - 5.0, data.start.z, 1, 3.0, 0)
    if not foundNode or not vehicleCoords then
        vehicleCoords = vector3(data.start.x + 8.0, data.start.y - 4.0, data.start.z)
        vehicleHeading = data.start.w or 0.0
        DebugPrint("No se encontró un nodo de carretera para el taxi; se usa la posición cercana de reserva.")
    end
    RequestCollisionAtCoord(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z)
    introVehicle = CreateVehicle(vehicleHash, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z,
        vehicleHeading or data.start.w or 0.0, false, false)
    if not DoesEntityExist(introVehicle) then
        DebugPrint(("CreateVehicle falló para el modelo %s."):format(tostring(selectedModel)))
        SetModelAsNoLongerNeeded(vehicleHash)
        SetModelAsNoLongerNeeded(driverHash)
        CompleteTaxi(false, true)
        return
    end

    introDriver = CreatePedInsideVehicle(introVehicle, 26, driverHash, -1, false, false)
    SetModelAsNoLongerNeeded(vehicleHash)
    SetModelAsNoLongerNeeded(driverHash)
    if not DoesEntityExist(introDriver) then
        DebugPrint("No se pudo crear el conductor dentro del taxi.")
        CleanupTaxi()
        CompleteTaxi(false, true)
        return
    end

    SetEntityAsMissionEntity(introVehicle, true, true)
    SetEntityAsMissionEntity(introDriver, true, true)
    SetBlockingOfNonTemporaryEvents(introDriver, true)
    SetPedCanBeDraggedOut(introDriver, false)
    SetVehicleDoorsLocked(introVehicle, 1)
    SetVehicleHandbrake(introVehicle, true)
    SetVehicleEngineOn(introVehicle, false, true, false)
    SetPedCanBeDraggedOut(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, true)
    SetEntityInvincible(introVehicle, true)
    SetEntityInvincible(introDriver, true)
    TaskEnterVehicle(ped, introVehicle, 10000, 2, 1.0, 1, 0)
    DoScreenFadeIn(700)
    DebugPrint(("Personaje caminando hacia el taxi en %.2f %.2f %.2f."):format(
        vehicleCoords.x, vehicleCoords.y, vehicleCoords.z))

    local boardingDeadline = GetGameTimer() + 12000
    while introActive and not IsPedInVehicle(ped, introVehicle, false) and GetGameTimer() < boardingDeadline do
        Wait(100)
    end
    if not IsPedInVehicle(ped, introVehicle, false) then
        DebugPrint("El personaje no llegó al taxi a tiempo; se le coloca en el asiento de pasajero para evitar bloquear la intro.")
        SetPedIntoVehicle(ped, introVehicle, 2)
    end
    SetPlayerControl(PlayerId(), true, 0)
    SetVehicleHandbrake(introVehicle, false)
    SetVehicleEngineOn(introVehicle, true, true, false)
    BeginTaxiDrive()
    UpdateTaxiHud(true, data.label or "destino", "Conversación: G · Prisa: R · Cambiar destino: E · Parar: Backspace")
    DebugPrint(("Taxi y conductor listos; comienza el trayecto hacia %s."):format(tostring(data.label or data.destination)))

    CreateThread(function()
        local lastProgress = GetGameTimer()
        local lastPosition = GetEntityCoords(introVehicle)
        while introActive and not taxiFinishing and introVehicle and DoesEntityExist(introVehicle) do
            Wait(500)
            if not taxiStopping and not IsPedInVehicle(PlayerPedId(), introVehicle, false) then
                DebugPrint("El jugador salió del taxi durante el trayecto; se vuelve a colocar en el asiento trasero.")
                SetPedIntoVehicle(PlayerPedId(), introVehicle, 2)
            end

            local vehicleCoords = GetEntityCoords(introVehicle)
            if #(vehicleCoords - lastPosition) > 3.0 then
                lastPosition = vehicleCoords
                lastProgress = GetGameTimer()
            end

            local remaining = math.max(0, math.floor((Config.Taxi.TripTimeout * 1000 -
                (GetGameTimer() - introTaxiStartedAt)) / 1000))
            if not taxiStopping and #(vehicleCoords - vector3(introDestination.x, introDestination.y, introDestination.z)) < 22.0 then
                DebugPrint(("Taxi llegó a %s (%.2f %.2f %.2f)."):format(
                    tostring(introDestinationKey), vehicleCoords.x, vehicleCoords.y, vehicleCoords.z))
                CompleteTaxi(false)
                return
            elseif not taxiStopping and (GetGameTimer() - lastProgress > (Config.Taxi.StuckTimeout * 1000) or remaining <= 0) then
                DebugPrint(("Taxi atascado o fuera de tiempo (restan %ss); activando rescate."):format(remaining))
                DoScreenFadeOut(300)
                Wait(350)
                CompleteTaxi(false, true)
                return
            end
        end
    end)

    CreateThread(function()
        while introActive and introVehicle and DoesEntityExist(introVehicle) do
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
            Wait(0)
        end
    end)
end

RegisterNetEvent('DP-MultiCharacter:client:introStarted', function(step)
    DebugPrint(("introStarted recibido; fase: %s."):format(tostring(step)))
    introActive = true
    SetIntroPlayerState(true)

    if step == "tailor" then
        local coords = Config.IntroFlow.TailorRoomCoords
        DebugPrint(("Trasladando al tailor room: %.2f %.2f %.2f."):format(coords.x, coords.y, coords.z))
        local ped = PlayerPedId()
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do
            Wait(0)
        end
        local collisionLoaded = StreamTeleport(ped, coords, coords.w)
        if not collisionLoaded then
            DebugPrint("Se mantiene la pantalla negra y no se abre qb-clothing hasta cargar el taller.")
            QBCore.Functions.Notify("No se pudo cargar el taller de personalización. Revisa F8 y reinicia DP-MultiCharacter.", "error")
            return
        end
        ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        SetEntityAlpha(ped, 255, false)
        SetEntityInvincible(ped, true)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetPedArmour(ped, 100)
        DoScreenFadeIn(500)
        if GetResourceState('qb-clothing') == 'started' then
            DebugPrint("Abriendo qb-clothing para personalización inicial.")
            TriggerEvent('DP-MultiCharacter:client:openClothing')
        else
            DebugPrint("qb-clothing no está iniciado; se solicita continuar sin personalización.")
            QBCore.Functions.Notify("qb-clothing no está iniciado; se omitirá la personalización inicial.", "error")
            TriggerServerEvent('DP-MultiCharacter:server:tailorFinished')
        end
    elseif step == "cinematic" then
        DebugPrint("Recuperando intro en fase cinemática.")
        TriggerEvent('DP-MultiCharacter:client:beginIntroCinematic')
    else
        DebugPrint("Recuperando intro directamente en el selector de spawn.")
        TriggerEvent('DP-MultiCharacter:client:openIntroSpawnSelector')
    end
end)

RegisterNetEvent('DP-MultiCharacter:client:introQueued', function()
    introActive = true
    SetIntroPlayerState(true)
    QBCore.Functions.Notify("La introducción está llena; se iniciará en cuanto quede una instancia libre.", "primary")
end)

RegisterNetEvent('DP-MultiCharacter:client:beginIntroCinematic', function()
    CreateThread(function()
        DebugPrint("Iniciando alejamiento de cámara desde el tailor room.")
        if Config.IntroCinematic and Config.IntroCinematic.Enabled == false then
            DebugPrint("Cinemática desactivada; notificando al servidor.")
            TriggerServerEvent('DP-MultiCharacter:server:cinematicFinished')
            return
        end
        local tailor = Config.IntroFlow.TailorRoomCoords
        local duration = math.max(3, tonumber(Config.IntroCinematic and Config.IntroCinematic.Duration) or
            tonumber(Config.IntroFlow.CinematicDuration) or 14)
        local cameraPosition = vector3(tailor.x - 4.0, tailor.y + 6.0, tailor.z + 2.0)
        local startFov = 40.0
        local endFov = 100.0
        DebugPrint(("Zoom óptico desde FOV %.0f a %.0f sin alejar la cámara del interior; duración %ss."):format(
            startFov, endFov, duration))
        local camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
        SetCamFov(camera, startFov)
        PointCamAtCoord(camera, tailor.x, tailor.y, tailor.z)
        SetCamActive(camera, true)
        RenderScriptCams(true, false, 0, true, true)
        DoScreenFadeIn(700)

        local startedAt = GetGameTimer()
        local fadeStarted = false
        while GetGameTimer() - startedAt < duration * 1000 do
            DisableAllControlActions(0)
            local progress = math.min(1.0, (GetGameTimer() - startedAt) / (duration * 1000))
            local eased = progress * progress * (3.0 - 2.0 * progress)
            SetCamFov(camera, startFov + (endFov - startFov) * eased)
            if not fadeStarted and GetGameTimer() - startedAt >= math.max(0, (duration - 3) * 1000) then
                fadeStarted = true
                DebugPrint("Iniciando fundido gradual a negro durante los últimos 3 segundos.")
                DoScreenFadeOut(3000)
            end
            Wait(0)
        end

        while not IsScreenFadedOut() do
            Wait(0)
        end
        DebugPrint("Pantalla completamente negra; esperando 2.5 segundos antes del selector.")
        Wait(2500)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(camera, false)
        DebugPrint("Cinemática terminada; avisando al servidor para abrir el selector.")
        TriggerServerEvent('DP-MultiCharacter:server:cinematicFinished')
    end)
end)

RegisterNetEvent('DP-MultiCharacter:client:tailorFinished', function()
    if introActive then
        DebugPrint("Confirmación de ropa recibida; avisando al servidor.")
        TriggerServerEvent('DP-MultiCharacter:server:tailorFinished')
    else
        DebugPrint("Confirmación de ropa ignorada porque la intro no está activa.")
    end
end)

RegisterNetEvent('DP-MultiCharacter:client:openIntroSpawnSelector', function()
    DebugPrint("Solicitud de apertura del selector de spawn.")
    introActive = true
    SetIntroPlayerState(true)
    TriggerEvent('DP-MultiCharacter:client:openSpawnUI')
end)

RegisterNetEvent('DP-MultiCharacter:client:startIntroTaxi', function(data)
    DebugPrint("Evento de taxi recibido del servidor.")
    StartTaxi(data)
end)

RegisterNetEvent('DP-MultiCharacter:client:startIntroWalk', function(destination)
    if not destination then
        TriggerServerEvent('DP-MultiCharacter:server:finishIntroWalk')
        return
    end

    CreateThread(function()
        local ped = PlayerPedId()
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do
            Wait(0)
        end
        SetEntityCoordsNoOffset(ped, destination.x, destination.y, destination.z, false, false, false)
        SetEntityHeading(ped, destination.w or 0.0)
        SetEntityVisible(ped, true, false)
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true, 0)
        SetEntityInvincible(ped, true)
        RequestCollisionAtCoord(destination.x, destination.y, destination.z)
        Wait(700)
        DoScreenFadeIn(500)

        local exitX = destination.x + 8.0
        local exitY = destination.y + 3.0
        TaskGoStraightToCoord(ped, exitX, exitY, destination.z, 1.0, 10000, destination.w or 0.0, 0.1)
        SetPlayerControl(PlayerId(), false, 0)
        local timeout = GetGameTimer() + 10000
        while GetGameTimer() < timeout and #(GetEntityCoords(ped) - vector3(exitX, exitY, destination.z)) > 1.5 do
            Wait(100)
        end
        TriggerServerEvent('DP-MultiCharacter:server:finishIntroWalk')
    end)
end)

RegisterNetEvent('DP-MultiCharacter:client:updateIntroTaxiDestination', function(key, label, coords, changes)
    DebugPrint(("Respuesta de cambio de destino: %s (%s)."):format(tostring(key), tostring(label)))
    introDestinationKey = key
    introDestination = coords
    introChanges = changes or introChanges + 1
    BeginTaxiDrive()
    UpdateTaxiHud(true, label, ("Cambios de destino restantes: %s"):format(
        math.max(0, Config.Taxi.MaxDestinationChanges - introChanges)))
    QBCore.Functions.Notify(("Nuevo destino: %s (%s cambios restantes)"):format(label,
        math.max(0, Config.Taxi.MaxDestinationChanges - introChanges)), "primary")
end)

RegisterNetEvent('DP-MultiCharacter:client:setIntroTaxiRush', function(enabled)
    if taxiStopping or taxiFinishing then
        return
    end
    DebugPrint(("Respuesta de prisa del taxi: %s."):format(tostring(enabled)))
    introRush = enabled == true
    if introDriver and DoesEntityExist(introDriver) and not taxiStopping then
        SetDriveTaskMaxCruiseSpeed(introDriver, introRush and 24.0 or 16.0)
    end
    UpdateTaxiHud(true, nil, introRush and "El taxista va con prisa." or "Conducción normal.")
    QBCore.Functions.Notify(introRush and "El taxista acelera." or "El taxista vuelve a conducir con calma.", "primary")
end)

RegisterNetEvent('DP-MultiCharacter:client:stopIntroTaxi', function(position)
    if taxiStopping or taxiFinishing then
        DebugPrint("Petición de parada duplicada ignorada.")
        return
    end
    DebugPrint("Servidor autorizó parada segura del taxi.")
    taxiStopping = true
    UpdateTaxiHud(true, nil, "Buscando un punto seguro para detenerse...")
    if not introVehicle or not DoesEntityExist(introVehicle) then
        taxiFinishing = true
        taxiDepartureRequested = true
        TriggerServerEvent('DP-MultiCharacter:server:finishIntroTaxi', true)
        return
    end

    local vehicleCoords = GetEntityCoords(introVehicle)
    local forward = GetEntityForwardVector(introVehicle)
    local stopCoords
    for distance = 18.0, 36.0, 6.0 do
        local searchX = vehicleCoords.x + forward.x * distance
        local searchY = vehicleCoords.y + forward.y * distance
        local found, node = GetClosestVehicleNodeWithHeading(searchX, searchY, vehicleCoords.z, 1, 3.0, 0)
        if found and node and #(node - vehicleCoords) > 10.0 then
            stopCoords = node
            break
        end
    end

    if stopCoords and introDriver and DoesEntityExist(introDriver) then
        ClearPedTasks(introDriver)
        TaskVehicleDriveToCoordLongrange(introDriver, introVehicle, stopCoords.x, stopCoords.y, stopCoords.z,
            8.0, 786603, 5.0)
        UpdateTaxiHud(true, nil, "Aparcando en el siguiente tramo seguro...")
        local timeout = GetGameTimer() + 20000
        while DoesEntityExist(introVehicle) and GetGameTimer() < timeout do
            local distance = #(GetEntityCoords(introVehicle) - stopCoords)
            if distance <= 8.0 and GetEntitySpeed(introVehicle) < 1.5 then
                break
            end
            Wait(250)
        end
    elseif not stopCoords then
        DebugPrint("No se encontró un nodo seguro por delante; frenando en la ubicación actual.")
    else
        DebugPrint("No hay conductor disponible para maniobrar; se detiene el taxi donde está.")
    end

    if DoesEntityExist(introDriver) then
        ClearPedTasks(introDriver)
    end
    SetVehicleHandbrake(introVehicle, true)
    SetVehicleForwardSpeed(introVehicle, 0.0)

    local ped = PlayerPedId()
    if IsPedInVehicle(ped, introVehicle, false) then
        TaskLeaveVehicle(ped, introVehicle, 0)
        local exitTimeout = GetGameTimer() + 10000
        while IsPedInVehicle(ped, introVehicle, false) and GetGameTimer() < exitTimeout do
            Wait(100)
        end
    end
    if IsPedInVehicle(ped, introVehicle, false) then
        DebugPrint("No se pudo completar la salida animada; se coloca al jugador junto al taxi detenido.")
        local exitCoords = GetOffsetFromEntityInWorldCoords(introVehicle, 1.5, -1.0, 0.0)
        SetEntityCoords(ped, exitCoords.x, exitCoords.y, exitCoords.z, false, false, false, false)
    end

    taxiFinishing = true
    taxiDepartureRequested = true
    DebugPrint("Taxi aparcado y jugador fuera; se solicita el cobro proporcional.")
    TriggerServerEvent('DP-MultiCharacter:server:finishIntroTaxi', true)
end)

RegisterNetEvent('DP-MultiCharacter:client:taxiStopDenied', function()
    DebugPrint("Servidor rechazó la parada del taxi por tiempo mínimo.")
    UpdateTaxiHud(true, nil, "La parada estará disponible en unos segundos.")
end)

RegisterNetEvent('DP-MultiCharacter:client:completeIntro', function(coords, markDone)
    DebugPrint(("completeIntro recibido (completado: %s, destino final: %s)."):format(
        tostring(markDone), DescribeCoords(coords)))
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do
        Wait(0)
    end
    if taxiDepartureRequested then
        taxiDepartureRequested = false
        StartTaxiDeparture()
    else
        CleanupTaxi()
    end
    taxiStopping = false
    ReleaseTailorInterior()
    local ped = PlayerPedId()
    SetPedCanBeDraggedOut(ped, true)
    SetIntroPlayerState(false)

    if coords and coords.x then
        local target = vector4(coords.x, coords.y, coords.z, coords.w or 0.0)
        if pendingCData then
            TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', target, pendingCData)
        else
            TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', target, QBCore.Functions.GetPlayerData())
        end
    else
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', Config.SpawnPoints.DefaultSpawn, pendingCData)
    end
    CreateThread(function()
        Wait(2500)
        TriggerServerEvent('DP-MultiCharacter:server:confirmIntroComplete')
    end)
    pendingCData = nil
    isNewCharacterFlow = false
    DebugPrint(markDone and "Intro finalizada." or "Intro recuperada con spawn normal.")
end)

RegisterNetEvent('DP-MultiCharacter:client:introUnavailable', function()
    ReleaseTailorInterior()
    introActive = false
    SetIntroPlayerState(false)
    if Config.SpawnPoints.SkipSelection then
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', Config.SpawnPoints.DefaultSpawn, pendingCData)
        Wait(1000)
        TriggerEvent('DP-MultiCharacter:client:openClothing')
    else
        TriggerEvent('DP-MultiCharacter:client:openSpawnUI')
    end
end)

RegisterNetEvent('DP-MultiCharacter:client:cleanupIntro', function()
    CleanupTaxi()
    ReleaseTailorInterior()
    introActive = false
    SetIntroPlayerState(false)
    RenderScriptCams(false, false, 0, true, true)
    DoScreenFadeIn(300)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    CleanupTaxi()
    ReleaseTailorInterior()
    if introActive then
        SetIntroPlayerState(false)
    end
    RenderScriptCams(false, false, 0, true, true)
end)
