local QBCore = exports['qb-core']:GetCoreObject()

-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
-- Esta función imprimirá mensajes en la consola (F8) solo si Config.Debug está activado.
local function DebugPrint(msg)
    if Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- ==========================================
-- 🎬 EVENTOS PRINCIPALES DEL CLIENTE
-- ==========================================
-- Evento principal para iniciar la selección de personaje al entrar al servidor
RegisterNetEvent('DP-MultiCharacter:client:chooseChar', function()
    DebugPrint("Iniciando el proceso de selección de personaje (chooseChar).")

    DoScreenFadeOut(10)
    Wait(1000)

    DebugPrint("Obteniendo y cargando el interior de la ubicación configurada.")
    local interior = GetInteriorAtCoords(Config.Interior.x, Config.Interior.y, Config.Interior.z - 18.9)
    LoadInterior(interior)

    -- Esperamos a que el interior cargue completamente en el cliente
    while not IsInteriorReady(interior) do
        Wait(1000)
        DebugPrint("Esperando a que el interior se cargue completamente...")
    end
    DebugPrint("Interior cargado correctamente.")

    DebugPrint("Teletransportando al jugador a las coordenadas ocultas.")
    SetEntityCoords(PlayerPedId(), Config.HiddenCoords.x, Config.HiddenCoords.y, Config.HiddenCoords.z)
    Wait(1500)

    DebugPrint("Cerrando las pantallas de carga iniciales.")
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    DebugPrint("Activando la interfaz de usuario (UI) principal.")
    ToggleUI(true)
end)

-- ==========================================
-- 🔌 NUI CALLBACKS (Comunicación JS -> LUA)
-- ==========================================
-- Solicitar lista de personajes disponibles y los slots máximos al servidor
RegisterNUICallback('setupCharacters', function(data, cb)
    DebugPrint("NUI Callback: 'setupCharacters' - Solicitando lista de personajes al servidor.")
    QBCore.Functions.TriggerCallback('DP-MultiCharacter:server:setupCharacters',
        function(result, maxSlots, lastCharacter)
            DebugPrint("Lista de personajes recibida. Enviando datos a la interfaz (Slots disponibles: " ..
                           tostring(maxSlots) .. ").")
            SendNUIMessage({
                action = "setupCharacters",
                characters = result,
                slots = maxSlots,
                lastCharacter = lastCharacter
            })
            -- Al recibir la data, spawneamos todos los personajes a la vez
            DebugPrint("Spawneando los peds de los personajes en sus respectivos slots.")
            SpawnAllPeds(result, maxSlots)
            cb("ok")
        end)
end)

-- Previsualizar Ped (Solo para actualizar la sombra al cambiar de género durante la creación)
RegisterNUICallback('previewPed', function(data, cb)
    DebugPrint("NUI Callback: 'previewPed' - Solicitud de previsualización recibida.")
    if data.slot then
        DebugPrint("Actualizando género del ped en el slot " .. tostring(data.slot) .. " al género " ..
                       tostring(data.gender) .. ".")
        UpdatePedGender(data.slot, data.gender)
    end
    cb("ok")
end)

-- Eliminar el Ped al cancelar o salir del proceso de creación
RegisterNUICallback('deletePreview', function(data, cb)
    DebugPrint("NUI Callback: 'deletePreview' - Se ha cancelado la previsualización.")
    -- Lo dejamos así por si cancelan registro, pero los peds los gestiona setupCharacters
    cb("ok")
end)

-- Enviar los datos del formulario de la interfaz al servidor para crear el personaje
RegisterNUICallback('createCharacter', function(data, cb)
    DebugPrint("NUI Callback: 'createCharacter' - Iniciando creación de un nuevo personaje.")
    ToggleUI(false)
    DebugPrint("Interfaz ocultada, eliminando todos los peds en pantalla para entrar al juego.")
    DeleteAllPeds()
    DebugPrint("Enviando petición al servidor para registrar personaje nuevo.")
    TriggerServerEvent('DP-MultiCharacter:server:createCharacter', data)
    cb("ok")
end)

-- Cargar en el mundo un personaje ya existente tras seleccionarlo en la interfaz
RegisterNUICallback('playCharacter', function(data, cb)
    DebugPrint("NUI Callback: 'playCharacter' - Personaje existente seleccionado para jugar.")
    ToggleUI(false)
    DebugPrint("Interfaz ocultada, eliminando los peds de previsualización.")
    DeleteAllPeds()
    DebugPrint("Enviando datos al servidor para iniciar sesión con este personaje.")
    TriggerServerEvent('DP-MultiCharacter:server:loadUserData', data.cData)
    cb("ok")
end)

-- Solicitar al servidor el borrado de un personaje tras confirmación en la UI
RegisterNUICallback('deleteCharacter', function(data, cb)
    DebugPrint("NUI Callback: 'deleteCharacter' - Solicitud para borrar personaje con CitizenID: " ..
                   tostring(data.citizenid))
    TriggerServerEvent('DP-MultiCharacter:server:deleteCharacter', data.citizenid)
    cb("ok")
end)

-- Reproducir sonidos de interfaz (clicks, hover, errores, etc.) para darle estilo al menú
RegisterNUICallback('playSound', function(data, cb)
    PlaySoundFrontend(-1, data.sound, "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
    cb('ok')
end)

-- Muestra un aviso de próximamente si hacen click en la tuerca/ajustes
RegisterNUICallback('openSettings', function(data, cb)
    DebugPrint("NUI Callback: 'openSettings' - Usuario intentó abrir el menú de ajustes.")
    -- En el cliente usamos la función nativa de notificaciones de QBCore
    QBCore.Functions.Notify("Menú de opciones próximamente disponible", "primary")
    cb("ok")
end)

-- Acercar la cámara (Zoom) y enfocar cuando el usuario selecciona un personaje específico
RegisterNUICallback('focusCharacter', function(data, cb)
    DebugPrint("NUI Callback: 'focusCharacter' - Enfocando cámara en el personaje del slot " .. tostring(data.slot))
    FocusCharacter(data.slot)
    cb("ok")
end)

-- Alejar la cámara para restaurar la vista general de todos los personajes
RegisterNUICallback('unfocusCharacter', function(data, cb)
    DebugPrint("NUI Callback: 'unfocusCharacter' - Quitando foco, restaurando vista de cámara general.")
    UnfocusCharacter()
    cb("ok")
end)

-- Reordenar personajes desde la pantalla de Opciones (Drag & Drop)
RegisterNUICallback('reorderCharacters', function(data, cb)
    DebugPrint("NUI Callback: 'reorderCharacters' - Guardando nuevo orden de personajes.")
    if data and data.order then
        TriggerServerEvent('DP-MultiCharacter:server:reorderCharacters', data.order)
    end
    cb("ok")
end)

-- El servidor nos avisa de que la BD ya está actualizada.
-- Enviamos un mensaje al NUI para que pida de nuevo la lista fresca.
RegisterNetEvent('DP-MultiCharacter:client:reorderDone', function()
    DebugPrint("Evento 'reorderDone' recibido. Notificando a la UI para refrescar.")
    SendNUIMessage({
        action = "reorderDone"
    })
end)
