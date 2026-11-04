# DP-MultiCharacter

Sistema de selección y creación de personajes para servidores **QBCore** (FiveM), con una interfaz NUI moderna estilo "launcher cinemático" (cámara, siluetas 3D en el mundo, tarjetas de personaje, panel de estadísticas, drag & drop para reordenar, sistema de traducciones, etc.).

---

## 📂 Estructura del proyecto

```
DP-MultiCharacter/
├── 📁 client/
│   ├── 📄 cl_main.lua      # Cámara, gestión de peds (personajes 3D), zoom/foco, spawn final
│   ├── 📄 cl_events.lua    # Entrada al servidor + NUI Callbacks (JS -> Lua)
│   ├── 📄 cl_spawn.lua     # Sistema integrado del selector de Spawn
│   └── 📄 cl_utils.lua     # Utilidades editables (notificaciones, integración con qb-clothing)
├── 📁 server/
│   ├── 📄 sv_main.lua      # Login/registro de personajes en QBCore, spawn, buckets
│   ├── 📄 sv_database.lua  # Consultas SQL: listar, borrar y reordenar personajes
│   └── 📄 sv_utils.lua     # Ítems/dinero de bienvenida, integraciones externas
├── 📁 locales/
│   ├── 📄 sistema.lua      # Motor de traducciones (_U() y GetTranslations())
│   ├── 📄 es.lua           # Idioma default predefinido
│   ├── 📄 de.lua
│   ├── 📄 en.lua
│   ├── 📄 fr.lua
│   ├── 📄 it.lua
│   └── 📄 pt.lua
├── 📁 ui/
│   ├── 🌐 index.html       # Estructura visual (4 pantallas + modal)
│   ├── 🎨 style.css        # Todo el diseño visual
│   ├── 📁 img              # Fondos, imágenes de spawn, etc...
│   │   ├── 🖼️ bg1.jpg
│   │   ├── 🖼️ bg2.png
│   │   └── 🖼️ bg3.jpg
│   ├── 📁 items            # Imagenes de items
│   │   ├── 🖼️ id_card.png
│   │   ├── 🖼️ kurkakola.png
│   │   ├── 🖼️ phone.png
│   │   ├── 🖼️ sandwich.png
│   │   ├── 🖼️ tosti.png
│   │   └── 🖼️ water_bottle.png
│   └── 📁 js/
│       ├── 📄 app.js        # Lógica principal del frontend (1480 líneas)
│       ├── 📄 sounds.js     # Sonidos de interfaz (hover/click)
│       └── 📄 validators.js # Validación del formulario de creación de personaje
├── 📄 config.lua            # Toda la configuración del recurso
├── 📄 fxmanifest.lua        # Manifiesto de FiveM (scripts, ui_page, dependencias)
└── 📝 readme.md             # Este archivo, donde alojo informacion y cosas a futuro sobre el script
```

**Dependencia obligatoria:** `qb-core`. También usa `oxmysql` para las queries SQL, y de forma opcional se integra con `qb-clothing`, `DP-Inventory` y `DP-RealMoney` si están presentes.

---

## 🧠 Filosofía general del sistema

1. Al conectarse, el jugador **no aparece en el mapa real**: se le teletransporta a una sala oculta bajo el mapa (`Config.HiddenCoords`) y se activa una interfaz NUI a pantalla completa.
2. En esa sala se generan hasta 7 "peds" (modelos 3D) alineados en fila: uno por cada slot de personaje. Los que ya tienen personaje muestran su skin real; los vacíos muestran una **silueta semitransparente ("sombra")**.
3. El jugador navega la interfaz (landing → lista de personajes → crear/jugar), y mientras lo hace, una cámara cinemática Lua se mueve/hace zoom en sincronía con lo que ocurre en el NUI.
4. Al confirmar "Jugar" o "Crear", la UI se cierra, se destruyen los peds de previsualización, y el servidor hace login/registro real en QBCore y hace aparecer al jugador en el mundo.

---

## 🛠️ `config.lua` — Configuración completa

