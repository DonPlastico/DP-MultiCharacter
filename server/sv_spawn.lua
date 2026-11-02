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

-- ==========================================
-- 🏢 APARTAMENTOS PROPIOS DEL JUGADOR (qb-apartments)
-- ==========================================
-- Mismo patrón que getOwnedHouses: consulta directa a la tabla `apartments`
-- de qb-apartments y cruce con el Config.Apartments.Locations para obtener
-- la label y las coordenadas de entrada de cada apartamento.
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getOwnedApartments', function(_, cb, cid)
    if not Config.SpawnPoints.ShowOwnedApartmentsOnMap then
        DebugPrint("ShowOwnedApartmentsOnMap está desactivado en el config. Devolviendo lista vacía.")
        cb({})
        return
    end

    if not cid then
        DebugPrint("getOwnedApartments llamado sin citizenid. Devolviendo lista vacía.")
        cb({})
        return
    end

    if GetResourceState('qb-apartments') ~= 'started' then
        DebugPrint("qb-apartments no está iniciado. Devolviendo lista vacía.")
        cb({})
        return
    end

    DebugPrint("Consultando apartamentos propios para el citizenid: " .. tostring(cid))
    -- OJO: ahora seleccionamos también type y label
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT name, type, label
        FROM apartments
        WHERE citizenid = ?
    ]], {cid})

    if not ok then
        DebugPrint("ERROR consultando apartamentos: " .. tostring(rows))
        cb({})
        return
    end

    if not rows or not rows[1] then
        DebugPrint("Sin apartamentos encontrados para este citizenid.")
        cb({})
        return
    end

    -- Cargar la config de qb-apartments (LoadResourceFile)
    local locations = {}
    local okCfg, cfgResult = pcall(function()
        local raw = LoadResourceFile('qb-apartments', 'config.lua')
        if not raw then
            return nil
        end
        local fn, err = load(raw .. '\nreturn Apartments', 'qb-apartments/config.lua', 't')
        if not fn then
            return nil
        end
        return fn()
    end)

    if okCfg and type(cfgResult) == 'table' and type(cfgResult.Locations) == 'table' then
        locations = cfgResult.Locations
    else
        DebugPrint("No se pudo cargar Apartments.Locations de qb-apartments.")
        cb({})
        return
    end

    local apartments = {}
    for i = 1, #rows do
        local row = rows[i]
        local aptType = row.type -- ← CLAVE: usar 'type', no 'name'
        local loc = locations[aptType]

        DebugPrint(("Procesando apartamento: name=%s, type=%s, label=%s → loc encontrada=%s"):format(
            tostring(row.name), tostring(row.type), tostring(row.label), tostring(loc ~= nil)))

        if loc and loc.coords and loc.coords.enter then
            local enter = loc.coords.enter
            apartments[#apartments + 1] = {
                name = row.name, -- apartamento54023 (ID único)
                label = row.label or loc.label or row.name, -- Fantastic Plaza 4023 (bonito)
                x = enter.x,
                y = enter.y,
                z = enter.z
            }
        else
            DebugPrint("Apartamento '" .. tostring(aptType) .. "' sin entrada en Apartments.Locations. Se omite.")
        end
    end

    DebugPrint("Apartamentos encontrados: " .. tostring(#apartments))
    cb(apartments)
end)

QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getLastLocation', function(_, cb, cid)
    if not cid then
        cb(nil);
        return
    end

    local ok, row = pcall(MySQL.query.await, 'SELECT position FROM players WHERE citizenid = ?', {cid})
    if ok and row and row[1] then
        local decoded = json.decode(row[1].position)
        if decoded and decoded.x then
            -- 🛑 FILTRO ANTI-SALA OCULTA
            local distToHidden =
                #(vector2(decoded.x, decoded.y) - vector2(Config.HiddenCoords.x, Config.HiddenCoords.y))

            if distToHidden < 50.0 or decoded.z < -50.0 then
                -- Devolvemos el aeropuerto para que el mapa no se rompa
                cb({
                    x = Config.SpawnPoints.DefaultSpawn.x,
                    y = Config.SpawnPoints.DefaultSpawn.y,
                    z = Config.SpawnPoints.DefaultSpawn.z
                })
                return
            end

            -- Si es válida, la enviamos
            cb(decoded)
            return
        end
    end
    cb(nil)
end)
