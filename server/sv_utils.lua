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
-- 🎁 UTILIDADES DE SERVIDOR (CONFIGURABLES)
-- ==========================================
-- Función para dar objetos y dinero a personajes recién creados
function GiveStarterItems(source)
    local src = source
    DebugPrint("Ejecutando GiveStarterItems para entregar dinero e inventario base.")
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        DebugPrint("ERROR: Jugador no encontrado al intentar dar los starter items.")
        return
    end

    -- Añadir dinero base (Editable)
    DebugPrint("Añadiendo a las cuentas: 5000 (Bank) y 500 (Cash).")
    Player.Functions.AddMoney('bank', 5000, "Dinero de bienvenida")
    Player.Functions.AddMoney('cash', 500, "Dinero de bienvenida")

    -- Información para la tarjeta de identidad
    local info = {
        citizenid = Player.PlayerData.citizenid,
        firstname = Player.PlayerData.charinfo.firstname,
        lastname = Player.PlayerData.charinfo.lastname,
        birthdate = Player.PlayerData.charinfo.birthdate,
        gender = Player.PlayerData.charinfo.gender,
        nationality = Player.PlayerData.charinfo.nationality
    }

    -- Otorgar objetos iniciales en DP-Inventory (ID Card y Teléfono)
    DebugPrint("Entregando ID Card y Móvil usando DP-Inventory.")
    exports['DP-Inventory']:AddItem(src, 'id_card', 1, false, info, 'DP-MultiCharacter:StarterItem')
    exports['DP-Inventory']:AddItem(src, 'phone', 1, false, {}, 'DP-MultiCharacter:StarterItem')
end

-- Función para cargar integraciones de scripts externos al iniciar sesión
function LoadIntegrations(source, cData)
    local src = source
    DebugPrint("Comprobando integraciones para el jugador " .. tostring(src))

    -- Integración recuperada de DP-RealMoney
    if GetResourceState("DP-RealMoney") ~= 'missing' then
        DebugPrint("Recurso DP-RealMoney detectado. Sincronizando dinero del HUD/Inventario.")
        exports['DP-RealMoney']:UpdateItem(src, 'cash')
        exports['DP-RealMoney']:UpdateItem(src, 'black_money')
        exports['DP-RealMoney']:UpdateItem(src, 'crypto')
    else
        DebugPrint("Recurso DP-RealMoney ausente o apagado. Omitiendo integración.")
    end
end

-- ==========================================
-- 🔊 VOLUMEN DE INTERFAZ (PERSISTENCIA EN BD POR JUGADOR)
-- ==========================================
-- Tabla usada: dp_multicharacter_settings
--   (id INT AUTO_INCREMENT PRIMARY KEY,
--    license VARCHAR(50) UNIQUE,
--    interface_volume INT DEFAULT 100,
--    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)
-- La tabla se crea automáticamente al arrancar (ver sv_database.lua).
-- Nota: se guarda por "license" (no ciudadano) porque es una preferencia de
-- interfaz del cliente, válida para todos los personajes del mismo jugador.

-- Callback para obtener el volumen de interfaz guardado del jugador (por licencia)
QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getInterfaceVolume', function(source, cb)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if not license then
        cb(100)
        return
    end

    local ok, row = pcall(MySQL.query.await,
        'SELECT interface_volume FROM dp_multicharacter_settings WHERE license = ?', {license})

    if ok and row and row[1] and row[1].interface_volume ~= nil then
        local vol = tonumber(row[1].interface_volume) or 100
        cb(math.max(0, math.min(100, vol)))
    else
        cb(100) -- Por defecto, 100%
    end
end)

-- Evento para guardar el volumen de interfaz del jugador (UPSERT por licencia)
RegisterNetEvent('DP-MultiCharacter:server:setInterfaceVolume', function(volume)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if not license then return end

    volume = tonumber(volume) or 100
    volume = math.max(0, math.min(100, volume))

    local ok, err = pcall(function()
        MySQL.insert.await(
            'INSERT INTO dp_multicharacter_settings (license, interface_volume, updated_at) ' ..
            'VALUES (?, ?, NOW()) ' ..
            'ON DUPLICATE KEY UPDATE interface_volume = VALUES(interface_volume), updated_at = NOW()',
            {license, volume}
        )
    end)

    if ok then
        DebugPrint("Volumen de interfaz guardado en BD (" .. tostring(license) .. "): " .. tostring(volume) .. "%")
    else
        DebugPrint("ERROR guardando volumen de interfaz: " .. tostring(err))
    end
end)
