local QBCore = exports['qb-core']:GetCoreObject()
local MIN_SLOTS = 1
local MAX_SLOTS = 7

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🗄️ CONSULTAS Y GESTIÓN DE BASE DE DATOS
-- ==========================================
-- Callback para solicitar la información de todos los personajes del jugador al abrir el menú
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:setupCharacters', function(source, cb)
    local license = QBCore.Functions.GetIdentifier(source, 'license')
    DebugPrint("Solicitando personajes para la licencia: " .. tostring(license))
    local plyChars = {}

    -- Determinamos la cantidad de slots permitidos
    local maxSlots = Config.DefaultSlots
    if Config.CustomSlots and Config.CustomSlots[license] then
        maxSlots = Config.CustomSlots[license]
        DebugPrint("Slots personalizados detectados (" .. tostring(maxSlots) .. ") para esta licencia.")
    end

    local configuredSlots = tonumber(maxSlots) or MIN_SLOTS
    maxSlots = math.max(MIN_SLOTS, math.min(MAX_SLOTS, math.floor(configuredSlots)))
    if configuredSlots ~= maxSlots then
        DebugPrint("Slots fuera de rango (" .. tostring(configuredSlots) .. "). Se ha aplicado el límite " ..
                       tostring(maxSlots) .. " (mínimo " .. tostring(MIN_SLOTS) .. ", máximo " .. tostring(MAX_SLOTS) ..
                       ").")
    end

    -- Consulta a la base de datos para obtener personajes y sus skins activas
    MySQL.query(
        'SELECT p.*, s.model, s.skin FROM players p LEFT JOIN playerskins s ON p.citizenid = s.citizenid AND s.active = 1 WHERE p.license = ? ORDER BY p.cid ASC',
        {license}, function(result)
            DebugPrint("Consulta SQL completada. Personajes encontrados: " .. tostring(#result))
            for i = 1, (#result), 1 do
                -- Decodificamos la información que viene en formato JSON desde la base de datos
                result[i].charinfo = json.decode(result[i].charinfo)
                result[i].money = json.decode(result[i].money)
                result[i].job = json.decode(result[i].job)

                -- Añadimos la lectura del Metadata y Gang
                if result[i].gang then
                    result[i].gang = json.decode(result[i].gang)
                end
                if result[i].metadata then
                    result[i].metadata = json.decode(result[i].metadata)
                end

                plyChars[#plyChars + 1] = result[i]
            end

            DebugPrint("Enviando datos procesados de los personajes al cliente.")
            cb(plyChars, maxSlots, plyChars[1])
        end)
end)

-- Evento para eliminar definitivamente un personaje de la base de datos
RegisterNetEvent('DP-MultiCharacter:server:deleteCharacter', function(citizenid)
    local src = source
    DebugPrint("Solicitud de eliminación de personaje recibida. CitizenID: " .. tostring(citizenid))

    -- Verificamos si el botón de borrado está habilitado en la configuración
    if not Config.EnableDeleteButton then
        DebugPrint("El borrado de personajes está desactivado. Cancelando acción.")
        return
    end

    -- Procedemos con la eliminación usando la función nativa de QBCore
    QBCore.Player.DeleteCharacter(src, citizenid)
    DebugPrint("Personaje eliminado exitosamente por QBCore (CitizenID: " .. tostring(citizenid) .. ")")
    TriggerClientEvent('QBCore:Notify', src, "Personaje eliminado correctamente", "success")
end)

-- Callback para obtener la skin de un personaje específico (modelo y ropa)
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getSkin', function(source, cb, citizenid)
    DebugPrint("Consultando skin en la base de datos para CitizenID: " .. tostring(citizenid))
    local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {citizenid, 1})

    if result[1] ~= nil then
        DebugPrint("Skin encontrada. Retornando modelo y datos.")
        cb(result[1].model, result[1].skin)
    else
        DebugPrint("No se ha encontrado ninguna skin activa para este personaje.")
        cb(nil, nil)
    end
end)

-- ==========================================
-- 🔀 REORDENAR PERSONAJES (Drag & Drop)
-- ==========================================
-- Recibe un array con { cid, citizenid } en el nuevo orden deseado.
-- Actualiza el campo `cid` de cada personaje para reflejar su nueva posición.
RegisterNetEvent('DP-MultiCharacter:server:reorderCharacters', function(order)
    local src = source
    if not order or type(order) ~= "table" or #order == 0 then
        DebugPrint("reorderCharacters: payload inválido o vacío.")
        return
    end

    DebugPrint("Reordenando " .. tostring(#order) .. " personajes para el jugador " .. tostring(src))

    -- Verificamos el license del jugador
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if not license then
        DebugPrint("reorderCharacters: no se pudo obtener la licencia del jugador.")
        return
    end

    -- Construimos los UPDATE en una sola transacción para que sea atómico
    -- (si uno falla, todos se revierten y la BD queda consistente)
    local updates = {}
    for _, entry in ipairs(order) do
        local newCid = tonumber(entry.cid)
        local citizenid = entry.citizenid

        if newCid and citizenid then
            updates[#updates + 1] = {
                query = 'UPDATE players SET cid = ? WHERE citizenid = ? AND license = ?',
                values = {newCid, citizenid, license}
            }
        else
            DebugPrint("  ⚠ Entrada inválida en payload: cid=" .. tostring(entry.cid) .. " citizenid=" ..
                           tostring(entry.citizenid))
        end
    end

    if #updates == 0 then
        DebugPrint("reorderCharacters: no hay updates válidos que aplicar.")
        return
    end

    -- Ejecutamos todo en transacción
    MySQL.transaction.await(updates)

    DebugPrint("  → " .. tostring(#updates) .. " personajes reordenados correctamente en la BD.")

    -- 🚨 IMPORTANTE: pausar un frame para asegurar que los cambios están en disco
    -- (MySQL.transaction.await ya espera, pero damos un margen por seguridad)
    Wait(100)

    -- Avisamos al cliente de que puede refrescar
    TriggerClientEvent('DP-MultiCharacter:client:reorderDone', src)

    -- Notificación visual (opcional, la UI ya se actualiza sola)
    TriggerClientEvent('QBCore:Notify', src, "Orden de personajes guardado", "success")
end)
