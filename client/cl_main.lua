local QBCore = exports['qb-core']:GetCoreObject()
local cam = nil
local charPeds = {}
local activePedCoords = {}

local randomSlotGenders = {}
CreateThread(function()
    Wait(200)
    math.randomseed(GetGameTimer())
    for i = 1, 10 do
        randomSlotGenders[tostring(i)] = math.random(0, 1)
    end
end)

local function DebugPrint(msg)
    if Config.Debug or (Config.IntroFlow and Config.IntroFlow.Debug) then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

local function SetPedNaked(ped, model)
    if model == joaat(Config.DefaultMaleModel) then
        SetPedComponentVariation(ped, 3, 15, 0, 0)
        SetPedComponentVariation(ped, 4, 14, 0, 0)
        SetPedComponentVariation(ped, 6, 34, 0, 0)
        SetPedComponentVariation(ped, 8, 15, 0, 0)
        SetPedComponentVariation(ped, 11, 15, 0, 0)
    elseif model == joaat(Config.DefaultFemaleModel) then
        SetPedComponentVariation(ped, 3, 15, 0, 0)
        SetPedComponentVariation(ped, 4, 15, 0, 0)
        SetPedComponentVariation(ped, 6, 35, 0, 0)
        SetPedComponentVariation(ped, 8, 15, 0, 0)
        SetPedComponentVariation(ped, 11, 15, 0, 0)
    end
end

function ToggleUI(state)
    SetNuiFocus(state, state)
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
        startingItems = Config.StartItemsList or {},
        startingBudget = startingBank
    })

    if state then
        QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getInterfaceVolume', function(volume)
            SendNUIMessage({
                action = "toggleUI",
                state = true,
                interfaceVolume = volume or 100
            })
        end)
        TriggerEvent('chat:clear')
        TriggerEvent('chat:client:showChat', false)
        TriggerServerEvent('DP-MultiCharacter:server:SetBucket', GetPlayerServerId(PlayerId()))
    else
        TriggerEvent('chat:client:showChat', true)
        TriggerServerEvent('DP-MultiCharacter:server:SetBucket', 0)
    end
    SetupCamera(state)
end

function SetupCamera(state)
    if state then
        DoScreenFadeIn(1000)
        FreezeEntityPosition(PlayerPedId(), true)
        SetEntityInvincible(PlayerPedId(), true)
        DisplayHud(false)
        DisplayRadar(false)

        cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", Config.CamCoords.x, Config.CamCoords.y, Config.CamCoords.z,
            0.0, 0.0, Config.CamCoords.w, 60.00, false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 1, true, true)

        CreateThread(function()
            while cam and DoesCamExist(cam) and IsCamActive(cam) do
                SetVehicleDensityMultiplierThisFrame(0.0)
                SetPedDensityMultiplierThisFrame(0.0)
                SetRandomVehicleDensityMultiplierThisFrame(0.0)
                SetParkedVehicleDensityMultiplierThisFrame(0.0)
                SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
                Wait(0)
            end
        end)
    else
        if not IsScreenFadedOut() then
            DoScreenFadeOut(300)
            while not IsScreenFadedOut() do
                Wait(0)
            end
        end

        DisplayHud(true)
        DisplayRadar(true)
        if cam then
            SetCamActive(cam, false)
            DestroyCam(cam, true)
            cam = nil
        end
        RenderScriptCams(false, false, 1, true, true)
    end
end

