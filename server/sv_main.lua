local QBCore = exports['qb-core']:GetCoreObject()
local hasDonePreloading = {}
local isSelectingChar = {} -- Guarda quién está en el menú
local characterCreationRequests = {}

local function DebugPrint(msg)
    if Config.Debug or (Config.IntroFlow and Config.IntroFlow.Debug) then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

local profanityList = {"puta", "cabron", "mierda", "admin", "moderator", "nigger", "hitler"}

local function CheckProfanity(text)
    if not text or type(text) ~= "string" then
        return true
    end
    local lowerText = string.lower(text)
    for i = 1, #profanityList do
        if string.find(lowerText, profanityList[i]) then
            return true
        end
    end
    return false
end

local function ValidateName(name, isLastName)
    if not name or type(name) ~= "string" then
        return false
    end
    local len = string.len(name)
    if isLastName then
        if len < 2 or len > 40 then
            return false
        end
    else
        if len < 2 or len > 30 then
            return false
        end
        if string.find(name, " ") then
            return false
        end
    end
    if string.match(name, "%d") then
        return false
    end
    if string.match(name, "[!@#$%%^&*()_=+%[%]{}|\\;:\"',.<>/?`~]") then
        return false
    end
    return true
end

local function ValidateDOB(dob)
    if not dob or type(dob) ~= "string" then
        return false
    end
    local y, m, d = dob:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y or not m or not d then
        return false
    end
    local birthYear = tonumber(y)
    local currentYear = tonumber(os.date("%Y"))
    local age = currentYear - birthYear
    local minAge = Config.MinAge or 18
    local maxAge = Config.MaxAge or 100
    if age < minAge or age > maxAge then
        return false
    end
    return true
end

local function ValidateNationality(nat)
    if not nat or type(nat) ~= "string" then
        return false
    end
    for i = 1, #Config.Nationalities do
        if Config.Nationalities[i].id == nat or Config.Nationalities[i].label == nat then
            return true
        end
    end
    return false
end

RegisterNetEvent('DP-MultiCharacter:server:loadUserData', function(cData)
    local src = source

    if QBCore.Player.Login(src, cData.citizenid) then
        QBCore.Commands.Refresh(src)
        LoadIntegrations(src, cData)

        MySQL.query('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {cData.citizenid, 1},
            function(result)
                if result and result[1] then
                    local skinData = json.decode(result[1].skin)
                    local model = result[1].model
                    TriggerClientEvent('DP-MultiCharacter:client:loadSkinAndSpawn', src, model, skinData, cData)
                else
                    ProceedToSpawn(src, cData)
                end
            end)
    else
        print("^1[FLOW DEBUG] ^7 ERROR: QBCore.Player.Login falló para CitizenID: " ..
                  tostring(cData and cData.citizenid))
    end
end)

function ProceedToSpawn(src, cData)
    local Player = QBCore.Functions.GetPlayer(src)
    if Config.IntroFlow and Config.IntroFlow.Enabled and Player and
        Player.PlayerData.metadata and Player.PlayerData.metadata.introDone == false then
        TriggerClientEvent('DP-MultiCharacter:client:resumeIntro', src, cData)
        return
    end

    if Config.SpawnPoints.SkipSelection then
        local coords = json.decode(cData.position)
        TriggerClientEvent('DP-MultiCharacter:client:spawnLastLocation', src, coords, cData)
    else
        TriggerClientEvent('DP-MultiCharacter:client:openSpawnUI', src)
    end
end

