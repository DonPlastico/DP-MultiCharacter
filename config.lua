Config = {}

Config.Debug = false -- Modo de depuración/debug, no activar a menos que sea necesario. Esto llenada de mensajes de depuración/debug en la consola/F8...

--[[
Configura tu lenguaje usando el código de idioma correspondiente. Por ejemplo:
    'es'  -> Español / Spanish
    'en'  -> Inglés / English
    'it'  -> Italiano / Italian
    'fr'  -> Francés / French
    'de'  -> Alemán / German
    'pt'  -> Portugués / Portuguese
]]

Config.Locale = 'es'

Config.ServerName = 'Servidor de Prueba' -- Nombre del servidor que se mostrará en la pantalla cinematica al seleccionar un personaje para jugar

Config.EnableDeleteButton = true -- ¿Permitir a los jugadores borrar a sus personajes?

Config.DefaultSlots = 2 -- Personajes gratuitos para todos los usuarios (mínimo: 1, máximo: 7)

Config.MinAge = 18 -- Edad mínima que debe tener un personaje para poder crearse (ej: 18 = mayoría de edad legal en España)
Config.MaxAge = 100 -- Edad máxima que se puede seleccionar para un personaje (a efectos de roleplay, no tiene sentido permitir más)
-- El selector de año del calendario de "Fecha de nacimiento" se calcula SIEMPRE en base a estos dos valores y a la fecha actual del servidor.
-- Ejemplo: si hoy es el año 2026 y Config.MinAge = 18, el año más reciente seleccionable será 2008 (2026 - 18).
-- Si Config.MaxAge = 100, el año más antiguo seleccionable será 1926 (2026 - 100). No hace falta tocar nada más, se recalcula solo cada año.

-- Ranuras VIP por licencia de Rockstar
Config.CustomSlots = {
    ['license:1fe52f26d4383515892ef12069befe56f33c421b'] = 7
}

Config.CommandLogOut = 'logout' -- Comando para cerrar sesión y volver a la selección de personajes

Config.Interior = vector3(-1082.23, -74.83, -99.0)

-- Zona donde escondemos al jugador real
Config.HiddenCoords = vector4(-1082.23, -74.83, -105.0, 90.0)

-- Coordenadas individuales para cada slot (separación de 1.15 en el eje Y)
Config.PedCoords = {
    vector4(-1082.23, -77.13, -99.0, 270.0), -- Slot 1 (Izquierda)
    vector4(-1082.23, -75.98, -99.0, 270.0), -- Slot 2 (Centro-Izquierda)
    vector4(-1082.23, -74.83, -99.0, 270.0), -- Slot 3 (Centro)
    vector4(-1082.23, -73.68, -99.0, 270.0), -- Slot 4 (Centro-Derecha)
    vector4(-1082.23, -72.53, -99.0, 270.0) -- Slot 5 (Derecha)
}

-- Separacion constante entre personajes cuando se calcula una distribucion centrada.
Config.PedSpacing = 1.15

-- Cámara más cerca, a la altura del pecho y centrada
Config.CamCoords = vector4(-1078.20, -74.83, -99.0, 90.0)

Config.CharactersAnimations = false -- Si es true, los personajes tendrán animaciones mientras están en la pantalla de selección de personajes. Si es false, los personajes estarán quietos.

Config.CharactersAnimation = {
    idle = {
        dict = "random@streer_race",
        name = "_car_b_lookout"
    },
    select = {
        dict = "anim@heists@ornate_bank@hostages@hit",
        name = "hit_loop_ped_b"
    }
}

Config.SpawnPoints = {
    SkipSelection = true, -- Si es true, spawnea en su última ubicación registrada si no hay script de apartamentos
    DefaultSpawn = vector4(-1046.02, -2751.97, 21.36, 326.05), -- Spawn de emergencia

    {
        label = "spawn_paleto_label",
        description = "spawn_paleto_description",
        image = "img/spawns/Paleto.png",
        coords = vector4(-247.0, 6330.0, 32.50, 225.0)
    },

    {
        label = "spawn_airport_label",
        description = "spawn_airport_description",
        image = "img/spawns/Airport.png",
        coords = vector4(-1046.02, -2751.97, 21.36, 326.05)
    },

    {
        label = "spawn_sandy_label",
        description = "spawn_sandy_description",
        image = "img/spawns/Sandy.png",
        coords = vector4(1839.0, 3672.0, 34.28, 206.35)
    }
}

