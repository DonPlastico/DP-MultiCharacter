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
    if Config.Debug then
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
        DoScreenFadeOut(500)
        Wait(500)
        DisplayHud(true)
        DisplayRadar(true)
        SetCamActive(cam, false)
        DestroyCam(cam, true)
        RenderScriptCams(false, false, 1, true, true)
        Wait(500)
        DoScreenFadeIn(1000)
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

-- Teletransporta físicamente al jugador al mundo asegurando el suelo
RegisterNetEvent('DP-MultiCharacter:client:spawnLastLocation', function(coords, cData)
    local ped = PlayerPedId()

    -- Validación estricta de tipos (table, vector3, vector4)
    if not coords or (type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4") or
        not coords.x then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    local distMenu = #(vector3(coords.x, coords.y, coords.z) -
                         vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z))
    if distMenu < 50.0 then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    DoScreenFadeOut(500)
    Wait(500)

    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)

    local heading = coords.w or coords.h or coords.a or coords.heading or 0.0
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1.0)
    SetEntityHeading(ped, heading + 0.0)

    -- FORZAMOS LA CARGA DEL MAPA ANTES DE SOLTAR AL JUGADOR
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    NewLoadSceneStart(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, 50.0, 0)

    local timeOut = 0
    while not IsNewLoadSceneLoaded() and timeOut < 5000 do
        Wait(50)
        timeOut = timeOut + 50
    end

    timeOut = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeOut < 5000 do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
        timeOut = timeOut + 50
    end

    NewLoadSceneStop()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false, true)

    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ClearPedTasksImmediately(ped)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')

    Wait(1000)
    DoScreenFadeIn(1000)
end)

-- Aplica el modelo y envía al jugador a los eventos de spawn
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

    local coords = DecodePosition(cData.position)
    if not coords or (type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4") or
        not coords.x then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    local distMenu = #(vector3(coords.x, coords.y, coords.z) -
                         vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z))
    if distMenu < 50.0 then
        coords = Config.SpawnPoints.DefaultSpawn
    end

    if Config.SpawnPoints.SkipSelection then
        TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', coords, cData)
    else
        -- PRE-TELEPORTE: Movemos al jugador congelado a su destino real para la cámara
        FreezeEntityPosition(playerPed, true)
        SetEntityVisible(playerPed, false, false)
        SetEntityCoords(playerPed, coords.x, coords.y, coords.z)

        TriggerEvent('DP-MultiCharacter:client:setupSpawns', cData, false, nil)
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
