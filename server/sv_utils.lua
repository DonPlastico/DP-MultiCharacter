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
