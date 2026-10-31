local QBCore = exports['qb-core']:GetCoreObject()

local function DebugPrint(msg)
    if Config.Debug then
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

    SetEntityCoords(PlayerPedId(), Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)
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

    print("^3[DEBUG POSICION] El servidor pidió logout. Mis coordenadas físicas justo ahora son: " .. tostring(pos) ..
              "^7")

    -- Le enviamos las coordenadas seguras al servidor para que las guarde ANTES de mandarnos a chooseChar
    TriggerServerEvent('DP-MultiCharacter:server:performLogout', pos, heading)
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
    ToggleUI(false)
    DeleteAllPeds()
    TriggerServerEvent('DP-MultiCharacter:server:createCharacter', data)
    cb("ok")
end)

RegisterNUICallback('playCharacter', function(data, cb)
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