function UpdatePedGender(slot, gender)
    if not charPeds[slot] or not charPeds[slot].isShadow then
        return
    end
    local model = joaat(Config.DefaultMaleModel)
    if gender == "Femenino" or gender == 1 or gender == "1" then
        model = joaat(Config.DefaultFemaleModel)
    end

    local thisSequence = currentSpawnSequence
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 500 do
        Wait(10)
        timeout = timeout + 1
    end
    if thisSequence ~= currentSpawnSequence then
        return
    end

    local coords = activePedCoords[slot] or Config.PedCoords[slot] or Config.PedCoords[1]
    if charPeds[slot].entity and DoesEntityExist(charPeds[slot].entity) then
        DeleteEntity(charPeds[slot].entity)
    end

    local ped = CreatePed(2, model, coords.x, coords.y, coords.z - 0.98, coords.w, false, true)
    SetPedComponentVariation(ped, 0, 0, 0, 2)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityAlpha(ped, 150, false)
    SetPedNaked(ped, model)
    charPeds[slot].entity = ped
end

local currentSpawnSequence = 0

local function ClearZombiePeds()
    local peds = GetGamePool('CPed')
    for i = 1, #peds do
        local ped = peds[i]
        if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local coords = GetEntityCoords(ped)
            if #(coords - vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)) < 20.0 then
                DeleteEntity(ped)
            end
        end
    end
end

local lastFocusedSlot = nil

function FocusCharacter(slot)
    if not charPeds[slot] then
        return
    end
    lastFocusedSlot = slot

    if charPeds[slot].isShadow then
        SetEntityAlpha(charPeds[slot].entity, 150, false)
    else
        ResetEntityAlpha(charPeds[slot].entity)
    end

    local targetCoords = activePedCoords[slot] or Config.PedCoords[slot] or Config.PedCoords[1]
    local zoomX = targetCoords.x + 1.8
    local zoomY = targetCoords.y
    local zoomZ = targetCoords.z + 0.35

    local camDuration = 800
    SetCamParams(cam, zoomX, zoomY, zoomZ, 0.0, 0.0, 90.0, 50.0, camDuration, 1, 1, 2)

    CreateThread(function()
        Wait(camDuration)
        if lastFocusedSlot ~= slot then
            return
        end
        for k, data in pairs(charPeds) do
            if k ~= slot then
                SetEntityAlpha(data.entity, 0, false)
            end
        end
    end)
end

function UnfocusCharacter()
    lastFocusedSlot = nil
    for k, data in pairs(charPeds) do
        if data.isShadow then
            SetEntityAlpha(data.entity, 150, false)
        else
            ResetEntityAlpha(data.entity)
        end
    end
    SetCamParams(cam, Config.CamCoords.x, Config.CamCoords.y, Config.CamCoords.z, 0.0, 0.0, Config.CamCoords.w, 60.0,
        800, 1, 1, 2)
end

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

function SpawnAllPeds(characters, maxSlots)
    currentSpawnSequence = currentSpawnSequence + 1
    local thisSequence = currentSpawnSequence
    DeleteAllPeds()
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

function DeleteAllPeds()
    lastFocusedSlot = nil
    for _, data in pairs(charPeds) do
        if data and data.entity and DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    charPeds = {}
end

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
    if sequenceId and sequenceId ~= currentSpawnSequence then
        return
    end

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
end

CreateThread(function()
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            TriggerEvent('DP-MultiCharacter:client:chooseChar')
            return
        end
    end
end)

local function DecodePosition(position)
    if type(position) == 'string' then
        return json.decode(position)
    end
    return position
end

-- =====================================================================
-- 🧱 ZONAS PESADAS (MLOs/mapeados que llenan el pool MapDataLoadedNode)
-- =====================================================================
-- "Pool Full, Size == 1100" es un límite de ENTRADAS de map data cargadas a la vez.
-- Aparecer de golpe en una zona con muchos MLO/ymap lo desborda; llegar poco a poco
-- (como con noclip) deja que el streaming cargue y descargue gradualmente.
-- Se puede sobrescribir en config.lua con Config.SpawnPoints.HeavyZones.
local function GetHeavyZones()
    return Config.SpawnPoints.HeavyZones or {{
        name = "mrpd",
        center = vector3(415.77, -970.74, 29.45),
        radius = 300.0
    }}
end

