# DP-MultiCharacter

Selector y gestor de personajes para **FiveM/QBCore**. Incluye interfaz NUI, creación y selección de personajes, previsualización 3D, opciones de aparición y un flujo de llegada para personajes nuevos.

> **Estado del documento:** describe el comportamiento encontrado en el recurso. Las secciones marcadas como *pendiente* o *limitación conocida* no deben interpretarse como funciones ya verificadas en un servidor FiveM en vivo.

## Contenido

1. [Funciones y estado](#funciones-y-estado)
2. [Requisitos e instalación](#requisitos-e-instalación)
3. [Uso del jugador](#uso-del-jugador)
4. [Configuración para owner y administración](#configuración-para-owner-y-administración)
5. [Integraciones](#integraciones)
6. [Datos y persistencia](#datos-y-persistencia)
7. [Guía para desarrollo](#guía-para-desarrollo)
8. [Estructura del recurso](#estructura-del-recurso)
9. [Diagnóstico](#diagnóstico)
10. [Flujo 14: llegada de personajes nuevos](#14-flujo-de-llegada-de-personajes-nuevos)
11. [Capturas pendientes](#capturas-pendientes)

## Funciones y estado

| Función | Estado actual |
|---|---|
| Selector de personajes QBCore, creación y carga de personajes | Implementado |
| Previsualizaciones 3D, cámara, lista y ficha de personaje | Implementado |
| Orden manual de personajes y eliminación recuperable | Implementado; la recuperación está limitada por el plazo interno de cinco días |
| Selector de spawn mediante DP-PauseMenu, puntos dinámicos, última ubicación y datos de propiedades | Implementado con integración externa; validar en el servidor concreto |
| Intro de personaje nuevo: personalización, cinemática, selector y taxi | Implementado en código; hay incidencias de ejecución descritas en [Flujo 14](#14-flujo-de-llegada-de-personajes-nuevos) |
| Preferencia para ocultar slots vacíos y volumen de interfaz | Implementado |
| Historial de actividad básico | Implementado; solo muestra eventos que hayan sido registrados |
| Compra de slots, preferencia de spawn y envío real de reportes | **No implementado**; las pantallas son maquetas |
| Exportación/importación de personajes | **No implementado**; genera una vista previa de ejemplo, no un backup restaurable |
| Importación/exportación múltiple y menú de organización | **No implementado** |
| Control de HUD/NUI pertenecientes a otros recursos | **Limitado**; este recurso no puede garantizar que otras interfaces se oculten |

## Requisitos e instalación

### Requisitos

- **QBCore** (`qb-core`).
- **oxmysql**, iniciado antes de este recurso. El manifiesto carga `@oxmysql/lib/MySQL.lua`.
- **DP-PauseMenu** para abrir el selector de spawn que se usa en los flujos normal y de intro.
- **qb-clothing** para personalizar el aspecto inicial. Si no está iniciado, el código de intro intenta continuar sin esa personalización.
- Tablas de personajes y skins de la instalación QBCore (`players`, `playerskins`).

La consulta de casas y apartamentos depende también de las tablas/configuración de esos recursos. No es obligatorio instalar esos sistemas si se desactivan las opciones correspondientes.

### Instalación

1. Copia `DP-MultiCharacter` en la carpeta de recursos del servidor.
2. Revisa [config.lua](./config.lua), en particular las licencias de slots especiales, URLs, coordenadas y opciones de intro.
3. En `server.cfg`, inicia primero las dependencias y después los recursos integrados. Por ejemplo:

   ```cfg
   ensure oxmysql
   ensure qb-core
   ensure DP-PauseMenu
   ensure qb-clothing
   ensure DP-MultiCharacter
   ```

   Ajusta los nombres y el orden a los recursos reales de tu servidor.
4. No hay un archivo SQL de instalación incluido. El recurso crea automáticamente `dp_multicharacter_settings` al iniciar; las demás tablas indicadas arriba pertenecen a QBCore o a integraciones.
5. Reinicia el recurso/servidor y prueba primero con un personaje de pruebas.

La NUI carga Axios, Flatpickr, fuentes e iconos desde CDN. Si el CEF del cliente no puede acceder a esos dominios, ciertos estilos, calendarios o componentes externos podrían no cargarse correctamente.

## Uso del jugador

### Elegir o crear personaje

La interfaz presenta una pantalla de inicio, una lista de personajes y una ficha con datos disponibles como identidad, dinero, empleo/banda y última actividad. El jugador puede elegir un personaje existente o abrir el formulario de creación. Los campos se validan en la interfaz y vuelven a validarse en el servidor.

El número de slots es individual según la licencia: se aplica `Config.CustomSlots[license]` si existe; de lo contrario, se usa `Config.DefaultSlots`. Los slots vacíos pueden ocultarse desde Preferencias.

### Opciones disponibles

- **Restaurar personaje:** muestra personajes eliminados dentro del plazo de recuperación, si hay un slot libre.
- **Sonido de interfaz:** permite cambiar el volumen; se conserva por licencia en la base de datos.
- **Ocultar slots vacíos:** preferencia local del cliente.
- **Ayuda web/Discord:** muestra los enlaces habilitados en la configuración.
- **Historial:** muestra fecha de creación, tiempo jugado, última actualización y eventos guardados en `metadata.activityLog`.
- **Orden:** permite reordenar personajes y guardar el orden de sus slots.

La interfaz también contiene controles visuales para otras opciones; consulta [Funciones y estado](#funciones-y-estado) antes de ofrecerlas como funciones disponibles.

### Cerrar sesión

El comando configurado en `Config.CommandLogOut` es `/logout` por defecto. El recurso guarda la posición segura, salud y armadura antes de cerrar la sesión y volver al selector. La posición dentro de la sala oculta no debe reemplazar la última posición real.

## Configuración para owner y administración

Las opciones principales están en [config.lua](./config.lua). Cambia las coordenadas con cuidado y conserva el formato `vector3`/`vector4` que espera el código.

### Acceso y límites

| Opción | Uso |
|---|---|
| `Config.Debug` | Activa mensajes de diagnóstico generales. |
| `Config.Locale` | Idioma: `es`, `en`, `de`, `fr`, `it` o `pt`. |
| `Config.EnableDeleteButton` | Permite o no eliminar personajes desde el selector. |
| `Config.DefaultSlots` | Slots por defecto; el servidor limita el resultado entre 1 y 7. |
| `Config.CustomSlots` | Excepciones por licencia. Sustituye la licencia de ejemplo por la del usuario autorizado; no publiques licencias reales en documentación o capturas. |
| `Config.MinAge` / `Config.MaxAge` | Rango permitido para la fecha de nacimiento. |
| `Config.RateLimits` | Espera entre solicitudes de creación, borrado, reordenamiento, exportación e importación. Los dos últimos límites no habilitan las funciones de backup. |
| `Config.CommandLogOut` | Nombre del comando para volver al selector. |
| `Config.EnableWebHelp`, `Config.WebHelpURL`, `Config.EnableDiscordHelp`, `Config.DiscordHelpURL` | Enlaces que aparecen en la interfaz. Sustituye los valores de ejemplo. |

No hay un panel administrativo ni un comando de administración de slots en este recurso. Los slots especiales se asignan editando `Config.CustomSlots`; no hay compra automática.

### Sala, cámara y modelos

- `Config.Interior`, `Config.HiddenCoords`, `Config.PedCoords`, `Config.PedSpacing` y `Config.CamCoords` controlan el selector y sus previsualizaciones.
- `Config.CharactersAnimations` habilita las animaciones de las previsualizaciones.
- `Config.DefaultMaleModel` y `Config.DefaultFemaleModel` definen los modelos base de las sombras/personajes nuevos.
- `Config.Nationalities` alimenta el selector de nacionalidad.

La UI calcula posiciones para los slots, pero hay cinco coordenadas predefinidas en `PedCoords`. Prueba la distribución si cambias la cantidad máxima de slots.

### Puntos de aparición

`Config.SpawnPoints` controla el flujo de spawn:

- `SkipSelection`: para el flujo normal de personajes existentes, decide si se omite el mapa y se intenta usar la última posición.
- `DefaultSpawn`: punto de emergencia/reserva.
- `EnableLastLocation`: incluye la última ubicación cuando está disponible.
- `EnableHouses`: permite consultar casas de `qb-houses`.
- `EnableApartments` y `ApartmentsStarting`: opciones para el selector y el flujo de apartamentos nuevos.
- `ShowOwnedApartmentsOnMap`: añade al mapa los apartamentos que ya posee el personaje.
- `DynamicSpawnBlips`: lista de puntos compartidos con DP-PauseMenu y utilizada para generar los destinos de la intro.

Cada punto dinámico usa `name`, `label`, `icon`, `info` y `coord` (`vector4`). Para la intro, usa nombres únicos y coordenadas cercanas al punto que el selector realmente devuelve. Ver [14.1](#141-unificar-y-validar-los-puntos-de-spawn).

### Intro, cinemática y taxi

- `Config.IntroFlow.Enabled`: activa el flujo de primera llegada de personajes nuevos.
- `Config.IntroFlow.Debug`: activa logs detallados de la intro en F8/consola; actualmente está activo en la configuración incluida. Desactívalo en producción si no estás depurando.
- `TailorRoomCoords`: coordenada de pruebas actual en la fábrica de Lester, en el taller de sastre.
- `BucketStart`, `MaxConcurrent`, `MaxQueue`, `BucketPopulation`: controlan instancias aisladas y la cola.
- `CinematicDuration`, junto con `Config.IntroCinematic.Enabled` y `Duration`, controla el zoom y duración. La cinemática actual hace zoom óptico, funde a negro y espera antes de abrir el mapa; no ofrece un control para saltarla.
- `Config.Taxi.Models` y `DriverModel`: modelos y probabilidades.
- `TrafficMode`: actualmente configurado como `private`; no significa que el taxi circule en el tráfico público.
- `BasePrice`, `PricePerMeter`, `MinFare`, `MaxFare`, `RushSurcharge`: parámetros de tarifa. La tarifa puede cobrar desde efectivo y banco según el comportamiento de servidor.
- `RushCooldown`, `MaxDestinationChanges`, `DestinationChangeCooldown`, `StuckTimeout`, `TripTimeout`: límites del trayecto y recuperación.

`Config.StartItemsList` define los artículos del carrito de creación (nombre, etiqueta, precio y cantidades mínimas/máximas). Los precios mostrados en la UI incluyen un recargo visual del 25%. Asegúrate de que cada nombre exista en `QBCore.Shared.Items`. No cambies la estructura del carrito sin revisar [client/cl_events.lua](./client/cl_events.lua) y [server/sv_utils.lua](./server/sv_utils.lua).

`Config.ExportCharacters` y `Config.ImportCharacters` controlan la visibilidad de botones; **no convierten las maquetas actuales en exportación/importación funcional**.

## Integraciones

| Recurso/sistema | Uso |
|---|---|
| `qb-core` | Login, datos, callbacks, dinero, notificaciones y comandos. Obligatorio. |
| `oxmysql` | Acceso a MySQL. Obligatorio en la práctica. |
| `DP-PauseMenu` | Selector de spawn y mapa. La intro reutiliza su export `OpenSpawnSelectorWithApartments`. |
| `qb-clothing` | Personalización inicial y guardado de apariencia. Necesario para completar la experiencia de ropa prevista. |
| `qb-houses` | Consulta de casas propias para ofrecerlas como spawn; depende de las tablas esperadas por el recurso. |
| `qb-apartments` | Consulta de apartamentos existentes y configuración de ubicaciones. |
| `DP-RealMoney` | Si está iniciado, se invoca `UpdateItem` al cargar el personaje para sincronizar los artículos monetarios. |
| `DP-Inventory` | No es la ruta usada para entregar el carrito inicial; los artículos se escriben en los datos QBCore del jugador. |

Las interfaces de otros recursos (HUD, minimapa, videos y NUI) no quedan necesariamente ocultas por DP-MultiCharacter. Su administración debe coordinarse con esos recursos.

## Datos y persistencia

- Personajes, skins, posiciones y metadatos se almacenan en las tablas de QBCore.
- El volumen de interfaz se guarda por licencia en `dp_multicharacter_settings`; la tabla se crea al iniciar.
- La eliminación normal marca el personaje para recuperación mediante `metadata.PROCESO_ELIMINACION`; no lo elimina inmediatamente.
- La ventana de restauración está fijada internamente en **cinco días**. Al vencer, una tarea periódica intenta purgar el personaje y datos asociados.
- Para restaurar, el personaje debe seguir dentro del plazo y debe existir un slot libre.
- El historial UI usa `metadata.activityLog`. Otros recursos/desarrolladores pueden registrar una entrada mediante el export `LogCharacterEvent` de [server/sv_utils.lua](./server/sv_utils.lua).

Haz copias de seguridad de la base de datos antes de cambiar esquemas o probar la purga de personajes.

## Guía para desarrollo

### Flujo normal

1. [client/cl_events.lua](./client/cl_events.lua) abre el selector, atiende callbacks NUI y solicita personajes al servidor.
2. [client/cl_main.lua](./client/cl_main.lua) gestiona la cámara, peds de previsualización, foco y presentación.
3. [server/sv_database.lua](./server/sv_database.lua) lista, ordena, elimina/restaura personajes y mantiene una caché corta.
4. [server/sv_main.lua](./server/sv_main.lua) valida identidad/edad/nacionalidad, crea o carga el personaje y procesa logout.
5. [client/cl_spawn.lua](./client/cl_spawn.lua) envía los datos de spawn al export de DP-PauseMenu y procesa la respuesta.
6. [server/sv_spawn.lua](./server/sv_spawn.lua) obtiene datos de última posición, casas y apartamentos.
7. [client/cl_utils.lua](./client/cl_utils.lua) concentra utilidades de cliente e integración de ropa.

### Flujo de intro

[server/sv_intro.lua](./server/sv_intro.lua) mantiene las fases, buckets, destinos, límites y cobro. [client/cl_intro.lua](./client/cl_intro.lua) hace las transiciones, streaming, cinemática y taxi. [client/cl_spawn.lua](./client/cl_spawn.lua) reusa el selector de mapa. `Config.IntroFlow.Destinations` se construye a partir de `Config.SpawnPoints.DynamicSpawnBlips` al cargar la configuración.

Los nombres de eventos `DP-MultiCharacter:*` son principalmente comunicación interna entre cliente y servidor; no deben considerarse una API pública estable sin revisar sus validaciones y ciclo de vida. El export `LogCharacterEvent` es la integración externa identificada en el código.

### NUI

- [ui/index.html](./ui/index.html) y [ui/style.css](./ui/style.css): estructura y presentación.
- [ui/js/app.js](./ui/js/app.js): pantallas, formularios, callbacks NUI, opciones e historial.
- [ui/js/validators.js](./ui/js/validators.js): validación de formulario en cliente; el servidor también valida datos.
- [ui/js/sounds.js](./ui/js/sounds.js): sonidos sintéticos WebAudio y volumen.
- [ui/js/dev.js](./ui/js/dev.js): simulador local de navegador con datos falsos; no representa la base de datos ni el estado real de FiveM.

## Estructura del recurso

```text
DP-MultiCharacter/
├── client/
│   ├── cl_events.lua
│   ├── cl_intro.lua
│   ├── cl_main.lua
│   ├── cl_spawn.lua
│   └── cl_utils.lua
├── server/
│   ├── sv_database.lua
│   ├── sv_intro.lua
│   ├── sv_main.lua
│   ├── sv_spawn.lua
│   └── sv_utils.lua
├── locales/                 # sistema.lua y traducciones de/de, en, es, fr, it, pt
├── ui/
│   ├── index.html
│   ├── style.css
│   ├── img/                  # imágenes de interfaz
│   ├── items/                # imágenes del carrito inicial
│   └── js/                   # app, dev, sonidos y validadores
├── config.lua
├── fxmanifest.lua
└── readme.md
```

## Diagnóstico

1. Activa `Config.Debug = true` y `Config.IntroFlow.Debug = true` temporalmente.
2. Revisa F8 y consola del servidor desde la creación hasta el spawn. Busca la fase que no avanza y el callback de DP-PauseMenu.
3. Comprueba que DP-PauseMenu y qb-clothing estén iniciados y que el export/evento esperado exista en las versiones instaladas.
4. Valida coordenadas y colisiones en el juego. No des por válida una ubicación solo porque sea numéricamente correcta.
5. Para incidencias de spawn, comprueba el identificador `name` y distancia del punto devuelto por el mapa frente a `DynamicSpawnBlips`.
6. Desactiva los logs de depuración una vez terminadas las pruebas.

Los errores de cliente asociados a carga de mapa/colisión requieren validación dentro de FiveM. El simulador de [ui/js/dev.js](./ui/js/dev.js) solo sirve para revisar la interfaz web y no valida Lua, buckets, tráfico ni streaming del mapa.

## 14. Flujo de llegada de personajes nuevos

El flujo se activa con `Config.IntroFlow.Enabled`. El personaje nuevo se crea en QBCore y se inicia la secuencia de intro: traslado al punto de personalización, confirmación de ropa, cinemática, selector DP-PauseMenu y viaje. El estado se conserva en metadatos para permitir una recuperación parcial si se interrumpe.

### 14.1 Unificar y validar los puntos de spawn

La fuente de puntos es `Config.SpawnPoints.DynamicSpawnBlips`. Durante la carga, esos mismos nombres, etiquetas y coordenadas alimentan `Config.IntroFlow.Destinations`; no mantengas una segunda lista independiente.

El servidor compara la respuesta del mapa con el punto configurado más cercano. Si queda a más de **150 m**, se considera no reconocido y se intenta usar `airport`. Por ello:

- conserva un punto llamado `airport` mientras uses esta ruta de reserva;
- comprueba que DP-PauseMenu devuelva coordenadas próximas a las configuradas;
- valida cada destino en el juego, en especial puntos dentro de interiores, carreteras o ubicaciones con coordenadas de entrada distintas;
- si el aeropuerto no existe en la lista, el servidor no podrá aplicar esa reserva correctamente.

**Limitación conocida:** una selección que no coincide con los puntos puede enviar al jugador al aeropuerto en vez del destino que esperaba. El sistema hace una aproximación por distancia, no identifica el blip seleccionado mediante un ID compartido.

### 14.2 Personalización inicial y coordenada de pruebas

La coordenada configurada para la prueba es `vector4(713.84, -961.53, 30.39, 180.0)`, en la fábrica de Lester. El cliente mantiene la pantalla negra durante la carga de escena/colisión y abre qb-clothing después de comprobar el resultado del streaming.

La ubicación es provisional: confirma en el servidor que la posición esté dentro del taller/interior esperado y que la versión de qb-clothing reciba la llamada de apertura y confirmación compatible. No se debe asumir que otra instalación de ropa usa los mismos eventos.

**Limitación conocida:** se han reportado apariciones fuera del lugar previsto, invisibilidad y problemas al completar la creación. El flujo contiene esperas de streaming acotadas, pero eso no sustituye una prueba en el mapa y con los recursos reales.

### 14.3 Cinemática y selector DP-PauseMenu

Al confirmar la ropa, el cliente realiza un zoom óptico desde la ubicación de personalización, funde a negro gradualmente y, tras la espera configurada, abre el mapa. No está previsto saltar la cinemática con una tecla.

DP-MultiCharacter administra el estado de la intro; DP-PauseMenu presenta el mapa. La selección se reenvía al servidor para validar el destino y comenzar el trayecto. Si el export no está disponible o falla, la ruta normal intenta usar el spawn de reserva; la intro requiere diagnóstico si no llega un callback válido.

### 14.4 Taxi, controles y HUD

El taxi es creado por el cliente en el bucket de la intro. El personaje camina hasta él, intenta subir al asiento trasero y el conductor recibe la ruta al destino. Los controles registrados mediante key mappings son:

| Tecla inicial | Acción |
|---|---|
| `G` | Solicitar una conversación breve con el taxista |
| `R` | Alternar la prisa |
| `E` | Cambiar a otro destino permitido |
| `Backspace` | Solicitar una parada segura |

Las teclas se pueden cambiar desde los ajustes de key bindings de FiveM. La parada está sujeta a un tiempo mínimo y a validación del servidor; el cobro depende del trayecto calculado y del dinero disponible.

**Incidencias comunicadas por probar/corregir:** se ha observado que `R` puede coincidir con una acción no deseada o provocar conducción en sentido extraño, y que `Backspace` puede finalizar el trayecto de forma abrupta. El código actual registra comandos dedicados y solicita la parada al servidor, pero hace falta repetir estas pruebas en el juego y revisar conflictos de key bindings/recursos antes de declarar los controles estables.

El panel NUI del taxi se activa después del intento de entrada al vehículo en el código actual. Aun así, se ha reportado que aparece antes de que el jugador esté sentado: verificarlo en vivo y no confundirlo con paneles de otros recursos. El minimapa, HUD, vídeos u otras NUI externas no están todos bajo el control de este recurso.

### 14.5 Precio y reglas del trayecto

La configuración controla tarifa base, precio por distancia, mínimo/máximo y recargo por prisa. El servidor aplica la tarifa al completar o interrumpir una carrera y limita cambios de destino, frecuencia de prisa, tiempo de atasco y duración máxima. El modo actual es privado: no se integra el taxi en el tráfico público.

La distancia recorrida se calcula entre coordenadas de inicio y final, no como una medición exacta de cada tramo de carretera. Ajusta los precios a esa limitación y pruébalos con los destinos largos.

### 14.6 Aislamiento, salud y depuración

El servidor asigna buckets para aislar intros concurrentes y mantiene una cola limitada. Durante el flujo, el cliente oculta el HUD/radar de GTA controlable por este recurso, congela o protege al personaje según la fase y registra las transiciones cuando el debug está activo.

Esto no puede ocultar de forma universal NUI de terceros. Cada HUD, minimapa personalizado, vídeo o overlay externo puede requerir una integración propia. El log de DP-MultiCharacter ayuda a localizar la fase, pero no demuestra por sí solo que taxi, UI o spawn hayan finalizado correctamente.

### 14.7 Trabajo pendiente antes de dar el flujo por cerrado

- Confirmar en una sesión real que todos los puntos dinámicos se reconocen y que la ruta de reserva al aeropuerto es clara.
- Corregir y volver a probar la orientación del taxi, los controles de prisa/parada y la salida/desaparición del vehículo.
- Verificar que el panel de taxi solo se vea una vez que el jugador esté sentado.
- Coordinar la ocultación de HUD, minimapa, vídeos y otras NUI de recursos externos.
- Probar en servidor real la coordenada provisional de Lester, el flujo de qb-clothing, visibilidad del ped, estado de salud y carga de colisión.
- Reproducir y diagnosticar los crashes/errores de streaming reportados (incluido `MapDataLoadedNode Pool Full`) con logs completos y recursos/versiones del servidor.

No se incluyen aquí como funciones terminadas diálogos avanzados, radio, tutoriales de bienvenida ni compra de apartamentos desde el taxi: no están implementados en el flujo actual.

## Capturas pendientes

Añade aquí capturas tomadas en el servidor real. Evita mostrar licencias, CitizenID de usuarios, datos personales o información administrativa sensible.

<!-- CAPTURA PENDIENTE: pantalla de inicio y selector de personajes. -->
<!-- CAPTURA PENDIENTE: ficha de personaje y pantalla de opciones. -->
<!-- CAPTURA PENDIENTE: formulario de creación y selección de artículos iniciales. -->
<!-- CAPTURA PENDIENTE: qb-clothing en la ubicación de pruebas de Lester. -->
<!-- CAPTURA PENDIENTE: selector de spawn de DP-PauseMenu. -->
<!-- CAPTURA PENDIENTE: taxi con controles/HUD durante el trayecto. -->
