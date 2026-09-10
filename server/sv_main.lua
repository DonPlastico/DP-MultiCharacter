local QBCore = exports['qb-core']:GetCoreObject()
local hasDonePreloading = {}

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- ⚙️ LÓGICA CORE DEL SERVIDOR
-- ==========================================
-- Mantenemos el nombre original del evento para asegurar compatibilidad con DP-RealMoney y otros scripts
-- Este evento se dispara cuando el usuario selecciona un personaje existente para entrar a jugar
RegisterNetEvent('DP-MultiCharacter:server:loadUserData', function(cData)
    local src = source
    DebugPrint("Evento 'loadUserData' disparado para iniciar sesión. CitizenID: " .. tostring(cData.citizenid))

    -- 1. Intentamos iniciar sesión en QBCore con el citizenid del personaje seleccionado
    if QBCore.Player.Login(src, cData.citizenid) then
        print('^2[QBCore]^7 ' .. GetPlayerName(src) .. ' (Citizen ID: ' .. cData.citizenid ..
                  ') ha cargado exitosamente!')
        DebugPrint("Login exitoso en QBCore para el jugador " .. GetPlayerName(src))

        QBCore.Commands.Refresh(src)

        -- 2. Llamamos a Utils para cargar integraciones como el export de DP-RealMoney
        DebugPrint("Cargando integraciones externas...")
        LoadIntegrations(src, cData)

        -- 3. Buscamos la skin activa en la base de datos para este citizenid
        DebugPrint("Buscando skin activa en la BD para aplicar al spawn.")
        MySQL.query('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {cData.citizenid, 1},
            function(result)
                if result and result[1] then
                    DebugPrint("Skin localizada. Enviando al cliente para aplicarla.")
                    local skinData = json.decode(result[1].skin)
                    local model = result[1].model

                    -- Enviamos la skin al cliente para que se aplique inmediatamente al modelo del jugador
                    TriggerClientEvent('DP-MultiCharacter:client:loadSkinAndSpawn', src, model, skinData, cData)
                else
                    -- Si no tiene skin guardada, procedemos al spawn normal sin skin personalizada
                    DebugPrint("Sin skin guardada. Redirigiendo a ProceedToSpawn normal.")
                    ProceedToSpawn(src, cData)
                end
            end)
    else
        DebugPrint("ERROR: Fallo al ejecutar QBCore.Player.Login con CitizenID: " .. tostring(cData.citizenid))
    end
end)

-- Función auxiliar interna para manejar el spawn de forma limpia
function ProceedToSpawn(src, cData)
    DebugPrint("Ejecutando ProceedToSpawn para el jugador.")
    if Config.SkipSelection then
        DebugPrint("Config.SkipSelection está activo. Retornando a la última ubicación (spawnLastLocation).")
        local coords = json.decode(cData.position)
        TriggerClientEvent('DP-MultiCharacter:client:spawnLastLocation', src, coords, cData)
    else
        DebugPrint("Config.SkipSelection inactivo. Abriendo menú nativo de qb-spawn.")
        TriggerClientEvent('qb-spawn:client:setupSpawns', src, cData, false, nil)
        TriggerClientEvent('qb-spawn:client:openUI', src, true)
    end
end

-- Evento para la creación de un personaje desde 0
RegisterNetEvent('DP-MultiCharacter:server:createCharacter', function(data)
    local src = source
    DebugPrint("Evento 'createCharacter' disparado. Creando nuevo perfil.")
    local newData = {}
    -- QBCore generará automáticamente el CID y el CitizenID si le pasamos false en la función Login
    newData.cid = data.cid
    newData.charinfo = data

    -- Intentamos iniciar el registro con false
    if QBCore.Player.Login(src, false, newData) then
        print('^2[QBCore]^7 ' .. GetPlayerName(src) .. ' ha creado un nuevo personaje.')
        DebugPrint("Personaje registrado exitosamente en QBCore.")

        QBCore.Commands.Refresh(src)

        -- Llamamos a la función abierta en sv_utils.lua
        DebugPrint("Otorgando dinero e items iniciales de bienvenida (GiveStarterItems).")
        GiveStarterItems(src)

        -- Mandamos al cliente a la selección de ropa
        DebugPrint("Mandando al jugador al menú de creación de ropa/físico (openClothing).")
        TriggerClientEvent('DP-MultiCharacter:client:openClothing', src)
    else
        DebugPrint("ERROR: Falló el registro de personaje en QBCore.Player.Login.")
    end
end)

-- ==========================================
-- 🌐 MANEJO DE DIMENSIONES (BUCKETS)
-- ==========================================
RegisterNetEvent('DP-MultiCharacter:server:SetBucket', function(bucket)
    local src = source
    DebugPrint("Asignando Routing Bucket (" .. tostring(bucket) .. ") al jugador " .. tostring(src))
    SetPlayerRoutingBucket(src, bucket)
end)
