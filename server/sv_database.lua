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
-- 🗄️ CREACIÓN DE TABLAS (IDEMPOTENTE)
-- ==========================================
-- Tabla de preferencias de interfaz por jugador (se usa para persistir en BD
-- el volumen de sonidos de interfaz, y en el futuro otras preferencias UI).
-- Se crea automáticamente si no existe; no requiere migración manual.
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dp_multicharacter_settings` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `license` VARCHAR(50) NOT NULL UNIQUE,
            `interface_volume` INT NOT NULL DEFAULT 100,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
    DebugPrint("Tabla dp_multicharacter_settings verificada/creada correctamente.")
end)

-- ==========================================
-- 🗄️ CONSULTAS Y GESTIÓN DE BASE DE DATOS
-- ==========================================

-- ⚡ SISTEMA DE CACHÉ EN MEMORIA
local CharCache = {}
local CACHE_DURATION = 15 -- Segundos que durará la caché antes de caducar

-- Función global para invalidar (borrar) la caché cuando haya cambios
function InvalidateCharacterCache(license)
    if license and CharCache[license] then
        CharCache[license] = nil
        DebugPrint("Caché invalidada y limpiada para la licencia: " .. tostring(license))
    end
end

-- Callback para solicitar la información de todos los personajes del jugador al abrir el menú
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:setupCharacters', function(source, cb)
    local license = QBCore.Functions.GetIdentifier(source, 'license')
    DebugPrint("Solicitando personajes para la licencia: " .. tostring(license))

    -- 1. COMPROBACIÓN DE CACHÉ
    if CharCache[license] and CharCache[license].expires > os.time() then
        DebugPrint("⚡ Sirviendo personajes desde CACHÉ (Ahorrando consulta SQL pesada).")
        local cached = CharCache[license].data
        cb(cached.plyChars, cached.maxSlots, cached.lastCharacter, cached.trashedCount)
        return
    end

    local plyChars = {}
    local trashedCount = 0

    -- Determinamos la cantidad de slots permitidos
    local maxSlots = Config.DefaultSlots
    if Config.CustomSlots and Config.CustomSlots[license] then
        maxSlots = Config.CustomSlots[license]
        DebugPrint("Slots personalizados detectados (" .. tostring(maxSlots) .. ") para esta licencia.")
    end

    local configuredSlots = tonumber(maxSlots) or MIN_SLOTS
    maxSlots = math.max(MIN_SLOTS, math.min(MAX_SLOTS, math.floor(configuredSlots)))
    if configuredSlots ~= maxSlots then
        DebugPrint("Slots fuera de rango. Se aplicó límite " .. tostring(maxSlots))
    end

    -- Consulta a la base de datos (Solo se ejecuta si la caché no existe o caducó)
    MySQL.query(
        'SELECT p.*, s.model, s.skin FROM players p LEFT JOIN playerskins s ON p.citizenid = s.citizenid AND s.active = 1 WHERE p.license = ? ORDER BY p.cid ASC',
        {license}, function(result)
            DebugPrint("Consulta SQL completada. Personajes encontrados: " .. tostring(#result))
            for i = 1, (#result), 1 do
                result[i].charinfo = json.decode(result[i].charinfo)
                result[i].money = json.decode(result[i].money)
                result[i].job = json.decode(result[i].job)

                if result[i].gang then
                    result[i].gang = json.decode(result[i].gang)
                end
                if result[i].metadata then
                    result[i].metadata = json.decode(result[i].metadata)
                end

                if result[i].metadata and result[i].metadata.deleted then
                    MySQL.query.await('DELETE FROM `players` WHERE citizenid = ?', {result[i].citizenid})
                elseif result[i].metadata and result[i].metadata.PROCESO_ELIMINACION then
                    trashedCount = trashedCount + 1
                else
                    plyChars[#plyChars + 1] = result[i]
                end
            end

            DebugPrint("Enviando datos. En papelera: " .. tostring(trashedCount))

            -- 2. GUARDAR EN CACHÉ LOS DATOS PROCESADOS
            CharCache[license] = {
                expires = os.time() + CACHE_DURATION,
                data = {
                    plyChars = plyChars,
                    maxSlots = maxSlots,
                    lastCharacter = plyChars[1],
                    trashedCount = trashedCount
                }
            }

            cb(plyChars, maxSlots, plyChars[1], trashedCount)
        end)
end)

-- ==========================================
-- 🗑️ BORRADO DE PERSONAJE (PAPELERA CON VENTANA DE RESTAURACIÓN)
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

-- Hard delete REAL y definitivo de un personaje y todos sus datos relacionados.
-- Extraído a función reutilizable: la usa tanto la purga automática (tras Config.RestoreWindowDays)
-- como cualquier borrado directo sin papelera que se necesite en el futuro. Devuelve la lista de
-- tablas que fallaron al limpiar (vacía si todo fue bien).
function HardDeleteCharacterFully(citizenid, src)
    local errors = {}

    -- 1) Tablas relacionadas, una a una (si alguna falla, el resto se completa igual)
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

    -- 2) Inventario de DP-Inventory (usa 'identifier' en vez de 'citizenid')
    local invOk, invErr = pcall(function()
        MySQL.query.await('DELETE FROM `inventories` WHERE identifier = ?', {citizenid})
    end)
    if not invOk then
        DebugPrint("  ⚠ No se pudo limpiar el inventario: " .. tostring(invErr))
        errors[#errors + 1] = 'inventories'
    end

    -- 3) Tablas del teléfono que usan device_id
    local phoneTables = {'phone_messages', 'phone_gallery', 'phone_note', 'phone_bleets'}
    for _, tabla in ipairs(phoneTables) do
        local ok, err = pcall(function()
            MySQL.query.await('DELETE FROM `' .. tabla .. '` WHERE device_id = ?', {citizenid})
        end)
        if not ok then
            DebugPrint("  ⚠ No se pudo limpiar " .. tabla .. ": " .. tostring(err))
        end
    end

    -- 4) HARD DELETE REAL del personaje en `players`
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

    -- 5) Si el personaje estaba cargado en memoria, limpiar SIN pasar por Logout()/Save()
    --    (Save() reinsertaría la fila que acabamos de borrar, "resucitando" al personaje).
    if src then
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
    end

    return errors
end

-- Evento para MOVER un personaje a la papelera (soft delete con ventana de recuperación).
-- Ya NO borra nada físicamente: solo marca el personaje con metadata.PROCESO_ELIMINACION
-- (timestamp del borrado). El hard delete real solo ocurre pasados Config.RestoreWindowDays,
-- vía el hilo de purga automática definido más abajo.
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:deleteCharacter', function(source, cb, citizenid)
    local src = source

    if not CheckRateLimit(src, 'delete') then
        TriggerClientEvent('QBCore:Notify', src, "Por favor, espera unos segundos antes de borrar otro personaje.",
            "error")
        cb(false)
        return
    end

    DebugPrint("Solicitud de eliminación (a papelera) de personaje recibida. CitizenID: " .. tostring(citizenid))

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
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local row = MySQL.query.await('SELECT license, metadata FROM players WHERE citizenid = ?', {citizenid})
    local ownerRow = row and row[1]

    if not ownerRow or ownerRow.license ~= license then
        DebugPrint("ERROR: El personaje no pertenece a este jugador o no existe. CitizenID: " .. tostring(citizenid))
        TriggerClientEvent('QBCore:Notify', src, "No se pudo borrar el personaje", "error")
        cb(false)
        return
    end

    DebugPrint("Verificación de propiedad OK. Moviendo el personaje a la papelera.")

    -- Decodificamos el metadata actual, le añadimos la marca de papelera, y lo reescribimos
    local metadata = {}
    local ok, decoded = pcall(json.decode, ownerRow.metadata)
    if ok and type(decoded) == 'table' then
        metadata = decoded
    end
    metadata.PROCESO_ELIMINACION = os.time() -- Timestamp UNIX del momento del borrado

    local updOk, updErr = pcall(function()
        -- ¡AQUÍ ESTÁ LA MAGIA! Ponemos cid = NULL para liberar el slot real en la base de datos
        MySQL.update.await('UPDATE players SET metadata = ?, cid = NULL WHERE citizenid = ?',
            {json.encode(metadata), citizenid})
    end)

    InvalidateCharacterCache(license)

    if not updOk then
        DebugPrint("  ⚠ ERROR marcando el personaje como PROCESO_ELIMINACION: " .. tostring(updErr))
        TriggerClientEvent('QBCore:Notify', src, "No se pudo borrar el personaje", "error")
        cb(false)
        return
    end

    -- Igual que antes: si el personaje estaba cargado en memoria, lo limpiamos sin Save()
    -- para que no se reescriban datos viejos encima del metadata que acabamos de actualizar.
    local player = QBCore.Functions.GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.citizenid == citizenid then
        DebugPrint("  → Limpiando sesión en memoria del personaje movido a papelera (sin guardar).")
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

    DebugPrint("Personaje movido a la papelera correctamente (CitizenID: " .. tostring(citizenid) ..
                   "). Días de margen: " .. tostring(Config.RestoreWindowDays))
    TriggerClientEvent('QBCore:Notify', src, "Personaje eliminado. Puedes restaurarlo en los próximos " ..
        tostring(Config.RestoreWindowDays) .. " días.", "success")

    cb(true)
end)

-- ==========================================
-- ♻️ RESTAURAR PERSONAJE (Papelera)
-- ==========================================
-- Callback: devuelve los personajes del jugador que están en la papelera y AÚN dentro
-- del plazo de recuperación, con los días restantes ya calculados.
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getDeletedCharacters', function(source, cb)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    DebugPrint("Solicitando personajes en papelera para la licencia: " .. tostring(license))

    local result = MySQL.query.await('SELECT * FROM players WHERE license = ?', {license})
    local deletedChars = {}
    local windowSeconds = (Config.RestoreWindowDays or 5) * 86400

    for i = 1, #result do
        local ok, metadata = pcall(json.decode, result[i].metadata)
        if ok and type(metadata) == 'table' and metadata.PROCESO_ELIMINACION then
            local deletedAt = tonumber(metadata.PROCESO_ELIMINACION) or 0
            local elapsed = os.time() - deletedAt
            local remainingSeconds = windowSeconds - elapsed

            if remainingSeconds > 0 then
                result[i].charinfo = json.decode(result[i].charinfo)
                result[i].deletedAt = deletedAt
                result[i].daysRemaining = math.ceil(remainingSeconds / 86400)
                deletedChars[#deletedChars + 1] = result[i]
            end
            -- Si remainingSeconds <= 0, ya debería estar purgado por el hilo automático;
            -- lo omitimos aquí también por seguridad (no se muestra como restaurable).
        end
    end

    DebugPrint("Personajes en papelera encontrados (dentro de plazo): " .. tostring(#deletedChars))
    cb(deletedChars)
end)

-- Evento: restaura un personaje desde la papelera (le busca un hueco libre y quita la marca)
RegisterNetEvent('DP-MultiCharacter:server:restoreCharacter', function(citizenid)
    local src = source
    DebugPrint("Solicitud de restauración de personaje recibida. CitizenID: " .. tostring(citizenid))

    if not citizenid or citizenid == '' then
        return
    end

    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local row = MySQL.query.await('SELECT license, metadata FROM players WHERE citizenid = ?', {citizenid})
    local ownerRow = row and row[1]

    if not ownerRow or ownerRow.license ~= license then
        TriggerClientEvent('QBCore:Notify', src, "No se pudo restaurar el personaje", "error")
        return
    end

    local ok, metadata = pcall(json.decode, ownerRow.metadata)
    if not ok or type(metadata) ~= 'table' or not metadata.PROCESO_ELIMINACION then
        TriggerClientEvent('QBCore:Notify', src, "Este personaje no está en la papelera", "error")
        return
    end

    -- Comprobamos que siga dentro del plazo
    local windowSeconds = (Config.RestoreWindowDays or 5) * 86400
    local elapsed = os.time() - (tonumber(metadata.PROCESO_ELIMINACION) or 0)
    if elapsed >= windowSeconds then
        TriggerClientEvent('QBCore:Notify', src, "El plazo para restaurar este personaje ya venció", "error")
        return
    end

    -- ==============================================================
    -- 🔍 BÚSQUEDA DE SLOT LIBRE PARA LA RESTAURACIÓN
    -- ==============================================================
    -- 1. Ver cuántos slots máximos tiene este jugador
    local maxSlots = Config.DefaultSlots
    if Config.CustomSlots and Config.CustomSlots[license] then
        maxSlots = Config.CustomSlots[license]
    end

    -- 2. Obtener todos los CIDs que ya tiene ocupados
    local activeChars = MySQL.query.await('SELECT cid FROM players WHERE license = ? AND cid IS NOT NULL', {license})
    local takenSlots = {}
    for i = 1, #activeChars do
        takenSlots[tonumber(activeChars[i].cid)] = true
    end

    -- 3. Buscar el primer slot vacío
    local freeSlot = nil
    for i = 1, maxSlots do
        if not takenSlots[i] then
            freeSlot = i
            break
        end
    end

    -- 4. Si no hay hueco, bloqueamos la restauración
    if not freeSlot then
        DebugPrint("ERROR: El jugador " .. GetPlayerName(src) .. " intentó restaurar pero no tiene slots libres.")
        TriggerClientEvent('QBCore:Notify', src,
            "No tienes ningún slot libre para restaurar este personaje. Borra uno primero.", "error")
        return
    end
    -- ==============================================================

    metadata.PROCESO_ELIMINACION = nil

    local updOk, updErr = pcall(function()
        -- Le asignamos el nuevo 'freeSlot' encontrado
        MySQL.update.await('UPDATE players SET metadata = ?, cid = ? WHERE citizenid = ?',
            {json.encode(metadata), freeSlot, citizenid})
    end)

    InvalidateCharacterCache(license)

    if not updOk then
        DebugPrint("  ⚠ ERROR restaurando el personaje: " .. tostring(updErr))
        TriggerClientEvent('QBCore:Notify', src, "No se pudo restaurar el personaje", "error")
        return
    end

    DebugPrint("Personaje restaurado correctamente en el Slot " .. tostring(freeSlot) .. " (CitizenID: " ..
                   tostring(citizenid) .. ")")
    TriggerClientEvent('QBCore:Notify', src, "Personaje restaurado correctamente", "success")
    TriggerClientEvent('DP-MultiCharacter:client:reorderDone', src)
end)

-- ==========================================
-- 🧹 PURGA AUTOMÁTICA DE LA PAPELERA (cada 24 horas)
-- ==========================================
-- Revisa periódicamente todos los personajes en PROCESO_ELIMINACION cuyo plazo
-- (Config.RestoreWindowDays) ya venció, y los elimina definitivamente y sin
-- posibilidad de recuperación mediante HardDeleteCharacterFully.
CreateThread(function()
    while true do
        Wait(24 * 60 * 60 * 1000) -- 24 horas

        DebugPrint("🧹 Iniciando revisión de purga automática de la papelera...")

        local windowSeconds = (Config.RestoreWindowDays or 5) * 86400
        local ok, result = pcall(MySQL.query.await, 'SELECT citizenid, metadata FROM players', {})

        if ok and result then
            local purgedCount = 0
            for i = 1, #result do
                local decOk, metadata = pcall(json.decode, result[i].metadata)
                if decOk and type(metadata) == 'table' and metadata.PROCESO_ELIMINACION then
                    local elapsed = os.time() - (tonumber(metadata.PROCESO_ELIMINACION) or 0)
                    if elapsed >= windowSeconds then
                        DebugPrint("  → Purgando definitivamente CitizenID " .. tostring(result[i].citizenid) ..
                                       " (superó el plazo de " .. tostring(Config.RestoreWindowDays) .. " días).")
                        HardDeleteCharacterFully(result[i].citizenid, nil)
                        purgedCount = purgedCount + 1
                    end
                end
            end
            DebugPrint("🧹 Purga automática completada. Personajes eliminados definitivamente: " ..
                           tostring(purgedCount))
        else
            DebugPrint("⚠ No se pudo ejecutar la revisión de purga automática (error en la consulta).")
        end
    end
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

    if not CheckRateLimit(src, 'reorder') then
        TriggerClientEvent('QBCore:Notify', src, "Has guardado el orden hace poco. Espera un momento.", "error")
        return
    end

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

    InvalidateCharacterCache(license)

    -- 🚨 IMPORTANTE: pausar un frame para asegurar que los cambios están en disco
    -- (MySQL.transaction.await ya espera, pero damos un margen por seguridad)
    Wait(100)

    -- Avisamos al cliente de que puede refrescar
    TriggerClientEvent('DP-MultiCharacter:client:reorderDone', src)

    -- Notificación visual (opcional, la UI ya se actualiza sola)
    TriggerClientEvent('QBCore:Notify', src, "Orden de personajes guardado", "success")
end)