local function FindHeavyZone(x, y)
    for _, zone in ipairs(GetHeavyZones()) do
        local d = #(vector2(x, y) - vector2(zone.center.x, zone.center.y))
        if d <= (zone.radius or 300.0) then
            return zone
        end
    end
    return nil
end

-- Libera la sala oculta del multicharacter para no arrastrar sus nodos de map data.
local function ReleaseHiddenRoom()
    local interior = GetInteriorAtCoords(Config.Interior.x, Config.Interior.y, Config.Interior.z - 18.9)
    if interior ~= 0 then
        UnpinInterior(interior)
    end
end

-- Mueve al ped (oculto y congelado) desde un punto de partida hasta el destino en
-- pasos pequeños, simulando que el jugador llega andando.
local function StagedApproach(ped, zone, x, y, z)
    local sp = Config.SpawnPoints
    local stepMeters = sp.ApproachStep or 12.0
    local stepWait = sp.ApproachWait or 250
    local stageDist = sp.ApproachDistance or 350.0

    local sx, sy, sz
    if zone.stage then
        sx, sy, sz = zone.stage.x, zone.stage.y, zone.stage.z or z
    else
        sx, sy, sz = x, y - stageDist, z
    end

    local total = #(vector2(x, y) - vector2(sx, sy))
    local steps = math.max(1, math.ceil(total / stepMeters))
    DebugPrint(("Aproximación escalonada: %d pasos desde %.1f %.1f hasta %.1f %.1f."):format(steps, sx, sy, x, y))

    SetEntityCoordsNoOffset(ped, sx, sy, sz + 30.0, false, false, false, true)
    RequestCollisionAtCoord(sx, sy, sz)
    Wait(stepWait * 4)

    for i = 1, steps do
        local f = i / steps
        local cx = sx + (x - sx) * f
        local cy = sy + (y - sy) * f
        local cz = sz + (z - sz) * f
        SetEntityCoordsNoOffset(ped, cx, cy, cz + 30.0, false, false, false, true)
        RequestCollisionAtCoord(cx, cy, cz)
        Wait(stepWait)
    end
end