| Variable                                                | Tipo                       | Descripción                                                                                                                                                                                                                                                             |
| ------------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Config.Debug`                                          | bool                       | Activa logs `[DP-MultiCharacter Debug]` en consola F8 y en consola del servidor. Útil para depurar sin ensuciar la consola en producción.                                                                                                                               |
| `Config.Locale`                                         | string                     | Idioma activo (`'es'`, `'en'`, `'it'`, `'fr'`, `'de'`, `'pt'`).                                                                                                                                                                                                         |
| `Config.ServerName`                                     | string                     | Nombre mostrado en la pantalla cinemática al entrar a jugar.                                                                                                                                                                                                            |
| `Config.EnableDeleteButton`                             | bool                       | Habilita/deshabilita el borrado de personajes desde la UI.                                                                                                                                                                                                              |
| `Config.DefaultSlots`                                   | number (1–7)               | Slots gratuitos para todos los jugadores.                                                                                                                                                                                                                               |
| `Config.CustomSlots`                                    | table `[license] = number` | Slots VIP por licencia Rockstar concreta (sobrescribe `DefaultSlots` para esa licencia).                                                                                                                                                                                |
| `Config.CommandLogOut`                                  | string                     | Comando de chat para cerrar sesión (`/logout`) y volver al selector.                                                                                                                                                                                                    |
| `Config.Interior`                                       | vector3                    | Coordenadas del interior que se precarga (`LoadInterior`) para que la sala oculta renderice bien.                                                                                                                                                                       |
| `Config.HiddenCoords`                                   | vector4                    | Coordenadas reales donde se esconde físicamente al jugador mientras ve el menú.                                                                                                                                                                                         |
| `Config.PedCoords`                                      | array de vector4 (5)       | Posiciones individuales predefinidas por slot (hasta 7).                                                                                                                                                                                                                |
| `Config.PedSpacing`                                     | number                     | Separación en el eje Y usada para centrar dinámicamente los peds cuando hay más o menos slots que posiciones fijas.                                                                                                                                                     |
| `Config.CamCoords`                                      | vector4                    | Posición general de la cámara cinemática (vista amplia de todos los personajes).                                                                                                                                                                                        |
| `Config.CharactersAnimations`                           | bool                       | Si `true`, los peds en pantalla tendrán animaciones idle en vez de estar estáticos.                                                                                                                                                                                     |
| `Config.CharactersAnimation`                            | table                      | Diccionario/nombre de animación para estado `idle` y `select`.                                                                                                                                                                                                          |
| `Config.SpawnPoints`                                    | table                      | `SkipSelection` (bool) + `DefaultSpawn` (vector4) + lista de puntos de spawn con `label`, `description`, `image`, `coords` (para cuando `SkipSelection = false`).                                                                                                       |
| `Config.StartItemsList`                                 | array                      | Ítems que **debería** recibir un personaje nuevo (actualmente definido pero no consumido directamente por `sv_utils.lua`, que reparte ítems fijos — ver sección de servidor).                                                                                           |
| `Config.ExportCharacters` / `Config.ImportCharacters`   | bool                       | Activan/desactivan (a nivel de config) los botones de exportar/importar personajes en formato "xmt". **Nota:** en el JS actual estos botones existen en la UI pero muestran `alert("Próximamente disponible")`; la lógica real de exportación aún no está implementada. |
| `Config.DefaultMaleModel` / `Config.DefaultFemaleModel` | string                     | Modelos base (`mp_m_freemode_01` / `mp_f_freemode_01`).                                                                                                                                                                                                                 |
| `Config.Nationalities`                                  | array de `{label, id}`     | Lista completa de países (código ISO de 2 letras) usada para el selector de nacionalidad y para pintar banderas vía `flagcdn.com`.                                                                                                                                      |

---

## ✍️ Personalización rápida

- **Cambiar idioma**: edita `Config.Locale`.
- **Cambiar slots gratuitos / VIP**: `Config.DefaultSlots` y `Config.CustomSlots`.
- **Cambiar ubicación de la sala de selección**: `Config.Interior`, `Config.HiddenCoords`, `Config.PedCoords`, `Config.CamCoords`.
- **Cambiar sistema de ropa**: edita el evento disparado en `cl_utils.lua` (`openClothing`) y las llamadas a `qb-clothing:client:loadPlayerClothing` en `cl_main.lua`.
- **Cambiar dinero/ítems de bienvenida**: edita `GiveStarterItems` en `sv_utils.lua` (y opcionalmente conecta `Config.StartItemsList`, que hoy está definido pero no se usa automáticamente).
- \*\*Activar el selector de spawn para personajes existentes en vez de "última ubicación": pon `SkipSelection = false` dentro de `Config.SpawnPoints`. La intro de personaje nuevo abre siempre el selector de DP-PauseMenu.

---

## 🧩 Integraciones externas (opcionales)

| Recurso        | Uso                                                        | Obligatorio                                                 |
| -------------- | ---------------------------------------------------------- | ----------------------------------------------------------- |
| `qb-core`      | Framework base (login, personajes, dinero, notificaciones) | ✅ Sí                                                       |
| `oxmysql`      | Todas las queries SQL                                      | ✅ Sí                                                       |
| `qb-clothing`  | Cargar y editar la ropa/apariencia del personaje           | Recomendado (se llama directamente por nombre de evento)    |
| `DP-Inventory` | Entrega de `id_card` y `phone` al crear personaje          | Opcional, falla si no está (revisar `sv_utils.lua`)         |
| `DP-RealMoney` | Sincroniza HUD de dinero (cash/black_money/crypto)         | Opcional, se detecta automáticamente con `GetResourceState` |

---

## 🚧 Pendientes por implementar

Lista de trabajo abierta: funcionalidades que hoy están solo como maqueta visual (placeholders, `alert("Próximamente disponible")`, botones sin lógica) o que directamente aún no existen, ordenadas para abordarlas más adelante. Cada punto describe el comportamiento final esperado.

### 1. Comprar Slots

Debe ser funcional de verdad, con dos modos configurables desde `config.lua` (a elección del dueño del servidor):

- **Modo "Coins/VIP in-game"**: se paga con un sistema de monedas ya existente en el servidor. El admin indica en el config el nombre del script de coins:
  - Si es uno de los sistemas ya soportados por `DP-MultiCharacter` de fábrica, basta con poner su nombre.
  - Si es un sistema **custom** propio del servidor, el admin deberá añadir manualmente la integración en `client`/`server` (dejar preparado el punto de enganche, claramente señalado en el código).
- **Modo "URL externa (Google Form / tienda web, etc.)"**: el modal simplemente enlaza a una URL de compra externa; la asignación real de los slots comprados la hace el admin **manualmente** desde archivos/BD tras recibir el pago.

### 2. Exportar Personaje (funcional)

- Encima del recuadro de "código generado", mostrar una lista de los personajes disponibles del usuario, **cada uno con un checkbox**. El usuario debe poder seleccionar entre **2 y 7 personajes** (mínimo 2, máximo 7 = límite máximo de slots del sistema) para exportar de una vez.
- El código generado (en JSON o XML, según el toggle) debe incluir el **detalle completo** de cada personaje seleccionado:
  - ID único de exportación (para poder verificarlo luego al importar).
  - CitizenID, nombre, apellidos, fecha de nacimiento, nacionalidad, género.
  - Economía: dinero en efectivo y en banco.
  - Teléfono.
  - Afiliaciones: trabajo, rango, bandas, si es jefe/líder.
  - Actividad: tiempo jugado, última conexión.
  - Apariencia/personaje: ropa, última ubicación de spawn, cara, tono de piel, pelo, accesorios, etc. — todo.
  - Slot que ocupaba.
- Crear en base de datos una tabla nueva, **`exportacion_multicharacters`**, que guarde estos datos exportados junto a su ID único.
- Botón de "Copiar" debe quedar plenamente funcional (ya lo está a nivel UI, falta el contenido real).

### 3. Importar Personaje (funcional)

- Al pegar el código y pulsar "Importar", el sistema debe:
  1. Buscar en la base de datos (`exportacion_multicharacters`) el registro cuyo ID único coincida (formato: 10 caracteres alfanuméricos, ej. `1G51E3KKA0`).
  2. Verificar que el contenido no haya sido alterado/corrompido respecto al guardado originalmente.
  3. Si es válido, crear ese personaje en la lista de personajes del usuario que importa, asociado a **su propia license**, con todos los datos tal cual se exportaron.
- Caso de uso: un jugador crea y exporta un personaje, se lo pasa a un amigo (Discord, etc.), y al importarlo, el amigo recibe una copia jugable de ese personaje asociada a su cuenta.
- El personaje exportado sigue existiendo también para quien lo exportó; si quiere borrarlo de su propia lista, es decisión suya (borrado normal). Pero **una vez exportado, el registro en `exportacion_multicharacters` no se puede eliminar desde la UI** — solo el owner del servidor puede borrarlo manualmente desde la base de datos.

### 5. Reportar Bug (funcional + integración con DP-AdminMenu)

- El mensaje que escriba el usuario debe llegar a los administradores a través de `DP-AdminMenu`, soportando tanto texto como imágenes adjuntas.
- Crear un comando configurable en `config.lua`, por ejemplo `/restart-ui [ID del jugador]`, que permita a un admin **reiniciar el script de `DP-MultiCharacter` únicamente para ese jugador concreto** (quitárselo y volver a cargárselo), útil cuando a alguien se le ha bugueado la interfaz o no le cargan cosas correctamente.
- Dejar la puerta abierta a añadir más herramientas de soporte para administradores en el futuro.

### 6. Exportar individual desde la tabla de Opciones

El botón de exportar de cada fila en la tabla debe abrir el **mismo modal** de Exportar/Importar, pero en una variante simplificada: sin el selector de personajes (checklist), ya que aplica únicamente al personaje de esa fila concreta. Solo debe mostrar el selector de Formato (JSON/XML) y el recuadro de código generado con todos los datos de ese personaje.

### 9. Completar todos los locales (traducción íntegra)

Revisar `locales/es.lua` y el resto de idiomas (`en`, `fr`, `it`, `de`, `pt`) para que **absolutamente todo el texto del script** pase por el sistema de traducciones (`_U()` / `data-trans`) — sin textos sueltos hardcodeados en español directamente en el HTML/JS/CLIENTS/SERVERS que se queden sin traducir al cambiar `Config.Locale` (Incluidos los Prints/Console.logs).

### 10. Seguridad — Anti-duplicación en Importar Personaje

Cuando se implemente el punto 4, contemplar el caso de que el **mismo código de importación se use varias veces** (por el mismo usuario o por usuarios distintos a la vez, ej. dos personas pegando el código casi simultáneamente). Definir en `config.lua` si un mismo ID de exportación se puede importar una única vez en total, un número limitado de veces, o de forma ilimitada — y aplicarlo con un lock/transacción en `sv_database.lua` para que no se puedan colar dos importaciones simultáneas del mismo código antes de que la primera termine de procesarse.

### 11. Gestión — Marcar personaje como favorito

El botón "Marcar como favorito" existe visualmente en el roadmap pero no está desarrollado como punto propio. Al marcarlo, ese personaje debe aparecer destacado visualmente en la lista de "Personajes" (por ejemplo con una estrella o borde distinto) y ordenarse primero por defecto en la tabla de Opciones. Guardar el estado de favorito en base de datos (metadata o tabla nueva), asociado al `citizenid`.

### 13. Administración — Panel de estadísticas globales del servidor (server-side)

Crear un comando o export pensado para administradores (o integrable en `DP-AdminMenu`) que devuelva estadísticas agregadas del sistema de personajes: número total de personajes activos en el servidor, media de slots usados por jugador, personajes creados en las últimas 24h/7 días, y personajes actualmente en `PROCESO_ELIMINACION` (ver punto 2) pendientes de purga.

### 14. Flujo de primera entrada: Tailor Room → cinemática → selector de spawn → taxi

Flujo completo, 100% scripteado, que se ejecuta **solo la primera vez que un personaje nuevo entra al mundo** (se marca en `metadata.introDone` para que, al volver a seleccionar ese personaje, no se repita la intro y se use el spawn normal / última posición). Todo el control de estados vive en el **servidor**; el cliente solo ejecuta cámara, animaciones y UI.

#### 14.1 Fase 1 · Creación en la Tailor Room (instancia privada)

- Al confirmar "Crear", el jugador es teletransportado a la **Tailor Room** (sala de creación de apariencia con `qb-clothing`).
- **Aislamiento total**: cada jugador se mueve a un **routing bucket propio y único** (`SetPlayerRoutingBucket`). Nadie ve a nadie; cada jugador solo se ve a sí mismo.
  - Los buckets se asignan desde un pool controlado (ej. a partir de un offset configurable, `Config.IntroBucketStart`) para no chocar con buckets de otros scripts, y se liberan siempre al terminar el flujo.
  - Desactivar población ambiental en ese bucket (`SetRoutingBucketPopulationEnabled`) mientras esté en la Tailor Room.
- Estado de seguridad: jugador **invencible, congelado y sin control del HUD/chat/teléfono/movimiento** durante toda la intro. Bloquear comandos y teclas que puedan sacarlo del flujo (inventario, menú de pausa, etc.).
- Si el jugador **se desconecta o crashea** en cualquier punto del flujo: limpiar bucket, borrar entidades (taxi/NPC) y, al reconectar, retomar en el último estado válido guardado (`metadata.introStep`) en vez de dejarlo bugueado.

#### 14.2 Fase 2 · Cinemática de llegada

- Al terminar la creación se lanza la cinemática del **personaje recién creado**: llegada a la ciudad → zoom óptico desde la Tailor Room → fundido a negro. El zoom mantiene la cámara dentro del interior para evitar que el streaming en altura agote `MapDataLoadedNode`.
- Al terminar el fundido, se abre el **selector de spawn** (DP-PauseMenu).
- Mejoras a contemplar:
  - Música/ambiente sonoro y efectos (motores del avión, anuncio de megafonía) configurables en `config.lua`, con `Config.IntroCinematic.Enabled` para poder desactivarla.
  - **Botón de saltar cinemática** (ej. tecla `Espacio` mantenida 1,5 s), configurable, por si el servidor la quiere obligatoria o no.
  - Si algo falla en la cinemática (timeout / error), pasar directamente al selector de spawn en lugar de dejar al jugador atascado.

#### 14.3 Fase 3 · Selector de spawn (con la lógica de cada opción)

Los puntos disponibles salen de `Config.SpawnPoints`. Los destinos iniciales del flujo:

| Destino             | Método de llegada                                    |
| ------------------- | ---------------------------------------------------- |
| ✈️ Aeropuerto       | Sale caminando de la terminal (secuencia scripteada) |
| 🚗 Concesionario    | Taxi                                                 |
| 🏖️ Gym Playa        | Taxi                                                 |
| 🏥 Hospital         | Taxi                                                 |
| 👮 Comisaría        | Taxi                                                 |
| 💼 Centro de empleo | Taxi                                                 |
| 🏢 Apartamentos     | Taxi                                                 |

**A) Spawn en el aeropuerto**

1. El jugador aparece en la terminal y realiza una **secuencia de caminata scripteada** (`TaskGoStraightToCoord` / `TaskFollowNavMeshToCoord`) hasta la salida.
2. Al terminar, se le **devuelve el control**, se le quita la invencibilidad y se restaura su **bucket por defecto (0)**.

**B) Spawn en cualquier otro sitio (taxi)**

1. El jugador **sigue en su bucket privado** mientras dura todo el trayecto.
2. Sale de la terminal igual que en el aeropuerto, y se **llama automáticamente a un taxi** (toda la secuencia scripteada: levanta la mano llamado a un taxi cercano, el taxi llega, para frente al jugador, este sube de forma animada como pasajero en uno de los asientos traseros).
3. El **taxista NPC** conduce hasta el destino elegido **respetando señales, semáforos, tráfico y el resto de jugadores de la ciudad**.
   - Ojo técnico: como el jugador va en un bucket privado, **no existe tráfico ni jugadores reales en su instancia**. Dos opciones, a decidir en `config.lua` (`Config.TaxiTrafficMode`):
     - `"private"`: trayecto aislado, sin tráfico real, más estable y barato en rendimiento (el "tráfico" es solo estético/cinemático).
     - `"world"`: el jugador y el taxi pasan al bucket 0 durante el trayecto (con el jugador invencible y el taxi protegido), para que el trayecto sea con tráfico y jugadores reales. Más realista, pero más propenso a bugs/trolleos.
   - Estilo de conducción configurable (flags de `SetDriveTaskDrivingStyle`) y velocidad máxima normal/moderada vs. con prisa.
4. **Llegada**: el taxi para a un lado de la acera junto al destino, le cobra el $ del trayecto desde el aeropuerto al destino, el jugador baja, **se da la vuelta como mirando a su alrededor** y el taxi se aleja. Cuando el taxi sale de la zona (distancia configurable), se **despawnea**.
5. Se le **devuelve el control**, se quita la invencibilidad y se cambia al **bucket por defecto (0)**.

#### 14.4 UI/NUI del taxi (aparece a mitad del trayecto)
Panel inferior con las acciones disponibles; los atajos se pueden reasignar desde la configuración de teclas de FiveM:

| Tecla         | Acción           | Comportamiento                                                                                                                                                                                                                                                                   |
| ------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **G**         | Conversar        | Abre un menú de preguntas y respuestas con el taxista. Primera versión: **conversación genérica** (mismas preguntas para todos). Ya se verá si se enlaza con el futuro **script de diálogos**.                                                                                   |
| **R**         | Meter prisa      | El NPC acelera y conduce de forma agresiva: **ignora señales y semáforos**, pero **sigue evitando choques con otros vehículos**.                                                                                                                                                 |
| **E**         | Cambiar destino  | Abre un **menú lateral** con los destinos; al elegir, **elimina el blip/GPS del destino anterior** y **marca el nuevo**. Recalcula ruta y tarifa extra por cambiarlo.                                                                                                            |
| **Backspace** | Solicitar parada | Deshabilitar la tecla F aqui, y debe solicitar el bajarse del taxi, **se detiene a un lado, sobre la acera**; se cobra la tarifa **proporcional al tramo recorrido** (no el total). Al cobrar, el taxi se aleja, se despawnea y el jugador pasa al bucket 0, sin invencibilidad. |

**Detalles de cada acción:**

- **Conversar (G)**:
  - Diálogos vía `locales/` para que también estén traducidos.
  - Ideas para ampliarlo: respuestas aleatorias de un pool por pregunta, frases distintas según el destino o la hora del día, y alguna "pregunta secreta" con lore o pistas del servidor (normas básicas, dónde está cada sitio, etc.).
- **Alternar prisa/normal (R)**:
  - Idea: posibilidad de **cobrar un pequeño extra** por la "carrera urgente" (configurable, `Config.Taxi.RushSurcharge`) y/o dar una **propina opcional**.
  - Añadir un cooldown para que no se pueda spamear y que la tecla se pueda desactivar desde el config.
- **Cambiar destino (E)**:
  - El menú debe mostrar el destino actual y no dejar seleccionar el ya seleccionado indicado.
  - En el mismo trayecto maximo 3 cambios (1 que es el destino original + 2 cambios disponibles) con cooldown entre ellos, y un indicador de restantes disponibles.
- **Solicitar parada (Backspace)**:
  - La tarifa se calcula **en el servidor**, nunca en el cliente: `tarifa = tarifaBase + (distanciaRecorrida × precioPorMetro)` (o proporcional: `tarifaTotal × (recorrido / distanciaTotal)`), con mínimo y máximo configurables.
  - El NPC debe detenerse en un punto seguro (acera / carril lateral), nunca en mitad de un cruce,carretera.

#### 14.5 Robustez y anti-exploits (a tener en cuenta desde el principio)

- **Servidor autoritativo**: el servidor decide el destino, la tarifa y cuándo termina cada fase; el cliente solo la solicita. Validar todos los eventos (que el jugador realmente esté en fase de taxi, que el destino exista en `Config.SpawnPoints`, etc.).
- **Taxi atascado**: si el vehículo no avanza durante X segundos, o no llega en Y minutos, mecanismo de recuperación (recalcular ruta → teletransportar cerca del destino con fundido a negro → último recurso: spawn directo en el destino).
- **Limpieza garantizada** de taxi + NPC + bucket en todos los casos (fin normal, desconexión, reinicio del recurso, error). Un `onResourceStop` que recorra el estado activo y lo restaure.
- Que nadie pueda **robar o bajarse del taxi** a mitad del flujo (puertas bloqueadas, `SetPedCanBeDraggedOut(false)`, etc.).
- El jugador **no puede morir ni recibir daño** durante la intro; además, el HUD/blips ajenos quedan ocultos.
- Guardar el **progreso del flujo** (`introStep`) para poder retomarlo si hay un corte.
- **Logs** (`Config.IntroFlow.Debug`) de cada fase para depurar fácilmente.
- Rendimiento: un solo taxi por jugador, 7 tipos de taxis, total aletoriedad, configurable cada uno y la probabilidad de aparecer x taxi, límite de intros simultáneas configurable si el servidor se llena (cola de espera).

#### 14.6 Configuración (`config.lua`)

```lua
Config.IntroFlow = {
    Enabled = true,
    Debug = true, -- Logs del flujo en F8 y consola del servidor
    TailorRoomCoords = vector4(713.84, -961.53, 30.39, 180.0), -- Fábrica de Lester (DP-AdminMenu)
    BucketStart = 5000,
    MaxConcurrent = 16,
    MaxQueue = 64,
    Destinations = {} -- Se genera desde Config.SpawnPoints.DynamicSpawnBlips
}

