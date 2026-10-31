local QBCore = exports['qb-core']:GetCoreObject()
local hasDonePreloading = {}

local function DebugPrint(msg)
    if Config.Debug then
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
    print("^3[DEBUG POSICION] Iniciando sesión para CID: " .. tostring(cData.citizenid) .. ". Posición en cData: " ..
              tostring(cData.position) .. "^7")

    if QBCore.Player.Login(src, cData.citizenid) then
        print('^2[QBCore]^7 ' .. GetPlayerName(src) .. ' (Citizen ID: ' .. cData.citizenid ..
                  ') ha cargado exitosamente!')
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
    end
end)

function ProceedToSpawn(src, cData)
    if Config.SpawnPoints.SkipSelection then
        local coords = json.decode(cData.position)
        TriggerClientEvent('DP-MultiCharacter:client:spawnLastLocation', src, coords, cData)
    else
        TriggerClientEvent('DP-MultiCharacter:client:setupSpawns', src, cData, false, nil)
        TriggerClientEvent('DP-MultiCharacter:client:openSpawnUI', src)
    end
end

RegisterNetEvent('DP-MultiCharacter:server:createCharacter', function(data)
    local src = source
    if not CheckRateLimit(src, 'create') then
        TriggerClientEvent('QBCore:Notify', src, "Estás haciendo esto demasiado rápido. Espera unos segundos.",
            "error")
        return
    end

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
            local initialLog = {{
                date = os.date("%d/%m/%Y, %H:%M:%S"),
                text = "Llegada a la ciudad.",
                icon = "fa-plane-arrival"
            }}
            Player.Functions.SetMetaData("activityLog", initialLog)
        end

        GiveStarterItems(src, data.cart, data.cartTotal)
        TriggerClientEvent('DP-MultiCharacter:client:openClothing', src)
    end
end)

RegisterNetEvent('DP-MultiCharacter:server:SetBucket', function(bucket)
    SetPlayerRoutingBucket(source, bucket)
end)

-- ==========================================
-- 🚪 NUEVO FLUJO DE LOGOUT (BLINDADO CONTRA LA SALA OSCURA)
-- ==========================================
QBCore.Commands.Add(Config.CommandLogOut, "Cerrar sesión", {}, false, function(source, args)
    print("^3[DEBUG POSICION] Comando /logout ejecutado. Pidiendo coordenadas reales al cliente...^7")
    TriggerClientEvent('DP-MultiCharacter:client:requestLogout', source)
end, "user")

RegisterNetEvent('DP-MultiCharacter:server:performLogout', function(pos, heading)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        print("^3[DEBUG POSICION] El servidor recibe las coordenadas reales del cliente: " .. tostring(pos) .. "^7")

        local dist = #(vector3(pos.x, pos.y, pos.z) -
                         vector3(Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z))
        if dist > 50.0 then
            Player.PlayerData.position = vector4(pos.x, pos.y, pos.z, heading)
            Player.Functions.SetPlayerData("position", Player.PlayerData.position)
            print("^2[DEBUG POSICION] Coordenadas inyectadas en QBCore con éxito. Guardando BD...^7")
        else
            print("^1[DEBUG POSICION] ¡ALERTA! El cliente estaba en la sala oculta. IGNORANDO GUARDADO.^7")
        end

        local license = QBCore.Functions.GetIdentifier(src, 'license')
        if license then
            InvalidateCharacterCache(license)
        end

        QBCore.Player.Logout(src)
        Wait(800) -- Damos tiempo extra a la base de datos
        TriggerClientEvent('DP-MultiCharacter:client:chooseChar', src)
    end
end)
