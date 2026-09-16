local QBCore = exports['qb-core']:GetCoreObject()
local cam = nil
local charPeds = {} -- Ahora es una tabla para guardar todos los Peds
local activePedCoords = {}

-- Generador de géneros aleatorios por sesión para las sombras (0 = Hombre, 1 = Mujer)
local randomSlotGenders = {}
CreateThread(function()
    Wait(200) -- Pequeño margen para asegurar entropía en la semilla
    math.randomseed(GetGameTimer())
    for i = 1, 10 do
        -- Usamos tostring() para obligar al JS a leerlo como Objeto exacto
        randomSlotGenders[tostring(i)] = math.random(0, 1)
    end
end)

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
-- Esta función imprimirá mensajes en la consola (F8) solo si Config.Debug está activado.
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🧍‍♂️ FUNCIÓN PARA DESNUDAR PEDS
-- ==========================================
local function SetPedNaked(ped, model)
    if model == joaat(Config.DefaultMaleModel) then
        -- Hombre desnudo (Boxers)
        SetPedComponentVariation(ped, 3, 15, 0, 0) -- Brazos (Desnudos)
        SetPedComponentVariation(ped, 4, 14, 0, 0) -- Pantalones (Boxers)
        SetPedComponentVariation(ped, 6, 34, 0, 0) -- Pies (Descalzo)
        SetPedComponentVariation(ped, 8, 15, 0, 0) -- Accesorio (Nada)
        SetPedComponentVariation(ped, 11, 15, 0, 0) -- Torso (Pecho descubierto)
    elseif model == joaat(Config.DefaultFemaleModel) then
        -- Mujer desnuda (Ropa interior)
        SetPedComponentVariation(ped, 3, 15, 0, 0) -- Brazos (Desnudos)
        SetPedComponentVariation(ped, 4, 15, 0, 0) -- Pantalones (Bragas)
        SetPedComponentVariation(ped, 6, 35, 0, 0) -- Pies (Descalza)
        SetPedComponentVariation(ped, 8, 15, 0, 0) -- Accesorio (Nada)
        SetPedComponentVariation(ped, 11, 15, 0, 0) -- Torso (Sujetador)
    end
end

-- ==========================================
-- 🖥️ GESTIÓN DE LA INTERFAZ Y MUNDO
-- ==========================================
-- Función para alternar la visibilidad de la interfaz de usuario y aislar al jugador
function ToggleUI(state)
    DebugPrint("ToggleUI ejecutado. Estado: " .. tostring(state))
    SetNuiFocus(state, state)

    -- Leemos el banco inicial que QBCore tiene configurado por defecto (si no lo encuentra, asume 10000)
    local startingBank = 10000
    if QBCore.Config and QBCore.Config.Money and QBCore.Config.Money.MoneyTypes then
        startingBank = QBCore.Config.Money.MoneyTypes.bank or 10000
    end

    SendNUIMessage({
        action = "toggleUI",
        state = state,
        debug = Config.Debug,
        translations = GetTranslations(),
        nationalities = Config.Nationalities,
        minAge = Config.MinAge or 18,
        maxAge = Config.MaxAge or 100,
        randomGenders = randomSlotGenders,
        hideLocked = GetHideLockedPreference(),
        exportCharacters = Config.ExportCharacters ~= nil and Config.ExportCharacters or false,
        importCharacters = Config.ImportCharacters ~= nil and Config.ImportCharacters or false,
        helpConfig = {
            enableWeb = Config.EnableWebHelp ~= nil and Config.EnableWebHelp or false,
            webURL = Config.WebHelpURL or '',
            enableDiscord = Config.EnableDiscordHelp ~= nil and Config.EnableDiscordHelp or false,
            discordURL = Config.DiscordHelpURL or ''
        },
        -- 🛒 NUEVOS DATOS PARA EL CARRITO DE COMPRAS (Starter Items)
        startingItems = Config.StartItemsList or {},
        startingBudget = startingBank -- Dinero leído directamente de QBCore
    })

    -- Al ABRIR la UI, solicitamos el volumen de interfaz persistido en BD y se lo
    -- reenviamos a la interfaz para que actualice su slider/sonidos con el valor real.
    if state then
        QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getInterfaceVolume', function(volume)
            SendNUIMessage({
                action = "toggleUI",
                state = true,
                interfaceVolume = volume or 100
            })
        end)
    end

    if state then
        -- Ocultar chat al entrar a la selección usando tu evento custom
        TriggerEvent('chat:clear')
        TriggerEvent('chat:client:showChat', false)

        -- Manda al jugador a una dimensión única (Routing Bucket)
        DebugPrint("Enviando jugador a una dimensión única (Routing Bucket).")
        TriggerServerEvent('DP-MultiCharacter:server:SetBucket', GetPlayerServerId(PlayerId()))
    else
        -- Mostrar chat al entrar al mundo
        TriggerEvent('chat:client:showChat', true)

        -- Lo devuelve al mundo normal (Bucket 0)
        DebugPrint("Devolviendo al jugador a la dimensión normal (Bucket 0).")
        TriggerServerEvent('DP-MultiCharacter:server:SetBucket', 0)
    end

    SetupCamera(state)
