-- ==========================================
-- 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
-- ==========================================
local function DebugPrint(msg)
    -- Validamos que Config exista, ya que este archivo podría cargar muy pronto
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Creamos la tabla global para almacenar los diccionarios de todos los idiomas
Locales = Locales or {}

-- Función principal para usar traducciones en los scripts Lua (Cliente y Servidor)
-- Recibe el string a traducir y los argumentos opcionales para formatear (ej: %s)
function _U(str, ...)
    local locale = Config.Locale or 'en'

    if Locales[locale] ~= nil then
        if Locales[locale][str] ~= nil then
            -- Devuelve el texto formateado con las variables que le pasemos
            return string.format(Locales[locale][str], ...)
        else
            -- Si falta una traducción específica, avisamos en consola y debug
            DebugPrint("ADVERTENCIA: Faltan traducciones para: [" .. locale .. "][" .. str .. "]")
            print('^3[DP-MultiCharacter] Faltan traducciones para: [' .. locale .. '][' .. str .. ']^7')
            return 'Texto no encontrado: ' .. str
        end
    else
        -- Si el idioma entero no existe en la tabla, lanzamos error crítico
        DebugPrint("ERROR CRÍTICO: El idioma '" .. tostring(locale) .. "' configurado en Config.Locale no existe.")
        print('^1[DP-MultiCharacter] Idioma configurado en Config.Locale no existe.^7')
        return 'Error de idioma'
    end
end

-- Función para exportar la tabla completa al NUI (Javascript/HTML)
-- Se utiliza al inicializar la UI para que todo el texto web se base en el Config.Locale actual
function GetTranslations()
    local locale = Config.Locale or 'en'
    DebugPrint("Exportando traducciones al NUI (Interfaz Web) usando idioma: " .. tostring(locale))
    return Locales[locale] or {}
end
