local QBCore = exports['qb-core']:GetCoreObject()
local MIN_SLOTS = 1
local MAX_SLOTS = 7

local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dp_multicharacter_settings` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `license` VARCHAR(50) NOT NULL UNIQUE,
            `interface_volume` INT NOT NULL DEFAULT 100,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end)

local CharCache = {}
local CACHE_DURATION = 15

function InvalidateCharacterCache(license)
    if license and CharCache[license] then
        CharCache[license] = nil
        DebugPrint("Caché invalidada para la licencia: " .. tostring(license))
    end
end

QBCore.Functions.CreateCallback('DP-MultiCharacter:server:setupCharacters', function(source, cb)
    local license = QBCore.Functions.GetIdentifier(source, 'license')

    if CharCache[license] and CharCache[license].expires > os.time() then
        local cached = CharCache[license].data
        cb(cached.plyChars, cached.maxSlots, cached.lastCharacter, cached.trashedCount)
        return
    end

    local plyChars = {}
    local trashedCount = 0

    local maxSlots = Config.DefaultSlots
    if Config.CustomSlots and Config.CustomSlots[license] then
        maxSlots = Config.CustomSlots[license]
    end

    local configuredSlots = tonumber(maxSlots) or MIN_SLOTS
    maxSlots = math.max(MIN_SLOTS, math.min(MAX_SLOTS, math.floor(configuredSlots)))

    MySQL.query(
        'SELECT p.*, s.model, s.skin FROM players p LEFT JOIN playerskins s ON p.citizenid = s.citizenid AND s.active = 1 WHERE p.license = ? ORDER BY p.cid ASC',
        {license}, function(result)
            for i = 1, (#result), 1 do
                -- AÑADIDO: Print de trazabilidad absoluta de la Base de Datos
                print("^5[DEBUG POSICION] BD cruda para " .. result[i].citizenid .. " -> " ..
                          tostring(result[i].position) .. "^7")

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

local DELETE_TABLES = {'apartments', 'bank_accounts', 'phone_invoices', 'playerskins', 'player_contacts',
                       'player_houses', 'player_mails', 'player_outfits', 'player_vehicles'}

local function TableSupportsCitizenId(tabla)
    local ok, res = pcall(MySQL.query.await,
        "SELECT COUNT(*) AS total FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'citizenid'",
        {tabla})
    if not ok or not res or not res[1] then
        return false
    end
    return tonumber(res[1].total) > 0
end

function HardDeleteCharacterFully(citizenid, src)
    local errors = {}
    for _, tabla in ipairs(DELETE_TABLES) do
        if TableSupportsCitizenId(tabla) then
            local ok, err = pcall(function()
                MySQL.query.await('DELETE FROM `' .. tabla .. '` WHERE citizenid = ?', {citizenid})
            end)
            if not ok then
                errors[#errors + 1] = tabla
            end
        end
    end
    pcall(function()
        MySQL.query.await('DELETE FROM `inventories` WHERE identifier = ?', {citizenid})
    end)

    local phoneTables = {'phone_messages', 'phone_gallery', 'phone_note', 'phone_bleets'}
    for _, tabla in ipairs(phoneTables) do
        pcall(function()
            MySQL.query.await('DELETE FROM `' .. tabla .. '` WHERE device_id = ?', {citizenid})
        end)
    end

    pcall(function()
        MySQL.query.await('DELETE FROM `players` WHERE citizenid = ?', {citizenid})
    end)

    if src then
        local player = QBCore.Functions.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.citizenid == citizenid then
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

QBCore.Functions.CreateCallback('DP-MultiCharacter:server:deleteCharacter', function(source, cb, citizenid)
    local src = source
    if not CheckRateLimit(src, 'delete') then
        cb(false)
        return
    end
    if not Config.EnableDeleteButton or not citizenid or citizenid == '' then
        cb(false)
        return
    end

    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local row = MySQL.query.await('SELECT license, metadata FROM players WHERE citizenid = ?', {citizenid})
    local ownerRow = row and row[1]
    if not ownerRow or ownerRow.license ~= license then
        cb(false)
        return
    end

    local metadata = {}
    local ok, decoded = pcall(json.decode, ownerRow.metadata)
    if ok and type(decoded) == 'table' then
        metadata = decoded
    end
    metadata.PROCESO_ELIMINACION = os.time()

    local updOk = pcall(function()
        MySQL.update.await('UPDATE players SET metadata = ?, cid = NULL WHERE citizenid = ?',
            {json.encode(metadata), citizenid})
    end)
    InvalidateCharacterCache(license)
    if not updOk then
        cb(false)
        return
    end

    local player = QBCore.Functions.GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.citizenid == citizenid then
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
    cb(true)
end)

QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getDeletedCharacters', function(source, cb)
    local license = QBCore.Functions.GetIdentifier(source, 'license')
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
        end
    end
    cb(deletedChars)
end)

RegisterNetEvent('DP-MultiCharacter:server:restoreCharacter', function(citizenid)
    local src = source
    if not citizenid or citizenid == '' then
        return
    end
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local row = MySQL.query.await('SELECT license, metadata FROM players WHERE citizenid = ?', {citizenid})
    local ownerRow = row and row[1]
    if not ownerRow or ownerRow.license ~= license then
        return
    end

    local ok, metadata = pcall(json.decode, ownerRow.metadata)
    if not ok or type(metadata) ~= 'table' or not metadata.PROCESO_ELIMINACION then
        return
    end

    local windowSeconds = (Config.RestoreWindowDays or 5) * 86400
    local elapsed = os.time() - (tonumber(metadata.PROCESO_ELIMINACION) or 0)
    if elapsed >= windowSeconds then
        return
    end

    local maxSlots = Config.DefaultSlots
    if Config.CustomSlots and Config.CustomSlots[license] then
        maxSlots = Config.CustomSlots[license]
    end

    local activeChars = MySQL.query.await('SELECT cid FROM players WHERE license = ? AND cid IS NOT NULL', {license})
    local takenSlots = {}
    for i = 1, #activeChars do
        takenSlots[tonumber(activeChars[i].cid)] = true
    end

    local freeSlot = nil
    for i = 1, maxSlots do
        if not takenSlots[i] then
            freeSlot = i
            break
        end
    end

    if not freeSlot then
        TriggerClientEvent('QBCore:Notify', src, "No tienes ningún slot libre para restaurar este personaje.", "error")
        return
    end
    metadata.PROCESO_ELIMINACION = nil

    pcall(function()
        MySQL.update.await('UPDATE players SET metadata = ?, cid = ? WHERE citizenid = ?',
            {json.encode(metadata), freeSlot, citizenid})
    end)
    InvalidateCharacterCache(license)
    TriggerClientEvent('QBCore:Notify', src, "Personaje restaurado correctamente", "success")
    TriggerClientEvent('DP-MultiCharacter:client:reorderDone', src)
end)

CreateThread(function()
    while true do
        Wait(24 * 60 * 60 * 1000)
        local windowSeconds = (Config.RestoreWindowDays or 5) * 86400
        local ok, result = pcall(MySQL.query.await, 'SELECT citizenid, metadata FROM players', {})
        if ok and result then
            for i = 1, #result do
                local decOk, metadata = pcall(json.decode, result[i].metadata)
                if decOk and type(metadata) == 'table' and metadata.PROCESO_ELIMINACION then
                    if (os.time() - (tonumber(metadata.PROCESO_ELIMINACION) or 0)) >= windowSeconds then
                        HardDeleteCharacterFully(result[i].citizenid, nil)
                    end
                end
            end
        end
    end
end)

QBCore.Functions.CreateCallback('DP-MultiCharacter:server:getSkin', function(source, cb, citizenid)
    local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {citizenid, 1})
    if result[1] ~= nil then
        cb(result[1].model, result[1].skin)
    else
        cb(nil, nil)
    end
end)

RegisterNetEvent('DP-MultiCharacter:server:reorderCharacters', function(order)
    local src = source
    if not CheckRateLimit(src, 'reorder') then
        return
    end
    if not order or type(order) ~= "table" or #order == 0 then
        return
    end
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if not license then
        return
    end

    local updates = {}
    for _, entry in ipairs(order) do
        if tonumber(entry.cid) and entry.citizenid then
            updates[#updates + 1] = {
                query = 'UPDATE players SET cid = ? WHERE citizenid = ? AND license = ?',
                values = {tonumber(entry.cid), entry.citizenid, license}
            }
        end
    end

    if #updates > 0 then
        MySQL.transaction.await(updates)
        InvalidateCharacterCache(license)
        Wait(100)
        TriggerClientEvent('DP-MultiCharacter:client:reorderDone', src)
    end
end)