end

-- Función para preparar la cámara cinemática, ocultar el HUD y bloquear NPCs
function SetupCamera(state)
    DebugPrint("SetupCamera ejecutado. Estado: " .. tostring(state))
    if state then
        DoScreenFadeIn(1000)
        FreezeEntityPosition(PlayerPedId(), true)
        SetEntityInvincible(PlayerPedId(), true) -- Hacerlo invencible
        DisplayHud(false)
        DisplayRadar(false)

        DebugPrint("Creando y activando la cámara del menú.")
        cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", Config.CamCoords.x, Config.CamCoords.y, Config.CamCoords.z,
            0.0, 0.0, Config.CamCoords.w, 60.00, false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 1, true, true)

        -- Hilo para bloquear spawns de NPCs mientras esté en el menú
        CreateThread(function()
            DebugPrint("Iniciando hilo para bloquear spawns de NPCs (ThisFrame).")
            -- Usamos Wait(0) por obligación del motor de GTA V, pero reforzamos la 
            -- condición para que muera instantáneamente al entrar al mundo.
            while cam and DoesCamExist(cam) and IsCamActive(cam) do
                SetVehicleDensityMultiplierThisFrame(0.0)
                SetPedDensityMultiplierThisFrame(0.0)
                SetRandomVehicleDensityMultiplierThisFrame(0.0)
                SetParkedVehicleDensityMultiplierThisFrame(0.0)
                SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
                Wait(0)
            end
            DebugPrint("Hilo de bloqueo de NPCs finalizado correctamente.")
        end)
    else
        DebugPrint("Destruyendo la cámara del menú y restaurando el HUD.")
        DoScreenFadeOut(500) -- Fundido a negro ANTES de destruir la cámara
        Wait(500)
        DisplayHud(true)
        DisplayRadar(true)
        SetCamActive(cam, false)
        DestroyCam(cam, true)
        RenderScriptCams(false, false, 1, true, true)

        -- SOLUCIÓN: Devolver la luz a la pantalla para que qb-clothing se vea
        Wait(500)
        DoScreenFadeIn(1000)
    end
end

-- Función para actualizar el género del modelo holográfico/sombra temporalmente
function UpdatePedGender(slot, gender)
    DebugPrint("Intentando actualizar el género del ped en el slot " .. tostring(slot) .. " a " .. tostring(gender))
    if not charPeds[slot] or not charPeds[slot].isShadow then
        DebugPrint("El slot " .. tostring(slot) .. " no contiene una sombra o no existe. Ignorando.")
        return
    end

    local model = joaat(Config.DefaultMaleModel)
    if gender == "Femenino" or gender == 1 or gender == "1" then
        model = joaat(Config.DefaultFemaleModel)
    end

    -- Guardamos la secuencia de spawn actual
    local thisSequence = currentSpawnSequence

    DebugPrint("Solicitando modelo para actualizar género: " .. tostring(model))
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 500 do
        Wait(10)
        timeout = timeout + 1
    end

    -- 🛡️ ANTI-DUPLICADOS: Si la secuencia cambió mientras esperábamos al modelo, abortamos
    if thisSequence ~= currentSpawnSequence then
        return
    end

    local coords = activePedCoords[slot] or Config.PedCoords[slot] or Config.PedCoords[1]

    -- Borramos la silueta vieja
    if charPeds[slot].entity and DoesEntityExist(charPeds[slot].entity) then
        DebugPrint("Eliminando entidad sombra anterior del slot " .. tostring(slot))
        DeleteEntity(charPeds[slot].entity)
    end

    -- Creamos la nueva
    DebugPrint("Creando nueva entidad sombra en el slot " .. tostring(slot))
    local ped = CreatePed(2, model, coords.x, coords.y, coords.z - 0.98, coords.w, false, true)
    SetPedComponentVariation(ped, 0, 0, 0, 2)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityAlpha(ped, 150, false)
    SetPedNaked(ped, model)

    charPeds[slot].entity = ped