Config.StartItemsList =
    { -- Items que se le darán al jugador al crear un personaje nuevo. Se pueden agregar más items, pero asegúrate de que existan entre tus items.
    {
        name = "water",
        amount = 5
    }, {
        name = "bread",
        amount = 5
    }, {
        name = "phone",
        amount = 1
    }}

Config.ExportCharacters = true -- Si es true, aparecerá un botón que permitira exportar los personajes que desee el jugador, con un formato xmt (ASIGNANDO UNA ID UNICA POR PERSONAJE). Si es false, no aparecera dicho botón por lo que no permitira exportar ningun personaje

Config.ImportCharacters = true -- Si es true, aparecerá un botón que permitira importar personajes que desee el jugador, pegando un texto xmt que se genera con un export (Si el ID unico no coincide o no lo tiene, no se podrá importar, para evitar gente lista que copia cosas de otros)... Si es false, no aparecera dicho botón por lo que no permitira importar ningun personaje

Config.DefaultMaleModel = 'mp_m_freemode_01' -- Modelo por defecto para personajes masculinos. Puedes cambiarlo a cualquier modelo válido de GTA V, pero asegúrate de que sea un modelo jugable y no un NPC.
Config.DefaultFemaleModel = 'mp_f_freemode_01' -- Modelo por defecto para personajes femeninos. Puedes cambiarlo a cualquier modelo válido de GTA V, pero asegúrate de que sea un modelo jugable y no un NPC.

