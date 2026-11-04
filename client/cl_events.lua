local QBCore = exports['qb-core']:GetCoreObject()

local function DebugPrint(msg)
    if Config.Debug or (Config.IntroFlow and Config.IntroFlow.Debug) then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

RegisterNetEvent('DP-MultiCharacter:client:chooseChar', function()
    DoScreenFadeOut(10)
    Wait(1000)

    local interior = GetInteriorAtCoords(Config.Interior.x, Config.Interior.y, Config.Interior.z - 18.9)
    LoadInterior(interior)
    while not IsInteriorReady(interior) do
        Wait(1000)
    end

    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)
    Wait(1500)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    ToggleUI(true)
end)

-- ==========================================
-- 🚪 INTERCEPTOR CLIENT-SIDE DEL LOGOUT
-- ==========================================
RegisterNetEvent('DP-MultiCharacter:client:requestLogout', function()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local health = GetEntityHealth(ped)
    local armor = GetPedArmour(ped)

    -- Le enviamos las coordenadas, la salud y la armadura al servidor
    TriggerServerEvent('DP-MultiCharacter:server:performLogout', pos, heading, health, armor)
end)

local function RequestCharactersAndSpawn()
    QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:setupCharacters',
        function(result, maxSlots, lastCharacter, trashedCount)
            SendNUIMessage({
                action = "setupCharacters",
                characters = result,
                slots = maxSlots,
                lastCharacter = lastCharacter,
                trashedSlots = trashedCount or 0
            })
            SpawnAllPeds(result, maxSlots)
        end)
end

RegisterNUICallback('setupCharacters', function(data, cb)
    RequestCharactersAndSpawn()
    cb("ok")
end)
RegisterNUICallback('previewPed', function(data, cb)
    if data.slot then
        UpdatePedGender(data.slot, data.gender)
    end
    cb("ok")
end)
RegisterNUICallback('deletePreview', function(data, cb)
    cb("ok")
end)

RegisterNUICallback('createCharacter', function(data, cb)
    DebugPrint("NUI createCharacter recibido; iniciando transición al servidor.")
    if not IsScreenFadedOut() then
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    ToggleUI(false)
    DeleteAllPeds()
    TriggerServerEvent('DP-MultiCharacter:server:createCharacter', data)
    cb("ok")
end)

RegisterNUICallback('playCharacter', function(data, cb)
    if not IsScreenFadedOut() then
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do
            Wait(0)
        end
    end

    ToggleUI(false)
    DeleteAllPeds()
    TriggerServerEvent('DP-MultiCharacter:server:loadUserData', data.cData)
    cb("ok")
end)

RegisterNUICallback('deleteCharacter', function(data, cb)
    QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:deleteCharacter', function(success)
        SendNUIMessage({
            action = "characterDeleted",
            success = success,
            citizenid = data.citizenid
        })
        cb("ok")
    end, data.citizenid)
end)

RegisterNUICallback('getDeletedCharacters', function(data, cb)
    QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getDeletedCharacters', function(deletedChars)
        SendNUIMessage({
            action = "deletedCharactersList",
            characters = deletedChars
        })
        cb("ok")
    end)
end)

RegisterNUICallback('restoreCharacter', function(data, cb)
    if data and data.citizenid then
        TriggerServerEvent('DP-MultiCharacter:server:restoreCharacter', data.citizenid)
    end
    cb("ok")
end)

local HIDE_LOCKED_KVP = 'DP_MC_hideLocked'
local hideLockedPref = false

CreateThread(function()
    Wait(0)
    hideLockedPref = GetResourceKvpInt(HIDE_LOCKED_KVP, 0) == 1
end)

function GetHideLockedPreference()
    return hideLockedPref
end
function SetHideLockedPreference(value)
    hideLockedPref = value and true or false
    SetResourceKvpInt(HIDE_LOCKED_KVP, hideLockedPref and 1 or 0)
end

RegisterNUICallback('setHideLocked', function(data, cb)
    SetHideLockedPreference(data.hideLocked == true or data.hideLocked == 'true')
    RequestCharactersAndSpawn()
    cb("ok")
end)

RegisterNUICallback('getInterfaceVolume', function(data, cb)
    QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:getInterfaceVolume', function(volume)
        cb(volume)
    end)
end)

RegisterNUICallback('setInterfaceVolume', function(data, cb)
    TriggerServerEvent('DP-MultiCharacter:server:setInterfaceVolume', tonumber(data.volume) or 100)
    cb("ok")
end)

RegisterNUICallback('openSettings', function(data, cb)
    QBCore.Functions.Notify("Menú de opciones próximamente disponible", "primary")
    cb("ok")
end)
RegisterNUICallback('focusCharacter', function(data, cb)
    FocusCharacter(data.slot)
    cb("ok")
end)
RegisterNUICallback('unfocusCharacter', function(data, cb)
    UnfocusCharacter()
    cb("ok")
end)
RegisterNUICallback('reorderCharacters', function(data, cb)
    if data and data.order then
        TriggerServerEvent('DP-MultiCharacter:server:reorderCharacters', data.order)
    end
    cb("ok")
end)

RegisterNetEvent('DP-MultiCharacter:client:reorderDone', function()
    SendNUIMessage({
        action = "reorderDone"
    })
end)

-- El personaje ya existe en la BD, ahora toca elegir spawn antes de la ropa.
RegisterNetEvent('DP-MultiCharacter:client:startSpawnSelection', function()
    DebugPrint("startSpawnSelection recibido. Preparando selector de spawn para personaje nuevo.")

    local QBCore = exports['qb-core']:GetCoreObject()
    QBCore.Functions.GetPlayerData(function(cData)
        if not cData or not cData.citizenid then
            DebugPrint("ADVERTENCIA: cData nulo al iniciar selector de spawn.")
            return
        end

        pendingCData = cData
        isNewCharacterFlow = true
        ToggleUI(false)
        DeleteAllPeds()
        SetupCamera(false)
        if Config.IntroFlow and Config.IntroFlow.Enabled then
            DebugPrint(("Personaje %s creado; solicitando inicio de intro."):format(tostring(cData.citizenid)))
            TriggerServerEvent('DP-MultiCharacter:server:startIntro')
            return
        end

        -- Ocultamos cualquier UI residual (la landing ya se ocultó al pulsar CREAR)
        ToggleUI(false)
        DeleteAllPeds()

        if Config.SpawnPoints.SkipSelection then
            -- Si SkipSelection está activo, va directo al spawn por defecto y luego abre ropa
            local coords = Config.SpawnPoints.DefaultSpawn
            TriggerEvent('DP-MultiCharacter:client:spawnLastLocation', coords, cData)
            Wait(1000)
            TriggerEvent('DP-MultiCharacter:client:openClothing')
        else
            -- Delegamos en openSpawnUI (que abre el mapa de DP-PauseMenu)
            pendingCData = cData
            isNewCharacterFlow = true
            TriggerEvent('DP-MultiCharacter:client:openSpawnUI')
        end
    end)
end)

RegisterNetEvent('DP-MultiCharacter:client:resumeIntro', function(cData)
    if not cData or not cData.citizenid then
        return
    end
    pendingCData = cData
    isNewCharacterFlow = true
    TriggerServerEvent('DP-MultiCharacter:server:resumeIntro')
end)
