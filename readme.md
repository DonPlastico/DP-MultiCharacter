# DP-MultiCharacter

Sistema de selección y creación de personajes para servidores **QBCore** (FiveM), con una interfaz NUI moderna estilo "launcher cinemático" (cámara, siluetas 3D en el mundo, tarjetas de personaje, panel de estadísticas, drag & drop para reordenar, sistema de traducciones, etc.).

Este documento explica **con detalle** cada archivo del recurso, cómo se comunican Lua ↔ NUI (JavaScript), qué hace cada función, cada botón de la interfaz y cómo configurarlo.

---

## 📂 Estructura del proyecto

```
DP-MultiCharacter/
├── client/
│   ├── cl_main.lua      # Cámara, gestión de peds (personajes 3D), zoom/foco, spawn final
│   ├── cl_events.lua    # Entrada al servidor + NUI Callbacks (JS -> Lua)
│   └── cl_utils.lua     # Utilidades editables (notificaciones, integración con qb-clothes)
├── server/
│   ├── sv_main.lua      # Login/registro de personajes en QBCore, spawn, buckets
│   ├── sv_database.lua  # Consultas SQL: listar, borrar y reordenar personajes
│   └── sv_utils.lua     # Ítems/dinero de bienvenida, integraciones externas
├── locales/
│   ├── sistema.lua      # Motor de traducciones (_U() y GetTranslations())
│   ├── es.lua / en.lua / fr.lua / it.lua / de.lua / pt.lua
├── ui/
│   ├── index.html       # Estructura visual (4 pantallas + modal)
│   ├── style.css        # Todo el diseño visual
│   ├── img/              # Fondos (bg1.jpg, bg2.png, bg3.jpg) e imágenes de spawn
│   └── js/
│       ├── app.js        # Lógica principal del frontend (1480 líneas)
│       ├── sounds.js     # Sonidos de interfaz (hover/click)
│       └── validators.js # Validación del formulario de creación de personaje
├── config.lua            # Toda la configuración del recurso
└── fxmanifest.lua        # Manifiesto de FiveM (scripts, ui_page, dependencias)
```

**Dependencia obligatoria:** `qb-core`. También usa `oxmysql` para las queries SQL, y de forma opcional se integra con `qb-clothing`/`qb-clothes`, `DP-Inventory` y `DP-RealMoney` si están presentes.

---

## 🧠 Filosofía general del sistema

1. Al conectarse, el jugador **no aparece en el mapa real**: se le teletransporta a una sala oculta bajo el mapa (`Config.HiddenCoords`) y se activa una interfaz NUI a pantalla completa.
2. En esa sala se generan hasta N "peds" (modelos 3D) alineados en fila: uno por cada slot de personaje. Los que ya tienen personaje muestran su skin real; los vacíos muestran una **silueta semitransparente ("sombra")**.
3. El jugador navega la interfaz (landing → lista de personajes → crear/jugar), y mientras lo hace, una cámara cinemática Lua se mueve/hace zoom en sincronía con lo que ocurre en el NUI.
4. Al confirmar "Jugar" o "Crear", la UI se cierra, se destruyen los peds de previsualización, y el servidor hace login/registro real en QBCore y hace aparecer al jugador en el mundo.

---

## ⚙️ `fxmanifest.lua`

Define el manifiesto estándar de FiveM:

- `fx_version 'cerulean'`, `game 'gta5'`, `lua54 'yes'`.
- **shared_scripts**: carga `config.lua` y todos los `locales/*.lua` (deben cargar en shared porque tanto cliente como servidor usan `_U()`/`GetTranslations()`).
- **client_scripts**: `cl_main.lua`, `cl_events.lua`, `cl_utils.lua` (en ese orden).
- **server_scripts**: `@oxmysql/lib/MySQL.lua`, `sv_main.lua`, `sv_database.lua`, `sv_utils.lua`.
- **ui_page**: `ui/index.html` (la página NUI que se carga en overlay).
- **files**: todos los assets que el NUI necesita servir (html, css, js, imágenes de fondo).
- **dependencies**: `qb-core`.

---

## 🛠️ `config.lua` — Configuración completa

| Variable | Tipo | Descripción |
|---|---|---|
| `Config.Debug` | bool | Activa logs `[DP-MultiCharacter Debug]` en consola F8 y en consola del servidor. Útil para depurar sin ensuciar la consola en producción. |
| `Config.Locale` | string | Idioma activo (`'es'`, `'en'`, `'it'`, `'fr'`, `'de'`, `'pt'`). |
| `Config.ServerName` | string | Nombre mostrado en la pantalla cinemática al entrar a jugar. |
| `Config.EnableDeleteButton` | bool | Habilita/deshabilita el borrado de personajes desde la UI. |
| `Config.DefaultSlots` | number (1–7) | Slots gratuitos para todos los jugadores. |
| `Config.CustomSlots` | table `[license] = number` | Slots VIP por licencia Rockstar concreta (sobrescribe `DefaultSlots` para esa licencia). |
| `Config.CommandLogOut` | string | Comando de chat para cerrar sesión (`/logout`) y volver al selector. |
| `Config.Interior` | vector3 | Coordenadas del interior que se precarga (`LoadInterior`) para que la sala oculta renderice bien. |
| `Config.HiddenCoords` | vector4 | Coordenadas reales donde se esconde físicamente al jugador mientras ve el menú. |
| `Config.PedCoords` | array de vector4 (5) | Posiciones individuales predefinidas por slot (hasta 5). |
| `Config.PedSpacing` | number | Separación en el eje Y usada para centrar dinámicamente los peds cuando hay más o menos slots que posiciones fijas. |
| `Config.CamCoords` | vector4 | Posición general de la cámara cinemática (vista amplia de todos los personajes). |
| `Config.CharactersAnimations` | bool | Si `true`, los peds en pantalla tendrán animaciones idle en vez de estar estáticos. |
| `Config.CharactersAnimation` | table | Diccionario/nombre de animación para estado `idle` y `select` (uso previsto, no toda la lógica de reproducción está en el código provisto). |
| `Config.SpawnPoints` | table | `SkipSelection` (bool) + `DefaultSpawn` (vector4) + lista de puntos de spawn con `label`, `description`, `image`, `coords` (para cuando `SkipSelection = false` y se delega en `qb-spawn`). |
| `Config.StartItemsList` | array | Ítems que **debería** recibir un personaje nuevo (actualmente definido pero no consumido directamente por `sv_utils.lua`, que reparte ítems fijos — ver sección de servidor). |
| `Config.ExportCharacters` / `Config.ImportCharacters` | bool | Activan/desactivan (a nivel de config) los botones de exportar/importar personajes en formato "xmt". **Nota:** en el JS actual estos botones existen en la UI pero muestran `alert("Próximamente disponible")`; la lógica real de exportación aún no está implementada. |
| `Config.DefaultMaleModel` / `Config.DefaultFemaleModel` | string | Modelos base (`mp_m_freemode_01` / `mp_f_freemode_01`). |
| `Config.Nationalities` | array de `{label, id}` | Lista completa de países (código ISO de 2 letras) usada para el selector de nacionalidad y para pintar banderas vía `flagcdn.com`. |

