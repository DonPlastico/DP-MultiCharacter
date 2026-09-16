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
-- 📜 HISTORIAL DE PERSONAJES (DECLARACIÓN TEMPRANA)
-- ==========================================
local function LogCharacterEvent(src, textMsg, iconName)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        return
    end

    local logs = Player.PlayerData.metadata["activityLog"] or {}

    table.insert(logs, 1, {
        date = os.date("%d/%m/%Y, %H:%M:%S"),
        text = textMsg,
        icon = iconName or "fa-info-circle"
    })

    if #logs > 15 then
        table.remove(logs)
    end

    Player.Functions.SetMetaData("activityLog", logs)
end

exports('LogCharacterEvent', LogCharacterEvent)

-- ==========================================
-- 🎁 UTILIDADES DE SERVIDOR (CONFIGURABLES)
-- ==========================================
function GiveStarterItems(source, cartPayload, cartTotal)
    local src = source
    DebugPrint("Ejecutando GiveStarterItems para entregar compras iniciales.")
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        return
    end

    -- Obtenemos el inventario crudo del jugador
    local items = Player.PlayerData.items or {}

    -- 1. Si compró cosas con dinero, calculamos el cobro de inmediato
    if cartPayload and cartTotal and tonumber(cartTotal) > 0 then
        -- En personajes nuevos, RemoveMoney a veces da fallos por la DB asíncrona.
        -- Como el QBCore acaba de darle el StartingBudget entero, se lo restamos matemáticamente
        -- y sobreescribimos la propiedad. Esto es 100% seguro.
        local currentBank = Player.PlayerData.money['bank'] or 0
        local newBank = currentBank - tonumber(cartTotal)
        if newBank < 0 then
            newBank = 0
        end

        Player.Functions.SetMoney('bank', newBank, "Compra de Starter Items")
        DebugPrint("Se han descontado $" .. tostring(cartTotal) .. " del banco por Starter Items (Nuevo saldo: $" ..
                       tostring(newBank) .. ").")
    end

    -- 2. Preparamos metadatos básicos
    local identityInfo = {
        citizenid = Player.PlayerData.citizenid,
        firstname = Player.PlayerData.charinfo.firstname,
        lastname = Player.PlayerData.charinfo.lastname,
        birthdate = Player.PlayerData.charinfo.birthdate,
        gender = Player.PlayerData.charinfo.gender,
        nationality = Player.PlayerData.charinfo.nationality
    }

    local itemsLogList = ""

    -- 3. Inyectamos los items directamente en la tabla de PlayerData
    -- Esto evita el uso de exports['DP-Inventory']:AddItem que choca con jugadores recién nacidos.
    local currentSlot = 1

    -- Si hay carrito, inyectamos cada ítem
    if cartPayload then
        for itemName, qty in pairs(cartPayload) do
            local itemInfo = QBCore.Shared.Items[itemName:lower()]
            if itemInfo then
                -- Buscamos el siguiente slot libre de forma cruda
                while items[currentSlot] do
                    currentSlot = currentSlot + 1
                end

                -- Creamos la estructura del item puro de QBCore
                local itemMetadata = {}
                if itemName == "id_card" then
                    itemMetadata = identityInfo
                elseif itemInfo.type == 'weapon' then
                    -- Las armas nuevas necesitan serie y calidad para no corromper el inventario
                    itemMetadata.serie = tostring(math.random(10, 99) .. string.char(math.random(65, 90)) ..
                                                      math.random(100, 999))
                    itemMetadata.quality = 100
                end

                items[currentSlot] = {
                    name = itemName,
                    amount = tonumber(qty) or 1,
                    info = itemMetadata,
                    label = itemInfo.label,
                    description = itemInfo.description or '',
                    weight = itemInfo.weight,
                    type = itemInfo.type,
                    unique = itemInfo.unique,
                    useable = itemInfo.useable,
                    image = itemInfo.image,
                    shouldClose = itemInfo.shouldClose,
                    slot = currentSlot,
                    combinable = itemInfo.combinable
                }

                itemsLogList = itemsLogList .. qty .. "x " .. itemName .. ", "
                DebugPrint("Inyectado directamente: " .. tostring(qty) .. "x " .. itemName .. " en slot " ..
                               tostring(currentSlot))
            end
        end
    end

    -- 4. Guardamos la tabla de items de vuelta al jugador de forma atómica
    Player.Functions.SetPlayerData('items', items)

    -- 5. Registro Historial
    if string.len(itemsLogList) > 0 then
        itemsLogList = string.sub(itemsLogList, 1, -3)
        local costStr = (cartTotal and tonumber(cartTotal) > 0) and "$" .. tostring(cartTotal) or "Gratis"
        LogCharacterEvent(src, "Obtuvo su Kit Inicial (Coste: " .. costStr .. "): " .. itemsLogList, "fa-box-open")
    else
        LogCharacterEvent(src, "Inició su aventura sin adquirir ítems iniciales.", "fa-user")
    end
end

-- Función para cargar integraciones de scripts externos al iniciar sesión
function LoadIntegrations(source, cData)
    local src = source
    DebugPrint("Comprobando integraciones para el jugador " .. tostring(src))

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
        cb(100)
    end
end)

RegisterNetEvent('DP-MultiCharacter:server:setInterfaceVolume', function(volume)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if not license then
        return
    end

    volume = tonumber(volume) or 100
    volume = math.max(0, math.min(100, volume))

    local ok, err = pcall(function()
        MySQL.insert.await('INSERT INTO dp_multicharacter_settings (license, interface_volume, updated_at) ' ..
                               'VALUES (?, ?, NOW()) ' ..
                               'ON DUPLICATE KEY UPDATE interface_volume = VALUES(interface_volume), updated_at = NOW()',
            {license, volume})
    end)

    if ok then
        DebugPrint("Volumen de interfaz guardado en BD (" .. tostring(license) .. "): " .. tostring(volume) .. "%")
    else
        DebugPrint("ERROR guardando volumen de interfaz: " .. tostring(err))
    end
end)

-- ==========================================
-- ⏱️ SISTEMA DE RATE LIMITING (ANTI-SPAM)
-- ==========================================
local actionCooldowns = {}

function CheckRateLimit(source, action)
    local license = QBCore.Functions.GetIdentifier(source, 'license')
    if not license then
        return false
    end

    local cooldownTime = Config.RateLimits and Config.RateLimits[action] or 5
    local currentTime = os.time()

    if not actionCooldowns[license] then
        actionCooldowns[license] = {}
    end

    if actionCooldowns[license][action] then
        local timePassed = currentTime - actionCooldowns[license][action]
        if timePassed < cooldownTime then
            return false
        end
    end

    actionCooldowns[license][action] = currentTime
    return true
end
