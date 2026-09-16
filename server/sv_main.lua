local QBCore = exports['qb-core']:GetCoreObject()
local hasDonePreloading = {}

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🛡️ FUNCIONES DE SEGURIDAD Y VALIDACIÓN
-- ==========================================
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
        -- El nombre no puede contener espacios
        if string.find(name, " ") then
            return false
        end
    end

    -- Comprobación básica de seguridad: no números ni caracteres especiales extraños
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
    -- Se espera formato YYYY-MM-DD
    local y, m, d = dob:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y or not m or not d then
        return false
    end

    local birthYear = tonumber(y)
    local currentYear = tonumber(os.date("%Y"))
    local age = currentYear - birthYear

    -- Comprobación contra Config.MinAge y Config.MaxAge
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
        -- Comprobamos si coincide con el ID ("es") o con la etiqueta ("España")
        if Config.Nationalities[i].id == nat or Config.Nationalities[i].label == nat then
            return true
        end
    end
    return false
end

-- ==========================================
-- ⚙️ LÓGICA CORE DEL SERVIDOR
-- ==========================================
-- Este evento se dispara cuando el usuario selecciona un personaje existente para entrar a jugar
RegisterNetEvent('DP-MultiCharacter:server:loadUserData', function(cData)
    local src = source
    DebugPrint("Evento 'loadUserData' disparado para iniciar sesión. CitizenID: " .. tostring(cData.citizenid))

    -- 1. Intentamos iniciar sesión en QBCore con el citizenid del personaje seleccionado
    if QBCore.Player.Login(src, cData.citizenid) then
        print('^2[QBCore]^7 ' .. GetPlayerName(src) .. ' (Citizen ID: ' .. cData.citizenid ..
                  ') ha cargado exitosamente!')
        DebugPrint("Login exitoso en QBCore para el jugador " .. GetPlayerName(src))

        QBCore.Commands.Refresh(src)

        -- 2. Llamamos a Utils para cargar integraciones como el export de DP-RealMoney
        DebugPrint("Cargando integraciones externas...")
        LoadIntegrations(src, cData)

        -- 3. Buscamos la skin activa en la base de datos para este citizenid
        DebugPrint("Buscando skin activa en la BD para aplicar al spawn.")
        MySQL.query('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {cData.citizenid, 1},
            function(result)
                if result and result[1] then
                    DebugPrint("Skin localizada. Enviando al cliente para aplicarla.")
                    local skinData = json.decode(result[1].skin)
                    local model = result[1].model

                    -- Enviamos la skin al cliente para que se aplique inmediatamente al modelo del jugador
                    TriggerClientEvent('DP-MultiCharacter:client:loadSkinAndSpawn', src, model, skinData, cData)
                else
                    -- Si no tiene skin guardada, procedemos al spawn normal sin skin personalizada
                    DebugPrint("Sin skin guardada. Redirigiendo a ProceedToSpawn normal.")
                    ProceedToSpawn(src, cData)
                end
            end)
    else
        DebugPrint("ERROR: Fallo al ejecutar QBCore.Player.Login con CitizenID: " .. tostring(cData.citizenid))
    end
end)

-- Función auxiliar interna para manejar el spawn de forma limpia
function ProceedToSpawn(src, cData)
    DebugPrint("Ejecutando ProceedToSpawn para el jugador.")
    if Config.SkipSelection then
        DebugPrint("Config.SkipSelection está activo. Retornando a la última ubicación (spawnLastLocation).")
        local coords = json.decode(cData.position)
        TriggerClientEvent('DP-MultiCharacter:client:spawnLastLocation', src, coords, cData)
    else
        DebugPrint("Config.SkipSelection inactivo. Abriendo menú nativo de qb-spawn.")
        TriggerClientEvent('qb-spawn:client:setupSpawns', src, cData, false, nil)
        TriggerClientEvent('qb-spawn:client:openUI', src, true)
    end
end