Config.Nationalities =
    { -- Nacionalidades disponibles para los personajes. Puedes agregar más nacionalidades, pero asegúrate de que tengan un código de país válido.
    {
        label = "Afganistán",
        id = "af"
    }, {
        label = "Albania",
        id = "al"
    }, {
        label = "Alemania",
        id = "de"
    }, {
        label = "Andorra",
        id = "ad"
    }, {
        label = "Angola",
        id = "ao"
    }, {
        label = "Antigua y Barbuda",
        id = "ag"
    }, {
        label = "Arabia Saudita",
        id = "sa"
    }, {
        label = "Argelia",
        id = "dz"
    }, {
        label = "Argentina",
        id = "ar"
    }, {
        label = "Armenia",
        id = "am"
    }, {
        label = "Australia",
        id = "au"
    }, {
        label = "Austria",
        id = "at"
    }, {
        label = "Azerbaiyán",
        id = "az"
    }, {
        label = "Bahamas",
        id = "bs"
    }, {
        label = "Bangladés",
        id = "bd"
    }, {
        label = "Barbados",
        id = "bb"
    }, {
        label = "Baréin",
        id = "bh"
    }, {
        label = "Bélgica",
        id = "be"
    }, {
        label = "Belice",
        id = "bz"
    }, {
        label = "Benín",
        id = "bj"
    }, {
        label = "Bielorrusia",
        id = "by"
    }, {
        label = "Birmania (Myanmar)",
        id = "mm"
    }, {
        label = "Bolivia",
        id = "bo"
    }, {
        label = "Bosnia y Herzegovina",
        id = "ba"
    }, {
        label = "Botsuana",
        id = "bw"
    }, {
        label = "Brasil",
        id = "br"
    }, {
        label = "Brunéi",
        id = "bn"
    }, {
        label = "Bulgaria",
        id = "bg"
    }, {
        label = "Burkina Faso",
        id = "bf"
    }, {
        label = "Burundi",
        id = "bi"
    }, {
        label = "Bután",
        id = "bt"
    }, {
        label = "Cabo Verde",
        id = "cv"
    }, {
        label = "Camboya",
        id = "kh"
    }, {
        label = "Camerún",
        id = "cm"
    }, {
        label = "Canadá",
        id = "ca"
    }, {
        label = "Catar",
        id = "qa"
    }, {
        label = "Chad",
        id = "td"
    }, {
        label = "Chile",
        id = "cl"
    }, {
        label = "China",
        id = "cn"
    }, {
        label = "Chipre",
        id = "cy"
    }, {
        label = "Ciudad del Vaticano",
        id = "va"
    }, {
        label = "Colombia",
        id = "co"
    }, {
        label = "Comoras",
        id = "km"
    }, {
        label = "Corea del Norte",
        id = "kp"
    }, {
        label = "Corea del Sur",
        id = "kr"
    }, {
        label = "Costa de Marfil",
        id = "ci"
    }, {
        label = "Costa Rica",
        id = "cr"
    }, {
        label = "Croacia",
        id = "hr"
    }, {
        label = "Cuba",
        id = "cu"
    }, {
        label = "Dinamarca",
        id = "dk"
    }, {
        label = "Dominica",
        id = "dm"
    }, {
        label = "Ecuador",
        id = "ec"
    }, {
        label = "Egipto",
        id = "eg"
    }, {
        label = "El Salvador",
        id = "sv"
    }, {
        label = "Emiratos Árabes Unidos",
        id = "ae"
    }, {
        label = "Eritrea",
        id = "er"
    }, {
        label = "Eslovaquia",
        id = "sk"
    }, {
        label = "Eslovenia",
        id = "si"
    }, {
        label = "España",
        id = "es"
    }, {
        label = "Estados Unidos",
        id = "us"
    }, {
        label = "Estonia",
        id = "ee"
    }, {
        label = "Esuatini",
        id = "sz"
    }, {
        label = "Etiopía",
        id = "et"
    }, {
        label = "Filipinas",
        id = "ph"
    }, {
        label = "Finlandia",
        id = "fi"
    }, {
        label = "Fiyi",
        id = "fj"
    }, {
        label = "Francia",
        id = "fr"
    }, {
        label = "Gabón",
        id = "ga"
    }, {
        label = "Gambia",
        id = "gm"
    }, {
        label = "Georgia",
        id = "ge"
    }, {
        label = "Ghana",
        id = "gh"
    }, {
        label = "Granada",
        id = "gd"
    }, {
        label = "Grecia",
        id = "gr"
    }, {
        label = "Guatemala",
        id = "gt"
    }, {
        label = "Guinea",
        id = "gn"
    }, {
        label = "Guinea-Bisáu",
        id = "gw"
    }, {
        label = "Guinea Ecuatorial",
        id = "gq"
    }, {
        label = "Guyana",
        id = "gy"
    }, {
        label = "Haití",
        id = "ht"
    }, {
        label = "Honduras",
        id = "hn"
    }, {
        label = "Hungría",
        id = "hu"
    }, {
        label = "India",
        id = "in"
    }, {
        label = "Indonesia",
        id = "id"
    }, {
        label = "Irak",
        id = "iq"
    }, {
        label = "Irán",
        id = "ir"
    }, {
        label = "Irlanda",
        id = "ie"
    }, {
        label = "Islandia",
        id = "is"
    }, {
        label = "Islas Marshall",
        id = "mh"
    }, {
        label = "Islas Salomón",
        id = "sb"
    }, {
        label = "Israel",
        id = "il"
    }, {
        label = "Italia",
        id = "it"
    }, {
        label = "Jamaica",
        id = "jm"
    }, {
        label = "Japón",
        id = "jp"
    }, {
        label = "Jordania",
        id = "jo"
    }, {
        label = "Kazajistán",
        id = "kz"
    }, {
        label = "Kenia",
        id = "ke"
    }, {
        label = "Kirguistán",
        id = "kg"
    }, {
        label = "Kiribati",
        id = "ki"
    }, {
        label = "Kuwait",
        id = "kw"
    }, {
        label = "Laos",
        id = "la"
    }, {
        label = "Lesoto",
        id = "ls"
    }, {
        label = "Letonia",
        id = "lv"
    }, {
        label = "Líbano",
        id = "lb"
    }, {
        label = "Liberia",
        id = "lr"
    }, {
        label = "Libia",
        id = "ly"
    }, {
        label = "Liechtenstein",
        id = "li"
    }, {
        label = "Lituania",
        id = "lt"
    }, {
        label = "Luxemburgo",
        id = "lu"
    }, {
        label = "Macedonia del Norte",
        id = "mk"
    }, {
        label = "Madagascar",
        id = "mg"
    }, {
        label = "Malasia",
        id = "my"
    }, {
        label = "Malaui",
        id = "mw"
    }, {
        label = "Maldivas",
        id = "mv"
    }, {
        label = "Malí",
        id = "ml"
    }, {
        label = "Malta",
        id = "mt"
    }, {
        label = "Marruecos",
        id = "ma"
    }, {
        label = "Mauricio",
        id = "mu"
    }, {
        label = "Mauritania",
        id = "mr"
    }, {
        label = "México",
        id = "mx"
    }, {
        label = "Micronesia",
        id = "fm"
    }, {
        label = "Moldavia",
        id = "md"
    }, {
        label = "Mónaco",
        id = "mc"
    }, {
        label = "Mongolia",
        id = "mn"
    }, {
        label = "Montenegro",
        id = "me"
    }, {
        label = "Mozambique",
        id = "mz"
    }, {
        label = "Namibia",
        id = "na"
    }, {
        label = "Nauru",
        id = "nr"
    }, {
        label = "Nepal",
        id = "np"
    }, {
        label = "Nicaragua",
        id = "ni"
    }, {
        label = "Níger",
        id = "ne"
    }, {
        label = "Nigeria",
        id = "ng"
    }, {
        label = "Noruega",
        id = "no"
    }, {
        label = "Nueva Zelanda",
        id = "nz"
    }, {
        label = "Omán",
        id = "om"
    }, {
        label = "Países Bajos",
        id = "nl"
    }, {
        label = "Pakistán",
        id = "pk"
    }, {
        label = "Palaos",
        id = "pw"
    }, {
        label = "Palestina",
        id = "ps"
    }, {
        label = "Panamá",
        id = "pa"
    }, {
        label = "Papúa Nueva Guinea",
        id = "pg"
    }, {
        label = "Paraguay",
        id = "py"
    }, {
        label = "Perú",
        id = "pe"
    }, {
        label = "Polonia",
        id = "pl"
    }, {
        label = "Portugal",
        id = "pt"
    }, {
        label = "Reino Unido",
        id = "gb"
    }, {
        label = "República Centroafricana",
        id = "cf"
    }, {
        label = "República Checa",
        id = "cz"
    }, {
        label = "República del Congo",
        id = "cg"
    }, {
        label = "República Democrática del Congo",
        id = "cd"
    }, {
        label = "República Dominicana",
        id = "do"
    }, {
        label = "República Sudafricana",
        id = "za"
    }, {
        label = "Ruanda",
        id = "rw"
    }, {
        label = "Rumanía",
        id = "ro"
    }, {
        label = "Rusia",
        id = "ru"
    }, {
        label = "Samoa",
        id = "ws"
    }, {
        label = "San Cristóbal y Nieves",
        id = "kn"
    }, {
        label = "San Marino",
        id = "sm"
    }, {
        label = "San Vicente y las Granadinas",
        id = "vc"
    }, {
        label = "Santa Lucía",
        id = "lc"
    }, {
        label = "Santo Tomé y Príncipe",
        id = "st"
    }, {
        label = "Senegal",
        id = "sn"
    }, {
        label = "Serbia",
        id = "rs"
    }, {
        label = "Seychelles",
        id = "sc"
    }, {
        label = "Sierra Leona",
        id = "sl"
    }, {
        label = "Singapur",
        id = "sg"
    }, {
        label = "Siria",
        id = "sy"
    }, {
        label = "Somalia",
        id = "so"
    }, {
        label = "Sri Lanka",
        id = "lk"
    }, {
        label = "Sudán",
        id = "sd"
    }, {
        label = "Sudán del Sur",
        id = "ss"
    }, {
        label = "Suecia",
        id = "se"
    }, {
        label = "Suiza",
        id = "ch"
    }, {
        label = "Surinam",
        id = "sr"
    }, {
        label = "Tailandia",
        id = "th"
    }, {
        label = "Tanzania",
        id = "tz"
    }, {
        label = "Tayikistán",
        id = "tj"
    }, {
        label = "Timor Oriental",
        id = "tl"
    }, {
        label = "Togo",
        id = "tg"
    }, {
        label = "Tonga",
        id = "to"
    }, {
        label = "Trinidad y Tobago",
        id = "tt"
    }, {
        label = "Túnez",
        id = "tn"
    }, {
        label = "Turkmenistán",
        id = "tm"
    }, {
        label = "Turquía",
        id = "tr"
    }, {
        label = "Tuvalu",
        id = "tv"
    }, {
        label = "Ucrania",
        id = "ua"
    }, {
        label = "Uganda",
        id = "ug"
    }, {
        label = "Uruguay",
        id = "uy"
    }, {
        label = "Uzbekistán",
        id = "uz"
    }, {
        label = "Vanuatu",
        id = "vu"
    }, {
        label = "Venezuela",
        id = "ve"
    }, {
        label = "Vietnam",
        id = "vn"
    }, {
        label = "Yemen",
        id = "ye"
    }, {
        label = "Yibuti",
        id = "dj"
    }, {
        label = "Zambia",
        id = "zm"
    }, {
        label = "Zimbabue",
        id = "zw"
    }}
