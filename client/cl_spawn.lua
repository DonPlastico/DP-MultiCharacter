local QBCore = exports['qb-core']:GetCoreObject()

local function DebugPrint(msg)
    if Config.Debug or (Config.IntroFlow and Config.IntroFlow.Debug) then
        print("^5[DP-MultiCharacter:Spawn Debug] ^7" .. msg)
    end
end

local function DescribeCoords(coords)
    if type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4" then
        return tostring(coords or "ninguna")
    end
    return ("%.2f %.2f %.2f"):format(
        tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
end

-- Datos del personaje pendiente de spawnear (los rellena cl_main.lua / cl_events.lua)
pendingCData = nil
isNewCharacterFlow = false

-- ==========================================
-- 🎥 CÁMARA Y ESTADO DEL JUGADOR DURANTE EL SELECTOR
-- ==========================================
-- Mientras el jugador está en el mapa de DP-PauseMenu, lo dejamos congelado e invisible
-- para que no se caiga ni interactúe con el mundo real. El mapa en sí lo abre el otro script.

local function FreezePlayerForSpawn()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    SetPlayerControl(PlayerId(), false, 0)

    -- 🛑 ELIMINADO: No creamos cámara propia aquí.
    -- DP-PauseMenu abrirá su UI a pantalla completa y tapará todo.
    -- Si dejamos la cámara del garaje, veremos la pared gris encima del mapa.
end

local function UnfreezePlayerAfterSpawn()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
end

-- ==========================================
-- 🚪 PUNTO DE ENTRADA DEL SELECTOR DE SPAWN
-- ==========================================
-- Este evento lo dispara DP-MultiCharacter cuando el jugador ha elegido personaje
-- (o ha terminado de crearlo) y necesita elegir dónde aparecer.
RegisterNetEvent('DP-MultiCharacter:client:openSpawnUI', function()
    local dynamicSpawnBlips = Config.SpawnPoints.DynamicSpawnBlips or {}
    DebugPrint(("openSpawnUI recibido (intro activa: %s, puntos dinámicos: %s)."):format(
        tostring(IsMultiCharacterIntroActive and IsMultiCharacterIntroActive()),
        tostring(#dynamicSpawnBlips)))
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    SendNUIMessage({
        action = 'spawnToggleUI',
        status = false
    })

    SetNuiFocus(false, false)
    FreezePlayerForSpawn()

    local citizenid = pendingCData and pendingCData.citizenid or nil

    local function OpenMapWithData(apartments, lastLocation)
        apartments = apartments or {}

        local success, err = pcall(function()
            if exports['DP-PauseMenu'] and exports['DP-PauseMenu'].OpenSpawnSelectorWithApartments then
                DebugPrint(("Abriendo DP-PauseMenu con %s blips, %s apartamentos y selección activa de intro: %s."):format(
                    #dynamicSpawnBlips, #apartments,
                    tostring(IsMultiCharacterIntroActive and IsMultiCharacterIntroActive())))
                local locToSend = nil
                if Config.SpawnPoints.EnableLastLocation then
                    locToSend = lastLocation
                end

                -- 👇 PASAMOS Config.SpawnPoints.EnableApartments COMO 6º ARGUMENTO 👇
                exports['DP-PauseMenu']:OpenSpawnSelectorWithApartments(function(coords)
                    DebugPrint(("Callback de DP-PauseMenu recibido: %s."):format(DescribeCoords(coords)))
                    HandleSpawnSelectionResult(coords)
                end, apartments, dynamicSpawnBlips, locToSend, Config.SpawnPoints.EnableLastLocation,
                    Config.SpawnPoints.EnableApartments)
            else
                DebugPrint("Export OpenSpawnSelectorWithApartments no disponible. Usando el clásico sin apartamentos.")
                exports['DP-PauseMenu']:OpenSpawnSelector(function(coords)
                    HandleSpawnSelectionResult(coords)
                end)
            end
        end)

        if not success then
            DebugPrint("Error abriendo el selector de spawn: " .. tostring(err))
            UnfreezePlayerAfterSpawn()
            TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', Config.SpawnPoints.DefaultSpawn, pendingCData)
        end
    end

    if citizenid then
        QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getOwnedApartments', function(apartments)

            -- ¡NUEVO! Ya no consultamos la BD de nuevo. 
            -- Usamos pendingCData que tiene la posición original intacta.
            local lastLoc = nil
            if pendingCData and pendingCData.position then
                local posType = type(pendingCData.position)

                -- Decodificamos dependiendo de si viene en string (JSON) o ya es tabla
                if posType == 'string' then
                    lastLoc = json.decode(pendingCData.position)
                elseif posType == 'table' then
                    lastLoc = pendingCData.position
                end

                -- Mantenemos tu SEGURO aquí en el cliente por precaución
                if lastLoc and lastLoc.x and lastLoc.y then
                    local dist =
                        #(vector2(lastLoc.x, lastLoc.y) - vector2(Config.HiddenCoords.x, Config.HiddenCoords.y))
                    if dist < 50.0 or (lastLoc.z and lastLoc.z < -50.0) then
                        lastLoc = {
                            x = Config.SpawnPoints.DefaultSpawn.x,
                            y = Config.SpawnPoints.DefaultSpawn.y,
                            z = Config.SpawnPoints.DefaultSpawn.z
                        }
                    end
                end
            end

            OpenMapWithData(apartments, lastLoc)

        end, citizenid)
    else
        DebugPrint("openSpawnUI sin pendingCData.citizenid. Abriendo mapa sin apartamentos.")
        OpenMapWithData({}, nil)
    end
end)

-- Callback común para procesar el resultado del mapa (extraído para no duplicar lógica)
function HandleSpawnSelectionResult(coords)
    DebugPrint(("Procesando selección %s; intro activa: %s."):format(
        DescribeCoords(coords), tostring(IsMultiCharacterIntroActive and IsMultiCharacterIntroActive())))
    if IsMultiCharacterIntroActive and IsMultiCharacterIntroActive() then
        DebugPrint("Enviando el punto elegido al servidor para validar e iniciar el taxi.")
        TriggerServerEvent('DP-MultiCharacter:server:confirmIntroSpawn', coords)
        return
    end

    if not IsScreenFadedOut() then
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    if coords and coords.x and coords.y then
        local targetCoords = vector4(coords.x, coords.y, coords.z or 0.0, 0.0)
        UnfreezePlayerAfterSpawn()
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', targetCoords, pendingCData)
        if isNewCharacterFlow then
            Wait(1000)
            TriggerEvent('DP-MultiCharacter:client:openClothing')
        end
    else
        UnfreezePlayerAfterSpawn()
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', Config.SpawnPoints.DefaultSpawn, pendingCData)
        if isNewCharacterFlow then
            Wait(1000)
            TriggerEvent('DP-MultiCharacter:client:openClothing')
        end
    end
end

-- =====================================================================
-- 🛑 CANCELACIÓN DEL SELECTOR DE SPAWN (VOLVER AL MULTICHARACTER)
-- =====================================================================
RegisterNetEvent('DP-PauseMenu:spawnCancelled', function()
    if IsMultiCharacterIntroActive and IsMultiCharacterIntroActive() then
        TriggerEvent('DP-MultiCharacter:client:openIntroSpawnSelector')
        return
    end

    -- Descongelamos al jugador para que pueda interactuar con el menú del multicharacter
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, false, false) -- Lo dejamos invisible para la cámara del multichar
    SetPlayerControl(PlayerId(), true, 0)

    -- Le devolvemos el foco a la interfaz del MultiCharacter
    SetNuiFocus(true, true)

    -- Enviamos la orden a la UI de que se vuelva a mostrar
    SendNUIMessage({
        action = "toggleUI",
        state = true
    })

    -- Si el jugador estaba en mitad de la selección, volvemos a pedir los personajes para que se vea la lista actualizada
    TriggerServerEvent('DP-MultiCharacter:server:refreshCharacters')

    Wait(400)
    DoScreenFadeIn(500)
end)

-- ==========================================
-- 🧹 LIMPIEZA AL DETENER EL RECURSO
-- ==========================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
end)

-- =====================================================================
-- 🛡️ SISTEMA DE EMERGENCIA ANTI-ATASCOS (REINICIO DE SCRIPT)
-- =====================================================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    -- Si el script se para mientras estamos en el flujo de spawn (congelados)
    if pendingCData then
        local ped = PlayerPedId()

        -- Restauramos el estado del jugador
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        SetEntityVisible(ped, true, false)
        SetPlayerControl(PlayerId(), true, 0)

        -- 🛑 TELETRANSPORTE DE EMERGENCIA AL SPAWN POR DEFECTO DEL MULTICHARACTER
        local defaultSpawn = Config.SpawnPoints.DefaultSpawn or vector4(-1046.02, -2751.97, 21.36, 326.05)

        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do
            Wait(0)
        end

        -- 🔥 1. Lo movemos un poco por encima del suelo sin forzar la escena 🔥
        SetEntityCoords(ped, defaultSpawn.x, defaultSpawn.y, defaultSpawn.z + 0.5, false, false, false, false)
        SetEntityHeading(ped, defaultSpawn.w or 0.0)

        -- 🔥 2. Dejamos que el motor cargue solo (Evita el crasheo Pool Full) 🔥
        Wait(1500)

        -- 🔥 3. Aseguramos las colisiones suavemente 🔥
        RequestCollisionAtCoord(defaultSpawn.x, defaultSpawn.y, defaultSpawn.z)
        local timeOut = 0
        while not HasCollisionLoadedAroundEntity(ped) and timeOut < 3000 do
            Wait(100)
            timeOut = timeOut + 100
        end

        -- Ajustamos a la Z perfecta
        SetEntityCoordsNoOffset(ped, defaultSpawn.x, defaultSpawn.y, defaultSpawn.z, false, false, false, true)

        DoScreenFadeIn(1000)

        -- Limpiamos el estado
        pendingCData = nil
        isNewCharacterFlow = false
    end
end)