end

-- ==========================================
-- 🧍‍♂️ GESTIÓN DE PEDS (CREACIÓN Y BORRADO)
-- ==========================================
local currentSpawnSequence = 0 -- Variable para controlar las condiciones de carrera asíncronas

-- Failsafe: Limpia cualquier ped "zombie" que haya quedado de un reinicio de script
local function ClearZombiePeds()
    DebugPrint("Ejecutando limpieza de peds zombies en la sala de selección.")
    local peds = GetGamePool('CPed')
    for i = 1, #peds do
        local ped = peds[i]
        -- Si existe, NO es un jugador real, y está a menos de 20 metros de la sala
        if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local coords = GetEntityCoords(ped)
            if #(coords - vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)) < 20.0 then
                DeleteEntity(ped)
            end
        end
    end
end

-- ==========================================
-- 🎥 SISTEMA DE ZOOM Y FOCO
-- ==========================================
local lastFocusedSlot = nil -- Guarda el último slot enfocado para saber a quién ocultar después

-- Función para acercar la cámara a un personaje específico (Zoom)
function FocusCharacter(slot)
    DebugPrint("Enfocando cámara en el personaje del slot " .. tostring(slot))
    if not charPeds[slot] then
        DebugPrint("No se encontró ped en el slot " .. tostring(slot) .. " para enfocar.")
        return
    end

    lastFocusedSlot = slot

    -- 1. Mostramos primero al personaje seleccionado (por si estaba oculto de un foco anterior)
    if charPeds[slot].isShadow then
        SetEntityAlpha(charPeds[slot].entity, 150, false)
    else
        ResetEntityAlpha(charPeds[slot].entity)
    end

    -- 2. Movemos la cámara suavemente hacia él (zoom al personaje)
    local targetCoords = activePedCoords[slot] or Config.PedCoords[slot] or Config.PedCoords[1]
    local zoomX = targetCoords.x + 1.8 -- Nos acercamos en el eje X
    local zoomY = targetCoords.y -- Mantenemos su Y para que quede centrado
    local zoomZ = targetCoords.z + 0.35 -- Apuntamos al pecho

    local camDuration = 800
    DebugPrint("Iniciando transición de cámara hacia las coordenadas del slot.")
    SetCamParams(cam, zoomX, zoomY, zoomZ, 0.0, 0.0, 90.0, 50.0, camDuration, 1, 1, 2)

    -- 3. Solo cuando la cámara TERMINA su movimiento, ocultamos al resto de personajes
    CreateThread(function()
        Wait(camDuration)

        -- Si mientras esperábamos el jugador ya cambió a otro personaje, no ocultamos nada aquí
        -- (el nuevo hilo que se disparó para ese otro slot se encargará de ocultar correctamente)
        if lastFocusedSlot ~= slot then
            return
        end

        DebugPrint("Ocultando el resto de personajes para centrar atención.")
        for k, data in pairs(charPeds) do
            if k ~= slot then
                SetEntityAlpha(data.entity, 0, false)
            end
        end
    end)
end

-- Función para alejar la cámara y volver a la vista general de todos
function UnfocusCharacter()
    DebugPrint("Quitando foco del personaje. Restaurando vista general.")
    lastFocusedSlot = nil -- Reseteamos para que el próximo FocusCharacter funcione limpio

    -- Mostrar a todos de nuevo
    for k, data in pairs(charPeds) do
        if data.isShadow then
            SetEntityAlpha(data.entity, 150, false)
        else
            ResetEntityAlpha(data.entity)
        end
    end

    -- Alejar camara a la posición global
    SetCamParams(cam, Config.CamCoords.x, Config.CamCoords.y, Config.CamCoords.z, 0.0, 0.0, Config.CamCoords.w, 60.0,
        800, 1, 1, 2)