> ⚠️ **Detalle importante de `Config.SpawnPoints`**: en el archivo tal cual está, hay una tabla anidada sin coma después de `DefaultSpawn = ...` seguida directamente de `{...}` (spawn de Paleto), lo cual en Lua real generaría un error de sintaxis. Si copias/pegas el config literal, revisa que quede así:
> ```lua
> Config.SpawnPoints = {
>     SkipSelection = true,
>     DefaultSpawn = vector4(...),
>     { label = "...", coords = vector4(...) },
>     ...
> }
> ```

---

## 🖥️ Lado SERVIDOR (`server/`)

### `sv_main.lua`

Contiene la lógica **core** de sesión.

- **`DebugPrint(msg)`**: helper interno, imprime con color `^5` solo si `Config.Debug`.

- **`DP-MultiCharacter:server:loadUserData` (evento de red)**
  Se dispara cuando el jugador pulsa "Jugar" sobre un personaje ya existente.
  1. Llama a `QBCore.Player.Login(src, cData.citizenid)`.
  2. Si el login es correcto: imprime en consola, refresca comandos (`QBCore.Commands.Refresh`), llama a `LoadIntegrations` (ver `sv_utils.lua`) y consulta la tabla `playerskins` para ver si hay una skin `active = 1` guardada para ese `citizenid`.
     - Si hay skin: dispara `DP-MultiCharacter:client:loadSkinAndSpawn` al cliente con `model`, `skinData` decodificado y los datos del personaje.
     - Si no hay skin: llama directamente a `ProceedToSpawn(src, cData)`.

- **`ProceedToSpawn(src, cData)`** (función global, no evento)
  - Si `Config.SkipSelection` (dentro de `Config.SpawnPoints`) es `true`: decodifica `cData.position` (JSON) y dispara `DP-MultiCharacter:client:spawnLastLocation` para volver a la última ubicación guardada del personaje.
  - Si es `false`: delega en `qb-spawn`, dos eventos: `qb-spawn:client:setupSpawns` y `qb-spawn:client:openUI`.

- **`DP-MultiCharacter:server:createCharacter` (evento de red)**
  Se dispara al confirmar el formulario de creación de personaje nuevo.
  1. Construye `newData = { cid = data.cid, charinfo = data }`.
  2. Llama `QBCore.Player.Login(src, false, newData)` — pasar `false` como segundo argumento le indica a QBCore que **genere automáticamente** un `citizenid` y registre un personaje nuevo con el `charinfo` recibido.
  3. Si tiene éxito: refresca comandos, llama a `GiveStarterItems(src)` (ver `sv_utils.lua`) y dispara `DP-MultiCharacter:client:openClothing` para mandar al jugador al editor de apariencia (`qb-clothes`).

- **`DP-MultiCharacter:server:SetBucket` (evento de red)**
  Llama `SetPlayerRoutingBucket(src, bucket)`. Se usa para meter a cada jugador en su **propia dimensión** mientras está en el selector, de modo que nadie vea a los demás jugadores ni sus peds de previsualización, y viceversa. Al cerrar la UI se le devuelve al bucket `0` (mundo normal).

### `sv_database.lua`

Todo lo relacionado con la base de datos MySQL (tabla `players` de QBCore, más `playerskins`).

- **Callback `DP-MultiCharacter:server:setupCharacters`** (`QBCore.Functions.CreateCallback`)
  Es la petición que el NUI dispara al abrir la interfaz.
  1. Obtiene la `license` del jugador vía `QBCore.Functions.GetIdentifier`.
  2. Calcula `maxSlots`: usa `Config.CustomSlots[license]` si existe, si no `Config.DefaultSlots`. El resultado se **clampa** siempre entre `MIN_SLOTS = 1` y `MAX_SLOTS = 7` con `math.max`/`math.min`/`math.floor`, avisando por debug si el valor configurado estaba fuera de rango.
  3. Ejecuta un `LEFT JOIN` entre `players` y `playerskins` (filtrando `active = 1`) para traer, en una sola query, tanto los datos del personaje como su skin/modelo activo, ordenado por `cid ASC`.
  4. Por cada fila decodifica los campos JSON (`charinfo`, `money`, `job`, y opcionalmente `gang`/`metadata` si existen).
  5. Llama al callback `cb(plyChars, maxSlots, plyChars[1])` — el tercer argumento (`plyChars[1]`, el personaje con menor `cid`) se usa en el cliente/NUI como **"último personaje"** para el botón "Continuar".

