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

    -- 1. Obligamos al juego a esperar medio segundo para que QBCore termine
    -- de guardar la ropa recién creada en la base de datos sin atragantarse.
    Wait(500)

    -- 2. Recargamos forzosamente los datos del jugador para asegurarnos
    -- de que el cliente tiene el citizenid y todo lo demás actualizado.
    QBCore.Functions.GetPlayerData(function(cData)
        if not cData or not cData.citizenid then
            DebugPrint("ADVERTENCIA: cData nulo o sin citizenid al salir de la ropa. Reintentando...")
            Wait(500)
            cData = QBCore.Functions.GetPlayerData()
        end

        if Config.SpawnPoints.SkipSelection then
            DebugPrint("SkipSelection activado. Mandando al spawn por defecto.")
            local coords = Config.DefaultSpawn

            -- Aseguramos posición física
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
            SetEntityHeading(PlayerPedId(), coords.w)
            SetEntityVisible(PlayerPedId(), true, false)
            FreezeEntityPosition(PlayerPedId(), false)

            -- 3. EL DESPERTAR: Forzamos la secuencia de inicio de sesión de QBCore
            -- Esto es crucial: le decimos al servidor "Oye, ya estoy en el suelo, 
            -- cárgame las llaves, el inventario, los trabajos..."
            TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
            TriggerEvent('QBCore:Client:OnPlayerLoaded')

            -- 4. Un último toque de seguridad para despertar el inventario
            TriggerEvent('DP-Inventory:client:updateInventory')
        else
            DebugPrint("Abriendo el selector de spawn propio de DP-MultiCharacter (personaje nuevo).")
            -- Se mantiene el paso por qb-apartments (recurso externo) como intermediario:
            -- es quien decide si el jugador ya tiene apartamento o si hay que ofrecerle
            -- elegir uno de los disponibles (Apartments.Starting). Solo cambiamos a qué
            -- eventos finales apunta (los propios de DP-MultiCharacter en vez de qb-spawn).
            if GetResourceState('qb-apartments') == 'started' then
                TriggerEvent('apartments:client:setupSpawnUI', cData)
            else
                -- Sin qb-apartments instalado: abrimos directamente el selector propio,
                -- sin ofrecer apartamentos (solo puntos fijos / casas / última ubicación).
                TriggerEvent('DP-MultiCharacter:client:setupSpawns', cData, true, nil)
                TriggerEvent('DP-MultiCharacter:client:openSpawnUI')
            end
        end
    end)
end)