end

-- Función auxiliar interna para buscar la data de un personaje concreto según su slot
local function GetCharacterBySlot(characters, slot)
    for _, char in pairs(characters) do
        if tonumber(char.cid) == tonumber(slot) then
            return char
        end
    end
    return nil
end

local function GetCenteredPedCoords(slot, totalSlots)
    local center = Config.PedCoords[3]
    local offset = (slot - ((totalSlots + 1) / 2)) * Config.PedSpacing

    return vector4(center.x, center.y + offset, center.z, center.w)
end

-- ==========================================
-- 🧍‍♂️ GESTIÓN DE PEDS (CREACIÓN Y BORRADO)
-- ==========================================
-- Función para generar todos los peds al abrir el menú (tanto reales como sombras)
function SpawnAllPeds(characters, maxSlots)
    currentSpawnSequence = currentSpawnSequence + 1
    local thisSequence = currentSpawnSequence

    DebugPrint("Iniciando SpawnAllPeds para " .. tostring(maxSlots) .. " slots máximos.")
    DeleteAllPeds() -- Limpiamos por seguridad

    -- Si es la primera vez que se carga la UI, forzamos limpieza de zombies
    if thisSequence == 1 then
        ClearZombiePeds()
    end

    activePedCoords = {}

    local hideLocked = GetHideLockedPreference()
    local visibleSlots = {}
    local hasCharacters = #characters > 0

    for slot = 1, maxSlots do
        local char = GetCharacterBySlot(characters, slot)
        if char then
            visibleSlots[#visibleSlots + 1] = {
                slot = slot,
                char = char
            }
        elseif not hideLocked then
            visibleSlots[#visibleSlots + 1] = {
                slot = slot,
                char = nil
            }
        elseif not hasCharacters and slot == 1 then
            visibleSlots[#visibleSlots + 1] = {
                slot = slot,
                char = nil
            }
        end
    end

    local totalVisible = #visibleSlots

    for visualIndex, entry in ipairs(visibleSlots) do
        local slot = entry.slot
        local char = entry.char
        local coords = GetCenteredPedCoords(visualIndex, totalVisible)
        activePedCoords[slot] = coords

        if char then
            SpawnSinglePed(slot, char.charinfo.gender, char.model, char.skin, coords, false, thisSequence)
        else
            local randomGender = randomSlotGenders[tostring(slot)] or 0
            SpawnSinglePed(slot, randomGender, nil, nil, coords, true, thisSequence)
        end
    end
end

-- Función para eliminar todos los peds almacenados en la tabla
function DeleteAllPeds()
    DebugPrint("Ejecutando DeleteAllPeds: Eliminando todos los personajes de previsualización.")
    lastFocusedSlot = nil
    for _, data in pairs(charPeds) do
        if data and data.entity and DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    charPeds = {}
end

-- Función para instanciar un Ped individualmente
function SpawnSinglePed(slot, gender, customModel, skinData, coords, isShadow, sequenceId)
    local model = joaat(Config.DefaultMaleModel)
    if gender == "Femenino" or gender == 1 or gender == "1" then
        model = joaat(Config.DefaultFemaleModel)
    end

    if customModel then
        local parsedModel = tonumber(customModel)
        model = parsedModel and parsedModel or joaat(customModel)
    end

    if not IsModelInCdimage(model) or not IsModelValid(model) then
        model = joaat(Config.DefaultMaleModel)
    end

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 500 do
        Wait(10)
        timeout = timeout + 1
    end

    -- 🛡️ ANTI-DUPLICADOS: Si la secuencia cambió mientras esperábamos, cancelamos
    if sequenceId and sequenceId ~= currentSpawnSequence then
        DebugPrint("Spawn cancelado para el slot " .. tostring(slot) .. " por cambio asíncrono.")
        return
    end

    -- 🛡️ ANTI-DUPLICADOS EXTRA: Si ya se registró un ped en este slot, lo borramos preventivamente
    if charPeds[slot] and charPeds[slot].entity and DoesEntityExist(charPeds[slot].entity) then
        DeleteEntity(charPeds[slot].entity)
    end

    local ped = CreatePed(2, model, coords.x, coords.y, coords.z - 0.98, coords.w, false, true)
    SetPedComponentVariation(ped, 0, 0, 0, 2)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if isShadow then
        SetEntityAlpha(ped, 150, false)
        SetPedNaked(ped, model)
    elseif skinData then
        local decodedSkin = type(skinData) == "string" and json.decode(skinData) or skinData
        TriggerEvent('qb-clothing:client:loadPlayerClothing', decodedSkin, ped)
    else
        SetPedNaked(ped, model)
    end

    charPeds[slot] = {
        entity = ped,
        isShadow = isShadow
    }
    DebugPrint("Ped creado y registrado exitosamente en el slot " .. tostring(slot))