- **`DP-MultiCharacter:server:deleteCharacter` (evento de red)**
  - Comprueba `Config.EnableDeleteButton`; si está desactivado, no hace nada.
  - Si está activado, llama `QBCore.Player.DeleteCharacter(src, citizenid)` (borrado nativo de QBCore) y notifica éxito con `QBCore:Notify`.

- **Callback `DP-MultiCharacter:server:getSkin`**
  Dado un `citizenid`, hace una query directa (`.await`) a `playerskins` y devuelve `model` y `skin` (o `nil, nil` si no hay ninguna activa). No parece estar consumido activamente en el flujo actual del cliente (que ya trae la skin embebida en `setupCharacters`), pero queda disponible como utilidad/API interna.

- **`DP-MultiCharacter:server:reorderCharacters` (evento de red)** — sistema de **Drag & Drop**
  Recibe un array `order = [{cid, citizenid}, ...]` con el nuevo orden deseado (ya calculado en el frontend).
  1. Valida que el payload sea una tabla no vacía.
  2. Obtiene la `license` del jugador.
  3. Construye una lista de `UPDATE players SET cid = ? WHERE citizenid = ? AND license = ?` por cada entrada válida.
  4. Ejecuta **todo en una única transacción** (`MySQL.transaction.await`) para que sea atómico: si algo falla, no queda la BD en un estado inconsistente a medias.
  5. Espera 100ms de margen de seguridad.
  6. Dispara `DP-MultiCharacter:client:reorderDone` al cliente (que a su vez reenvía el mensaje al NUI) y manda una notificación `QBCore:Notify` de éxito.

### `sv_utils.lua`

Funciones auxiliares "abiertas" pensadas para que el dueño del recurso las edite fácilmente.

- **`GiveStarterItems(source)`**
  - Añade dinero fijo: **5000 al banco** y **500 en efectivo** (`Player.Functions.AddMoney`). *Nota: estos valores están hardcodeados, no leen de `Config.StartItemsList` (que solo define ítems, no dinero); si quieres que el dinero también sea configurable habría que enlazarlo manualmente aquí.*
  - Construye un objeto `info` con `citizenid`, `firstname`, `lastname`, `birthdate`, `gender`, `nationality` (para usar como metadata de una tarjeta de identidad).
  - Llama a `exports['DP-Inventory']:AddItem` dos veces: un `id_card` (con la `info` como metadata) y un `phone`. **Requiere el recurso externo `DP-Inventory`.**

- **`LoadIntegrations(source, cData)`**
  Comprueba si el recurso `DP-RealMoney` está corriendo (`GetResourceState(...) ~= 'missing'`). Si es así, llama tres exports para sincronizar el HUD de dinero: `cash`, `black_money`, `crypto`. Si no está presente, simplemente lo omite (no rompe nada).

---

## 🎮 Lado CLIENTE (`client/`)

### `cl_main.lua` — cámara, peds y ciclo de vida del mundo 3D

Variables de módulo: `cam` (handle de la cámara), `charPeds` (tabla `slot -> {entity, isShadow}`), `activePedCoords` (coordenadas realmente usadas por slot, ya centradas).

- **`ToggleUI(state)`**
  Función central que abre/cierra toda la experiencia:
  - `SetNuiFocus(state, state)`: da/quita el foco de mouse+teclado al NUI.
  - Envía un mensaje `toggleUI` al NUI con `state`, `debug` (el `Config.Debug` actual), `translations` (diccionario completo vía `GetTranslations()`) y `nationalities` (`Config.Nationalities`).
  - Si `state = true`: oculta el chat (`chat:client:showChat(false)`, `chat:clear`) y manda al jugador a un **routing bucket único** vía `DP-MultiCharacter:server:SetBucket`.
  - Si `state = false`: reactiva el chat y devuelve al bucket `0`.
  - Llama siempre a `SetupCamera(state)`.

- **`SetupCamera(state)`**
  - Al **abrir** (`state = true`): fade-in de pantalla, congela y hace invencible al ped real del jugador, oculta HUD/radar, crea una cámara con `CreateCamWithParams` en `Config.CamCoords` y la activa (`RenderScriptCams`). Lanza además un **hilo en bucle** que, mientras exista `cam`, fuerza a `0.0` todos los multiplicadores de densidad de peds/vehículos del juego — así ningún NPC ni tráfico aparece de fondo mientras se ve el menú.
  - Al **cerrar** (`state = false`): fade-out (500ms), espera, restaura HUD/radar y destruye la cámara.

- **`UpdatePedGender(slot, gender)`**
  Se usa **solo sobre siluetas ("sombra")**: si el slot no existe o no es sombra, no hace nada. Si lo es, calcola el modelo (`mp_m_freemode_01` o `mp_f_freemode_01` según `gender`), lo pre-carga (`RequestModel` con timeout de 5s), borra la entidad sombra anterior y crea una nueva en las mismas coordenadas, con alpha reducido (`150`) para dar el efecto translúcido característico.

- **Sistema de foco/zoom** (`lastFocusedSlot`, `FocusCharacter`, `UnfocusCharacter`)
  - **`FocusCharacter(slot)`**: mueve suavemente la cámara (`SetCamParams`, 800ms) hacia el personaje del slot indicado, acercándose en X y apuntando a la altura del pecho. Tras ese tiempo (usando un `CreateThread` con `Wait(800)`), **oculta** (alpha `0`) a todos los demás peds para centrar visualmente la atención — pero solo si el slot enfocado sigue siendo el mismo (evita condiciones de carrera si el jugador cambia de personaje muy rápido).
  - **`UnfocusCharacter()`**: restaura la visibilidad de todos los peds (alpha `150` si son sombra, alpha normal si son reales) y regresa la cámara a la vista general (`Config.CamCoords`).

