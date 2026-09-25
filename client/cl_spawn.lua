local QBCore = exports['qb-core']:GetCoreObject()

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter:Spawn Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🎥 CÁMARA INDEPENDIENTE DEL SELECTOR DE SPAWN
-- ==========================================
-- Cámara propia y separada de la del selector de personajes (esta se abre DESPUÉS,
-- cuando el jugador ya está listo para entrar al mundo, tal y como hacía qb-spawn
-- con sus propias variables 'cam'/'cam2').
local spawnCam = nil
local spawnCam2 = nil
local choosingSpawn = false
local currentHouses = {} -- Casas del jugador cacheadas para esta sesión de selección
local currentApartments = {} -- Apartamentos disponibles (solo en modo creación de personaje)
local pendingCData = nil -- Datos del personaje que se está a punto de spawnear
local isNewCharacterFlow = false -- true = viene de crear personaje nuevo (permite apartamentos)

-- Misma proporción de altura/ángulo que usaba qb-spawn originalmente
local CAM_HIGH_Z = 1500
local CAM_CLOSE_Z = 50
local CAM_POINT_AT_HIGH = 75
local CAM_POINT_AT_CLOSE = 0
local CAM_TRANSITION_1 = 500
local CAM_TRANSITION_2 = 1000

-- ==========================================
-- 🖥️ MOSTRAR / OCULTAR LA UI DEL SELECTOR
-- ==========================================
local function SetSpawnUIDisplay(visible)
    choosingSpawn = visible
    SetNuiFocus(visible, visible)
    SendNUIMessage({
        action = 'spawnToggleUI',
        status = visible,
        translations = GetTranslations()
    })
end

-- Cámara general alta, apuntando hacia la posición actual del jugador (vista de conjunto)
local function OpenSpawnCamera()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)

    SetEntityVisible(ped, false, false)
    DoScreenFadeOut(250)
    Wait(1000)
    DoScreenFadeIn(250)

    spawnCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z + CAM_HIGH_Z, -85.0, 0.0, 0.0, 100.0,
        false, 0)
    SetCamActive(spawnCam, true)
    RenderScriptCams(true, false, 1, true, true)
end

-- Mueve la cámara con interpolación de 2 fases hacia unas coordenadas concretas
-- (misma lógica que el SetCam original de qb-spawn: primero un plano alto, luego uno cercano)
local function MoveSpawnCameraTo(coords)
    if DoesCamExist(spawnCam2) then
        DestroyCam(spawnCam2, true)
    end

    spawnCam2 = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z + CAM_HIGH_Z, 300.0, 0.0,
        0.0, 110.0, false, 0)
    PointCamAtCoord(spawnCam2, coords.x, coords.y, coords.z + CAM_POINT_AT_HIGH)
    SetCamActiveWithInterp(spawnCam2, spawnCam, CAM_TRANSITION_1, true, true)
    if DoesCamExist(spawnCam) then
        DestroyCam(spawnCam, true)
    end
    Wait(CAM_TRANSITION_1)

    spawnCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z + CAM_CLOSE_Z, 300.0, 0.0,
        0.0, 110.0, false, 0)
    PointCamAtCoord(spawnCam, coords.x, coords.y, coords.z + CAM_POINT_AT_CLOSE)
    SetCamActiveWithInterp(spawnCam, spawnCam2, CAM_TRANSITION_2, true, true)
end

local function DestroySpawnCameras()
    if DoesCamExist(spawnCam) then
        SetCamActive(spawnCam, false)
        DestroyCam(spawnCam, true)
        spawnCam = nil
    end
    if DoesCamExist(spawnCam2) then
        SetCamActive(spawnCam2, false)
        DestroyCam(spawnCam2, true)
        spawnCam2 = nil
    end
    RenderScriptCams(false, true, 500, true, true)
end

-- ==========================================
-- 🧍 PRE/POST SPAWN (fundido de pantalla + limpieza de cámara)
-- ==========================================
local function PreSpawnPlayer()
    SetSpawnUIDisplay(false)
    DoScreenFadeOut(500)
    Wait(1500)
end

local function PostSpawnPlayer()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    DestroySpawnCameras()
    SetEntityVisible(ped, true, false)
    Wait(500)
    DoScreenFadeIn(250)
end

-- ==========================================
-- 🚪 PUNTO DE ENTRADA: abrir el selector de spawn
-- ==========================================
-- newCharacter: true si viene de crear un personaje nuevo (habilita apartamentos)
-- apartments: lista de apartamentos disponibles a ofrecer (solo si newCharacter y Config lo permite)
RegisterNetEvent('DP-MultiCharacter:client:setupSpawns', function(cData, newCharacter, apartments)
    DebugPrint("setupSpawns recibido. Personaje nuevo: " .. tostring(newCharacter))
    pendingCData = cData
    isNewCharacterFlow = newCharacter or false
    currentApartments = apartments or {}

    if newCharacter and Config.SpawnPoints.EnableApartments then
        SendNUIMessage({
            action = 'spawnSetupApartments',
            locations = currentApartments,
            isNew = true
        })
    else
        -- Pedimos las casas propias al servidor (si la integración está activa)
        if Config.SpawnPoints.EnableHouses then
            QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getOwnedHouses', function(houses)
                currentHouses = houses or {}
                SendNUIMessage({
                    action = 'spawnSetupLocations',
                    locations = Config.SpawnPoints,
                    houses = currentHouses,
                    enableLastLocation = Config.SpawnPoints.EnableLastLocation and not newCharacter,
                    isNew = newCharacter or false
                })
            end, cData.citizenid)
        else
            currentHouses = {}
            SendNUIMessage({
                action = 'spawnSetupLocations',
                locations = Config.SpawnPoints,
                houses = {},
                enableLastLocation = Config.SpawnPoints.EnableLastLocation and not newCharacter,
                isNew = newCharacter or false
            })
        end
    end