end

-- Función alternativa/legacy para previsualizar peds
function SpawnPreviewPed(gender, customModel, skinData)
    DebugPrint("Spawneando PreviewPed (Legacy).")
    -- Limpiar el ped anterior si existe
    if charPed ~= nil then
        DeleteEntity(charPed)
        charPed = nil
    end

    -- 1. Determinar el modelo base según el género
    local model = joaat(Config.DefaultMaleModel)
    if gender == "Femenino" or gender == 1 or gender == "1" then
        model = joaat(Config.DefaultFemaleModel)
    end

    -- 2. Procesar el modelo guardado en la base de datos
    if customModel then
        local parsedModel = tonumber(customModel)
        if parsedModel then
            -- Si es un número (ej. "1885233650"), lo usamos directamente
            model = parsedModel
        else
            -- Si es texto (ej. "mp_m_freemode_01"), lo convertimos a hash
            model = joaat(customModel)
        end
    end

    -- 3. Failsafe: Si el modelo es inválido, forzamos el default para que no se congele
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        model = joaat(Config.DefaultMaleModel)
        if gender == "Femenino" or gender == 1 or gender == "1" then
            model = joaat(Config.DefaultFemaleModel)
        end
    end

    -- 4. Solicitar y esperar el modelo con un tiempo límite de seguridad
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 500 do
        Wait(10)
        timeout = timeout + 1
    end

    -- 5. Crear y congelar el ped
    charPed = CreatePed(2, model, Config.PedCoords.x, Config.PedCoords.y, Config.PedCoords.z - 0.98, Config.PedCoords.w,
        false, true)

    SetPedComponentVariation(charPed, 0, 0, 0, 2)
    FreezeEntityPosition(charPed, true)
    SetEntityInvincible(charPed, true)
    SetBlockingOfNonTemporaryEvents(charPed, true)

    -- 6. Aplicar la ropa guardada usando qb-clothing
    if skinData then
        local decodedSkin = type(skinData) == "string" and json.decode(skinData) or skinData
        Wait(50) -- Pequeño margen para asegurar que el ped existe físicamente
        TriggerEvent('qb-clothing:client:loadPlayerClothing', decodedSkin, charPed)
    end
end

-- ==========================================
-- 🚀 EVENTOS DE CONEXIÓN Y SPAWN FINAL
-- ==========================================
-- Hilo principal para detectar la entrada al servidor y abrir el selector
CreateThread(function()
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            DebugPrint("Sesión de red iniciada. Disparando 'chooseChar'.")
            TriggerEvent('DP-MultiCharacter:client:chooseChar')
            return
        end
    end
end)

-- Decodifica un string JSON a tabla si es necesario
local function DecodePosition(position)
    if type(position) == 'string' then
        return json.decode(position)
    end
    return position
end