-- Evento para la creación de un personaje desde 0
RegisterNetEvent('DP-MultiCharacter:server:createCharacter', function(data)
    local src = source
    DebugPrint("Evento 'createCharacter' disparado. Creando nuevo perfil.")

    -- 🚨 COMPROBACIÓN DE RATE LIMIT
    if not CheckRateLimit(src, 'create') then
        TriggerClientEvent('QBCore:Notify', src, "Estás haciendo esto demasiado rápido. Espera unos segundos.",
            "error")
        return
    end

    -- ==============================================================
    -- 🚨 PROTECCIÓN Y VALIDACIÓN SERVER-SIDE ANTI-EXPLOITS
    -- ==============================================================
    if not data or type(data) ~= "table" then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " envió un payload de creación nulo o inválido.")
        DropPlayer(src, "Exploit Detectado: Payload de creación de personaje corrupto.")
        return
    end

    local fname = data.firstname
    local lname = data.lastname
    local dob = data.birthdate
    local gender = tostring(data.gender)
    local nationality = data.nationality

    -- 1. Validar Nombres y Apellidos
    if not ValidateName(fname, false) or not ValidateName(lname, true) then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " introdujo nombre/apellido con formato inválido o longitud extrema.")
        DropPlayer(src, "Validación fallida: Formato de Nombre o Apellido inválido.")
        return
    end

    -- 2. Filtro Anti-Profanidad
    if CheckProfanity(fname) or CheckProfanity(lname) then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " intentó usar palabras bloqueadas (Profanity).")
        DropPlayer(src, "Validación fallida: El nombre contiene palabras no permitidas.")
        return
    end

    -- 3. Validar Fecha de Nacimiento (Rango de Edad)
    if not ValidateDOB(dob) then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " intentó crear un personaje fuera del rango de edad permitido.")
        DropPlayer(src,
            "Validación fallida: Edad del personaje fuera de los límites permitidos (" .. tostring(Config.MinAge) ..
                "-" .. tostring(Config.MaxAge) .. ").")
        return
    end

    -- 4. Validar Nacionalidad
    if not ValidateNationality(nationality) then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " introdujo una nacionalidad no contemplada en el Config.")
        DropPlayer(src, "Validación fallida: Nacionalidad no válida.")
        return
    end

    -- 5. Validar Género (Generalmente QBCore maneja "0" / "1" o "Masculino" / "Femenino")
    if gender ~= "0" and gender ~= "1" and gender ~= "Masculino" and gender ~= "Femenino" then
        print("^1[DP-MultiCharacter | SEGURIDAD] ^7Jugador " .. GetPlayerName(src) ..
                  " intentó inyectar un género no válido.")
        DropPlayer(src, "Validación fallida: Género no válido.")
        return
    end

    local newData = {}
    -- QBCore generará automáticamente el CID y el CitizenID si le pasamos false en la función Login
    newData.cid = data.cid
    newData.charinfo = data

    -- Intentamos iniciar el registro con false
    if QBCore.Player.Login(src, false, newData) then
        print('^2[QBCore]^7 ' .. GetPlayerName(src) .. ' ha creado un nuevo personaje de forma segura.')
        DebugPrint("Personaje registrado exitosamente en QBCore.")

        local license = QBCore.Functions.GetIdentifier(src, 'license')
        if license then
            InvalidateCharacterCache(license)
        end

        QBCore.Commands.Refresh(src)

        -- ==========================================
        -- 📝 REGISTRO DE HISTORIAL Y CREACIÓN
        -- ==========================================
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            -- 1. Guardar la fecha exacta de creación (en memoria)
            Player.Functions.SetMetaData("created_at", os.time() * 1000)

            -- 2. Crear el primer evento del historial (en memoria)
            local initialLog = {{
                date = os.date("%d/%m/%Y, %H:%M:%S"),
                text = "Llegada a la ciudad (Personaje creado).",
                icon = "fa-plane-arrival"
            }}
            Player.Functions.SetMetaData("activityLog", initialLog)
        end

        -- Llamamos a la función abierta en sv_utils.lua pasándole el carrito
        DebugPrint("Otorgando dinero e items iniciales de bienvenida (GiveStarterItems).")
        local cartItems = data.cart or nil
        local cartTotal = tonumber(data.cartTotal) or 0
        GiveStarterItems(src, cartItems, cartTotal)

        -- Mandamos al cliente a la selección de ropa
        DebugPrint("Mandando al jugador al menú de creación de ropa/físico (openClothing).")
        TriggerClientEvent('DP-MultiCharacter:client:openClothing', src)
    else
        DebugPrint("ERROR: Falló el registro de personaje en QBCore.Player.Login.")
    end
end)

-- ==========================================
-- 🌐 MANEJO DE DIMENSIONES (BUCKETS)
-- ==========================================
RegisterNetEvent('DP-MultiCharacter:server:SetBucket', function(bucket)
    local src = source
    DebugPrint("Asignando Routing Bucket (" .. tostring(bucket) .. ") al jugador " .. tostring(src))
    SetPlayerRoutingBucket(src, bucket)
end)

-- ==========================================
-- 🚪 COMANDO DE LOGOUT (CAMBIAR DE PERSONAJE)
-- ==========================================
QBCore.Commands.Add(Config.CommandLogOut, "Cerrar sesión y cambiar de personaje", {}, false, function(source, args)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if Player then
        DebugPrint("Jugador " .. GetPlayerName(src) .. " cerrando sesión mediante comando.")

        -- QBCore.Player.Logout se encarga de guardar todo en la base de datos
        -- (posición, inventario, dinero, etc.) y limpia la sesión activa en el servidor.
        QBCore.Player.Logout(src)

        -- Pequeño margen de seguridad para asegurar que el guardado ha terminado
        Wait(500)

        -- Disparamos el evento cliente que inicia todo el proceso de la UI desde cero
        TriggerClientEvent('DP-MultiCharacter:client:chooseChar', src)
    else
        DebugPrint("Comando de logout usado, pero el jugador no tenía ninguna sesión activa.")
    end
end, "user")
