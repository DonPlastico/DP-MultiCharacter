# DP-MultiCharacter

Sistema de selección y creación de personajes desde cero, altamente optimizado, estructurado para futuras actualizaciones y preparado para la protección de código (Escrow).

## 📂 Estructura del Proyecto

```markdown
DP-MultiCharacter/
├── 📁 client
│ ├── 📄 cl_events.lua (Lógica core encriptable: NUI focus, cámara, spawn ped)
│ ├── 📄 cl_main.lua (Receptores de eventos y NUI Callbacks)
│ └── 📄 cl_utils.lua (Funciones editables: integraciones externas, notificaciones)
├── 📁 locales (Sistema de traducciones)
│ ├── 📄 en.lua  
│ ├── 📄 es.lua  
│ ├── 📄 fr.lua  
│ ├── 📄 it.lua  
│ └── 📄 sistema.lua (Funcionamiento de los archivos locales para su funcionamiento)  
├── 📁 server  
│ ├── 📄 sv_database.lua (Consultas SQL puras a la tabla players)
│ ├── 📄 sv_main.lua (Lógica core encriptable: manejo de sesión, QBCore login)
│ └── 📄 sv_utils.lua (Lógica abierta: validaciones, asignación de dinero/ítems)
├── 📁 ui  
│ ├── 📁 js  
│ │ ├── 📄 app.js (Lógica principal del frontend, peticiones al cliente)
│ │ ├── 📄 sounds.js (Emisión de sonidos "PIM" estilo GTA V)
│ │ └── 📄 validators.js (Filtros y validación del nombre/apellidos/fecha)
│ ├── 🌐 index.html (Estructura visual)
│ └── 🎨 style.css (Diseño visual)
├── 📄 config.lua (Configuración principal: coordenadas, opciones, cámara)
├── 📄 fxmanifest.lua (Manifiesto del script y dependencias)
└── 📝 readme.md
```

## 🚀 Hoja de Ruta y Funcionamiento