RegisterNetEvent('DP-MultiCharacter:server:createCharacter', function(data)
    local src = source
    if characterCreationRequests[src] then
        DebugPrint(("Petición duplicada de creación ignorada para %s."):format(src))
        return
    end

    if not CheckRateLimit(src, 'create') then
        DebugPrint(("Petición de creación de %s bloqueada por rate limit."):format(src))
        TriggerClientEvent('QBCore:Notify', src, "Estás haciendo esto demasiado rápido. Espera unos segundos.",
            "error")
        return
    end
    characterCreationRequests[src] = true

    if not data or type(data) ~= "table" then
        DropPlayer(src, "Exploit Detectado")
        return
    end
    if not ValidateName(data.firstname, false) or not ValidateName(data.lastname, true) then
        DropPlayer(src, "Nombre inválido")
        return
    end
    if CheckProfanity(data.firstname) or CheckProfanity(data.lastname) then
        DropPlayer(src, "Profanity")
        return
    end
    if not ValidateDOB(data.birthdate) then
        DropPlayer(src, "Edad inválida")
        return
    end
    if not ValidateNationality(data.nationality) then
        DropPlayer(src, "Nacionalidad inválida")
        return
    end

    local newData = {}
    newData.cid = data.cid
    newData.charinfo = data

    if QBCore.Player.Login(src, false, newData) then
        local license = QBCore.Functions.GetIdentifier(src, 'license')
        if license then
            InvalidateCharacterCache(license)
        end
        QBCore.Commands.Refresh(src)

        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.SetMetaData("created_at", os.time() * 1000)
            Player.Functions.SetMetaData("health", 200)
            Player.Functions.SetMetaData("armor", 100)
            Player.Functions.SetMetaData("hunger", 100)
            Player.Functions.SetMetaData("thirst", 100)
            Player.Functions.SetMetaData("stress", 0)
            if Config.IntroFlow and Config.IntroFlow.Enabled then
                Player.Functions.SetMetaData("introDone", false)
                Player.Functions.SetMetaData("introStep", "tailor")
            end
            Player.Functions.SetMetaData("activityLog", {{
                date = os.date("%d/%m/%Y, %H:%M:%S"),
                text = "Llegada a la ciudad.",
                icon = "fa-plane-arrival"
            }})
        end

        GiveStarterItems(src, data.cart, data.cartTotal)

        -- Le decimos al cliente que ya está creado y que abra el selector de spawn.
        TriggerClientEvent('DP-MultiCharacter:client:startSpawnSelection', src)
    else
        characterCreationRequests[src] = nil
        print(("^1[DP-MultiCharacter]^7 QBCore.Player.Login falló al crear personaje para %s."):format(src))
    end
end)

RegisterNetEvent('DP-MultiCharacter:server:SetBucket', function(bucket)
    local src = source
    SetPlayerRoutingBucket(src, bucket)

    -- 🛑 BLOQUEAMOS EL GUARDADO DE QBCORE CUANDO ENTRAMOS A LA SALA OCULTA
    if bucket ~= 0 then
        isSelectingChar[src] = true
    else
        isSelectingChar[src] = nil
    end
end)

AddEventHandler('DP-MultiCharacter:server:bucketStarted', function(src)
    isSelectingChar[src] = true
end)

AddEventHandler('DP-MultiCharacter:server:bucketReleased', function(src)
    isSelectingChar[src] = nil
end)

-- ==========================================
-- 🚪 NUEVO FLUJO DE LOGOUT (BLINDADO CONTRA LA SALA OSCURA)
-- ==========================================
QBCore.Commands.Add(Config.CommandLogOut, "Cerrar sesión", {}, false, function(source, args)
    TriggerClientEvent('DP-MultiCharacter:client:requestLogout', source)
end, "user")

