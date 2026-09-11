# DP-MultiCharacter

Sistema de selección y creación de personajes para servidores **QBCore** (FiveM), con una interfaz NUI moderna estilo "launcher cinemático" (cámara, siluetas 3D en el mundo, tarjetas de personaje, panel de estadísticas, drag & drop para reordenar, sistema de traducciones, etc.).

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
2. En esa sala se generan hasta 7 "peds" (modelos 3D) alineados en fila: uno por cada slot de personaje. Los que ya tienen personaje muestran su skin real; los vacíos muestran una **silueta semitransparente ("sombra")**.
3. El jugador navega la interfaz (landing → lista de personajes → crear/jugar), y mientras lo hace, una cámara cinemática Lua se mueve/hace zoom en sincronía con lo que ocurre en el NUI.
4. Al confirmar "Jugar" o "Crear", la UI se cierra, se destruyen los peds de previsualización, y el servidor hace login/registro real en QBCore y hace aparecer al jugador en el mundo.

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
| `Config.PedCoords` | array de vector4 (5) | Posiciones individuales predefinidas por slot (hasta 7). |
| `Config.PedSpacing` | number | Separación en el eje Y usada para centrar dinámicamente los peds cuando hay más o menos slots que posiciones fijas. |
| `Config.CamCoords` | vector4 | Posición general de la cámara cinemática (vista amplia de todos los personajes). |
| `Config.CharactersAnimations` | bool | Si `true`, los peds en pantalla tendrán animaciones idle en vez de estar estáticos. |
| `Config.CharactersAnimation` | table | Diccionario/nombre de animación para estado `idle` y `select`. |
| `Config.SpawnPoints` | table | `SkipSelection` (bool) + `DefaultSpawn` (vector4) + lista de puntos de spawn con `label`, `description`, `image`, `coords` (para cuando `SkipSelection = false` y se delega en `qb-spawn`). |
| `Config.StartItemsList` | array | Ítems que **debería** recibir un personaje nuevo (actualmente definido pero no consumido directamente por `sv_utils.lua`, que reparte ítems fijos — ver sección de servidor). |
| `Config.ExportCharacters` / `Config.ImportCharacters` | bool | Activan/desactivan (a nivel de config) los botones de exportar/importar personajes en formato "xmt". **Nota:** en el JS actual estos botones existen en la UI pero muestran `alert("Próximamente disponible")`; la lógica real de exportación aún no está implementada. |
| `Config.DefaultMaleModel` / `Config.DefaultFemaleModel` | string | Modelos base (`mp_m_freemode_01` / `mp_f_freemode_01`). |
| `Config.Nationalities` | array de `{label, id}` | Lista completa de países (código ISO de 2 letras) usada para el selector de nacionalidad y para pintar banderas vía `flagcdn.com`. |

---

## ✍️ Personalización rápida

- **Cambiar idioma**: edita `Config.Locale`.
- **Cambiar slots gratuitos / VIP**: `Config.DefaultSlots` y `Config.CustomSlots`.
- **Cambiar ubicación de la sala de selección**: `Config.Interior`, `Config.HiddenCoords`, `Config.PedCoords`, `Config.CamCoords`.
- **Cambiar sistema de ropa**: edita el evento disparado en `cl_utils.lua` (`openClothing`) y las llamadas a `qb-clothing:client:loadPlayerClothing` en `cl_main.lua`.
- **Cambiar dinero/ítems de bienvenida**: edita `GiveStarterItems` en `sv_utils.lua` (y opcionalmente conecta `Config.StartItemsList`, que hoy está definido pero no se usa automáticamente).
- **Activar el selector de spawn nativo de `qb-spawn`** en vez de "última ubicación": pon `SkipSelection = false` dentro de `Config.SpawnPoints`.

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