end)

RegisterNetEvent('DP-MultiCharacter:client:openSpawnUI', function()
    DebugPrint("openSpawnUI recibido. Abriendo cámara y UI del selector.")
    OpenSpawnCamera()
    Wait(500)
    SetSpawnUIDisplay(true)
end)

-- ==========================================
-- 🔌 NUI CALLBACKS
-- ==========================================
RegisterNUICallback('spawnExit', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'spawnToggleUI',
        status = false
    })
    choosingSpawn = false
    cb('ok')
end)

-- El jugador pasa el cursor/selecciona una tarjeta: movemos la cámara hacia ese punto
-- SIN spawnear todavía (igual que el 'setCam' del qb-spawn original)
RegisterNUICallback('spawnPreviewLocation', function(data, cb)
    local locType = tostring(data.type)
    local locId = tostring(data.id)
    DebugPrint("Previsualizando cámara para tipo=" .. locType .. " id=" .. locId)

    DoScreenFadeOut(200)
    Wait(500)
    DoScreenFadeIn(200)

    if locType == 'current' then
        local pos = GetEntityCoords(PlayerPedId())
        MoveSpawnCameraTo(pos)
    elseif locType == 'house' then
        local house = currentHouses[tonumber(locId)]
        if house and house.coords then
            MoveSpawnCameraTo(house.coords.enter or house.coords)
        end
    elseif locType == 'apartment' then
        -- locId es la clave string del tipo de apartamento (ej. "luxury_apartment"),
        -- igual que en Apartments.Locations, no un índice numérico.
        local apt = currentApartments[locId]
        if apt and apt.coords then
            MoveSpawnCameraTo(apt.coords.enter or apt.coords)
        end
    else
        -- Punto fijo de Config.SpawnPoints (índice numérico dentro de la tabla)
        local point = Config.SpawnPoints[tonumber(locId)]
        if point and point.coords then
            MoveSpawnCameraTo(point.coords)
        end
    end

    cb('ok')
end)

-- Confirmación final: el jugador elige "Empezar aquí"
RegisterNUICallback('spawnConfirm', function(data, cb)
    local locType = tostring(data.type)
    local locId = tostring(data.id)
    local ped = PlayerPedId()
    DebugPrint("Confirmando spawn. Tipo=" .. locType .. " id=" .. locId)

    if locType == 'apartment' then
        -- Los apartamentos siguen gestionándose por qb-apartments (recurso externo);
        -- DP-MultiCharacter solo deja de depender de qb-spawn como intermediario.
        -- IMPORTANTE: apartments:server:CreateApartment(type, label, firstSpawn) espera
        -- el TIPO del apartamento (la clave string dentro de Apartments.Locations, ej.
        -- "luxury_apartment"), NO un índice numérico. 'locId' aquí es esa misma clave,
        -- tal como llega en Apartments.Locations al NUI (ver spawnSetupApartments).
        local apt = currentApartments[locId]
        PreSpawnPlayer()
        Wait(3500)
        TriggerServerEvent('apartments:server:CreateApartment', locId, apt and apt.label or nil, true)
        TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
        TriggerEvent('QBCore:Client:OnPlayerLoaded')
        PostSpawnPlayer()
        cb('ok')
        return
    end

    PreSpawnPlayer()

    if locType == 'current' then
        local pos = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        SetEntityCoords(ped, pos.x, pos.y, pos.z)
        SetEntityHeading(ped, heading)
    elseif locType == 'house' then
        local house = currentHouses[tonumber(locId)]
        -- Delegamos en qb-houses (recurso externo) para que gestione la entrada
        -- correctamente (blips, interiores, meta de "dentro de casa", etc.)
        if house and house.house then
            TriggerEvent('qb-houses:client:enterOwnedHouse', house.house)
        end
        TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
        TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)
    else
        local point = Config.SpawnPoints[tonumber(locId)]
        if point and point.coords then
            local c = point.coords
            SetEntityCoords(ped, c.x, c.y, c.z)
            SetEntityHeading(ped, c.w or 0.0)
        end
        TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
        TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)
    end

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    PostSpawnPlayer()
    
    if locType ~= 'apartment' and isNewCharacterFlow then
        Wait(1000)
        TriggerEvent('qb-clothing:client:CreateFirstCharacter')
    end
    
    cb('ok')
end)

-- ==========================================
-- 🚫 BLOQUEO DE CONTROLES MIENTRAS EL SELECTOR ESTÁ ABIERTO
-- ==========================================
CreateThread(function()
    while true do
        if choosingSpawn then
            DisableAllControlActions(0)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- ==========================================
-- 🧹 LIMPIEZA AL DETENER/REINICIAR EL RECURSO
-- ==========================================
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    DestroySpawnCameras()
    DisplayHud(true)
    DisplayRadar(true)
    FreezeEntityPosition(PlayerPedId(), false)
end)