Config.Taxi = {
    Models = { { model = 'taxi', chance = 100 } }, -- la configuracion incluye siete modelos
    DriverModel = 's_m_m_gentransport',
    TrafficMode = 'private',
    BasePrice = 50,
    PricePerMeter = 0.15,
    MinFare = 25,
    MaxFare = 2500,
    RushSurcharge = 5,
    MaxDestinationChanges = 2,
    DestinationChangeCooldown = 10,
    StuckTimeout = 30,
    TripTimeout = 900,
}
```

**Estado de esta implementación:** DP-MultiCharacter conserva el estado y los buckets de la intro en el servidor; para mostrar el mapa reutiliza el export `OpenSpawnSelectorWithApartments` de DP-PauseMenu. Los buckets concurrentes y el máximo de espera se regulan con `MaxConcurrent`/`MaxQueue`. Los destinos válidos se resuelven desde `Config.IntroFlow.Destinations`; una selección fuera de esos puntos cae al aeropuerto. El taxi es una entidad local en el bucket privado, con panel NUI y controles G/R/E/Backspace registrados como atajos independientes; el cobro y la validación del destino se hacen en el servidor. El jugador viaja en el asiento trasero del lado del pasajero y las teclas nativas de salida quedan bloqueadas durante el trayecto. La prisa solo cambia la velocidad máxima, sin reiniciar la ruta del conductor. Al pedir parada, el taxi busca un punto de carretera por delante, deja salir al jugador, cobra el tramo recorrido y se aleja antes de desaparecer. `TrafficMode` está fijado a `private` en esta primera versión; no se cambia al bucket público durante la carrera. Para un personaje nuevo, `qb-clothing` aplica el aspecto base en ropa interior y, al confirmar, notifica a DP-MultiCharacter para continuar la cinemática y el selector; cancelar no avanza el flujo. Al iniciar se restaura la visibilidad y se asignan vida, armadura y necesidades completas. Si una intro se interrumpe, el siguiente inicio del personaje vuelve al selector de spawn.

La cámara hace un zoom óptico desde la Tailor Room, funde gradualmente a negro y espera 2,5 segundos antes de abrir el selector; no se mueve a gran altitud ni se puede saltar. Al iniciar la intro se ocultan la UI de selección, los peds de previsualización, la cámara y su hilo de densidad antes de pasar al servidor. La personalización usa las coordenadas de la Fábrica de Lester de DP-AdminMenu. La pantalla permanece negra mientras se solicita la escena y la colisión del destino; qb-clothing solo se abre cuando ambas están listas. `Config.IntroFlow.Destinations` se genera desde `Config.SpawnPoints.DynamicSpawnBlips`, por lo que ambos selectores comparten puntos y coordenadas; todos esos puntos inician el viaje en taxi. El personaje camina hasta el taxi antes de subir. `TripTimeout` es de 900 segundos para permitir viajes largos como Paleto Bay. Con `Config.IntroFlow.Debug = true` (activado para esta depuración) se registran las fases y la respuesta de DP-PauseMenu en F8 y en la consola del servidor. No crea un avión físico ni reproduce sonido (`SoundEnabled` queda apagado). Los teleports cargan únicamente una escena acotada en las coordenadas destino y no usan el salto de 500 m, que puede agotar el pool de nodos del mapa.

#### 14.7 Futuras ideas

- Taxista con personalidad/nombre aleatorio y diálogos propios.
- Radio del taxi con emisoras seleccionables durante el trayecto.
- Salida por defecto del aeropuerto en taxi o en transporte público (bus/metro) como alternativas más baratas.
- Destinos adicionales configurables por el admin directamente en `Config.SpawnPoints` (cada uno con su propio punto de bajada).
- Misión/guía de bienvenida al terminar la intro: marcar en el mapa los sitios clave (empleo, concesionario, hospital) como tutorial.
- Quitar lo de aparecer en apartamento o comprarlo, que salgan todos los apartamentos, disponibles, cuando llegue a uno de ellos en taxi, pueda comprar una habitación.

---

### A. Experiencia de usuario (UI/NUI)

- **Landing con noticias del servidor**: bloque configurable con novedades, eventos y changelog (texto y/o imagen), editable desde `config.lua` o desde un panel admin.
- **Estados de carga** (_skeleton loaders_) y transiciones suaves para que la UI nunca parezca congelada mientras cargan los peds.

### B. Creación de personaje

- **Validaciones más estrictas**: lista negra de nombres/apellidos (famosos, insultos, "Test Test"…), formato (mayúscula inicial, sin números ni emojis), rango de edad mínima/máxima y fecha de nacimiento coherente.
- **Unicidad opcional** de nombre + apellidos para evitar personajes idénticos.
- **Biografía / trasfondo opcional**: texto corto de historia que se muestra en la ficha del personaje.

### C. Seguridad y anti-abuso

- **Bloqueo de personaje en uso**: que el mismo personaje no pueda estar cargado en dos jugadores/sesiones a la vez (lock por `citizenid`).
- **Borrado seguro con periodo de gracia** (relacionado con `PROCESO_ELIMINACION`): el personaje no se purga al instante, se puede restaurar durante X días y el borrado requiere confirmar escribiendo el nombre del personaje.
- **Tabla de auditoría** (`multichar_logs`) con eventos importantes para revisar sanciones o disputas.
- **CK (Character Kill)**: permitir que un admin marque un personaje como fallecido permanentemente. Pasa a verse como "💀 Fallecido" en la lista, queda archivado y deja de ser jugable (sin borrar su historial).
- **Bloqueo administrativo de personaje**, por ejemplo por sanción, mientras se resuelve un caso.

### D. Rendimiento

- **Carga diferida (lazy load)** de las skins pesadas: cargar primero las tarjetas y los peds visibles, y completar el resto de forma asíncrona.
- **Liberar recursos** siempre: `SetModelAsNoLongerNeeded`, borrado de peds de previsualización, cierre de cámaras y `RemoveAnimDict`.
- **Bucles inactivos**: ningún `while true` ni `Wait(0)` cuando la UI no está abierta (objetivo: ~0.00 ms en idle).

### E. Sesión y flujo de juego

- **`/logout` más robusto**: guardar el estado antes de salir, con cooldown y bloqueos (muerto, esposado, en combate, dentro de un vehículo, en mitad de una acción).
- **Cambio de personaje sin salir del servidor**, con fundido a negro y limpieza completa del estado del anterior.
- **Botón "Cambiar de personaje"** accesible desde el menú de pausa.
- **Autoguardado periódico** y guardado garantizado en `playerDropped` (posición, vida, armadura, necesidades, inventario y apariencia).
- **Reglas de spawn inteligentes**: si el personaje murió, aparecer en el hospital; si tiene una propiedad (casa/habitación), ofrecerla como punto de spawn; si no, su última posición.

### F. Integraciones y API para otros scripts

- **Eventos públicos** para que otros recursos reaccionen: `DP-MultiCharacter:characterCreated`, `characterSelected`, `characterLogout` y `characterDeleted`.
- **Capa _bridge_ (adaptadores)** para inventario (`DP-Inventory`, `ox_inventory`, `qb-inventory`), ropa (`qb-clothing`, `illenium-appearance`) y apartamentos, con un único punto de configuración en vez de llamadas directas por nombre de evento.
- **Slots por rol de Discord**: asignar slots VIP automáticamente según los roles del jugador, sin editar `Config.CustomSlots` a mano.
- **Integración con `DP-AdminMenu`**: ver/editar personajes de un jugador, restaurar eliminados, marcar CK, cambiar slots y consultar el historial de actividad.

### G. Herramientas de administración

- **Slots VIP en base de datos** (`multichar_slots`) en lugar de `Config.CustomSlots`, para poder cambiarlos en caliente sin reiniciar el recurso.
- **Comandos admin** de ejemplo: `/multichar-list [id]`, `/multichar-restore [citizenid]`, `/multichar-setslots [license] [n]`, `/multichar-ck [citizenid]` y el `/restart-ui [id]` ya planteado en el punto 5.
- **Auto-migración SQL**: crear las tablas (`CREATE TABLE IF NOT EXISTS`) al iniciar y guardar una versión del esquema para poder actualizar sin hacerlo a mano.
- **Comando de diagnóstico** (`/multichar-diag`): comprueba dependencias, tablas, locales incompletos y valores erróneos del `config.lua`, y muestra un informe en consola.
- **Aviso de nueva versión** (consulta opcional al repositorio de GitHub al iniciar).

### H. Documentación y mantenimiento del proyecto

- **Instalación paso a paso** en el README: dependencias, orden en `server.cfg`, SQL a importar y configuración mínima.
- **FAQ y _troubleshooting_**: problemas comunes (UI en negro, peds invisibles, personaje que no guarda...) y cómo resolverlos.
- **Changelog** con versionado semántico (`1.0.0`, `1.1.0`...).
- **Carpeta `shared/`** para constantes y enums (estados de intro, tipos de evento) y **`bridge/`** para los adaptadores.
- **Puntos de enganche señalados** en el código con comentarios `-- HOOK:` para que cualquier admin sepa dónde integrar su propio script.
- **Checklist de pruebas manuales** antes de cada versión (crear, borrar, cambiar de personaje, `/logout`, reinicio del recurso, desconexión a mitad de intro).
- **Capturas de pantalla / GIFs** de cada pantalla de la UI en el README.