-- Spawnea en el destino mientras mantiene al jugador oculto durante la carga de colisiones.
RegisterNetEvent('DP-MultiCharacter:client:spawnLastLocation', function(coords, cData)
    local ped = PlayerPedId()

    -- Validate saved coordinates before using them in streaming natives.
    if not coords or (type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4") then
        coords = Config.SpawnPoints.DefaultSpawn
    end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 10000 or math.abs(y) > 10000 or z < -200 or
        z > 2000 then
        DebugPrint(("Coordenadas de spawn inválidas (%s, %s, %s); usando el spawn por defecto."):format(tostring(
            coords.x), tostring(coords.y), tostring(coords.z)))
        coords = Config.SpawnPoints.DefaultSpawn
        x, y, z = coords.x, coords.y, coords.z
    end

    local distMenu = #(vector2(x, y) - vector2(Config.HiddenCoords.x, Config.HiddenCoords.y))

    if distMenu < 5.0 then
        coords = Config.SpawnPoints.DefaultSpawn
        x, y, z = coords.x, coords.y, coords.z
    end
    local heading = tonumber(coords.w or coords.h or coords.a or coords.heading) or 0.0
    DebugPrint(("spawnLastLocation: destino %.2f %.2f %.2f (heading %.2f)."):format(x, y, z, heading))

    if not IsScreenFadedOut() then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    -- 🛑 PROTEGER PED
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    -- Soltamos la sala oculta antes de cargar el mundo real.
    ReleaseHiddenRoom()
    Wait(500)

    -- Zonas pesadas: nunca aparecemos de golpe en ellas.
    local zone = FindHeavyZone(x, y)
    if zone then
        if Config.SpawnPoints.HeavyZoneMode == "safe" and zone.safe then
            -- Modo seguro: aparece en un punto ligero y el jugador camina el resto.
            DebugPrint(("Zona pesada '%s': usando punto seguro."):format(tostring(zone.name)))
            x, y, z = zone.safe.x, zone.safe.y, zone.safe.z
            heading = tonumber(zone.safe.w) or heading
        else
            DebugPrint(("Zona pesada '%s': aproximación escalonada."):format(tostring(zone.name)))
            StagedApproach(ped, zone, x, y, z)
        end
    end

    -- Colocación final (+ interior si lo hay)
    SetEntityCoordsNoOffset(ped, x, y, z + 1.0, false, false, false, true)
    SetEntityHeading(ped, heading + 0.0)
    RequestCollisionAtCoord(x, y, z)

    local interior = GetInteriorAtCoords(x, y, z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local t0 = GetGameTimer()
        while not IsInteriorReady(interior) and GetGameTimer() - t0 < 8000 do
            Wait(100)
        end
    end

    local timeOut = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeOut < 8000 do
        RequestCollisionAtCoord(x, y, z)
        Wait(100)
        timeOut = timeOut + 100
    end

    if timeOut >= 8000 then
        DebugPrint(("Colisiones no cargaron en 8 s para %.2f %.2f %.2f; se mantiene el spawn solicitado."):format(x, y,
            z))
    end

    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    SetEntityHeading(ped, heading + 0.0)

    -- 🛑 RESTAURAR PED
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    ClearPedTasksImmediately(ped)

    -- 🛑 APLICAR SALUD Y ARMADURA
    local isFirstSpawn = isNewCharacterFlow or (cData and cData.metadata and cData.metadata.introDone == false)
    if isFirstSpawn then
        local maxHealth = GetEntityMaxHealth(ped)
        SetEntityHealth(ped, maxHealth)
        SetPedArmour(ped, 100)
    elseif cData and cData.metadata then
        local savedHealth = cData.metadata.health or 200
        local savedArmor = cData.metadata.armor or 0
        SetEntityHealth(ped, savedHealth)
        SetPedArmour(ped, savedArmor)
    end

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')

    -- Dejamos que el streaming se asiente antes de enseñar el mundo.
    Wait(1500)
    DoScreenFadeIn(1000)

    -- Ya no hace falta mantener el interior fijado en memoria.
    if interior ~= 0 then
        Wait(3000)
        UnpinInterior(interior)
    end
end)

RegisterNetEvent('DP-MultiCharacter:client:loadSkinAndSpawn', function(model, skinData, cData)
    local playerPed = PlayerPedId()
    local skinModel = tonumber(model) or joaat(model or Config.DefaultMaleModel)

    RequestModel(skinModel)
    while not HasModelLoaded(skinModel) do
        Wait(10)
    end
    SetPlayerModel(PlayerId(), skinModel)
    SetModelAsNoLongerNeeded(skinModel)

    playerPed = PlayerPedId()
    if skinData then
        TriggerEvent('qb-clothing:client:loadPlayerClothing', skinData, playerPed)
    end

    if Config.IntroFlow and Config.IntroFlow.Enabled and cData.metadata and cData.metadata.introDone == false then
        pendingCData = cData
        isNewCharacterFlow = true
        TriggerServerEvent('DP-MultiCharacter:server:resumeIntro')
        return
    end

    local coords = DecodePosition(cData.position)
    if not coords or not coords.x then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    local distMenu2D = #(vector2(coords.x, coords.y) - vector2(Config.HiddenCoords.x, Config.HiddenCoords.y))

    if distMenu2D < 50.0 or coords.z < -50.0 then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    if Config.SpawnPoints.SkipSelection then
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', coords, cData)
    else
        pendingCData = cData
        isNewCharacterFlow = false
        TriggerEvent('DP-MultiCharacter:client:openSpawnUI')
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
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
    DisplayHud(true)
    DisplayRadar(true)
    FreezeEntityPosition(PlayerPedId(), false)
end)