-- Teletransporta físicamente al jugador al mundo una vez cargado el personaje
RegisterNetEvent('DP-MultiCharacter:client:spawnLastLocation', function(coords, cData)
    DebugPrint("Evento 'spawnLastLocation' disparado. Cargando colisiones del mundo.")
    local ped = PlayerPedId()

    -- 1. Si no hay coordenadas (ej: personaje totalmente nuevo), usamos DefaultSpawn
    -- Verificamos si es tabla, vector3 o vector4 para no romper la lógica
    if not coords or (type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4") or
        not coords.x then
        DebugPrint("Coordenadas inválidas. Usando Spawn por defecto.")
        coords = Config.DefaultSpawn
    end

    -- 2. BLOQUEO DE HIDDENCOORDS: Evita spawnear debajo de la sala de personajes
    local distMenu = #(vector3(coords.x, coords.y, coords.z) -
                         vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z))
    if distMenu < 50.0 then
        DebugPrint("Jugador intentaba spawnear en el menú oculto. Redirigiendo a DefaultSpawn.")
        coords = Config.DefaultSpawn
    end

    -- 3. Congelamos al jugador (incluso si cambió de modelo) y lo movemos
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, coords.x, coords.y, coords.z)

    -- Soporte universal para la rotación (vector4 usa 'w', JSONs suelen usar 'a', 'h' o 'heading')
    local heading = coords.w or coords.h or coords.a or coords.heading or 0.0
    SetEntityHeading(ped, heading + 0.0) -- Se suma 0.0 para forzar que sea un decimal

    -- 4. Pedimos al juego que cargue el suelo en ese punto
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local timeOut = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeOut < 3000 do
        Wait(50)
        timeOut = timeOut + 50
    end

    -- 5. Lo fijamos exactamente al suelo
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, true)

    -- 6. Hacer visible, descongelar y quitar invencibilidad YA SOBRE TIERRA FIRME
    DebugPrint("Terreno cargado. Descongelando al jugador.")
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ClearPedTasksImmediately(ped) -- Limpia animaciones de caída

    -- 7. Carga de eventos de QBCore
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')

    DoScreenFadeIn(1000)
    DebugPrint("Secuencia de spawn completada.")
end)

-- Aplica el modelo, la ropa final y envía al jugador a los eventos de spawn
RegisterNetEvent('DP-MultiCharacter:client:loadSkinAndSpawn', function(model, skinData, cData)
    DebugPrint("Evento 'loadSkinAndSpawn' disparado. Aplicando skin final al ped del jugador.")
    local playerPed = PlayerPedId()

    -- Asegurar que el modelo del jugador sea el correcto (FreeMode u otro personalizado)
    local skinModel = tonumber(model) or joaat(model or Config.DefaultMaleModel)

    RequestModel(skinModel)
    while not HasModelLoaded(skinModel) do
        Wait(10)
    end

    SetPlayerModel(PlayerId(), skinModel)
    SetModelAsNoLongerNeeded(skinModel)

    playerPed = PlayerPedId()

    -- Aplicar la ropa/skin guardada utilizando qb-clothing (o el sistema de ropa que uses)
    if skinData then
        DebugPrint("Datos de skin detectados, enviando a 'qb-clothing:client:loadPlayerClothing'")
        TriggerEvent('qb-clothing:client:loadPlayerClothing', skinData, playerPed)
    end

    -- Una vez aplicada la skin, enviamos al jugador al selector de spawns o su última ubicación
    if Config.SkipSelection then
        DebugPrint("SkipSelection activado. Spawneando directamente en última posición.")
        local coords = DecodePosition(cData.position)
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', coords, cData)
    else
        DebugPrint("SkipSelection desactivado. Abriendo selector de spawn de qb-spawn.")
        TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
        TriggerEvent('qb-spawn:client:openUI', true)
    end
end)

-- ==========================================
-- 🧹 LIMPIEZA AL DETENER/REINICIAR EL RECURSO
-- ==========================================
-- Sin esto, si se reinicia el script mientras el selector está abierto, los peds
-- de los personajes (y la silueta de preview) quedan "sueltos" y se convierten
-- en NPCs que caminan por el mapa.
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    DebugPrint("Deteniendo recurso. Ejecutando rutinas de limpieza (Eliminando cámara, Peds...).")
    DeleteAllPeds()

    if charPed and DoesEntityExist(charPed) then
        DeleteEntity(charPed)
        charPed = nil
    end

    if cam then
        SetCamActive(cam, false)
        DestroyCam(cam, true)
        cam = nil
    end

    -- Por seguridad, devolvemos al jugador a un estado normal si el recurso se detiene con el menú abierto
    DisplayHud(true)
    DisplayRadar(true)
    FreezeEntityPosition(PlayerPedId(), false)
end)