- **`GetCharacterBySlot(characters, slot)`** (local): busca en el array de personajes cuál tiene `cid == slot`.

- **`GetCenteredPedCoords(slot, totalSlots)`** (local): calcula dinámicamente la posición en el eje Y de cada ped para que el conjunto quede siempre centrado respecto al slot 3 (`Config.PedCoords[3]`), usando `Config.PedSpacing` como separación constante — así funciona igual de bien con 1 slot que con 7.

- **`SpawnAllPeds(characters, maxSlots)`**
  Limpia todo con `DeleteAllPeds()`, y por cada slot de `1` a `maxSlots` calcula sus coordenadas centradas y llama a `SpawnSinglePed`, pasando los datos reales del personaje si existe, o `nil`/`isShadow = true` si el slot está vacío.

- **`DeleteAllPeds()`**
  Borra físicamente todas las entidades guardadas en `charPeds` y resetea la tabla + `lastFocusedSlot`.

- **`SpawnSinglePed(slot, gender, customModel, skinData, coords, isShadow)`**
  - Resuelve el modelo: por género por defecto, o `customModel` (acepta tanto hash numérico como nombre string vía `joaat`), con fallback si el modelo resultante es inválido (`IsModelInCdimage`/`IsModelValid`).
  - Crea el ped (`CreatePed`), lo congela, invencible y bloquea eventos no temporales.
  - Si es sombra: alpha `150` y variación de componentes por defecto (silueta genérica).
  - Si no es sombra y trae `skinData`: dispara `qb-clothing:client:loadPlayerClothing` para vestirlo con su ropa real guardada.
  - Guarda `{entity, isShadow}` en `charPeds[slot]`.

- **`SpawnPreviewPed(gender, customModel, skinData)`** — función **legacy/alternativa**, no forma parte del flujo principal de múltiples slots (usa una única variable global `charPed` y coordenadas fijas `Config.PedCoords.x/y/z` en vez de la tabla indexada). Se mantiene en el código pero el flujo activo real pasa por `SpawnAllPeds`/`SpawnSinglePed`.

- **Hilo de arranque**: en un `CreateThread`, hace polling (`Wait(0)`) hasta que `NetworkIsSessionStarted()` sea verdadero, y entonces dispara `DP-MultiCharacter:client:chooseChar` una única vez (`return` corta el hilo).

- **`DP-MultiCharacter:client:spawnLastLocation` (evento de red)**
  Teletransporte final y real del jugador al mundo:
  1. Si no hay coordenadas válidas (nuevas, corruptas, o de tipo incorrecto), usa `Config.DefaultSpawn`.
  2. **Bloqueo de seguridad**: si las coordenadas objetivo están a menos de 50 unidades de `Config.HiddenCoords`, se sustituyen por `Config.DefaultSpawn` (evita que un personaje "nuevo" sin posición guardada termine cayendo literalmente en la sala oculta del selector).
  3. Congela al ped, mueve sus coordenadas, calcula el heading (soporta `w`, `h`, `a` o `heading` según el formato de origen de los datos).
  4. Pide carga de colisión (`RequestCollisionAtCoord`) y espera hasta 3s a que el suelo esté listo (`HasCollisionLoadedAroundEntity`).
  5. Ajusta la posición exacta sobre el suelo (`SetEntityCoordsNoOffset`).
  6. Hace visible, descongela, quita invencibilidad, limpia animaciones de caída.
  7. Dispara los eventos estándar de QBCore (`QBCore:Server:OnPlayerLoaded`, `QBCore:Client:OnPlayerLoaded`) y hace fade-in final.

- **`DP-MultiCharacter:client:loadSkinAndSpawn` (evento de red)**
  Aplica el **modelo definitivo** del jugador (no ya el ped de previsualización, sino su propio personaje jugable): pide y espera el modelo, `SetPlayerModel`, libera el modelo de memoria (`SetModelAsNoLongerNeeded`), aplica la ropa guardada vía `qb-clothing:client:loadPlayerClothing`, y finalmente decide si ir directo a `spawnLastLocation` (si `SkipSelection`) o abrir el selector nativo de `qb-spawn`.

- **`onResourceStop`**: rutina de limpieza si el script se reinicia con el menú abierto — borra todos los peds, la cámara, y restaura HUD/radar/movimiento del jugador para que no queden NPCs "sueltos" caminando por el mapa.

### `cl_events.lua` — puente NUI ↔ Lua

- **`DP-MultiCharacter:client:chooseChar` (evento de red)**
  Flujo de entrada: fade-out, carga el interior configurado (`LoadInterior`, esperando con `IsInteriorReady`), teletransporta al jugador a `Config.HiddenCoords`, cierra las pantallas de carga nativas (`ShutdownLoadingScreen(Nui)`), y finalmente llama `ToggleUI(true)`.

