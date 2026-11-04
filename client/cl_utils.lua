local QBCore = exports['qb-core']:GetCoreObject()

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🔧 UTILIDADES DEL CLIENTE
-- ==========================================
function SendNotify(msg, type)
    DebugPrint("Enviando notificación al jugador: " .. tostring(msg) .. " | Tipo: " .. tostring(type))
    QBCore.Functions.Notify(msg, type)
end

RegisterNetEvent('DP-MultiCharacter:client:openClothing', function()
    DebugPrint("Evento 'openClothing' disparado. Abriendo menú de creación de personaje inicial.")
    TriggerEvent('qb-clothing:client:CreateFirstCharacter')
end)

-- ==========================================
-- 🔗 ENLACE DE COMPATIBILIDAD CON ROPA Y SPAWN
-- ==========================================
RegisterNetEvent('qb-multicharacter:client:chooseSpawn', function()
    DebugPrint("qb-clothing ha terminado. Iniciando secuencia final de spawn...")

    if IsMultiCharacterIntroActive and IsMultiCharacterIntroActive() then
        TriggerEvent('DP-MultiCharacter:client:tailorFinished')
        return
    end

    Wait(500)

    QBCore.Functions.GetPlayerData(function(cData)
        if not cData or not cData.citizenid then
            DebugPrint("ADVERTENCIA: cData nulo o sin citizenid al salir de la ropa.")
            return
        end

        if Config.SpawnPoints.SkipSelection then
            -- Flujo directo
            local coords = Config.SpawnPoints.DefaultSpawn
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
            SetEntityHeading(PlayerPedId(), coords.w)
            SetEntityVisible(PlayerPedId(), true, false)
            FreezeEntityPosition(PlayerPedId(), false)

            TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
            TriggerEvent('QBCore:Client:OnPlayerLoaded')
            TriggerEvent('DP-Inventory:client:updateInventory')
        else
            -- Personaje nuevo: ya pasó por el mapa ANTES de abrir la ropa, así que
            -- aquí ya está en el mundo. Solo sincronizamos.
            SetEntityVisible(PlayerPedId(), true, false)
            FreezeEntityPosition(PlayerPedId(), false)

            TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
            TriggerEvent('QBCore:Client:OnPlayerLoaded')
            TriggerEvent('DP-Inventory:client:updateInventory')
        end
    end)
end)

RegisterNetEvent('qb-clothing:client:firstCharacterSaved', function()
    if not (IsMultiCharacterIntroActive and IsMultiCharacterIntroActive()) then
        return
    end

    DebugPrint("qb-clothing confirmó la primera apariencia. Continuando la intro.")
    TriggerEvent('DP-MultiCharacter:client:tailorFinished')
end)
