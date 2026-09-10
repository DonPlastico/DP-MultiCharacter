const resName = GetParentResourceName();
let charactersData = [];
let selectedSlot = null;
let selectedGender = null;
let maxSlots = 4;
let currentLandingIndex = 1; // 0=Play, 1=Chars, 2=Options
let isZoomed = false; // Nueva variable para controlar el zoom
let isUnfocusing = false; // true mientras la cámara vuelve a la vista general (evita glitches)
const UNFOCUS_DURATION = 850; // Debe ser >= al tiempo que tarda la cámara en alejarse en cl_main.lua (800ms)
let DEBUG_MODE = false; // Variable global para almacenar el estado del Config.Debug
let translations = {}; // Variable global para almacenar las traducciones cargadas desde Lua
let selectedNationality = null;
let nationalitiesData = [];
let lastCharacter = null;

// ==========================================
// 🛠️ FUNCIÓN DE DEPURACIÓN (DEBUG)
// ==========================================
function DebugPrint(msg) {
    if (DEBUG_MODE) {
        console.log("[DP-MultiCharacter JS Debug] " + msg);
    }
}

function Translate(key, fallback) {
    return translations[key] || fallback;
}

// ==========================================
// 🌐 MOTOR DE TRADUCCIONES FRONTEND
// ==========================================
function applyTranslations() {
    DebugPrint("Aplicando traducciones al DOM HTML...");

    // Traducir textos estándar
    document.querySelectorAll('[data-trans]').forEach(el => {
        const key = el.getAttribute('data-trans');
        if (translations[key]) {
            el.innerText = translations[key];
        }
    });

    // Traducir placeholders de inputs
    document.querySelectorAll('[data-trans-placeholder]').forEach(el => {
        const key = el.getAttribute('data-trans-placeholder');
        if (translations[key]) {
            el.setAttribute('placeholder', translations[key]);
        }
    });
}

// === MUESTRA/OCULTA "MOVER" Y "SELECCIONAR" DEL FOOTER SEGÚN SI HAY UN PERSONAJE ENFOCADO ===
function setFooterZoomState(zoomed) {
    const moveEl = document.getElementById('footer-move');
    const selectEl = document.getElementById('footer-select');
    if (moveEl) moveEl.style.display = zoomed ? "flex" : "none";
    if (selectEl) selectEl.style.display = zoomed ? "flex" : "none";
    DebugPrint("Estado del footer actualizado. Zoomed: " + zoomed);
}