- **NUI Callbacks** (`RegisterNUICallback`) — cada uno recibe `data` desde el JS y un callback `cb` que **debe** llamarse para que `axios` resuelva la promesa en el frontend:

  | Callback | Qué hace |
  |---|---|
  | `setupCharacters` | Llama al callback de servidor `DP-MultiCharacter:server:setupCharacters`, reenvía el resultado al NUI (`action: "setupCharacters"`) y llama `SpawnAllPeds` con los datos recibidos. |
  | `previewPed` | Llama `UpdatePedGender(data.slot, data.gender)` — usado al elegir género en el formulario de creación. |
  | `deletePreview` | No-op actualmente (placeholder para cancelar previsualización). |
  | `createCharacter` | Cierra la UI (`ToggleUI(false)`), borra todos los peds, y reenvía `data` al servidor vía `DP-MultiCharacter:server:createCharacter`. |
  | `playCharacter` | Igual que arriba pero dispara `DP-MultiCharacter:server:loadUserData` con `data.cData`. |
  | `deleteCharacter` | Reenvía `data.citizenid` a `DP-MultiCharacter:server:deleteCharacter`. |
  | `playSound` | Reproduce un sonido de frontend nativo (`PlaySoundFrontend`) — usado por `sounds.js`. |
  | `openSettings` | Muestra una notificación QBCore "Próximamente disponible" (placeholder del botón de ajustes). |
  | `focusCharacter` | Llama `FocusCharacter(data.slot)`. |
  | `unfocusCharacter` | Llama `UnfocusCharacter()`. |
  | `reorderCharacters` | Reenvía `data.order` a `DP-MultiCharacter:server:reorderCharacters`. |

- **`DP-MultiCharacter:client:reorderDone` (evento de red)**: reenvía un simple `{action: "reorderDone"}` al NUI para que la interfaz sepa que ya puede pedir datos frescos.

### `cl_utils.lua`

- **`SendNotify(msg, type)`**: wrapper centralizado sobre `QBCore.Functions.Notify`, pensado para poder sustituir el sistema de notificaciones (ej. por `ox_lib`) editando un único punto.
- **`DP-MultiCharacter:client:openClothing` (evento de red)**: tras crear un personaje nuevo, dispara `qb-clothes:client:CreateFirstCharacter` para abrir el editor de apariencia inicial. *(Si tu servidor usa `illenium-appearance` u otro sistema de ropa, este es el único punto que hay que tocar.)*

---

## 🌍 Sistema de idiomas (`locales/`)

### `sistema.lua` — motor de traducción

- `Locales` es la tabla global donde cada idioma (`es`, `en`, etc.) registra su propio diccionario.
- **`_U(str, ...)`**: función de traducción para usar **dentro de Lua** (cliente o servidor). Busca `Locales[Config.Locale][str]`, y si existe la formatea con `string.format` (soporta `%s`, `%d`, etc. como argumentos extra). Si falta la clave, imprime una advertencia en consola y devuelve un string de aviso en vez de romper el script. Si el idioma configurado no existe en absoluto, imprime un error crítico.
- **`GetTranslations()`**: devuelve la tabla completa del idioma activo — es lo que `cl_main.lua` envía al NUI dentro de `ToggleUI` para que el frontend traduzca toda la interfaz de una sola vez.

### Archivos de idioma (`es.lua`, `en.lua`, `fr.lua`, `it.lua`, `de.lua`, `pt.lua`)

Cada uno registra `Locales['<código>'] = { clave = 'texto', ... }`. Claves relevantes (ejemplo en español):

- Landing: `ui_continue_story_title/desc`, `ui_characters_title/desc`, `ui_options_title/desc`, `ui_continue_button`, `ui_characters_button`, `ui_options_button`.
- HUD de selección: `ui_move`, `ui_select`, `ui_exit`, `ui_select_character`.
- Panel de detalle: `ui_profile`, `ui_online`, `ui_identity`, `ui_economy_contact`, `ui_affiliations`, `ui_skills`, `ui_activity`, `ui_playtime`, `ui_last_seen`.
- Acciones: `ui_new_character`, `ui_selected_character`, `ui_create`, `ui_play`, `ui_delete`, `ui_cancel`, `ui_confirm`.
- Formulario de creación: `ui_create_character_title`, `ui_firstname`, `ui_lastname`, `ui_birthdate`, `ui_gender`, `ui_male`, `ui_female`, placeholders.
- Modal de borrado: `ui_delete_title`, `ui_delete_warning`, `ui_delete_confirm_btn`.
- Mensajes de sistema: `char_deleted`, `invalid_name`, `profanity_detected`, `loading_data`.

Para añadir un idioma nuevo: duplica cualquier archivo, tradúcelo, cárgalo en `fxmanifest.lua` (`shared_scripts`) y pon su código en `Config.Locale`.

---

## 🖼️ La interfaz (`ui/`)

`ui/index.html` contiene **cuatro pantallas** (contenedores `.screen-container` que se muestran/ocultan con `showScreen()`), más un modal:

1. **`#landing-screen`** — Menú principal con 3 tarjetas grandes: *Continuar historia*, *Personajes*, *Opciones*. Cada una tiene fondo (`.landing-bg`) e imagen de carátula (`.landing-image-card`) con reflejo (`.landing-reflection-card`), que se resaltan según cuál está activa. El botón "Continuar" (`#btn-land-play`) aparece deshabilitado (`.disabled`) si el jugador no tiene ningún personaje aún.
2. **`#character-list`** — Pantalla de selección: `#slots-wrapper` (fila horizontal de slots generados dinámicamente), `#detailed-char-info` (panel lateral con toda la info del personaje enfocado) y `#action-buttons` (botón central Jugar/Crear + flechas de navegación).
3. **`#options-screen`** — Panel de administración personal: sidebar con secciones (Personajes, Preferencias, Soporte), estadísticas (`#stat-active-chars`, `#stat-available-slots`, `#stat-total-slots`) y una **tabla** completa de personajes (`#options-characters-table`) con buscador, orden por columnas y reordenamiento por arrastre.
4. **`#character-register`** — Formulario de creación: nombre, apellidos, selector de nacionalidad (con banderas y buscador), fecha de nacimiento, género.
5. **`#delete-modal`** — Modal de confirmación de borrado (`.modal-overlay`).

`ui/style.css` (52K) contiene todo el diseño: fondos con overlay, animaciones de "shine" en las tarjetas del landing, estilos de la tabla de opciones (incluyendo estado de arrastre `.dragging`/`.drag-over`), paneles con blur, badges de trabajo/banda, barras de progreso de habilidades, etc.

