-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Inicializamos los textos para el idioma español dentro de la tabla global Locales
Locales['es'] = {
    ['ui_continue_story_title'] = 'CONTINÚA TU HISTORIA',
    ['ui_continue_story_desc'] = 'Carga inmediata de tu última sesión • Estado, ubicación y activos guardados listos para reanudar el rol sin esperas.',
    ['ui_characters_title'] = 'PERSONAJES',
    ['ui_characters_desc'] = 'Selector de identidades múltiples • Crea nuevos ciudadanos, revisa profesiones, cuentas bancarias y administra tus registros.',
    ['ui_options_title'] = 'OPCIONES',
    ['ui_options_desc'] = 'Panel de control del sistema • Personaliza parámetros gráficos, volumen de audio, efectos de sonido y preferencias del cliente.',
    ['ui_continue_button'] = 'CONTINÚA CON TU HISTORIA',
    ['ui_characters_button'] = 'PERSONAJES',
    ['ui_options_button'] = 'OPCIONES',
    ['ui_move'] = 'MOVER',
    ['ui_select'] = 'SELECCIONAR',
    ['ui_exit'] = 'SALIR',
    ['ui_select_character'] = 'SELECCIONA UN PERSONAJE/SLOT',
    ['ui_profile'] = 'PERFIL',
    ['ui_online'] = 'EN LÍNEA',
    ['ui_identity'] = 'IDENTIDAD',
    ['ui_economy_contact'] = 'ECONOMÍA Y CONTACTO',
    ['ui_affiliations'] = 'AFILIACIONES',
    ['ui_skills'] = 'HABILIDADES',
    ['ui_activity'] = 'ACTIVIDAD',
    ['ui_playtime'] = 'Tiempo jugado:',
    ['ui_last_seen'] = 'Última visita:',
    ['ui_new_character'] = 'NUEVO PERSONAJE',
    ['ui_selected_character'] = 'PERSONAJE SELECCIONADO',
    ['ui_create'] = 'CREAR',
    ['ui_create_character_title'] = 'CREAR PERSONAJE',
    ['ui_firstname'] = 'NOMBRE',
    ['ui_lastname'] = 'APELLIDOS',
    ['ui_birthdate'] = 'FECHA DE NACIMIENTO',
    ['ui_gender'] = 'GÉNERO',
    ['ui_male'] = 'MASCULINO',
    ['ui_female'] = 'FEMENINO',
    ['ui_placeholder_firstname'] = 'Ej: John',
    ['ui_placeholder_lastname'] = 'Ej: Doe Smith',
    ['ui_play'] = 'JUGAR',
    ['ui_delete'] = 'BORRAR',
    ['ui_cancel'] = 'CANCELAR',
    ['ui_confirm'] = 'CONFIRMAR',
    ['ui_empty_slot'] = 'RANURA VACÍA',
    ['ui_delete_title'] = '¿ELIMINAR PERSONAJE?',
    ['ui_delete_warning'] = 'Esta acción no se puede deshacer.',
    ['ui_delete_confirm_btn'] = 'SÍ, BORRAR',
    ['char_deleted'] = 'Personaje eliminado de la base de datos.',
    ['invalid_name'] = 'El nombre o apellido contiene caracteres no válidos.',
    ['profanity_detected'] = 'Se ha detectado una palabra no permitida en tu nombre.',
    ['loading_data'] = 'Cargando información del jugador...'
}

DebugPrint("Diccionario de idioma Español ('es') registrado correctamente.")
