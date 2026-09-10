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
-- Adaptador de notificaciones (Editable por el cliente)
-- Esta función centraliza las notificaciones enviadas al jugador desde la UI.
function SendNotify(msg, type)
    DebugPrint("Enviando notificación al jugador: " .. tostring(msg) .. " | Tipo: " .. tostring(type))
    QBCore.Functions.Notify(msg, type)
end

-- Evento activado tras la inserción en SQL para llevar al jugador a personalizar su personaje
RegisterNetEvent('DP-MultiCharacter:client:openClothing', function()
    DebugPrint("Evento 'openClothing' disparado. Abriendo menú de creación de personaje inicial.")
    -- Por defecto apuntamos a qb-clothing. 
    -- Si el servidor usa illenium-appearance u otro, se cambia aquí.
    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end)