### `ui/js/sounds.js`

Módulo `Sounds` con 3 métodos (`playNav`, `playSelect`, `playCancel`) que hacen `axios.post` al callback Lua `playSound`. Se enganchan **listeners globales** a nivel de `document.body`:
- `mouseover` sobre cualquier `button`, `.char-slot` o `.gender-btn` → sonido de navegación.
- `click` sobre esos mismos elementos → sonido de selección, **salvo** si el elemento tiene clase `.btn-danger` o es `#btn-cancel-reg`/`#btn-modal-cancel`, en cuyo caso suena "cancelar".

### `ui/js/validators.js`

Módulo `Validator`, totalmente independiente de la UI (solo lógica pura):

- `profanityList`: lista negra básica de palabras prohibidas (ampliable).
- `validateName(name)`: regex solo-letras (con acentos/ñ), longitud 2–30, sin espacios — para el nombre.
- `validateLastName(lastName)`: regex letras + espacios, longitud 2–40 — para apellidos compuestos.
- `checkProfanity(text)`: comprueba si el texto (en minúsculas) contiene alguna palabra de la lista negra.
- `validateForm(firstname, lastname, dob, gender, nationality)`: validación conjunta que se llama al pulsar "Crear". Devuelve `{valid: true}` o `{valid: false, msg: "..."}` con el primer error encontrado (campos vacíos → formato de nombre → formato de apellido → palabras prohibidas).

### `ui/js/app.js` — el corazón del frontend (≈1480 líneas)

#### Estado global

```js
resName              // nombre del recurso (para las rutas axios.post)
charactersData        // array con todos los personajes del jugador (tal cual llega del server)
selectedSlot           // slot actualmente seleccionado/enfocado
selectedGender          // género elegido en el formulario de creación
maxSlots                // nº de slots permitidos para este jugador
currentLandingIndex     // 0=Jugar, 1=Personajes, 2=Opciones (landing)
isZoomed                // true si la cámara está haciendo zoom sobre un personaje
isUnfocusing             // true mientras la cámara vuelve a la vista general (anti-glitch)
DEBUG_MODE               // refleja Config.Debug, recibido desde Lua
translations              // diccionario de idioma activo
selectedNationality        // id de país elegido
nationalitiesData           // lista completa de países (de Config.Nationalities)
lastCharacter                // personaje con menor cid, usado por "Continuar"
```

#### Comunicación NUI ↔ Lua

Todo mensaje **Lua → JS** llega vía `window.addEventListener('message', ...)`, comparando `data.action`:

| `action` recibida | Efecto en el frontend |
|---|---|
| `toggleUI` | Actualiza `DEBUG_MODE`, `translations` (+ aplica `applyTranslations()`), `nationalitiesData` (+ `renderNationalities()`), muestra/oculta `#app`. Si se abre: `showScreen('landing-screen')`, randomiza los destellos de las tarjetas y pide `setupCharacters` al Lua. Si se cierra: `resetForm()`. |
| `setupCharacters` | Guarda `charactersData`, `maxSlots`, `lastCharacter`; llama `renderSlots()`, `updateLandingScreen()`, `updateOptionsStats()` y, si la pantalla de Opciones está visible, refresca su tabla. |
| `showLanding` / `hideLanding` | Muestra/oculta directamente `#landing-screen` (uso puntual/externo). |
| `reorderDone` | Vuelve a pedir `setupCharacters` para sincronizar tras un reordenamiento. |

Todo mensaje **JS → Lua** se hace con `axios.post(`https://${resName}/<callback>`, JSON.stringify(payload))`, correspondiéndose 1 a 1 con los `RegisterNUICallback` de `cl_events.lua` listados más arriba.

#### Navegación del Landing (ratón + teclado)

- Clic en cualquiera de las 3 tarjetas de imagen o en los botones inferiores cambia `currentLandingIndex`, actualiza fondo, tarjeta activa y reflejo activo (`updateLandingHover`).
- Flechas ← → cambian de tarjeta (con límite: si no hay personajes, no se puede ir al índice 0 "Continuar"). Enter simula clic en el botón resaltado.
- `Escape` tiene comportamiento contextual según qué pantalla/estado esté activo: cierra el modal de borrado, cancela el formulario de registro, sale de Opciones al landing, o — si está en la lista de personajes con zoom activo — deshace el zoom (restaura cámara, oculta panel, vuelve a mostrar slots) antes de, en un segundo `Escape`, volver al landing.
- Con el panel enfocado (`isZoomed`), ← → navegan entre personajes (`navigateCharacter`) y Enter simula clic en el botón principal de acción.

#### Selección y zoom de personajes

- **`selectSlot(slotId, animateDirection)`**: marca visualmente el slot activo, oculta el título superior, muestra la botonera de acción, oculta el contenedor de slots (mientras la cámara hace zoom), pide `focusCharacter` al Lua, y decide el contenido del panel lateral: si el slot tiene personaje, `updateDetailedPanel(charData)`; si está vacío, prepara el modo "crear" y pide una previsualización de silueta masculina por defecto. Si se está navegando entre personajes ya con el panel abierto (`animateDirection != 0`), aplica un pequeño **crossfade** (`content-fading`, 140ms) en vez de recargar todo el panel de golpe.
- **`navigateCharacter(direction)` / `processNavQueue()`**: sistema de **cola de navegación** — si el jugador pulsa flechas muy rápido, cada pulsación se encola (`navQueue`) y se procesa una a una respetando `NAV_STEP_DURATION` (850ms, sincronizado con la duración de la animación de cámara en Lua), para que la cámara "recorra" visualmente cada personaje intermedio en vez de saltar de golpe.
- **`pulseArrow(direction)`**: añade brevemente la clase `.pressed` a la flecha correspondiente para dar feedback visual del input.

