local QBCore = exports['qb-core']:GetCoreObject()

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter:Spawn Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🏠 CASAS PROPIAS DEL JUGADOR (qb-houses)
-- ==========================================
-- Sustituye a 'qb-spawn:server:getOwnedHouses'. qb-houses sigue siendo el recurso
-- que gestiona las casas de verdad; aquí solo consultamos qué casas posee este
-- citizenid para poder ofrecerlas como tarjetas en el carrusel de spawn.
--
-- qb-houses no expone ningún export para consultar la dirección legible de una
-- casa: su Config.Houses vive en memoria DENTRO de su propio recurso (inaccesible
-- desde aquí) y se carga desde la tabla `houselocations` (name, label, coords).
-- Por eso hacemos un JOIN directo entre `player_houses` (qué casas posee el
-- jugador) y `houselocations` (datos de cada casa: label/dirección y coords),
-- que es la misma fuente de verdad que usa qb-houses internamente.
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getOwnedHouses', function(_, cb, cid)
    if not Config.SpawnPoints.EnableHouses then
        DebugPrint("EnableHouses está desactivado en el config. Devolviendo lista vacía.")
        cb({})
        return
    end

    if not cid then
        DebugPrint("getOwnedHouses llamado sin citizenid. Devolviendo lista vacía.")
        cb({})
        return
    end

    DebugPrint("Consultando casas propias para el citizenid: " .. tostring(cid))
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT ph.house, hl.label, hl.coords
        FROM player_houses ph
        INNER JOIN houselocations hl ON hl.name = ph.house
        WHERE ph.citizenid = ?
    ]], {cid})

    if not ok then
        DebugPrint("ERROR consultando casas propias (¿existen las tablas de qb-houses?): " .. tostring(rows))
        cb({})
        return
    end

    if not rows or not rows[1] then
        DebugPrint("Sin casas encontradas para este citizenid.")
        cb({})
        return
    end

    -- Decodificamos las coordenadas (vienen como JSON string en houselocations)
    -- y armamos la lista final con solo lo que el carrusel necesita.
    local houses = {}
    for i = 1, #rows do
        local row = rows[i]
        local decodedCoords = nil

        local decodeOk, decoded = pcall(json.decode, row.coords)
        if decodeOk and type(decoded) == 'table' then
            decodedCoords = decoded
        end

        if decodedCoords then
            houses[#houses + 1] = {
                house = row.house, -- Identificador usado por qb-houses:client:enterOwnedHouse
                label = row.label, -- Dirección real y legible (houselocations.label)
                coords = decodedCoords
            }
        else
            DebugPrint("  ⚠ No se pudo decodificar coords de la casa " .. tostring(row.house) .. ", se omite.")
        end
    end

    DebugPrint("Casas encontradas: " .. tostring(#houses))
    cb(houses)
end)