RegisterNetEvent('DP-MultiCharacter:server:performLogout', function(pos, heading, health, armor)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if Player then
        -- 1. Actualizamos la vida y el chaleco en los metadatos antes de guardar
        if health then
            Player.Functions.SetMetaData("health", health)
        end
        if armor then
            Player.Functions.SetMetaData("armor", armor)
        end

        -- 2. COMPROBACIÓN 2D DE SEGURIDAD (Posición)
        local dist = #(vector2(pos.x, pos.y) - vector2(Config.HiddenCoords.x, Config.HiddenCoords.y))

        if dist > 50.0 then
            local safePosition = {
                x = pos.x,
                y = pos.y,
                z = pos.z,
                w = heading
            }
            Player.PlayerData.position = safePosition
            Player.Functions.SetPlayerData("position", Player.PlayerData.position)

            -- Guardamos también directamente por MySQL por redundancia y seguridad
            MySQL.update.await('UPDATE players SET position = ?, last_updated = CURRENT_TIMESTAMP WHERE citizenid = ?',
                {json.encode(safePosition), Player.PlayerData.citizenid})
        else
            print("^3[LOGOUT] Jugador en sala oculta. Conservando última posición real.^7")
        end

        -- 🔥 3. GUARDADO COMPLETO DEL PERSONAJE 🔥
        -- Esto fuerza a QBCore a guardar Inventario, Metadatos, Trabajos, Dinero, etc.
        Player.Functions.Save()

        -- 4. Cerramos sesión y mandamos al selector
        QBCore.Player.Logout(src)
        characterCreationRequests[src] = nil
        Wait(800)
        TriggerClientEvent('DP-MultiCharacter:client:chooseChar', src)
    end
end)

-- Evento para forzar la recarga de personajes cuando el jugador vuelve del mapa
RegisterNetEvent('DP-MultiCharacter:server:refreshCharacters', function()
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    if license then
        -- Invalidamos la caché para que la próxima petición traiga datos frescos
        InvalidateCharacterCache(license)
    end
end)

function SavePlayerPosition(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        return
    end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        -- 🛑 ESCUDO ANTI-SALA OCULTA Y ANTI-VACÍO
        local distToHidden = #(vector3(pos.x, pos.y, pos.z) -
                                 vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z))
        local isDeadOrVoid = (pos.z < -10.0) or (pos.x == 0.0 and pos.y == 0.0)

        if distToHidden > 50.0 and not isDeadOrVoid then
            local safePosition = {
                x = pos.x,
                y = pos.y,
                z = pos.z,
                w = heading
            }
            Player.PlayerData.position = safePosition
            Player.Functions.SetPlayerData("position", Player.PlayerData.position)

            MySQL.update.await('UPDATE players SET position = ?, last_updated = CURRENT_TIMESTAMP WHERE citizenid = ?',
                {json.encode(safePosition), Player.PlayerData.citizenid})
        else
            print("^3[POSICIÓN] Ignorando guardado: El jugador está en la sala oculta o en el vacío.^7")
        end
    end
end

-- Guardar posición al desconectar
AddEventHandler('playerDropped', function()
    local src = source
    characterCreationRequests[src] = nil
    SavePlayerPosition(src)
end)

-- 🛑 ESCUDO ANTI-GUARDADO DE QBCORE EN LA SALA OCULTA
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if isSelectingChar[src] then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            -- Forzamos a QBCore a no guardar la posición actual
            Player.Functions.SetPlayerData("position", Player.PlayerData.position)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000) -- Cada 2 segundos
        for src, isInMenu in pairs(isSelectingChar) do
            if isInMenu then
                local Player = QBCore.Functions.GetPlayer(src)
                if Player then
                    -- Si está en el menú, le forzamos la posición del casino/aeropuerto en memoria
                    -- para que si QBCore guarda, guarde la posición real, no la de la sala oculta.
                    -- (Puedes cambiar esto por la posición que tú quieras).
                    local safePos = {
                        x = -1046.02,
                        y = -2751.97,
                        z = 21.36,
                        w = 326.05
                    }
                    Player.PlayerData.position = safePos
                end
            end
        end
    end
end)

-- 🛑 GUARDADO AUTOMÁTICO DE SALUD CADA 5 MINUTOS (POR SI SE CAE) - ELIMINADO PORQUE GUARDA LA SALA OCULTA
--[[ 
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000) -- 5 minutos
        for _, src in ipairs(GetPlayers()) do
            local Player = QBCore.Functions.GetPlayer(tonumber(src))
            if Player then
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 then
                    local health = GetEntityHealth(ped)
                    local armor = GetPedArmour(ped)
                    MySQL.update.await('UPDATE players SET health = ?, armor = ? WHERE citizenid = ?',
                        {health, armor, Player.PlayerData.citizenid})
                end
            end
        end
    end
end)
]]