#### Panel de detalle (`updateDetailedPanel`)

Rellena dinámicamente:
- **Identidad**: nombre completo, fecha de nacimiento, nacionalidad (buscada en `nationalitiesData` por id), género.
- **Economía y contacto**: cash, banco (formateados con separador de miles), teléfono (con fallback a `metadata.phonedata.SerialNumber` si el campo directo no existe).
- **Afiliaciones**: fila de trabajo (oculta si `job.name === "unemployed"`, con badge "JEFE" si `isboss`), fila de banda ilegal (oculta si `gang.name === "none"`, badge "LÍDER" si `isboss`). El grupo entero se oculta si no hay ni trabajo ni banda.
- **Habilidades**: lee `metadata.skills`/`metadata.Skills` (soporta que venga como string JSON escapado), genera dinámicamente una barra de progreso por habilidad con icono (mapa de iconos predefinido para `strength`, `cardio`, `driving`, `shooting`, `farming`, `fishing`, `mining`, `crafting`, `gathering`, con `fa-star` como fallback), y anima el llenado de las barras 100ms después de insertarlas en el DOM.
- **Actividad**: tiempo jugado (`metadata.playtime` en segundos, convertido a horas/minutos) y última visita (`formatDateTime(charData.last_updated)`).

#### Formulario de creación

- Botones de género (`.gender-btn`) alternan clase `.active`, guardan `selectedGender` y piden un `previewPed` actualizado a Lua.
- Selector de nacionalidad **custom** (no un `<select>` nativo): al hacer clic en `#nationality-display` se abre/cierra un dropdown (`#nationality-dropdown`) con buscador en tiempo real (filtra por id de país o nombre) y banderas cargadas desde `flagcdn.com` (con fallback textual si la imagen falla). Clic fuera del wrapper lo cierra.
- Al pulsar **Crear** (`#btn-create-reg`): recoge los valores, ejecuta `Validator.validateForm(...)`; si falla muestra un `alert` con el mensaje de error y no continúa. Si pasa, construye el payload (`cid`, `firstname`, `lastname`, `birthdate`, `gender` como `0`/`1`, `nationality`) y lo envía vía `createCharacter`, reseteando después el formulario.
- **Cancelar** (`#btn-cancel-reg`): vuelve a la lista de personajes, limpia el panel/estado de zoom, notifica `deletePreview` a Lua y pide `unfocusCharacter` para alejar la cámara (con el mismo patrón de `setTimeout(UNFOCUS_DURATION)` usado en otros puntos para esperar a que la animación de cámara termine antes de re-mostrar los slots).

#### Borrado de personaje

Flujo con modal de confirmación (`#delete-modal`): el botón de borrar dentro del panel lateral, o el botón de la tabla de Opciones, abren el modal. `#btn-modal-cancel` lo cierra sin hacer nada; `#btn-modal-confirm` envía `deleteCharacter` a Lua, cierra el panel, deshace el zoom y — tras esperar a que la cámara termine de alejarse — vuelve a pedir `setupCharacters` para refrescar la lista completa (nuevos slots vacíos, stats, tabla, etc.).

#### Pantalla de Opciones (`OptionsTable`, IIFE encapsulado)

Módulo autocontenido con estado privado (`sortState`, `searchQuery`, `dragSrcCid`, `els`):

- **`getProcessedRows()`**: filtra `charactersData` por texto de búsqueda (nombre completo, `cid` o `citizenid`) y ordena según `sortState` (`key`: `cid`/`name`/`citizenid`, `dir`: `asc`/`desc`).
- **`render()`**: reconstruye toda la tabla (`<tbody>`) a partir de la lista procesada. Si está vacía, muestra el estado vacío (`#table-empty-state`) con mensaje distinto según haya o no búsqueda activa. Cada fila incluye: manija de arrastre, badge del slot (`#cid`), nombre, citizenid, y botones de exportar/borrar. Actualiza también los iconos de ordenación (`fa-sort-up`/`fa-sort-down`) en las cabeceras.
- **Drag & Drop manual con eventos de ratón** (no usa la API HTML5 nativa de drag, por fiabilidad dentro de CEF/NUI):
  - `mousedown` sobre `.drag-handle` → `handleDragStart`: crea un elemento "fantasma" (clon flotante que sigue al cursor) y engancha listeners globales de `mousemove`/`mouseup`.
  - `handleDragMove`: mueve el fantasma y detecta sobre qué fila está el cursor (comparando `getBoundingClientRect()`), marcándola con `.drag-over`.
  - `handleDragEnd`: si se soltó sobre una fila distinta a la de origen, reordena `charactersData` en memoria (`splice`), **reasigna los `cid` secuencialmente** (`1..N`), vuelve a renderizar inmediatamente (UI optimista) y envía el nuevo orden a Lua vía `reorderCharacters`; tras confirmar, pide `setupCharacters` de nuevo para sincronizar con la BD real.
- **Ordenación por cabecera** (`handleSortClick`): clic en un `<th data-sort="...">` alterna dirección si ya era la columna activa, o la selecciona en ascendente si es una columna nueva.
- **Búsqueda** (`handleSearch`): input en tiempo real sobre `#table-search`.
- **`init()`**: cachea referencias DOM y engancha los listeners de cabecera/buscador.
- API pública expuesta: `init`, `render`, `reset()` (limpia búsqueda y orden, útil al reabrir la pantalla), `setData()` (alias de `render` para cuando cambian los datos externamente).

