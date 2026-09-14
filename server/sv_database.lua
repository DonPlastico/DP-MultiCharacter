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

                -- LIMPIEZA AUTOMÁTICA de personajes marcados como borrados (soft delete antiguo):
                -- antes quedaban en la BD aunque no se mostraran. Ahora los borramos de verdad.
                if result[i].metadata and result[i].metadata.deleted then
                    DebugPrint("Eliminando físicamente personaje previamente marcado como borrado (CitizenID: " ..
                                   tostring(result[i].citizenid) .. ")")
                    MySQL.query.await('DELETE FROM `players` WHERE citizenid = ?', {result[i].citizenid})
                else
                    plyChars[#plyChars + 1] = result[i]
                end
            end

            DebugPrint("Enviando datos procesados de los personajes al cliente.")
            cb(plyChars, maxSlots, plyChars[1])
        end)
end)

-- ==========================================
-- 🗑️ BORRADO DE PERSONAJE (A PRUEBA DE FALLOS)
-- ==========================================
-- Definimos aquí la lista de tablas que intenta borrar qb-core con
-- "DELETE ... WHERE citizenid = ?", para replicarla pero de forma segura.
-- (qb-core hace la MISMA transacción; si una tabla no existe o no tiene
-- la columna citizenid, la transacción completa aborta y NO se borra nada).
local DELETE_TABLES = {'apartments', 'bank_accounts', 'phone_invoices', 'playerskins', 'player_contacts',
                       'player_houses', 'player_mails', 'player_outfits', 'player_vehicles'}

-- Comprueba si la tabla existe y tiene la columna citizenid
-- (evita errores en rojo de "Unknown column" / "doesn't exist")
local function TableSupportsCitizenId(tabla)
    local ok, res = pcall(MySQL.query.await,
        "SELECT COUNT(*) AS total FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'citizenid'",
        {tabla})
    if not ok or not res or not res[1] then
        return false
    end
    return tonumber(res[1].total) > 0
end