document.addEventListener('DOMContentLoaded', () => {
    DebugPrint("DOM cargado. Inicializando eventos principales de la interfaz.");

    // Función para desincronizar los destellos de las tarjetas del menú para un efecto visual dinámico
    function randomizeCardShines() {
        const delays = [0, 2.6, 5.2];
        DebugPrint("Aplicando efecto visual de destello aleatorio a las tarjetas del landing.");

        for (let currentIndex = delays.length - 1; currentIndex > 0; currentIndex--) {
            const randomIndex = Math.floor(Math.random() * (currentIndex + 1));
            const temporaryDelay = delays[currentIndex];
            delays[currentIndex] = delays[randomIndex];
            delays[randomIndex] = temporaryDelay;
        }

        document.querySelectorAll('.landing-image-card').forEach((card, index) => {
            const shineDelay = `${delays[index]}s`;
            card.style.setProperty('--shine-delay', shineDelay);

            const reflection = document.getElementById(`ref-card-${index + 1}`);
            if (reflection) {
                reflection.style.setProperty('--shine-delay', shineDelay);
            }
        });
    }

    // Receptor principal de eventos NUI desde Lua
    window.addEventListener('message', (event) => {
        const data = event.data;

        if (data.action === "toggleUI") {
            // Actualizamos la variable global de debug recibida desde Lua
            if (data.debug !== undefined) {
                DEBUG_MODE = data.debug;
                DebugPrint("Modo de depuración JS actualizado a: " + DEBUG_MODE);
            }

            // Recibimos y aplicamos el diccionario de idiomas desde Lua
            if (data.translations) {
                translations = data.translations;
                applyTranslations();
            }

            // Guardar las nacionalidades que vienen del Config de Lua
            if (data.nationalities) {
                nationalitiesData = data.nationalities;
                renderNationalities(nationalitiesData);
            }

            DebugPrint("Evento 'toggleUI' recibido. Estado: " + data.state);
            document.getElementById('app').style.display = data.state ? "block" : "none";

            if (data.state) {
                showScreen('landing-screen');
                randomizeCardShines();
                DebugPrint("Solicitando setupCharacters a Lua mediante NUI Post.");
                axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
            } else {
                // Si se cierra la UI por completo (entra a jugar), reseteamos los inputs por seguridad
                resetForm();
            }
        } else if (data.action === "setupCharacters") {
            DebugPrint("Evento 'setupCharacters' recibido. Procesando " + (data.characters ? data.characters.length : 0) + " personajes para " + data.slots + " slots.");
            charactersData = data.characters;
            maxSlots = data.slots || 4;
            lastCharacter = data.lastCharacter || null;
            renderSlots();
            updateLandingScreen();
            updateOptionsStats();

            // Si la pantalla de opciones está visible, refresca la tabla
            if (document.getElementById('options-screen').style.display !== "none") {
                OptionsTable.render();
            }
        } else if (data.action === "showLanding") {
            DebugPrint("Evento 'showLanding' recibido. Mostrando menú inicial.");
            showScreen('landing-screen');
        } else if (data.action === "hideLanding") {
            DebugPrint("Evento 'hideLanding' recibido. Ocultando menú inicial.");
            document.getElementById('landing-screen').style.display = "none";
        } else if (data.action === "reorderDone") {
            DebugPrint("Evento 'reorderDone' recibido. Refrescando personajes desde el servidor...");
            // Pedimos la lista fresca al servidor: llegará por 'setupCharacters' y se
            // recalcularán los slots, la tabla, las stats, etc.
            axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
        }
    });

    // === LÓGICA LANDING SCREEN (RATÓN Y TECLADO) ===
    const landBtns = [
        document.getElementById('btn-land-play'),
        document.getElementById('btn-land-chars'),
        document.getElementById('btn-land-options')
    ];

    // Actualiza los hovers visuales y los fondos al navegar por el menú principal
    function updateLandingHover(index) {
        landBtns.forEach((btn, i) => {
            if (i === index) {
                btn.classList.add('active');

                // Actualizar fondo asociado al botón activo
                document.querySelectorAll('.landing-bg').forEach(bg => bg.classList.remove('show'));
                document.getElementById(btn.dataset.target).classList.add('show');

                // Actualizar cards de imagen superiores
                document.querySelectorAll('.landing-image-card').forEach(card => card.classList.remove('active'));
                const cardId = btn.dataset.card;
                if (cardId) {
                    document.getElementById(cardId).classList.add('active');
                }

                // Actualizar cards de reflejo inferiores
                document.querySelectorAll('.landing-reflection-card').forEach(ref => ref.classList.remove('active'));
                const refId = `ref-card-${i + 1}`;
                document.getElementById(refId).classList.add('active');

            } else {
                btn.classList.remove('active');
            }
        });
    }

    // Interacción con las cards de imagen (hacer click en una card cambia la selección principal)
    document.querySelectorAll('.landing-image-card').forEach((card, index) => {
        card.addEventListener('click', () => {
            // Solo si el botón correspondiente no está disabled
            const btn = landBtns[index];
            if (!btn.classList.contains('disabled')) {
                DebugPrint("Click en tarjeta de imagen del landing. Índice: " + index);
                currentLandingIndex = index;
                updateLandingHover(currentLandingIndex);
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
            }
        });

        card.addEventListener('mouseenter', () => {
            if (!card.classList.contains('disabled')) {
                // Solo efecto visual, no cambiar selección automáticamente al pasar el ratón
            }
        });
    });

    // Hover con ratón en los botones principales
    landBtns.forEach((btn, index) => {
        btn.addEventListener('mouseenter', () => {
            if (!btn.classList.contains('disabled')) {
                currentLandingIndex = index;
                updateLandingHover(currentLandingIndex);
            }
        });
    });

    // Navegación principal con flechas del teclado y tecla Escape
    document.addEventListener('keydown', (e) => {
        if (e.key === "Escape") {
            // Cancelar el modal de borrado si está abierto
            if (document.getElementById('delete-modal').style.display === "flex") {
                DebugPrint("Modal de borrado cancelado mediante tecla ESC.");
                document.getElementById('delete-modal').style.display = "none";
                return;
            }
            // Cancelar el formulario de registro de personaje
            if (document.getElementById('character-register').style.display === "block") {
                DebugPrint("Registro cancelado mediante tecla ESC.");
                document.getElementById('btn-cancel-reg').click();
                return;
            }
            // Salir de la pantalla de opciones de vuelta al landing
            if (document.getElementById('options-screen').style.display === "block") {
                DebugPrint("Saliendo de la pantalla de opciones. Volviendo al Landing.");
                showScreen('landing-screen');
                if (typeof Sounds !== 'undefined') Sounds.playCancel();
                return;
            }

            // Lógica para salir de la selección de personaje y volver atrás
            if (document.getElementById('character-list').style.display === "block") {
                if (isZoomed) {
                    DebugPrint("Quitando zoom y restaurando vista general desde ESC.");
                    isZoomed = false;
                    isUnfocusing = true; // Bloquea nuevas selecciones hasta que la cámara termine de alejarse
                    navQueue = [];
                    isNavigating = false;
                    document.querySelectorAll('.char-slot').forEach(el => el.classList.remove('active'));
                    selectedSlot = null;
                    document.getElementById('action-buttons').style.display = "none";
                    setFooterZoomState(false);
                    document.querySelector('.top-title').classList.remove('hidden');

                    // Ocultar panel detallado de stats
                    document.getElementById('detailed-char-info').classList.add('hidden');

                    axios.post(`https://${resName}/unfocusCharacter`, JSON.stringify({}));
                    if (typeof Sounds !== 'undefined') Sounds.playCancel();

                    // Esperamos a que la cámara termine de alejarse (misma duración que en cl_main.lua)
                    // antes de volver a mostrar el selector de slots y permitir elegir otro personaje.
                    // Así evitamos el glitch de solapamiento si se selecciona demasiado rápido.
                    setTimeout(() => {
                        document.getElementById('slots-wrapper').classList.remove('slots-hidden');
                        isUnfocusing = false;
                        DebugPrint("Solicitando lista actualizada de personajes tras borrado.");
                        axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
                        // Al recibir setupCharacters, updateOptionsStats() se llamará automáticamente
                    }, UNFOCUS_DURATION);
                } else {
                    DebugPrint("Saliendo de la lista de personajes. Volviendo al Landing.");
                    showScreen('landing-screen');
                    if (typeof Sounds !== 'undefined') Sounds.playCancel();
                }
                return;
            }
        }

        // Flechas para navegar entre personajes lateralmente cuando el panel de detalle está enfocado (zoom)
        if (document.getElementById('character-list').style.display === "block" && isZoomed) {
            if (e.key === "ArrowRight") {
                DebugPrint("Navegando al siguiente personaje (Flecha Derecha).");
                navigateCharacter(1);
                return;
            } else if (e.key === "ArrowLeft") {
                DebugPrint("Navegando al personaje anterior (Flecha Izquierda).");
                navigateCharacter(-1);
                return;
            } else if (e.key === "Enter") {
                // Simular clic en el botón principal (JUGAR o CREAR)
                DebugPrint("Pulsado ENTER. Simulando clic en acción principal.");
                document.getElementById('main-action-btn').click();
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                return;
            }
        }

        // Navegación con flechas para el Landing Screen inicial
        if (document.getElementById('landing-screen').style.display !== "none") {
            if (e.key === "ArrowRight") {
                currentLandingIndex = Math.min(2, currentLandingIndex + 1);
                updateLandingHover(currentLandingIndex);
                if (typeof Sounds !== 'undefined') Sounds.playNav();
            } else if (e.key === "ArrowLeft") {
                let minIndex = charactersData.length > 0 ? 0 : 1;
                currentLandingIndex = Math.max(minIndex, currentLandingIndex - 1);
                updateLandingHover(currentLandingIndex);
                if (typeof Sounds !== 'undefined') Sounds.playNav();
            } else if (e.key === "Enter") {
                DebugPrint("Ejecutando acción del Landing Screen (Enter). Botón: " + currentLandingIndex);
                landBtns[currentLandingIndex].click();
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
            }
        }
    });

    // Acción directa para Jugar con el último personaje
    document.getElementById('btn-land-play').addEventListener('click', () => {
        if (lastCharacter) {
            DebugPrint("Acción rápida: Jugar con el personaje principal.");
            axios.post(`https://${resName}/playCharacter`, JSON.stringify({ cData: lastCharacter }));
        }
    });

    // Acción para abrir la lista de ranuras/slots
    document.getElementById('btn-land-chars').addEventListener('click', () => {
        DebugPrint("Abriendo pantalla de selección manual de personajes.");
        showScreen('character-list');
        setFooterZoomState(false); // Al entrar mostramos solo "ESC - SALIR" hasta enfocar un personaje
    });

    document.getElementById('btn-land-options').addEventListener('click', () => {
        DebugPrint("Abriendo pantalla de opciones.");
        showScreen('options-screen');
        OptionsTable.reset();
        OptionsTable.render();
        updateOptionsStats();
        if (typeof Sounds !== 'undefined') Sounds.playSelect();
    });

    // === LÓGICA DE CLIC EN LOS SLOTS INDIVIDUALES ===
    document.getElementById('slots-wrapper').addEventListener('click', (e) => {
        if (isUnfocusing) {
            DebugPrint("Clic ignorado: La cámara se está alejando actualmente.");
            return; // Bloqueado mientras la cámara vuelve a la vista general
        }

        const slotEl = e.target.closest('.char-slot');
        if (!slotEl) return;

        const slotId = parseInt(slotEl.dataset.slot);
        DebugPrint("Slot " + slotId + " clicado.");
        selectSlot(slotId);
    });

    // === FLECHAS DE LA BOTONERA CENTRAL (navegación de personajes con el ratón) ===
    const arrowLeftEl = document.querySelector('.action-arrows-left');
    const arrowRightEl = document.querySelector('.action-arrows-right');
    if (arrowLeftEl) arrowLeftEl.addEventListener('click', () => navigateCharacter(-1));
    if (arrowRightEl) arrowRightEl.addEventListener('click', () => navigateCharacter(1));

    // Abrir modal de confirmación de borrado desde el panel lateral
    const deleteBtn = document.getElementById('panel-btn-delete');
    if (deleteBtn) {
        deleteBtn.addEventListener('click', () => {
            if (selectedSlot !== null) {
                DebugPrint("Abriendo modal de confirmación de borrado para el slot: " + selectedSlot);
                document.getElementById('delete-modal').style.display = "flex";
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
            }
        });
    }

    // Acción unificada del botón central gigante (Jugar o Crear) dependiendo de si el slot está ocupado
    document.getElementById('main-action-btn').addEventListener('click', () => {
        const charData = charactersData.find(c => c.cid === selectedSlot);
        if (charData) {
            DebugPrint("Enviando petición a servidor para jugar con CitizenID: " + charData.citizenid);
            axios.post(`https://${resName}/playCharacter`, JSON.stringify({ cData: charData }));
        } else {
            DebugPrint("El slot está vacío. Abriendo formulario de registro de personaje.");
            showScreen('character-register');
            resetForm();
        }
    });

    // Selección de género en el formulario de creación
    document.querySelectorAll('.gender-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.gender-btn').forEach(el => el.classList.remove('active'));
            const target = e.target.closest('.gender-btn');
            target.classList.add('active');
            selectedGender = target.dataset.gender;

            DebugPrint("Género actualizado a: " + selectedGender + ". Solicitando preview a Lua.");
            // Actualizamos la sombra (silueta) en el mundo en tiempo real al cambiar de género
            axios.post(`https://${resName}/previewPed`, JSON.stringify({
                gender: selectedGender,
                slot: selectedSlot
            }));
        });
    });

    // Envío del formulario de registro
    document.getElementById('btn-create-reg').addEventListener('click', () => {
        const firstname = document.getElementById('reg-firstname').value.trim();
        const lastname = document.getElementById('reg-lastname').value.trim();
        const dob = document.getElementById('reg-dob').value;

        const validation = Validator.validateForm(firstname, lastname, dob, selectedGender, selectedNationality);
        if (!validation.valid) {
            alert(validation.msg);
            return;
        }

        const data = {
            cid: selectedSlot,
            firstname: firstname,
            lastname: lastname,
            birthdate: dob,
            gender: selectedGender === "Masculino" ? 0 : 1,
            nationality: selectedNationality
        };

        DebugPrint("Enviando petición createCharacter para nuevo personaje.");
        axios.post(`https://${resName}/createCharacter`, JSON.stringify(data));

        // Limpiamos el formulario AQUÍ, ya que el personaje se va a crear correctamente
        resetForm();
    });

    // Cancelar el registro y volver a la vista general de personajes
    document.getElementById('btn-cancel-reg').addEventListener('click', () => {
        DebugPrint("Cancelando registro. Volviendo a la lista manteniendo los datos.");
        showScreen('character-list');
        document.getElementById('detailed-char-info').classList.add('hidden');
        document.getElementById('action-buttons').style.display = "none";
        document.querySelectorAll('.char-slot').forEach(el => el.classList.remove('active'));
        axios.post(`https://${resName}/deletePreview`, JSON.stringify({}));
        document.querySelector('.top-title').classList.remove('hidden');

        // Restaurar la cámara y la vista general de los personajes
        isZoomed = false;
        isUnfocusing = true;
        navQueue = [];
        isNavigating = false;
        selectedSlot = null;
        setFooterZoomState(false);

        // Alejar la cámara llamando a Lua
        axios.post(`https://${resName}/unfocusCharacter`, JSON.stringify({}));

        // Esperar a que termine la animación de la cámara para mostrar los slots nuevamente
        setTimeout(() => {
            document.getElementById('slots-wrapper').classList.remove('slots-hidden');
            isUnfocusing = false;
        }, UNFOCUS_DURATION);
    });

    // Cerrar modal de confirmación de borrado
    document.getElementById('btn-modal-cancel').addEventListener('click', () => {
        DebugPrint("Borrado cancelado desde el modal.");
        document.getElementById('delete-modal').style.display = "none";
    });

    // Confirmar borrado definitivo del personaje
    document.getElementById('btn-modal-confirm').addEventListener('click', () => {
        const charData = charactersData.find(c => c.cid === selectedSlot);
        if (charData) {
            DebugPrint("Confirmado borrado del personaje CitizenID: " + charData.citizenid);
            axios.post(`https://${resName}/deleteCharacter`, JSON.stringify({ citizenid: charData.citizenid }));

            // Ocultar paneles y UI al enviar el borrado
            document.getElementById('delete-modal').style.display = "none";
            document.getElementById('detailed-char-info').classList.add('hidden');
            document.getElementById('action-buttons').style.display = "none";

            // Salimos del zoom igual que con ESC, para que la lista se recargue con la cámara ya alejada
            isZoomed = false;
            isUnfocusing = true;
            navQueue = [];
            isNavigating = false;
            selectedSlot = null;
            setFooterZoomState(false);
            axios.post(`https://${resName}/unfocusCharacter`, JSON.stringify({}));

            // Re-solicitamos la lista de personajes actualizada después de que la cámara vuelva
            setTimeout(() => {
                document.getElementById('slots-wrapper').classList.remove('slots-hidden');
                isUnfocusing = false;
                DebugPrint("Solicitando lista actualizada de personajes tras borrado.");
                axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
            }, UNFOCUS_DURATION);
        }
    });

    // --- LÓGICA DEL SELECTOR DE NACIONALIDAD ---
    const natOptionsContainer = document.getElementById('nationality-options');
    const natDisplay = document.getElementById('nationality-display');
    const natWrapper = document.getElementById('nationality-wrapper');
    const natDropdown = document.getElementById('nationality-dropdown');
    const natSearch = document.getElementById('nationality-search');
    const natText = document.getElementById('nationality-text');

    // Función para renderizar las opciones dinámicamente
    function renderNationalities(list) {
        natOptionsContainer.innerHTML = '';
        list.forEach(nat => {
            const opt = document.createElement('div');
            opt.className = 'dropdown-option';
            opt.dataset.id = nat.id.toLowerCase();
            opt.dataset.name = nat.label.toLowerCase();

            opt.innerHTML = `
            <img src="https://flagcdn.com/24x18/${nat.id}.png" class="flag-icon" onerror="this.outerHTML='<div class=\\'fallback-flag\\'>${nat.id}</div>'">
            <span>${nat.label}</span>
        `;

            opt.addEventListener('click', () => {
                selectedNationality = nat.id;
                natText.innerText = nat.label;
                natDisplay.classList.add('selected');
                natWrapper.classList.remove('open');
                natDropdown.classList.add('hidden');
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
            });

            natOptionsContainer.appendChild(opt);
        });
    }

    // Llamamos a renderizar cuando se cargue la UI (usará los datos que lleguen de Lua)
    // (Asegúrate de llamarlo también dentro del bloque toggleUI si se reabre la UI)
    renderNationalities(nationalitiesData);

    // 3. Abrir/Cerrar el desplegable
    natDisplay.addEventListener('click', (e) => {
        e.stopPropagation(); // Evita que el evento "click outside" lo cierre instantáneamente
        natWrapper.classList.toggle('open');
        natDropdown.classList.toggle('hidden');
        if (!natDropdown.classList.contains('hidden')) {
            natSearch.focus(); // Auto-foco en el buscador
        }
    });

    // 4. Cerrar si haces click fuera del menú
    document.addEventListener('click', (e) => {
        if (natWrapper && !natWrapper.contains(e.target)) {
            natWrapper.classList.remove('open');
            natDropdown.classList.add('hidden');
        }
    });

    // 5. Buscador en tiempo real
    natSearch.addEventListener('input', (e) => {
        const searchVal = e.target.value.toLowerCase();
        document.querySelectorAll('.dropdown-option').forEach(opt => {
            if (opt.dataset.id.includes(searchVal) || opt.dataset.name.includes(searchVal)) {
                opt.style.display = 'flex';
            } else {
                opt.style.display = 'none';
            }
        });
    });

    function updateOptionsStats() {
        const totalChars = charactersData.length;
        const totalSlots = maxSlots;
        const availableSlots = Math.max(0, totalSlots - totalChars);

        const elActive = document.getElementById('stat-active-chars');
        const elAvailable = document.getElementById('stat-available-slots');
        const elTotal = document.getElementById('stat-total-slots');

        if (elActive) elActive.innerText = totalChars;
        if (elAvailable) elAvailable.innerText = availableSlots;
        if (elTotal) elTotal.innerText = totalSlots;

        DebugPrint(`Stats actualizadas: ${totalChars} activos / ${availableSlots} disponibles / ${totalSlots} totales`);
    }

    // ==========================================
    // === PANTALLA DE OPCIONES — MÓDULO COMPLETO ===
    // ==========================================
    /**
     * OptionsTable: gestor de la tabla custom de personajes.
     * - Búsqueda en tiempo real
     * - Ordenación por columnas (slot, nombre, citizenid)
     * - Drag & Drop para reordenar (persistido vía callback a Lua)
     * - Render dinámico y estado vacío
     */
    const OptionsTable = (() => {
        // Estado interno
        let sortState = { key: 'cid', dir: 'asc' };
        let searchQuery = '';
        let dragSrcCid = null;

        // Referencias del DOM (se rellenan en init)
        let els = {};

        // ==========================================
        // UTILIDADES
        // ==========================================
        const $ = (sel) => document.querySelector(sel);
        const $$ = (sel) => Array.from(document.querySelectorAll(sel));

        function escapeHtml(str) {
            if (str === null || str === undefined) return '';
            return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#039;');
        }

        // ==========================================
        // FILTRADO + ORDENACIÓN
        // ==========================================
        function getProcessedRows() {
            let list = [...charactersData];

            // 1) Filtro de búsqueda (por nombre o citizenid o cid)
            if (searchQuery) {
                const q = searchQuery.toLowerCase();
                list = list.filter(c => {
                    const name = `${c.charinfo.firstname} ${c.charinfo.lastname}`.toLowerCase();
                    const cid = String(c.cid);
                    const citizen = String(c.citizenid || '').toLowerCase();
                    return name.includes(q) || cid.includes(q) || citizen.includes(q);
                });
            }

            // 2) Ordenación
            const { key, dir } = sortState;
            const mult = dir === 'asc' ? 1 : -1;

            list.sort((a, b) => {
                let va, vb;
                switch (key) {
                    case 'cid':
                        va = a.cid; vb = b.cid;
                        break;
                    case 'name':
                        va = `${a.charinfo.firstname} ${a.charinfo.lastname}`.toLowerCase();
                        vb = `${b.charinfo.firstname} ${b.charinfo.lastname}`.toLowerCase();
                        break;
                    case 'citizenid':
                        va = String(a.citizenid || '').toLowerCase();
                        vb = String(b.citizenid || '').toLowerCase();
                        break;
                    default:
                        va = a.cid; vb = b.cid;
                }
                if (va < vb) return -1 * mult;
                if (va > vb) return 1 * mult;
                return 0;
            });

            return list;
        }

        // ==========================================
        // RENDER
        // ==========================================
        function render() {
            if (!els.tbody) return;

            const list = getProcessedRows();
            els.tbody.innerHTML = '';

            // Estado vacío
            if (list.length === 0) {
                if (els.emptyState) {
                    els.emptyState.style.display = 'flex';
                    els.emptyState.querySelector('p').innerText = searchQuery
                        ? 'Sin resultados para tu búsqueda'
                        : 'No hay personajes que mostrar';
                }
                return;
            } else {
                if (els.emptyState) els.emptyState.style.display = 'none';
            }

            // Construir filas
            const frag = document.createDocumentFragment();

            list.forEach(char => {
                const tr = document.createElement('tr');
                tr.dataset.cid = char.cid;
                tr.dataset.citizenid = char.citizenid || '';
                tr.draggable = false;

                const fullName = `${char.charinfo.firstname} ${char.charinfo.lastname}`;

                tr.innerHTML = `
                    <td class="col-drag">       <!-- 1. Drag handle -->
                        <div class="drag-handle" title="Arrastrar para reordenar">
                            <i class="fas fa-grip-vertical"></i>
                        </div>
                    </td>
                    <td class="col-slot">       <!-- 2. Slot number -->
                        <span class="slot-badge">#${char.cid}</span>
                    </td>
                    <td class="col-name">       <!-- 3. Nombre completo -->
                        <span class="char-name" title="${escapeHtml(fullName)}">${escapeHtml(fullName)}</span>
                    </td>
                    <td class="col-citizen">    <!-- 4. CitizenID -->
                        <span class="char-citizen">${escapeHtml(char.citizenid || '---')}</span>
                    </td>
                    <td class="col-actions">    <!-- 5. Botones -->
                        <div class="table-actions">
                            <button class="table-btn btn-export-char" title="Exportar personaje" data-cid="${char.cid}">
                                <i class="fas fa-file-export"></i>
                            </button>
                            <button class="table-btn btn-delete-char" title="Eliminar personaje" data-cid="${char.cid}">
                                <i class="fas fa-trash"></i>
                            </button>
                        </div>
                    </td>
                `;

                // Acciones
                tr.querySelector('.btn-export-char').addEventListener('click', (e) => {
                    e.stopPropagation();
                    DebugPrint("Exportar personaje CID: " + char.cid);
                    if (typeof Sounds !== 'undefined') Sounds.playSelect();
                    alert("Próximamente disponible");
                });

                tr.querySelector('.btn-delete-char').addEventListener('click', (e) => {
                    e.stopPropagation();
                    selectedSlot = parseInt(char.cid);
                    DebugPrint("Abriendo modal de borrado desde opciones para el slot: " + selectedSlot);
                    document.getElementById('delete-modal').style.display = "flex";
                    if (typeof Sounds !== 'undefined') Sounds.playSelect();
                });

                // Drag handle — enganchamos mousedown SOLO al handle
                const handle = tr.querySelector('.drag-handle');
                handle.addEventListener('mousedown', (e) => {
                    e.preventDefault();
                    e.stopPropagation();

                    // Asignamos el tr a una variable temporal ANTES de llamar
                    // porque currentTarget en mousedown apunta al handle, no al tr
                    dragSrcRow = tr;                       // ← global en el módulo
                    handleDragStart.call(tr, e);
                });

                frag.appendChild(tr);
            });

            els.tbody.appendChild(frag);

            // Actualizar iconos de sort en headers
            $$('.characters-table th[data-sort]').forEach(th => {
                // Limpiar clases y resetear icono a neutro
                th.classList.remove('sort-asc', 'sort-desc');
                const icon = th.querySelector('.sort-icon');
                if (icon) {
                    icon.classList.remove('fa-sort', 'fa-sort-up', 'fa-sort-down');
                    icon.classList.add('fa-sort'); // por defecto, neutro
                }

                // Marcar la columna activa y poner su icono correcto
                if (th.dataset.sort === sortState.key) {
                    if (sortState.dir === 'asc') {
                        th.classList.add('sort-asc');
                        if (icon) {
                            icon.classList.remove('fa-sort');
                            icon.classList.add('fa-sort-up');
                        }
                    } else {
                        th.classList.add('sort-desc');
                        if (icon) {
                            icon.classList.remove('fa-sort');
                            icon.classList.add('fa-sort-down');
                        }
                    }
                }
            });
        }

        // ==========================================
        // DRAG & DROP (con MOUSE EVENTS, más fiable en CEF)
        // ==========================================
        let isDragging = false;
        let dragStartY = 0;
        let dragGhostEl = null;
        let dragSrcRow = null;
        let lastDragOverRow = null;

        function handleDragStart(e) {
            // Solo botón izquierdo
            if (e.button !== 0) return;

            dragSrcCid = parseInt(dragSrcRow.dataset.cid);
            isDragging = true;
            dragStartY = e.clientY;

            dragSrcRow.classList.add('dragging');

            // Crear "fantasma" flotante
            dragGhostEl = dragSrcRow.cloneNode(true);
            dragGhostEl.style.position = 'fixed';
            dragGhostEl.style.pointerEvents = 'none';
            dragGhostEl.style.opacity = '0.85';
            dragGhostEl.style.zIndex = '9999';
            dragGhostEl.style.width = dragSrcRow.offsetWidth + 'px';
            dragGhostEl.style.background = 'rgba(20, 20, 20, 0.95)';
            dragGhostEl.style.transform = 'translate(-50%, -50%)';
            dragGhostEl.style.left = e.clientX + 'px';
            dragGhostEl.style.top = e.clientY + 'px';
            document.body.appendChild(dragGhostEl);

            // Bloquear selección de texto mientras arrastramos
            document.body.style.userSelect = 'none';

            // Enlazar listeners globales
            document.addEventListener('mousemove', handleDragMove);
            document.addEventListener('mouseup', handleDragEnd);
        }

        function handleDragMove(e) {
            if (!isDragging || !dragGhostEl) return;

            // Mover el fantasma
            dragGhostEl.style.left = e.clientX + 'px';
            dragGhostEl.style.top = e.clientY + 'px';

            // Detectar sobre qué fila está el cursor
            const rows = Array.from(els.tbody.querySelectorAll('tr'));
            let hoveredRow = null;

            for (const row of rows) {
                const rect = row.getBoundingClientRect();
                if (e.clientY >= rect.top && e.clientY <= rect.bottom) {
                    hoveredRow = row;
                    break;
                }
            }

            // Quitar clase de la fila anterior
            if (lastDragOverRow && lastDragOverRow !== hoveredRow) {
                lastDragOverRow.classList.remove('drag-over');
            }

            if (hoveredRow && hoveredRow !== dragSrcRow) {
                hoveredRow.classList.add('drag-over');
                lastDragOverRow = hoveredRow;
            } else {
                lastDragOverRow = null;
            }
        }

        function handleDragEnd(e) {
            if (!isDragging) return;
            isDragging = false;

            // Limpiar fantasma
            if (dragGhostEl && dragGhostEl.parentNode) {
                dragGhostEl.parentNode.removeChild(dragGhostEl);
            }
            dragGhostEl = null;

            document.body.style.userSelect = '';

            // Quitar clases visuales
            if (dragSrcRow) dragSrcRow.classList.remove('dragging');
            els.tbody.querySelectorAll('tr').forEach(tr => tr.classList.remove('drag-over'));

            // Ejecutar el reordenamiento si soltamos sobre otra fila
            if (lastDragOverRow && dragSrcRow && lastDragOverRow !== dragSrcRow) {
                const targetCid = parseInt(lastDragOverRow.dataset.cid);
                DebugPrint(`Drag & Drop: mover CID ${dragSrcCid} → antes de CID ${targetCid}`);

                const srcIndex = charactersData.findIndex(c => c.cid === dragSrcCid);
                const dstIndex = charactersData.findIndex(c => c.cid === targetCid);

                if (srcIndex !== -1 && dstIndex !== -1) {
                    const [moved] = charactersData.splice(srcIndex, 1);
                    charactersData.splice(dstIndex, 0, moved);

                    // Reasignar CID según el nuevo orden 1..N
                    charactersData.forEach((c, i) => { c.cid = i + 1; });

                    // Refrescar UI
                    render();

                    // Persistir en Lua
                    const orderPayload = charactersData.map(c => ({
                        cid: c.cid,
                        citizenid: c.citizenid
                    }));

                    if (typeof Sounds !== 'undefined') Sounds.playSelect();

                    axios.post(`https://${resName}/reorderCharacters`, JSON.stringify({
                        order: orderPayload
                    })).then(() => {
                        // Tras guardar en BD, volvemos a pedir la lista fresca al servidor
                        // para que charactersData quede sincronizado con la realidad.
                        DebugPrint("Reorden guardado. Solicitando setupCharacters para refrescar datos...");
                        setTimeout(() => {
                            axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
                        }, 250);
                    }).catch(() => {
                        DebugPrint("Aviso: el endpoint /reorderCharacters no respondió.");
                    });
                }
            }

            // Reset
            dragSrcRow = null;
            dragSrcCid = null;
            lastDragOverRow = null;

            // Quitar listeners globales
            document.removeEventListener('mousemove', handleDragMove);
            document.removeEventListener('mouseup', handleDragEnd);
        }

        // ==========================================
        // ORDENACIÓN POR CABECERA
        // ==========================================
        function handleSortClick(e) {
            const th = e.currentTarget;
            const key = th.dataset.sort;
            if (!key) return;

            if (sortState.key === key) {
                sortState.dir = sortState.dir === 'asc' ? 'desc' : 'asc';
            } else {
                sortState.key = key;
                sortState.dir = 'asc';
            }

            DebugPrint(`Ordenando por "${key}" (${sortState.dir})`);
            if (typeof Sounds !== 'undefined') Sounds.playNav();
            render();
        }

        // ==========================================
        // BÚSQUEDA
        // ==========================================
        function handleSearch(e) {
            searchQuery = e.target.value.trim();
            render();
        }

        // ==========================================
        // INICIALIZACIÓN
        // ==========================================
        function init() {
            els.tbody = document.getElementById('options-characters-tbody');
            els.emptyState = document.getElementById('table-empty-state');
            els.searchInput = document.getElementById('table-search');

            if (!els.tbody) {
                DebugPrint("OptionsTable: no se encontró #options-characters-tbody.");
                return;
            }

            // Headers de ordenación
            $$('.characters-table th[data-sort]').forEach(th => {
                th.addEventListener('click', handleSortClick);
            });

            // Buscador
            if (els.searchInput) {
                els.searchInput.addEventListener('input', handleSearch);
            }

            DebugPrint("OptionsTable inicializado correctamente.");
        }

        // ==========================================
        // API PÚBLICA
        // ==========================================
        return {
            init,
            render,
            reset() {
                searchQuery = '';
                sortState = { key: 'cid', dir: 'asc' };
                if (els.searchInput) els.searchInput.value = '';
                render();
            },
            setData() {
                // Llamado cuando charactersData cambia (ej: tras borrar)
                render();
            }
        };
    })();

    // Inicializar cuando el DOM esté listo
    OptionsTable.init();

    // Alias de compatibilidad (por si lo usas desde otros sitios)
    function renderOptionsCharactersTable() {
        OptionsTable.render();
    }

    // ==========================================
    // BOTONES DE LA PANTALLA DE OPCIONES
    // ==========================================
    (() => {
        // --- Importar / Exportar (top bar) ---
        const btnImportMulti = document.getElementById('btn-import-multi');
        const btnExportMulti = document.getElementById('btn-export-multi');

        if (btnImportMulti) {
            btnImportMulti.addEventListener('click', () => {
                DebugPrint("Click en Importar Múltiples.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        if (btnExportMulti) {
            btnExportMulti.addEventListener('click', () => {
                DebugPrint("Click en Exportar Múltiples.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        // ==========================================
        // BLOQUE 1: PERSONAJES
        // ==========================================
        const btnBuySlot = document.getElementById('btn-buy-slot');
        if (btnBuySlot) {
            btnBuySlot.addEventListener('click', () => {
                DebugPrint("Click en Comprar Slots.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnRestoreChar = document.getElementById('btn-restore-char');
        if (btnRestoreChar) {
            btnRestoreChar.addEventListener('click', () => {
                DebugPrint("Click en Restaurar Personaje.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnFavoriteChar = document.getElementById('btn-favorite-char');
        if (btnFavoriteChar) {
            btnFavoriteChar.addEventListener('click', () => {
                DebugPrint("Click en Marcar Favorito.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnExportChar = document.getElementById('btn-export-char');
        if (btnExportChar) {
            btnExportChar.addEventListener('click', () => {
                DebugPrint("Click en Exportar Personaje.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnImportChar = document.getElementById('btn-import-char');
        if (btnImportChar) {
            btnImportChar.addEventListener('click', () => {
                DebugPrint("Click en Importar Personaje.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        // ==========================================
        // BLOQUE 2: PREFERENCIAS
        // ==========================================
        const btnDefaultChar = document.getElementById('btn-default-char');
        if (btnDefaultChar) {
            btnDefaultChar.addEventListener('click', () => {
                DebugPrint("Click en Personaje por Defecto.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnSpawnPref = document.getElementById('btn-spawn-pref');
        if (btnSpawnPref) {
            btnSpawnPref.addEventListener('click', () => {
                DebugPrint("Click en Spawn Preferido.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnHideLocked = document.getElementById('btn-hide-locked');
        if (btnHideLocked) {
            btnHideLocked.addEventListener('click', () => {
                DebugPrint("Click en Ocultar Bloqueados.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        const btnSoundToggle = document.getElementById('btn-sound-toggle');
        if (btnSoundToggle) {
            btnSoundToggle.addEventListener('click', () => {
                DebugPrint("Click en Sonidos de Interfaz.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }

        // ==========================================
        // BLOQUE 3: SOPORTE
        // ==========================================
        const btnReportBug = document.getElementById('btn-report-bug');
        if (btnReportBug) {
            btnReportBug.addEventListener('click', () => {
                DebugPrint("Click en Reportar Bug.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Abriendo reporte de bugs vinculado a DP-AdminMenu...");
            });
        }

        const btnDiscord = document.getElementById('btn-discord');
        if (btnDiscord) {
            btnDiscord.addEventListener('click', () => {
                DebugPrint("Click en Discord.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible: abre tu Discord");
            });
        }

        const btnTerms = document.getElementById('btn-terms');
        if (btnTerms) {
            btnTerms.addEventListener('click', () => {
                DebugPrint("Click en Términos del Servidor.");
                if (typeof Sounds !== 'undefined') Sounds.playSelect();
                alert("Próximamente disponible");
            });
        }
    })();
});

// ===============================================
// === FUNCIONES DE APOYO (RUTEO DE PANTALLAS) ===
// ===============================================
// Función maestra para cambiar entre las secciones de la UI de forma limpia
function showScreen(screenId) {
    DebugPrint("Cambiando pantalla a: " + screenId);
    document.getElementById('landing-screen').style.display = "none";
    document.getElementById('character-list').style.display = "none";
    document.getElementById('character-register').style.display = "none";
    document.getElementById('options-screen').style.display = "none";

    document.getElementById(screenId).style.display = screenId === "landing-screen" ? "flex" : "block";

    if (screenId === "landing-screen") {
        document.querySelectorAll('.landing-bg').forEach(bg => bg.classList.remove('show'));
        document.getElementById('bg-' + (currentLandingIndex + 1)).classList.add('show');
    } else if (screenId === "options-screen") {
        // Asegurar que el fondo de opciones tenga la clase show
        const bgOpt = document.getElementById('bg-options');
        if (bgOpt) bgOpt.classList.add('show');
    }
}

// === SELECCIONAR / ENFOCAR UN SLOT (click inicial o navegación con flechas) ===
// animateDirection: 0 = sin animación (primer click), 1 = siguiente (derecha), -1 = anterior (izquierda)
function selectSlot(slotId, animateDirection = 0) {
    DebugPrint("Ejecutando selectSlot para el slot: " + slotId);
    document.querySelectorAll('.char-slot').forEach(el => el.classList.remove('active'));
    const slotEl = document.querySelector(`.char-slot[data-slot="${slotId}"]`);
    if (slotEl) slotEl.classList.add('active');

    selectedSlot = slotId;
    const charData = charactersData.find(c => c.cid === slotId);

    // Ocultar el título superior al seleccionar un personaje
    document.querySelector('.top-title').classList.add('hidden');

    // Mostrar botonera de acción principal
    document.getElementById('action-buttons').style.display = "flex";

    // Ocultar los contenedores de los slots mientras la cámara se enfoca
    document.getElementById('slots-wrapper').classList.add('slots-hidden');

    isZoomed = true;
    setFooterZoomState(true); // Al enfocar un personaje mostramos indicaciones de MOVER + SELECCIONAR + SALIR

    // El zoom/pan de cámara ya se anima suavemente en el cliente Lua.
    axios.post(`https://${resName}/focusCharacter`, JSON.stringify({ slot: slotId }));

    const panel = document.getElementById('detailed-char-info');
    const panelBody = panel.querySelector('.panel-body');
    const panelWasVisible = !panel.classList.contains('hidden');

    // Aplica el contenido correspondiente (datos del personaje o pantalla de "crear")
    function applyContent() {
        if (charData) {
            DebugPrint("Slot ocupado. Renderizando estadísticas del personaje.");
            document.getElementById('action-header-text').innerText = Translate('ui_selected_character', 'PERSONAJE SELECCIONADO');
            document.getElementById('action-btn-text').innerText = Translate('ui_play', 'JUGAR');
            updateDetailedPanel(charData);
        } else {
            DebugPrint("Slot vacío. Preparando interfaz de Nuevo Personaje.");
            document.getElementById('detailed-char-info').classList.add('hidden');
            document.getElementById('action-header-text').innerText = Translate('ui_new_character', 'NUEVO PERSONAJE');
            document.getElementById('action-btn-text').innerText = Translate('ui_create', 'CREAR');

            // Se solicita la previsualización del ped (sombra de hombre por defecto)
            axios.post(`https://${resName}/previewPed`, JSON.stringify({
                gender: "Masculino",
                slot: slotId
            }));
        }
    }

    if (animateDirection !== 0 && panelBody && panelWasVisible && charData) {
        // Navegando con flechas y el panel ya está visible con un personaje:
        // solo cambiamos el contenido interno con un crossfade (desvanecimiento), el panel NO se oculta.
        panelBody.classList.add('content-fading');
        setTimeout(() => {
            applyContent();
            panelBody.classList.remove('content-fading');
        }, 140);
    } else {
        // Primera selección (o pasamos a un slot vacío): comportamiento normal de aparición del panel completo
        applyContent();
    }

    if (typeof Sounds !== 'undefined') Sounds.playNav();
}

let navQueue = [];
let isNavigating = false;
const NAV_STEP_DURATION = 850; // Debe ser >= al tiempo que tarda la cámara en moverse en cl_main.lua (800ms)

// === NAVEGAR AL PERSONAJE ANTERIOR (-1) O SIGUIENTE (+1) DE FORMA CÍCLICA ===
// Si se pulsa varias veces rápido, encolamos cada paso para que la cámara
// pase visualmente por todos los personajes intermedios en vez de dar saltos raros.
function navigateCharacter(direction) {
    if (!isZoomed || selectedSlot === null || maxSlots <= 1) return;
    navQueue.push(direction);
    processNavQueue();
}

function processNavQueue() {
    if (isNavigating || navQueue.length === 0) return;

    isNavigating = true;
    const direction = navQueue.shift();

    let newSlot = selectedSlot + direction;
    if (newSlot < 1) newSlot = maxSlots;
    if (newSlot > maxSlots) newSlot = 1;

    DebugPrint("Navegando al slot: " + newSlot);
    selectSlot(newSlot, direction);
    pulseArrow(direction);

    // Esperamos a que termine esta transición (cámara + fade) antes de procesar el siguiente paso en la cola
    setTimeout(() => {
        isNavigating = false;
        processNavQueue();
    }, NAV_STEP_DURATION);
}

// === ANIMACIÓN DE "PULSADO" EN LAS FLECHAS (clic con ratón o tecla del teclado) ===
function pulseArrow(direction) {
    const el = document.querySelector(direction > 0 ? '.action-arrows-right' : '.action-arrows-left');
    if (!el) return;
    el.classList.add('pressed');
    setTimeout(() => el.classList.remove('pressed'), 180);
}

// === FUNCIÓN PARA ACTUALIZAR EL PANEL DE ESTADÍSTICAS DEL PERSONAJE ===
function updateDetailedPanel(charData) {
    if (!charData) {
        document.getElementById('detailed-char-info').classList.add('hidden');
        return;
    }

    // 1. Identidad básica
    document.getElementById('det-name').innerText = `${charData.charinfo.firstname} ${charData.charinfo.lastname}`;
    document.getElementById('det-dob').innerText = charData.charinfo.birthdate;
    const nationalityId = String(charData.charinfo.nationality || '').toLowerCase();
    const nationality = nationalitiesData.find((item) => String(item.id).toLowerCase() === nationalityId);
    document.getElementById('det-nat').innerText = nationality ? nationality.label : (charData.charinfo.nationality || '---');
    document.getElementById('det-gender').innerText = charData.charinfo.gender === 0 ? "Masculino" : "Femenino";

    // 2. Economía y Teléfono
    document.getElementById('det-cash').innerText = `$${(charData.money.cash || 0).toLocaleString()}`;
    document.getElementById('det-bank').innerText = `$${(charData.money.bank || 0).toLocaleString()}`;

    let phone = charData.charinfo.phone;
    if (!phone && charData.metadata && charData.metadata.phonedata) {
        // Fallback por si usan otro sistema de teléfono basado en metadata
        phone = charData.metadata.phonedata.SerialNumber;
    }
    document.getElementById('det-phone').innerText = phone || "No asignado";

    // 3. Trabajo civil/oficial
    let rowJob = document.getElementById('row-job');
    const hasJob = charData.job && charData.job.name !== "unemployed";
    if (hasJob) {
        let badge = charData.job.isboss ? `<span class="boss-badge">JEFE</span>` : '';
        document.getElementById('det-job').innerHTML = `${charData.job.label} - ${charData.job.grade.name} ${badge}`;
        rowJob.style.display = "flex";
    } else {
        rowJob.style.display = "none";
    }

    // 4. Banda/Gang ilegal
    let rowGang = document.getElementById('row-gang');
    const hasGang = charData.gang && charData.gang.name !== "none";
    if (hasGang) {
        let badge = charData.gang.isboss ? `<span class="boss-badge">LÍDER</span>` : '';
        document.getElementById('det-gang').innerHTML = `${charData.gang.label} - ${charData.gang.grade.name} ${badge}`;
        rowGang.style.display = "flex";
    } else {
        rowGang.style.display = "none";
    }
    document.getElementById('group-factions').style.display = hasJob || hasGang ? 'block' : 'none';

    // 5. Tiempo jugado (Metadatos)
    let rawPlaytime = (charData.metadata && charData.metadata.playtime) ? parseInt(charData.metadata.playtime) : 0;
    if (isNaN(rawPlaytime)) rawPlaytime = 0;
    let hours = Math.floor(rawPlaytime / 3600);
    let mins = Math.floor((rawPlaytime % 3600) / 60);
    document.getElementById('det-playtime').innerText = `${hours}h ${mins}m`;

    // 6. Última visita al servidor
    let lastSeen = charData.last_updated ? formatDateTime(charData.last_updated) : "Desconocido";
    document.getElementById('det-lastseen').innerText = lastSeen;

    // 7. Sistema de Skills/Habilidades (Dinámico)
    let skillsContainer = document.getElementById('det-skills-container');
    let groupSkills = document.getElementById('group-skills');
    skillsContainer.innerHTML = '';

    let skillsObj = (charData.metadata && (charData.metadata.skills || charData.metadata.Skills)) || null;
    // Si viene como string escapado, intentar parsear
    if (typeof skillsObj === 'string') {
        try { skillsObj = JSON.parse(skillsObj); } catch (e) { skillsObj = null; }
    }

    if (skillsObj && Object.keys(skillsObj).length > 0) {
        groupSkills.style.display = 'block';
        // Iconografía base para las habilidades típicas de FiveM
        const skillIcons = {
            'strength': 'fa-dumbbell',
            'cardio': 'fa-heart-pulse',
            'driving': 'fa-car',
            'shooting': 'fa-crosshairs',
            'farming': 'fa-seedling',
            'fishing': 'fa-fish',
            'mining': 'fa-hammer',
            'crafting': 'fa-screwdriver-wrench',
            'gathering': 'fa-boxes-stacked'
        };

        for (const [skillName, skillData] of Object.entries(skillsObj)) {
            let pct = Math.min(Math.max(skillData.Current || 0, 0), 100);
            let icon = skillData.icon || skillIcons[skillName.toLowerCase()] || 'fa-star';

            const skillDiv = document.createElement('div');
            skillDiv.className = 'skill-item';
            skillDiv.innerHTML = `
                <div class="skill-header">
                    <span class="skill-name"><i class="fas ${icon}"></i> ${skillName}</span>
                    <span class="skill-pct">${pct}%</span>
                </div>
                <div class="skill-bar-bg">
                    <div class="skill-bar-fill" style="width: 0%"></div>
                </div>
            `;
            skillsContainer.appendChild(skillDiv);
        }

        // Animación progresiva de las barras de progreso de skills
        setTimeout(() => {
            const fills = skillsContainer.querySelectorAll('.skill-bar-fill');
            const skills = Object.values(skillsObj);
            fills.forEach((fill, index) => {
                if (skills[index]) {
                    let pct = Math.min(Math.max(skills[index].Current || 0, 0), 100);
                    fill.style.width = `${pct}%`;
                }
            });
        }, 100);
    } else {
        groupSkills.style.display = 'none'; // Si no hay habilidades, ocultar panel
    }

    // Mostrar panel lateral completo
    document.getElementById('detailed-char-info').classList.remove('hidden');
}

// Configura la visibilidad y texto dinámico del Landing Screen en base a los personajes existentes
function updateLandingScreen() {
    const playBtn = document.getElementById('btn-land-play');
    const textSpan = document.getElementById('text-last-char');
    const nameSpan = document.getElementById('last-character-name');

    if (lastCharacter) {
        playBtn.classList.remove('disabled');
        textSpan.innerText = Translate('ui_continue_button', 'CONTINÚA CON TU HISTORIA');
        nameSpan.innerText = `${lastCharacter.charinfo.firstname} ${lastCharacter.charinfo.lastname}`;
    } else {
        playBtn.classList.add('disabled');
        textSpan.innerText = Translate('ui_continue_button', 'CONTINÚA CON TU HISTORIA');
        nameSpan.innerText = '';
        currentLandingIndex = 1; // Forzar foco de inicio a la lista "Personajes" si no hay ninguno creado
    }
}

function formatDateTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;

    const pad = (number) => String(number).padStart(2, '0');
    return `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()}, ` +
        `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

// Construye e inyecta los contenedores (slots) HTML para cada ranura de personaje permitida
function renderSlots() {
    DebugPrint("Renderizando HTML de slots (" + maxSlots + " totales).");
    const wrapper = document.getElementById('slots-wrapper');
    wrapper.innerHTML = '';

    for (let i = 1; i <= maxSlots; i++) {
        const char = charactersData.find(c => c.cid === i);

        if (char) {
            // Slot ocupado
            wrapper.innerHTML += `
                <div class="char-slot" data-slot="${i}">
                    <div class="slot-details">
                        <span class="slot-name">${char.charinfo.firstname} ${char.charinfo.lastname}</span>
                    </div>
                </div>
            `;
        } else {
            // Slot vacío (con icono de más)
            wrapper.innerHTML += `
                <div class="char-slot empty-slot" data-slot="${i}">
                    <span class="material-symbols-outlined slot-icon">add</span>
                </div>
            `;
        }
    }
}

// Limpia el formulario de registro para evitar que queden datos cacheados
function resetForm() {
    document.getElementById('reg-firstname').value = '';
    document.getElementById('reg-lastname').value = '';
    document.getElementById('reg-dob').value = '';
    selectedNationality = null;
    document.getElementById('nationality-text').innerText = Translate('ui_search_country', 'Selecciona un país de nacimiento');
    document.getElementById('nationality-display').classList.remove('selected');
    document.getElementById('nationality-search').value = '';
    document.querySelectorAll('.dropdown-option').forEach((option) => {
        option.style.display = 'flex';
    });
    document.querySelectorAll('.gender-btn').forEach(el => el.classList.remove('active'));
    document.querySelector('[data-gender="Masculino"]').classList.add('active');
    selectedGender = "Masculino";

    // Resetear el selector custom
    selectedNationality = null;
    document.getElementById('nationality-text').innerText = Translate('ui_search_country', 'Selecciona un país de nacimiento');
    document.getElementById('nationality-display').classList.remove('selected');
    document.getElementById('nationality-search').value = '';
    document.querySelectorAll('.dropdown-option').forEach(opt => opt.style.display = 'flex');

    DebugPrint("Formulario de registro reseteado.");
}