**Botones de Opciones actualmente en estado "placeholder"** (muestran `alert("Próximamente disponible")` o similar, sin lógica real implementada todavía): Importar/Exportar múltiples personajes, Comprar slots, Restaurar personaje, Marcar favorito, Exportar/Importar personaje individual, Personaje por defecto, Spawn preferido, Ocultar bloqueados, Sonidos de interfaz (toggle), Discord, Términos del servidor. El botón **Reportar bug** también es un placeholder pero menciona una integración futura con `DP-AdminMenu`.

#### Funciones de apoyo globales

- **`showScreen(screenId)`**: oculta las 4 pantallas y muestra solo la solicitada; gestiona además qué fondo (`.landing-bg`) debe estar visible según el contexto.
- **`updateLandingScreen()`**: habilita/deshabilita el botón "Continuar" según exista o no `lastCharacter`, actualiza el nombre mostrado, y si no hay ningún personaje fuerza el foco inicial a la tarjeta "Personajes" (índice `1`) en vez de "Continuar".
- **`formatDateTime(value)`**: formatea una fecha a `DD/MM/AAAA, HH:MM:SS`; si el valor no es una fecha válida, lo devuelve tal cual.
- **`renderSlots()`**: reconstruye el HTML de `#slots-wrapper` según `maxSlots`, insertando una tarjeta con nombre para cada slot ocupado, o una tarjeta vacía con icono "+" (`material-symbols-outlined`) para los libres.
- **`resetForm()`**: limpia todos los campos del formulario de creación (nombre, apellido, fecha, nacionalidad, género vuelto a "Masculino" por defecto) — se llama tanto al cerrar la UI del todo como al abrir el formulario de creación desde cero.

---

## 🔄 Flujo completo resumido

1. Jugador entra al servidor → `cl_main.lua` detecta `NetworkIsSessionStarted()` → dispara `chooseChar`.
2. `cl_events.lua`: fade-out, precarga interior, teletransporte oculto, cierre de loading screens → `ToggleUI(true)`.
3. `ToggleUI` activa cámara, aísla al jugador en su propio bucket, y manda `toggleUI` + traducciones + nacionalidades al NUI.
4. El NUI, al recibir `toggleUI: true`, pide `setupCharacters` → Lua pide al servidor (`sv_database.lua`) la lista real → responde con personajes + slots + "último personaje" → se spawnean todos los peds (`SpawnAllPeds`) y se renderiza la UI (landing por defecto).
5. Jugador navega: Landing → Personajes (`#character-list`) → clic en un slot → `selectSlot` → zoom de cámara (`FocusCharacter`) + panel de detalle o formulario de creación.
6. **Si juega un personaje existente**: `playCharacter` → servidor hace `QBCore.Player.Login` → si hay skin activa, se aplica el modelo/ropa real (`loadSkinAndSpawn`) → se teletransporta al mundo real (`spawnLastLocation`), respetando `SkipSelection` o el selector de `qb-spawn`.
7. **Si crea un personaje nuevo**: formulario validado → `createCharacter` → servidor registra en QBCore, entrega dinero/ítems de bienvenida (`GiveStarterItems`) → se abre el editor de ropa (`qb-clothes:client:CreateFirstCharacter`).
8. **Si borra un personaje**: modal de confirmación → `deleteCharacter` → `QBCore.Player.DeleteCharacter` → refresco de la lista.
9. **Si reordena personajes** (pantalla de Opciones, drag & drop): reordenamiento optimista en el frontend → `reorderCharacters` → transacción SQL atómica en el servidor → confirmación → refresco de datos reales.

---

## 🧩 Integraciones externas (opcionales)

| Recurso | Uso | Obligatorio |
|---|---|---|
| `qb-core` | Framework base (login, personajes, dinero, notificaciones) | ✅ Sí |
| `oxmysql` | Todas las queries SQL | ✅ Sí |
| `qb-clothing` / `qb-clothes` | Cargar y editar la ropa/apariencia del personaje | Recomendado (se llama directamente por nombre de evento) |
| `qb-spawn` | Selector de puntos de spawn cuando `SkipSelection = false` | Solo si no usas `SkipSelection` |
| `DP-Inventory` | Entrega de `id_card` y `phone` al crear personaje | Opcional, falla si no está (revisar `sv_utils.lua`) |
| `DP-RealMoney` | Sincroniza HUD de dinero (cash/black_money/crypto) | Opcional, se detecta automáticamente con `GetResourceState` |

---

## 🐛 Depuración

Activa `Config.Debug = true` para obtener:
- En consola del **servidor**: mensajes `^5[DP-MultiCharacter Debug]` detallando cada paso de login, creación, borrado, reordenamiento y queries.
- En consola del **cliente (F8)**: mismos mensajes para cámara, spawn de peds, zoom/unfocus y eventos NUI.
- En **consola del navegador NUI** (F12 dentro del contexto de FiveM, o inspección remota): `[DP-MultiCharacter JS Debug]` para cada acción del frontend (render de slots, selección, drag & drop, validaciones, etc.).

---

## ✍️ Personalización rápida

- **Cambiar idioma**: edita `Config.Locale`.
- **Cambiar slots gratuitos / VIP**: `Config.DefaultSlots` y `Config.CustomSlots`.
- **Cambiar ubicación de la sala de selección**: `Config.Interior`, `Config.HiddenCoords`, `Config.PedCoords`, `Config.CamCoords`.
- **Cambiar sistema de ropa**: edita el evento disparado en `cl_utils.lua` (`openClothing`) y las llamadas a `qb-clothing:client:loadPlayerClothing` en `cl_main.lua`.
- **Cambiar dinero/ítems de bienvenida**: edita `GiveStarterItems` en `sv_utils.lua` (y opcionalmente conecta `Config.StartItemsList`, que hoy está definido pero no se usa automáticamente).
- **Activar el selector de spawn nativo de `qb-spawn`** en vez de "última ubicación": pon `SkipSelection = false` dentro de `Config.SpawnPoints`.