-- Evento para eliminar definitivamente un personaje de la base de datos
-- (Usamos callback para que el cliente sepa CUÁNDO termina el borrado
--  y refresque la lista al instante, sin tener que recargar la UI)
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:deleteCharacter', function(source, cb, citizenid)
    local src = source
    DebugPrint("Solicitud de eliminación de personaje recibida. CitizenID: " .. tostring(citizenid))

    -- Verificamos si el botón de borrado está habilitado en la configuración
    if not Config.EnableDeleteButton then
        DebugPrint("El borrado de personajes está desactivado. Cancelando acción.")
        cb(false)
        return
    end

    if not citizenid or citizenid == '' then
        DebugPrint("ERROR: CitizenID vacío. No se puede borrar el personaje.")
        TriggerClientEvent('QBCore:Notify', src, "No se pudo borrar el personaje (CitizenID vacío)", "error")
        cb(false)
        return
    end

    -- Seguridad: comprobamos que el personaje pertenezca realmente al jugador
    -- (misma comprobación que hace QBCore.Player.DeleteCharacter)
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local ownerLicense = MySQL.scalar.await('SELECT license FROM players WHERE citizenid = ?', {citizenid})

    if not ownerLicense or ownerLicense ~= license then
        DebugPrint("ERROR: El personaje no pertenece a este jugador o no existe. CitizenID: " .. tostring(citizenid))
        TriggerClientEvent('QBCore:Notify', src, "No se pudo borrar el personaje", "error")
        cb(false)
        return
    end

    DebugPrint("Verificación de propiedad OK. Procediendo con el borrado.")

    -- 1) HARD DELETE en las tablas relacionadas, UNA A UNA (sin transacción suicida):
    --    si alguna falla, el resto se completa igual y avisamos del fallo concreto.
    --    (El borrado físico en `players` se hace al final, en el paso 5.)
    local errors = {}
    for _, tabla in ipairs(DELETE_TABLES) do
        if TableSupportsCitizenId(tabla) then
            local ok, err = pcall(function()
                MySQL.query.await('DELETE FROM `' .. tabla .. '` WHERE citizenid = ?', {citizenid})
            end)
            if not ok then
                DebugPrint("  ⚠ No se pudo limpiar la tabla " .. tabla .. ": " .. tostring(err))
                errors[#errors + 1] = tabla
            else
                DebugPrint("  → Tabla " .. tabla .. " limpiada para CitizenID " .. citizenid)
            end
        else
            DebugPrint("  ⚠ Tabla " .. tabla .. " omitida (no existe o no tiene columna citizenid).")
        end
    end

    -- 3) Limpieza del inventario de DP-Inventory (usa 'identifier' en vez de 'citizenid')
    local invOk, invErr = pcall(function()
        MySQL.query.await('DELETE FROM `inventories` WHERE identifier = ?', {citizenid})
    end)
    if not invOk then
        DebugPrint("  ⚠ No se pudo limpiar el inventario: " .. tostring(invErr))
        errors[#errors + 1] = 'inventories'
    end

    -- 4) Limpieza de tablas del teléfono que usan device_id (relacionado con citizenid vía metadata)
    local phoneTables = {'phone_messages', 'phone_gallery', 'phone_note', 'phone_bleets'}
    for _, tabla in ipairs(phoneTables) do
        local ok, err = pcall(function()
            MySQL.query.await('DELETE FROM `' .. tabla .. '` WHERE device_id = ?', {citizenid})
        end)
        if not ok then
            DebugPrint("  ⚠ No se pudo limpiar " .. tabla .. ": " .. tostring(err))
        end
    end

    -- 5) HARD DELETE REAL del personaje en la tabla `players`
    --    (esto es lo que elimina la fila de la base de datos de verdad)
    local delOk, delErr = pcall(function()
        MySQL.query.await('DELETE FROM `players` WHERE citizenid = ?', {citizenid})
    end)
    if not delOk then
        DebugPrint("  ⚠ ERROR eliminando el personaje de players: " .. tostring(delErr))
        errors[#errors + 1] = 'players'
    else
        DebugPrint("  → Personaje eliminado físicamente de la tabla players (CitizenID: " .. tostring(citizenid) ..
                       ")")
    end

    -- 6) Si el personaje borrado estaba cargado en memoria (Player object activo con ese citizenid),
    --    lo limpiamos de QBCore SIN pasar por Logout() ni por Save().
    --    Motivo: tanto player.Functions.Logout() como QBCore.Player.Logout() ejecutan internamente
    --    player.Functions.Save() ANTES de limpiar la sesión (así lo hace qb-core de fábrica). Ese guardado
    --    vuelve a escribir en `players` la fila que acabamos de eliminar, "resucitando" al personaje.
    --    Por eso antes hacía falta pulsar borrar 2 veces: la 1ª vez se borraba y el Save() del Logout lo
    --    devolvía; la 2ª vez ya no quedaba ningún Player en memoria que lo resucitara.
    --    Para evitarlo, limpiamos las tablas internas de QBCore directamente, sin invocar ningún Save()
    --    (con pcall por seguridad, por si algún fork de QBCore no expone esas tablas con ese nombre).
    local player = QBCore.Functions.GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.citizenid == citizenid then
        DebugPrint("  → Limpiando sesión en memoria del personaje borrado (sin guardar, para no resucitarlo).")
        TriggerClientEvent('QBCore:Client:OnPlayerUnload', src)
        TriggerEvent('QBCore:Server:OnPlayerUnload', src)
        pcall(function()
            if QBCore.Players then
                QBCore.Players[src] = nil
            end
            if QBCore.PlayersByCitizenId then
                QBCore.PlayersByCitizenId[citizenid] = nil
            end
        end)
    end

    if #errors == 0 then
        DebugPrint("Personaje eliminado exitosamente (CitizenID: " .. tostring(citizenid) .. ")")
        TriggerClientEvent('QBCore:Notify', src, "Personaje eliminado correctamente", "success")
    else
        DebugPrint("Personaje eliminado con errores parciales: " .. table.concat(errors, ", "))
        TriggerClientEvent('QBCore:Notify', src,
            "Personaje eliminado, pero hubo errores en: " .. table.concat(errors, ", "), "error")
    end

    cb(true)
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
