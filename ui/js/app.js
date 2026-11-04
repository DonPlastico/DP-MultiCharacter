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
let minAge = 18; // Comodín inicial de seguridad (Se machaca con el Config al abrir)
let maxAge = 100; // Comodín inicial de seguridad (Se machaca con el Config al abrir)
let flatpickrInstance = null; // Referencia global a la instancia del datepicker para poder recalcularla si cambian minAge/maxAge
let interfaceVolume = 100; // Volumen (0-100) de los sonidos de interfaz; se carga de localStorage al iniciar
let trashedSlots = 0; // Nº de slots ocupados por personajes en la papelera (PROCESO_ELIMINACION)
let randomSlotGenders = {}; // Variable para guardar los géneros
let hideLockedSlots = false; // Si true, los slots vacíos ("bloqueados") NO se muestran en el selector
const HIDE_LOCKED_STORAGE_KEY = "dpmc_hide_locked"; // localStorage (fallback rápido solo-UI)
const VOLUME_STORAGE_KEY = "dpmc_interface_volume"; // localStorage (arranque rápido, la BD manda)
let exportCharactersEnabled = true; // Config.ExportCharacters (Lua manda el valor real al abrir la UI)
let importCharactersEnabled = true; // Config.ImportCharacters (Lua manda el valor real al abrir la UI)
let startingItemsData = []; // Los items que nos manda Lua desde el config
let startingBudget = 0; // El dinero que nos dice Lua que tendremos al empezar
let cartItems = {}; // { "water": 2, "bread": 1 }
let cartTotal = 0; // Total a pagar

// ==========================================
// 🛡️ CONFIGURACIÓN GLOBAL DE RED (AXIOS)
// ==========================================
// Establecer un timeout máximo de 8 segundos (8000ms) para TODAS las peticiones
axios.defaults.timeout = 8000;

// Interceptor para capturar automáticamente CUALQUIER error de conexión
axios.interceptors.response.use(
  (response) => response,
  (error) => {
    DebugPrint("Error de red interceptado: " + (error.message || error));

    let errorMsg = Translate(
      "ui_error_server",
      "Error interno al procesar la solicitud en el servidor.",
    );

    // Comprobar si el error fue por superar el timeout
    if (
      error.code === "ECONNABORTED" ||
      (error.message && error.message.includes("timeout"))
    ) {
      errorMsg = Translate(
        "ui_error_timeout",
        "Tiempo de espera agotado. El servidor no responde o se ha reiniciado.",
      );
    }

    // Alerta visual con el modal custom
    showAlert(errorMsg, Translate("ui_error_title", "ERROR DE CONEXIÓN"), "error");

    // Rechazar la promesa para que salte a los .catch() individuales y libere los botones
    return Promise.reject(error);
  },
);

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
  document.querySelectorAll("[data-trans]").forEach((el) => {
    const key = el.getAttribute("data-trans");
    if (translations[key]) {
      el.innerText = translations[key];
    }
  });

  // Traducir placeholders de inputs
  document.querySelectorAll("[data-trans-placeholder]").forEach((el) => {
    const key = el.getAttribute("data-trans-placeholder");
    if (translations[key]) {
      el.setAttribute("placeholder", translations[key]);
    }
  });
}

// === MUESTRA/OCULTA "MOVER" Y "SELECCIONAR" DEL FOOTER SEGÚN SI HAY UN PERSONAJE ENFOCADO ===
function setFooterZoomState(zoomed) {
  const moveEl = document.getElementById("footer-move");
  const selectEl = document.getElementById("footer-select");
  if (moveEl) moveEl.style.display = zoomed ? "flex" : "none";
  if (selectEl) selectEl.style.display = zoomed ? "flex" : "none";
  DebugPrint("Estado del footer actualizado. Zoomed: " + zoomed);
}

// ==========================================
// 🔒 BLOQUEO GLOBAL DE UI DURANTE LOADINGS
// ==========================================
// Mientras cualquier acción async está en curso (crear personaje, jugar, borrar,
// restaurar, comprar slot...), el usuario podía seguir pulsando OTROS botones,
// abrir otros modales, cancelar con Escape, navegar con flechas, etc. — eso podía
// disparar peticiones simultáneas/contradictorias a Lua y romper el estado del
// script (p.ej. cancelar la creación de un personaje a medio crear). Para evitarlo,
// isUILocked se activa junto con CUALQUIER setButtonLoading(btn, true), y un overlay
// invisible a pantalla completa captura todos los clics mientras tanto. El listener
// global de teclado (Escape/Enter/flechas) comprueba esta misma bandera y no hace
// nada si está bloqueado. Se cuenta con un contador (no un booleano simple) por si
// en algún momento hubiera dos loadings solapados; solo se desbloquea cuando el
// último de ellos termina.
let isUILocked = false;
let uiLockCount = 0;
let uiLockOverlayEl = null;

function getUILockOverlay() {
  if (!uiLockOverlayEl) {
    uiLockOverlayEl = document.createElement("div");
    uiLockOverlayEl.id = "ui-lock-overlay";
    uiLockOverlayEl.style.position = "fixed";
    uiLockOverlayEl.style.top = "0";
    uiLockOverlayEl.style.left = "0";
    uiLockOverlayEl.style.width = "100%";
    uiLockOverlayEl.style.height = "100%";
    uiLockOverlayEl.style.zIndex = "99999"; // Por encima de cualquier modal (incluido modal-alert)
    uiLockOverlayEl.style.background = "transparent";
    uiLockOverlayEl.style.display = "none";
    uiLockOverlayEl.style.cursor = "wait";
    // Capturamos y anulamos el clic en fase de captura, antes de que llegue a
    // ningún otro listener delegado (incluido el de sonidos), para que ni
    // siquiera suene nada mientras la UI está bloqueada.
    uiLockOverlayEl.addEventListener(
      "click",
      (e) => {
        e.stopPropagation();
        e.preventDefault();
      },
      true,
    );
    document.body.appendChild(uiLockOverlayEl);
  }
  return uiLockOverlayEl;
}

function lockUI() {
  uiLockCount++;
  isUILocked = true;
  getUILockOverlay().style.display = "block";
  DebugPrint("UI bloqueada (loadings activos: " + uiLockCount + ").");
}

function unlockUI() {
  uiLockCount = Math.max(0, uiLockCount - 1);
  if (uiLockCount === 0) {
    isUILocked = false;
    getUILockOverlay().style.display = "none";
    DebugPrint("UI desbloqueada (sin loadings activos).");
  } else {
    DebugPrint("UI sigue bloqueada (loadings activos restantes: " + uiLockCount + ").");
  }
}

// ==========================================
// ⏳ ESTADOS DE CARGA (LOADING)
// ==========================================
function setButtonLoading(btn, isLoading) {
  if (!btn) return;
  if (isLoading) {
    // Guardamos el HTML original si no se ha guardado aún
    if (!btn.dataset.originalHtml) {
      btn.dataset.originalHtml = btn.innerHTML;
    }
    // Fijamos el ancho actual para evitar que el botón "encoja" al poner el spinner
    btn.style.minWidth = btn.offsetWidth + "px";
    btn.disabled = true;
    btn.style.pointerEvents = "none";
    btn.innerHTML = '<i class="fas fa-circle-notch fa-spin"></i>';
    lockUI();
  } else {
    btn.disabled = false;
    btn.style.pointerEvents = "auto";
    if (btn.dataset.originalHtml) {
      btn.innerHTML = btn.dataset.originalHtml;
    }
    btn.style.minWidth = "";
    unlockUI();
  }
}

// ==========================================
// 📅 FUNCIONES GLOBALES DEL CALENDARIO CUSTOM
// ==========================================
function getAgeYearRange() {
  const currentYear = new Date().getFullYear();
  const newestYear = currentYear - minAge; // Año más reciente permitido (el más "joven")
  const oldestYear = currentYear - maxAge; // Año más antiguo permitido (el más "mayor")
  return { newestYear, oldestYear };
}

function applyAgeLimitsToFlatpickr(instance) {
  const { newestYear, oldestYear } = getAgeYearRange();

  // SOLUCIÓN ZONA HORARIA: Usar new Date(año, mes, día) evita que el límite del 31 de Dic
  // se mueva al 30 de Dic por culpa del uso horario local del jugador.
  instance.set("minDate", new Date(oldestYear, 0, 1));
  instance.set("maxDate", new Date(newestYear, 11, 31));

  // EL TRUCO DEFINITIVO: Sobreescribimos el "hoy" interno de Flatpickr
  instance.now = new Date(newestYear, 0, 1, 12, 0, 0);

  DebugPrint(
    `Límites del datepicker recalculados. Años permitidos: ${oldestYear} - ${newestYear}`,
  );
}

// ==========================================
// ⚠️ SISTEMA DE ALERTAS CUSTOM (Sustituye alert())
// ==========================================
function showAlert(msg, title = "ATENCIÓN", type = "error") {
  const modal = document.getElementById("modal-alert");
  document.getElementById("alert-title").innerText = title;
  document.getElementById("alert-message").innerText = msg;

  const icon = document.getElementById("alert-icon");
  if (type === "error") {
    icon.className = "fas fa-exclamation-triangle warning-icon";
  } else {
    icon.className = "fas fa-info-circle modal-icon";
  }

  modal.style.display = "flex";
}

document.addEventListener("DOMContentLoaded", () => {
  DebugPrint("DOM cargado. Inicializando eventos principales de la interfaz.");

  // Botón de cierre del modal de alerta
  const btnAlertOk = document.getElementById("btn-alert-ok");
  if (btnAlertOk) {
    btnAlertOk.addEventListener("click", () => {
      document.getElementById("modal-alert").style.display = "none";
    });
  }

  // Cargar el volumen de interfaz guardado (localStorage por ahora; ver saveInterfaceVolume)
  const storedVolume = localStorage.getItem("dpmc_interface_volume");
  if (storedVolume !== null) {
    const parsedVolume = parseInt(storedVolume);
    if (!isNaN(parsedVolume)) interfaceVolume = Math.max(0, Math.min(100, parsedVolume));
  }

  // Cargar la preferencia de "Ocultar Bloqueados" guardada (localStorage por ahora; ver Lua)
  const storedHideLocked = localStorage.getItem(HIDE_LOCKED_STORAGE_KEY);
  if (storedHideLocked !== null && storedHideLocked !== "") {
    hideLockedSlots = storedHideLocked === "true";
  }
  DebugPrint("Preferencia 'Ocultar Bloqueados' cargada: " + hideLockedSlots);

  const MONTH_NAMES_ES = [
    "Enero",
    "Febrero",
    "Marzo",
    "Abril",
    "Mayo",
    "Junio",
    "Julio",
    "Agosto",
    "Septiembre",
    "Octubre",
    "Noviembre",
    "Diciembre",
  ];

  // Construye el panel de selección de MES (grid 3x4) dentro del stack de días
  function buildMonthPicker(instance, stack) {
    const panel = document.createElement("div");
    panel.className = "fp-month-picker";

    // SOLUCIÓN BUG DEL SCROLL: Bloqueamos que la rueda del ratón cambie los meses de Flatpickr
    panel.addEventListener("wheel", (e) => e.stopPropagation());

    // Título dinámico
    const title = document.createElement("div");
    title.className = "fp-panel-title";
    title.innerText = "Selecciona el Mes";
    panel.appendChild(title);

    const grid = document.createElement("div");
    grid.className = "fp-picker-grid";

    MONTH_NAMES_ES.forEach((name, index) => {
      const btn = document.createElement("div");
      btn.className = "fp-month-btn";
      btn.innerText = name;
      btn.dataset.month = index;
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        // SOLUCIÓN BUG DEL MES EXACTO: Solo le pasamos el "index" y false.
        instance.changeMonth(index, false);
        closePickerPanels(panel, yearPanelRef, instance);
      });
      grid.appendChild(btn);
    });

    const closeBtn = document.createElement("div");
    closeBtn.className = "fp-close-picker";
    closeBtn.innerHTML = '<span class="material-symbols-outlined">keyboard_arrow_up</span>';
    closeBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      closePickerPanels(panel, yearPanelRef, instance);
    });

    panel.appendChild(grid);
    panel.appendChild(closeBtn);
    stack.appendChild(panel);
    return panel;
  }

  // Construye el panel de selección de AÑO (lista en scroll) dentro del stack de días
  function buildYearPicker(instance, stack) {
    const panel = document.createElement("div");
    panel.className = "fp-year-picker";

    // SOLUCIÓN BUG DEL SCROLL: Bloqueamos que la rueda del ratón cambie los meses por detrás
    panel.addEventListener("wheel", (e) => e.stopPropagation());

    // Título dinámico
    const title = document.createElement("div");
    title.className = "fp-panel-title";
    title.innerText = "Selecciona el Año";
    panel.appendChild(title);

    const list = document.createElement("div");
    list.className = "fp-picker-list";
    panel.appendChild(list);

    const closeBtn = document.createElement("div");
    closeBtn.className = "fp-close-picker";
    closeBtn.innerHTML = '<span class="material-symbols-outlined">keyboard_arrow_up</span>';
    closeBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      closePickerPanels(monthPanelRef, panel, instance);
    });
    panel.appendChild(closeBtn);

    stack.appendChild(panel);
    return panel;
  }

  // Rellena (o refresca) la lista de años
  function populateYearPicker(instance, yearPanel) {
    const list = yearPanel.querySelector(".fp-picker-list");
    list.innerHTML = "";

    const { newestYear, oldestYear } = getAgeYearRange();

    for (let year = newestYear; year >= oldestYear; year--) {
      const btn = document.createElement("div");
      btn.className = "fp-year-btn";
      btn.innerText = year;
      btn.dataset.year = year;
      if (year === instance.currentYear) btn.classList.add("selected");

      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        instance.changeYear(year);
        closePickerPanels(monthPanelRef, yearPanel, instance); // <--- Pasamos instance
      });

      list.appendChild(btn);
    }
  }

  // Cierra ambos paneles y vuelve a MOSTRAR la grid de días
  function closePickerPanels(monthPanel, yearPanel, instance) {
    if (monthPanel) monthPanel.classList.remove("visible");
    if (yearPanel) yearPanel.classList.remove("visible");
    if (instance && instance.calendarContainer) {
      instance.calendarContainer.classList.remove("fp-panel-open"); // <--- Muestra los días
    }
  }

  function syncPickerSelection(instance, monthPanel, yearPanel) {
    monthPanel.querySelectorAll(".fp-month-btn").forEach((btn) => {
      btn.classList.toggle("selected", parseInt(btn.dataset.month) === instance.currentMonth);
    });
    yearPanel.querySelectorAll(".fp-year-btn").forEach((btn) => {
      btn.classList.toggle("selected", parseInt(btn.dataset.year) === instance.currentYear);
    });
  }

  let monthPanelRef = null;
  let yearPanelRef = null;

  // --- INICIALIZAR FLATPICKR (CALENDARIO CUSTOM) ---
  flatpickrInstance = flatpickr("#reg-dob", {
    dateFormat: "Y-m-d",
    disableMobile: true,
    locale: "es",
    static: true,
    onOpen: function (selectedDates, dateStr, instance) {
      if (selectedDates.length === 0) {
        const { newestYear } = getAgeYearRange();
        instance.jumpToDate(new Date(newestYear, 0, 1));
        if (instance.currentYearElement) instance.currentYearElement.value = newestYear;
        const monthDisplay = instance.calendarContainer.querySelector(
          ".fp-custom-month-display",
        );
        if (monthDisplay) monthDisplay.innerText = MONTH_NAMES_ES[0];
        if (yearPanelRef && monthPanelRef) {
          populateYearPicker(instance, yearPanelRef);
          syncPickerSelection(instance, monthPanelRef, yearPanelRef);
        }
      }
    },
    onClose: function (selectedDates, dateStr, instance) {
      closePickerPanels(monthPanelRef, yearPanelRef, instance);
    },
    onReady: function (selectedDates, dateStr, instance) {
      const header = instance.monthNav;
      const yearInputWrapper = instance.currentYearElement.parentNode;
      const prevMonthBtn = instance.prevMonthNav;
      const nextMonthBtn = instance.nextMonthNav;

      const parentGroup = instance.element.closest(".input-group");
      if (parentGroup) {
        parentGroup.style.position = "relative";
      }

      applyAgeLimitsToFlatpickr(instance);
      header.innerHTML = "";

      // --- FILA 1: SELECTOR DE AÑO ---
      const yearRow = document.createElement("div");
      yearRow.className = "fp-custom-row fp-custom-year";

      const btnPrevYear = document.createElement("div");
      btnPrevYear.className = "fp-custom-btn";
      btnPrevYear.innerHTML = '<i class="fas fa-angle-double-left"></i>';
      btnPrevYear.addEventListener("click", (e) => {
        e.stopPropagation();
        if (btnPrevYear.classList.contains("disabled")) return; // Bloquea el click si está deshabilitado
        instance.changeYear(instance.currentYear - 1);
      });

      const btnNextYear = document.createElement("div");
      btnNextYear.className = "fp-custom-btn";
      btnNextYear.innerHTML = '<i class="fas fa-angle-double-right"></i>';
      btnNextYear.addEventListener("click", (e) => {
        e.stopPropagation();
        if (btnNextYear.classList.contains("disabled")) return; // Bloquea el click si está deshabilitado
        instance.changeYear(instance.currentYear + 1);
      });

      yearRow.appendChild(btnPrevYear);
      yearRow.appendChild(yearInputWrapper);
      yearRow.appendChild(btnNextYear);
      yearInputWrapper
        .querySelectorAll(".arrowUp, .arrowDown")
        .forEach((el) => (el.style.display = "none"));

      // --- FUNCIÓN PARA BLOQUEAR FLECHAS DE AÑO ---
      instance.updateYearButtons = function () {
        const { newestYear, oldestYear } = getAgeYearRange();
        // Alterna la clase 'disabled' basándose en los límites
        btnPrevYear.classList.toggle("disabled", instance.currentYear <= oldestYear);
        btnNextYear.classList.toggle("disabled", instance.currentYear >= newestYear);
      };

      // Ejecutamos la comprobación por primera vez
      instance.updateYearButtons();

      // --- FILA 2: SELECTOR DE MES ---
      const monthRow = document.createElement("div");
      monthRow.className = "fp-custom-row fp-custom-month";

      prevMonthBtn.innerHTML = '<i class="fas fa-angle-left"></i>';
      prevMonthBtn.className = "fp-custom-btn";

      nextMonthBtn.innerHTML = '<i class="fas fa-angle-right"></i>';
      nextMonthBtn.className = "fp-custom-btn";

      const monthDisplay = document.createElement("div");
      monthDisplay.className = "fp-custom-month-display";
      monthDisplay.innerText = MONTH_NAMES_ES[instance.currentMonth];

      monthRow.appendChild(prevMonthBtn);
      monthRow.appendChild(monthDisplay);
      monthRow.appendChild(nextMonthBtn);

      header.appendChild(yearRow);
      header.appendChild(monthRow);

      // --- ENVOLVER GRID DE DÍAS Y CREAR PANELES ---
      const daysContainer = instance.daysContainer;
      const stack = document.createElement("div");
      stack.className = "fp-days-stack";
      daysContainer.parentNode.insertBefore(stack, daysContainer);
      stack.appendChild(daysContainer);

      monthPanelRef = buildMonthPicker(instance, stack);
      yearPanelRef = buildYearPicker(instance, stack);
      populateYearPicker(instance, yearPanelRef);
      syncPickerSelection(instance, monthPanelRef, yearPanelRef);

      // --- EVENTOS CLICK: OCULTAN LOS DÍAS AL ABRIR ---
      monthDisplay.addEventListener("click", (e) => {
        e.stopPropagation();
        closePickerPanels(null, yearPanelRef, instance);
        syncPickerSelection(instance, monthPanelRef, yearPanelRef);
        monthPanelRef.classList.add("visible");
        instance.calendarContainer.classList.add("fp-panel-open");
      });

      yearInputWrapper.querySelector(".numInput.cur-year").addEventListener("click", (e) => {
        e.stopPropagation();
        closePickerPanels(monthPanelRef, null, instance);
        populateYearPicker(instance, yearPanelRef);
        yearPanelRef.classList.add("visible");
        instance.calendarContainer.classList.add("fp-panel-open");
      });
    },
    onMonthChange: function (selectedDates, dateStr, instance) {
      const display = instance.calendarContainer.querySelector(".fp-custom-month-display");
      if (display) display.innerText = MONTH_NAMES_ES[instance.currentMonth];
      if (monthPanelRef && yearPanelRef)
        syncPickerSelection(instance, monthPanelRef, yearPanelRef);
      if (instance.updateYearButtons) instance.updateYearButtons(); // Re-comprobar bloqueos
    },
    onYearChange: function (selectedDates, dateStr, instance) {
      const display = instance.calendarContainer.querySelector(".fp-custom-month-display");
      if (display) display.innerText = MONTH_NAMES_ES[instance.currentMonth];
      if (monthPanelRef && yearPanelRef) {
        populateYearPicker(instance, yearPanelRef);
        syncPickerSelection(instance, monthPanelRef, yearPanelRef);
      }
      if (instance.updateYearButtons) instance.updateYearButtons(); // Re-comprobar bloqueos
    },
    onChange: function () {},
  });

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

    document.querySelectorAll(".landing-image-card").forEach((card, index) => {
      const shineDelay = `${delays[index]}s`;
      card.style.setProperty("--shine-delay", shineDelay);

      const reflection = document.getElementById(`ref-card-${index + 1}`);
      if (reflection) {
        reflection.style.setProperty("--shine-delay", shineDelay);
      }
    });
  }

  // Receptor principal de eventos NUI desde Lua
  window.addEventListener("message", (event) => {
    const data = event.data;

    if (data.action === "introTaxiHud") {
      const hud = document.getElementById("intro-taxi-hud");
      if (hud) {
        hud.classList.toggle("visible", data.show === true);
        if (data.destination !== undefined) {
          document.getElementById("intro-taxi-destination").textContent = data.destination || "Taxi en camino";
        }
        if (data.status !== undefined) {
          document.getElementById("intro-taxi-status").textContent = data.status || "";
        }
      }
    } else if (data.action === "toggleUI") {
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

      // Recibir configuración de Starter Items y dinero
      if (data.startingItems) {
        startingItemsData = data.startingItems;
      }
      if (data.startingBudget !== undefined) {
        startingBudget = data.startingBudget;
      }

      // Guardar la edad mínima/máxima configurada en Lua (Config.MinAge / Config.MaxAge)
      // y recalcular los límites del datepicker de fecha de nacimiento en consecuencia.
      if (data.minAge !== undefined) minAge = data.minAge;
      if (data.maxAge !== undefined) maxAge = data.maxAge;
      if (data.randomGenders !== undefined) randomSlotGenders = data.randomGenders;
      if (flatpickrInstance) {
        applyAgeLimitsToFlatpickr(flatpickrInstance);
      }

      // Estado persistente de "Ocultar Bloqueados" enviado desde Lua (KVP):
      // si viene definido, tiene prioridad sobre el localStorage de arranque.
      if (data.hideLocked !== undefined) {
        hideLockedSlots = !!data.hideLocked;
        localStorage.setItem(HIDE_LOCKED_STORAGE_KEY, String(hideLockedSlots));
        DebugPrint(
          "Preferencia 'Ocultar Bloqueados' sincronizada desde Lua: " + hideLockedSlots,
        );
      }
      // Subtexto del sidebar coherente con el estado actual
      const hlSubEl = document.getElementById("hide-locked-sub");
      if (hlSubEl) {
        hlSubEl.innerText = hideLockedSlots
          ? Translate("ui_hide_locked_on", "Solo personajes creados")
          : Translate("ui_hide_locked_off", "Slots vacíos fuera del selector");
      }
      // Si el modal está abierto en ese momento, refrescar su UI
      if (document.getElementById("modal-hide-locked").style.display !== "none") {
        refreshHideLockedUI();
      }

      // Volumen de interfaz persistido en BD (enviado por Lua desde cl_main.lua):
      // si viene definido, tiene prioridad sobre el localStorage de arranque.
      if (data.interfaceVolume !== undefined) {
        interfaceVolume = Math.max(0, Math.min(100, parseInt(data.interfaceVolume) || 0));
        localStorage.setItem(VOLUME_STORAGE_KEY, String(interfaceVolume));
        DebugPrint("Volumen de interfaz sincronizado desde BD: " + interfaceVolume + "%");
      }
      // Si el modal de sonidos está abierto en ese momento, refrescar su UI
      if (
        document.getElementById("modal-sound-toggle").style.display !== "none" &&
        typeof window.refreshSoundSlider === "function"
      ) {
        window.refreshSoundSlider(interfaceVolume);
      }

      // Configuración de ayuda/soporte (Web y/o Discord) enviada desde Lua:
      if (data.helpConfig) {
        helpConfig = data.helpConfig;
        DebugPrint(
          "Configuración de ayuda sincronizada desde Lua: " + JSON.stringify(helpConfig),
        );
      }

      // Visibilidad de Exportar/Importar Personaje según Config.ExportCharacters / Config.ImportCharacters.
      // Si vienen definidos, aplicamos el estado; si no, no tocamos nada (evita ocultar por error
      // en mensajes toggleUI parciales, como el que solo trae interfaceVolume tras abrir la UI).
      if (data.exportCharacters !== undefined) {
        exportCharactersEnabled = !!data.exportCharacters;
      }
      if (data.importCharacters !== undefined) {
        importCharactersEnabled = !!data.importCharacters;
      }
      if (data.exportCharacters !== undefined || data.importCharacters !== undefined) {
        applyExportImportVisibility();
      }

      DebugPrint("Evento 'toggleUI' recibido. Estado: " + data.state);
      document.getElementById("app").style.display = data.state ? "block" : "none";

      if (data.state) {
        resetCharacterListState(); // Limpia cualquier panel/selección residual de una sesión anterior (p.ej. tras /logout)
        showScreen("landing-screen");
        randomizeCardShines();
        DebugPrint("Solicitando setupCharacters a Lua mediante NUI Post.");
        axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
      } else {
        // Si se cierra la UI por completo (entra a jugar), reseteamos los inputs por seguridad
        resetForm();
      }
    } else if (data.action === "setupCharacters") {
      DebugPrint(
        "Evento 'setupCharacters' recibido. Procesando " +
          (data.characters ? data.characters.length : 0) +
          " personajes para " +
          data.slots +
          " slots.",
      );
      charactersData = data.characters;
      maxSlots = data.slots || 4;
      lastCharacter = data.lastCharacter || null;
      trashedSlots = data.trashedSlots || 0; // Slots ocupados por personajes en la papelera (no se listan, pero bloquean el hueco)
      renderSlots();
      updateLandingScreen();
      updateOptionsStats();

      // Si la pantalla de opciones está visible, refresca la tabla
      if (document.getElementById("options-screen").style.display !== "none") {
        OptionsTable.render();
      }
    } else if (data.action === "showLanding") {
      DebugPrint("Evento 'showLanding' recibido. Mostrando menú inicial.");
      showScreen("landing-screen");
    } else if (data.action === "hideLanding") {
      DebugPrint("Evento 'hideLanding' recibido. Ocultando menú inicial.");
      document.getElementById("landing-screen").style.display = "none";
    } else if (data.action === "reorderDone") {
      DebugPrint("Evento 'reorderDone' recibido. Refrescando personajes desde el servidor...");
      // Pedimos la lista fresca al servidor: llegará por 'setupCharacters' y se
      // recalcularán los slots, la tabla, las stats, etc.
      axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
    } else if (data.action === "characterDeleted") {
      DebugPrint(
        "Evento 'characterDeleted' recibido (success: " +
          data.success +
          "). Refrescando lista al instante.",
      );
      // El servidor ya terminó de borrar: pedimos la lista fresca AHORA,
      // sin esperar a que el usuario salga y vuelva a entrar.
      axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
    } else if (data.action === "deletedCharactersList") {
      DebugPrint(
        "Evento 'deletedCharactersList' recibido. Personajes en papelera: " +
          (data.characters ? data.characters.length : 0),
      );
      renderRestoreList(data.characters || []);
    } else if (data.action === "spawnToggleUI") {
      DebugPrint("Evento 'spawnToggleUI' recibido. Estado: " + data.status);

      // Si DP-MultiCharacter ya ha terminado (JUGAR o CONTINÚA), ocultamos su #app
      // para que DP-PauseMenu pueda dibujar su mapa encima SIN superposiciones.
      if (!data.status) {
        document.getElementById("app").style.display = "none";
        // Aseguramos que se limpien TODOS los modales abiertos
        document.querySelectorAll(".modal-overlay").forEach((m) => (m.style.display = "none"));
      }
    }
  });

  // === LÓGICA LANDING SCREEN (RATÓN Y TECLADO) ===
  const landBtns = [
    document.getElementById("btn-land-play"),
    document.getElementById("btn-land-chars"),
    document.getElementById("btn-land-options"),
  ];

  // Actualiza los hovers visuales y los fondos al navegar por el menú principal
  function updateLandingHover(index) {
    landBtns.forEach((btn, i) => {
      if (i === index) {
        btn.classList.add("active");

        // Actualizar fondo asociado al botón activo
        document.querySelectorAll(".landing-bg").forEach((bg) => bg.classList.remove("show"));
        document.getElementById(btn.dataset.target).classList.add("show");

        // Actualizar cards de imagen superiores
        document
          .querySelectorAll(".landing-image-card")
          .forEach((card) => card.classList.remove("active"));
        const cardId = btn.dataset.card;
        if (cardId) {
          document.getElementById(cardId).classList.add("active");
        }

        // Actualizar cards de reflejo inferiores
        document
          .querySelectorAll(".landing-reflection-card")
          .forEach((ref) => ref.classList.remove("active"));
        const refId = `ref-card-${i + 1}`;
        document.getElementById(refId).classList.add("active");
      } else {
        btn.classList.remove("active");
      }
    });
  }

  // Interacción con las cards de imagen (hacer click en una card cambia la selección principal)
  document.querySelectorAll(".landing-image-card").forEach((card, index) => {
    card.addEventListener("click", () => {
      // Solo si el botón correspondiente no está disabled
      const btn = landBtns[index];
      if (!btn.classList.contains("disabled")) {
        DebugPrint("Click en tarjeta de imagen del landing. Índice: " + index);
        currentLandingIndex = index;
        updateLandingHover(currentLandingIndex);
      }
    });

    card.addEventListener("mouseenter", () => {
      if (!card.classList.contains("disabled")) {
        // Solo efecto visual, no cambiar selección automáticamente al pasar el ratón
      }
    });
  });

  // Hover con ratón en los botones principales
  landBtns.forEach((btn, index) => {
    btn.addEventListener("mouseenter", () => {
      if (!btn.classList.contains("disabled")) {
        currentLandingIndex = index;
        updateLandingHover(currentLandingIndex);
      }
    });
  });

  // Navegación principal con flechas del teclado y tecla Escape
  document.addEventListener("keydown", (e) => {
    // Mientras cualquier loading esté activo, ESC/Enter/flechas no deben hacer
    // absolutamente nada (evita cancelar, navegar o confirmar otra acción a medio
    // camino de una petición ya en curso hacia el servidor).
    if (isUILocked) {
      DebugPrint("Tecla ignorada: la UI está bloqueada por un loading en curso.");
      return;
    }

    if (e.key === "Escape") {
      // Cerrar CUALQUIER modal que esté abierto (Borrar, Comprar, Ajustes...)
      const openModals = Array.from(document.querySelectorAll(".modal-overlay")).filter(
        (m) => m.style.display === "flex",
      );
      if (openModals.length > 0) {
        DebugPrint("Cerrando modal mediante tecla ESC.");
        if (typeof Sounds !== "undefined") Sounds.playCancel();
        openModals.forEach((m) => {
          // El modal de ocultar bloqueados descarta los cambios sin guardar
          if (
            m.id === "modal-hide-locked" &&
            typeof window.closeHideLockedModal === "function"
          ) {
            window.closeHideLockedModal(true);
            return;
          }
          m.style.display = "none";
        });
        return;
      }
      // Cancelar el formulario de registro de personaje
      if (document.getElementById("character-register").style.display === "block") {
        DebugPrint("Registro cancelado mediante tecla ESC.");
        document.getElementById("btn-cancel-reg").click(); // El listener global de click ya reproduce sonido
        return;
      }
      // Salir de la pantalla de opciones de vuelta al landing
      if (document.getElementById("options-screen").style.display === "block") {
        DebugPrint("Saliendo de la pantalla de opciones. Volviendo al Landing.");
        if (typeof Sounds !== "undefined") Sounds.playCancel();
        showScreen("landing-screen");
        return;
      }

      // Lógica para salir de la selección de personaje y volver atrás
      if (document.getElementById("character-list").style.display === "block") {
        if (isZoomed) {
          DebugPrint("Quitando zoom y restaurando vista general desde ESC.");
          if (typeof Sounds !== "undefined") Sounds.playCancel();
          isZoomed = false;
          isUnfocusing = true; // Bloquea nuevas selecciones hasta que la cámara termine de alejarse
          navQueue = [];
          isNavigating = false;
          document
            .querySelectorAll(".char-slot")
            .forEach((el) => el.classList.remove("active"));
          selectedSlot = null;
          document.getElementById("action-buttons").style.display = "none";
          setFooterZoomState(false);
          document.querySelector(".top-title").classList.remove("hidden");

          // Ocultar panel detallado de stats
          document.getElementById("detailed-char-info").classList.add("hidden");

          axios.post(`https://${resName}/unfocusCharacter`, JSON.stringify({}));

          // Esperamos a que la cámara termine de alejarse (misma duración que en cl_main.lua)
          // antes de volver a mostrar el selector de slots y permitir elegir otro personaje.
          // Así evitamos el glitch de solapamiento si se selecciona demasiado rápido.
          setTimeout(() => {
            document.getElementById("slots-wrapper").classList.remove("slots-hidden");
            isUnfocusing = false;
            DebugPrint("Solicitando lista actualizada de personajes tras borrado.");
            axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
            // Al recibir setupCharacters, updateOptionsStats() se llamará automáticamente
          }, UNFOCUS_DURATION);
        } else {
          DebugPrint("Saliendo de la lista de personajes. Volviendo al Landing.");
          if (typeof Sounds !== "undefined") Sounds.playCancel();
          showScreen("landing-screen");
        }
        return;
      }
      // Ninguna condición anterior aplicó: ESC no hace nada en este contexto, así
      // que deliberadamente NO se reproduce ningún sonido aquí.
    }

    // Flechas para navegar entre personajes lateralmente cuando el panel de detalle está enfocado (zoom)
    if (document.getElementById("character-list").style.display === "block" && isZoomed) {
      if (e.key === "ArrowRight") {
        DebugPrint("Navegando al siguiente personaje (Flecha Derecha).");
        if (typeof Sounds !== "undefined") Sounds.playNav();
        navigateCharacter(1);
        return;
      } else if (e.key === "ArrowLeft") {
        DebugPrint("Navegando al personaje anterior (Flecha Izquierda).");
        if (typeof Sounds !== "undefined") Sounds.playNav();
        navigateCharacter(-1);
        return;
      } else if (e.key === "Enter") {
        // Simular clic en el botón principal (JUGAR o CREAR)
        DebugPrint("Pulsado ENTER. Simulando clic en acción principal.");
        document.getElementById("main-action-btn").click(); // El listener global de click ya reproduce sonido
        return;
      }
    }

    // Navegación con flechas para el Landing Screen inicial
    if (document.getElementById("landing-screen").style.display !== "none") {
      if (e.key === "ArrowRight") {
        const newIndex = Math.min(2, currentLandingIndex + 1);
        if (newIndex !== currentLandingIndex && typeof Sounds !== "undefined")
          Sounds.playNav();
        currentLandingIndex = newIndex;
        updateLandingHover(currentLandingIndex);
      } else if (e.key === "ArrowLeft") {
        let minIndex = charactersData.length > 0 ? 0 : 1;
        const newIndex = Math.max(minIndex, currentLandingIndex - 1);
        if (newIndex !== currentLandingIndex && typeof Sounds !== "undefined")
          Sounds.playNav();
        currentLandingIndex = newIndex;
        updateLandingHover(currentLandingIndex);
      } else if (e.key === "Enter") {
        DebugPrint(
          "Ejecutando acción del Landing Screen (Enter). Botón: " + currentLandingIndex,
        );
        landBtns[currentLandingIndex].click(); // El listener global de click ya reproduce sonido
      }
    }
  });

  // Acción directa para Jugar con el último personaje
  document.getElementById("btn-land-play").addEventListener("click", (e) => {
    if (lastCharacter) {
      DebugPrint("Acción rápida: Jugar con el personaje principal.");
      const btn = e.currentTarget;
      setButtonLoading(btn, true);

      // Falsa carga de 1.5s antes de decirle a Lua que nos meta al servidor
      setTimeout(() => {
        axios
          .post(`https://${resName}/playCharacter`, JSON.stringify({ cData: lastCharacter }))
          .catch(() => DebugPrint("Petición playCharacter abortada o fallida."))
          .finally(() => setButtonLoading(btn, false));
      }, 1500);
    }
  });

  // Acción para abrir la lista de ranuras/slots
  document.getElementById("btn-land-chars").addEventListener("click", () => {
    DebugPrint("Abriendo pantalla de selección manual de personajes.");
    showScreen("character-list");
    setFooterZoomState(false); // Al entrar mostramos solo "ESC - SALIR" hasta enfocar un personaje
  });

  document.getElementById("btn-land-options").addEventListener("click", () => {
    DebugPrint("Abriendo pantalla de opciones.");
    showScreen("options-screen");
    OptionsTable.reset();
    OptionsTable.render();
    updateOptionsStats();
  });

  // === LÓGICA DE CLIC EN LOS SLOTS INDIVIDUALES ===
  document.getElementById("slots-wrapper").addEventListener("click", (e) => {
    if (isUnfocusing) {
      DebugPrint("Clic ignorado: La cámara se está alejando actualmente.");
      return; // Bloqueado mientras la cámara vuelve a la vista general
    }

    const slotEl = e.target.closest(".char-slot");
    if (!slotEl) return;

    const slotId = parseInt(slotEl.dataset.slot);
    DebugPrint("Slot " + slotId + " clicado.");
    selectSlot(slotId);
  });

  // === FLECHAS DE LA BOTONERA CENTRAL (navegación de personajes con el ratón) ===
  const arrowLeftEl = document.querySelector(".action-arrows-left");
  const arrowRightEl = document.querySelector(".action-arrows-right");
  if (arrowLeftEl) arrowLeftEl.addEventListener("click", () => navigateCharacter(-1));
  if (arrowRightEl) arrowRightEl.addEventListener("click", () => navigateCharacter(1));

  // Abrir modal de confirmación de borrado desde el panel lateral
  const deleteBtn = document.getElementById("panel-btn-delete");
  if (deleteBtn) {
    deleteBtn.addEventListener("click", () => {
      if (selectedSlot !== null) {
        DebugPrint("Abriendo modal de confirmación de borrado para el slot: " + selectedSlot);
        document.getElementById("delete-modal").style.display = "flex";
      }
    });
  }

  // Acción unificada del botón central gigante (Jugar o Crear)
  document.getElementById("main-action-btn").addEventListener("click", (e) => {
    const charData = charactersData.find((c) => c.cid === selectedSlot);
    const btn = e.currentTarget;

    if (charData) {
      DebugPrint(
        "Enviando petición a servidor para jugar con CitizenID: " + charData.citizenid,
      );
      setButtonLoading(btn, true);

      setTimeout(() => {
        axios
          .post(`https://${resName}/playCharacter`, JSON.stringify({ cData: charData }))
          .catch(() => DebugPrint("Petición playCharacter abortada o fallida."))
          .finally(() => setButtonLoading(btn, false));
      }, 1500);
    } else {
      DebugPrint("El slot está vacío. Abriendo formulario de registro de personaje.");
      showScreen("character-register");
      resetForm();
    }
  });

  // Selección de género en el formulario de creación
  document.querySelectorAll(".gender-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      document.querySelectorAll(".gender-btn").forEach((el) => el.classList.remove("active"));
      const target = e.target.closest(".gender-btn");
      target.classList.add("active");
      selectedGender = target.dataset.gender;

      // --- Sobreescribimos el género aleatorio inicial con la decisión del jugador ---
      if (selectedSlot !== null) {
        // Convertimos el string a 1 (Mujer) o 0 (Hombre) para que coincida con la lógica de cl_main.lua
        randomSlotGenders[selectedSlot] = selectedGender === "Femenino" ? 1 : 0;
      }

      DebugPrint("Género actualizado a: " + selectedGender + ". Solicitando preview a Lua.");
      // Actualizamos la sombra (silueta) en el mundo en tiempo real al cambiar de género
      axios.post(
        `https://${resName}/previewPed`,
        JSON.stringify({
          gender: selectedGender,
          slot: selectedSlot,
        }),
      );
    });
  });

  // Objeto global temporal para guardar los datos del personaje mientras el jugador compra
  let pendingCharacterData = null;
  let characterCreationSubmitted = false;

  // Envío del formulario de registro (Paso 1: Validación y transición a Tienda)
  document.getElementById("btn-create-reg").addEventListener("click", (e) => {
    const firstname = document.getElementById("reg-firstname").value.trim();
    const lastname = document.getElementById("reg-lastname").value.trim();
    const dob = document.getElementById("reg-dob").value;

    const validation = Validator.validateForm(
      firstname,
      lastname,
      dob,
      selectedGender,
      selectedNationality,
    );
    if (!validation.valid) {
      showAlert(validation.msg, "ERROR DE VALIDACIÓN", "error");
      return;
    }

    // Guardamos los datos para usarlos luego
    pendingCharacterData = {
      cid: selectedSlot,
      firstname: firstname,
      lastname: lastname,
      birthdate: dob,
      gender: selectedGender === "Masculino" ? 0 : 1,
      nationality: selectedNationality,
    };
    characterCreationSubmitted = false;

    DebugPrint("Formulario validado. Abriendo pantalla de Starting Items.");

    // Renderizamos la tienda de cero y la mostramos
    renderStarterItems();
    showScreen("starter-items-screen");
  });

  // Acción del botón inferior de la Tienda (Purchase / Skip)
  document.getElementById("btn-starter-purchase").addEventListener("click", () => {
    let totalItemsInCart = 0;
    for (const qty of Object.values(cartItems)) {
      totalItemsInCart += qty;
    }

    if (totalItemsInCart > 0) {
      const summaryList = document.getElementById("starter-summary-list");
      summaryList.innerHTML = "";

      startingItemsData.forEach((item) => {
        const qty = cartItems[item.name];
        if (qty > 0) {
          const price = getModifiedPrice(item.price);
          const lineTotal = price * qty;
          const priceDisplay = price === 0 ? "GRATIS" : `$${lineTotal.toLocaleString()}`;
          const imageName = item.name.toLowerCase();

          summaryList.innerHTML += `
                        <div class="starter-summary-item">
                            <span class="starter-summary-item-name">
                                <img src="items/${imageName}.png" onerror="this.style.display='none';">
                                ${qty}x ${item.name}
                            </span>
                            <span>${priceDisplay}</span>
                        </div>
                    `;
        }
      });
      document.getElementById("starter-summary-price").innerText =
        `$${cartTotal.toLocaleString()}`;
      document.getElementById("modal-starter-confirm").style.display = "flex";
    } else {
      submitFinalCharacterCreation(null);
    }
  });

  // Cancelar en el Modal de Confirmación del Carrito
  document.getElementById("btn-starter-cancel").addEventListener("click", () => {
    document.getElementById("modal-starter-confirm").style.display = "none";
  });

  // Confirmar Compra y Enviar a Lua
  document.getElementById("btn-starter-accept").addEventListener("click", (e) => {
    document.getElementById("modal-starter-confirm").style.display = "none";

    // Filtramos cartItems para mandar solo los que tienen cantidad > 0
    let purchasedItems = {};
    for (const [itemName, qty] of Object.entries(cartItems)) {
      if (qty > 0) purchasedItems[itemName] = qty;
    }

    submitFinalCharacterCreation(purchasedItems);
  });

  // Función que consolida el envío final al servidor
  function submitFinalCharacterCreation(cartPayload) {
    if (!pendingCharacterData || characterCreationSubmitted) return;
    characterCreationSubmitted = true;

    const finalData = {
      ...pendingCharacterData,
      cart: cartPayload,
      cartTotal: cartTotal,
    };

    DebugPrint("Enviando petición createCharacter a Lua con el carrito incluido.");
    const btnPurchase = document.getElementById("btn-starter-purchase");
    setButtonLoading(btnPurchase, true);

    setTimeout(() => {
      axios
        .post(`https://${resName}/createCharacter`, JSON.stringify(finalData))
        .catch(() => DebugPrint("Petición createCharacter abortada o fallida."))
        .finally(() => {
          setButtonLoading(btnPurchase, false);
          resetForm();
          pendingCharacterData = null;
          characterCreationSubmitted = false;
        });
    }, 1500);
  }

  // Cancelar el registro y volver a la vista general de personajes
  document.getElementById("btn-cancel-reg").addEventListener("click", () => {
    DebugPrint("Cancelando registro. Volviendo a la lista manteniendo los datos.");
    showScreen("character-list");
    document.getElementById("detailed-char-info").classList.add("hidden");
    document.getElementById("action-buttons").style.display = "none";
    document.querySelectorAll(".char-slot").forEach((el) => el.classList.remove("active"));
    axios.post(`https://${resName}/deletePreview`, JSON.stringify({}));
    document.querySelector(".top-title").classList.remove("hidden");

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
      document.getElementById("slots-wrapper").classList.remove("slots-hidden");
      isUnfocusing = false;
    }, UNFOCUS_DURATION);
  });

  // Cerrar modal de confirmación de borrado
  document.getElementById("btn-modal-cancel").addEventListener("click", () => {
    DebugPrint("Borrado cancelado desde el modal.");
    document.getElementById("delete-modal").style.display = "none";
  });

  // Confirmar borrado definitivo del personaje
  document.getElementById("btn-modal-confirm").addEventListener("click", (e) => {
    const charData = charactersData.find((c) => c.cid === selectedSlot);
    if (charData) {
      DebugPrint("Confirmado borrado del personaje CitizenID: " + charData.citizenid);
      const btn = e.currentTarget;
      setButtonLoading(btn, true);
      const startTime = Date.now();

      axios
        .post(
          `https://${resName}/deleteCharacter`,
          JSON.stringify({ citizenid: charData.citizenid }),
        )
        .catch(() => DebugPrint("Petición deleteCharacter abortada o fallida."))
        .finally(() => {
          // Calculamos cuánto tardó el servidor. Si fue instantáneo, forzamos la espera a 1.5s.
          const elapsed = Date.now() - startTime;
          const waitTime = Math.max(0, 1500 - elapsed);

          setTimeout(() => {
            setButtonLoading(btn, false);
            // Ocultar paneles y UI
            document.getElementById("delete-modal").style.display = "none";
            document.getElementById("detailed-char-info").classList.add("hidden");
            document.getElementById("action-buttons").style.display = "none";

            // Salimos del zoom
            isZoomed = false;
            isUnfocusing = true;
            navQueue = [];
            isNavigating = false;
            selectedSlot = null;
            setFooterZoomState(false);
            axios
              .post(`https://${resName}/unfocusCharacter`, JSON.stringify({}))
              .catch(() => {});

            setTimeout(() => {
              document.getElementById("slots-wrapper").classList.remove("slots-hidden");
              isUnfocusing = false;
            }, UNFOCUS_DURATION);
          }, waitTime);
        });
    }
  });

  // --- LÓGICA DEL SELECTOR DE NACIONALIDAD ---
  const natOptionsContainer = document.getElementById("nationality-options");
  const natDisplay = document.getElementById("nationality-display");
  const natWrapper = document.getElementById("nationality-wrapper");
  const natDropdown = document.getElementById("nationality-dropdown");
  const natSearch = document.getElementById("nationality-search");
  const natText = document.getElementById("nationality-text");

  // Función para renderizar las opciones dinámicamente
  function renderNationalities(list) {
    natOptionsContainer.innerHTML = "";
    list.forEach((nat) => {
      const opt = document.createElement("div");
      opt.className = "dropdown-option";
      opt.dataset.id = nat.id.toLowerCase();
      opt.dataset.name = nat.label.toLowerCase();

      opt.innerHTML = `
            <img src="https://flagcdn.com/24x18/${nat.id}.png" class="flag-icon" onerror="this.outerHTML='<div class=\\'fallback-flag\\'>${nat.id}</div>'">
            <span>${nat.label}</span>
        `;

      opt.addEventListener("click", () => {
        selectedNationality = nat.id;
        natText.innerText = nat.label;
        natDisplay.classList.add("selected");
        natWrapper.classList.remove("open");
        natDropdown.classList.add("hidden");
      });

      natOptionsContainer.appendChild(opt);
    });
  }

  // Llamamos a renderizar cuando se cargue la UI (usará los datos que lleguen de Lua)
  // (Asegúrate de llamarlo también dentro del bloque toggleUI si se reabre la UI)
  renderNationalities(nationalitiesData);

  // 3. Abrir/Cerrar el desplegable
  natDisplay.addEventListener("click", (e) => {
    e.stopPropagation(); // Evita que el evento "click outside" lo cierre instantáneamente
    natWrapper.classList.toggle("open");
    natDropdown.classList.toggle("hidden");
    if (!natDropdown.classList.contains("hidden")) {
      natSearch.focus(); // Auto-foco en el buscador
    }
  });

  // 4. Cerrar si haces click fuera del menú
  document.addEventListener("click", (e) => {
    if (natWrapper && !natWrapper.contains(e.target)) {
      natWrapper.classList.remove("open");
      natDropdown.classList.add("hidden");
    }
  });

  // 5. Buscador en tiempo real
  natSearch.addEventListener("input", (e) => {
    const searchVal = e.target.value.toLowerCase();
    document.querySelectorAll(".dropdown-option").forEach((opt) => {
      if (opt.dataset.id.includes(searchVal) || opt.dataset.name.includes(searchVal)) {
        opt.style.display = "flex";
      } else {
        opt.style.display = "none";
      }
    });
  });

  function updateOptionsStats() {
    const totalChars = charactersData.length;
    const totalSlots = maxSlots;
    const availableSlots = Math.max(0, totalSlots - totalChars);

    const elActive = document.getElementById("stat-active-chars");
    const elAvailable = document.getElementById("stat-available-slots");
    const elTotal = document.getElementById("stat-total-slots");

    if (elActive) elActive.innerText = totalChars;
    if (elAvailable) elAvailable.innerText = availableSlots;
    if (elTotal) elTotal.innerText = totalSlots;

    DebugPrint(
      `Stats actualizadas: ${totalChars} activos / ${availableSlots} disponibles / ${totalSlots} totales`,
    );
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
    let sortState = { key: "cid", dir: "asc" };
    let searchQuery = "";
    let dragSrcCid = null;

    // Referencias del DOM (se rellenan en init)
    let els = {};

    // ==========================================
    // UTILIDADES
    // ==========================================
    const $ = (sel) => document.querySelector(sel);
    const $$ = (sel) => Array.from(document.querySelectorAll(sel));

    function escapeHtml(str) {
      if (str === null || str === undefined) return "";
      return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    // ==========================================
    // FILTRADO + ORDENACIÓN
    // ==========================================
    function getProcessedRows() {
      let list = [...charactersData];

      // 1) Filtro de búsqueda (por nombre o citizenid o cid)
      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        list = list.filter((c) => {
          const name = `${c.charinfo.firstname} ${c.charinfo.lastname}`.toLowerCase();
          const cid = String(c.cid);
          const citizen = String(c.citizenid || "").toLowerCase();
          return name.includes(q) || cid.includes(q) || citizen.includes(q);
        });
      }

      // 2) Ordenación
      const { key, dir } = sortState;
      const mult = dir === "asc" ? 1 : -1;

      list.sort((a, b) => {
        let va, vb;
        switch (key) {
          case "cid":
            va = a.cid;
            vb = b.cid;
            break;
          case "name":
            va = `${a.charinfo.firstname} ${a.charinfo.lastname}`.toLowerCase();
            vb = `${b.charinfo.firstname} ${b.charinfo.lastname}`.toLowerCase();
            break;
          case "citizenid":
            va = String(a.citizenid || "").toLowerCase();
            vb = String(b.citizenid || "").toLowerCase();
            break;
          default:
            va = a.cid;
            vb = b.cid;
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
      els.tbody.innerHTML = "";

      // Estado vacío
      if (list.length === 0) {
        if (els.emptyState) {
          els.emptyState.style.display = "flex";
          els.emptyState.querySelector("p").innerText = searchQuery
            ? "Sin resultados para tu búsqueda"
            : "No hay personajes que mostrar";
        }
        return;
      } else {
        if (els.emptyState) els.emptyState.style.display = "none";
      }

      // Construir filas
      const frag = document.createDocumentFragment();

      list.forEach((char) => {
        const tr = document.createElement("tr");
        tr.dataset.cid = char.cid;
        tr.dataset.citizenid = char.citizenid || "";
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
                        <span class="char-citizen">${escapeHtml(char.citizenid || "---")}</span>
                    </td>
                    <td class="col-actions">    <!-- 5. Botones -->
                        <div class="table-actions">
                            <button class="table-btn btn-history-char" title="Historial de Actividad" data-cid="${char.cid}">
                                <i class="fas fa-clipboard-list"></i>
                            </button>
                            <button class="table-btn btn-export-char" title="Exportar personaje" data-cid="${char.cid}">
                                <i class="fas fa-file-export"></i>
                            </button>
                            <button class="table-btn btn-delete-char" title="Eliminar personaje" data-cid="${char.cid}">
                                <i class="fas fa-trash"></i>
                            </button>
                        </div>
                    </td>
                `;

        // Botón Historial
        tr.querySelector(".btn-history-char").addEventListener("click", (e) => {
          e.stopPropagation();
          window.openHistoryModal(char);
        });

        // Acciones existentes
        tr.querySelector(".btn-export-char").addEventListener("click", (e) => {
          e.stopPropagation();
          DebugPrint("Exportar personaje CID: " + char.cid);
          window.openExportImportModal("export", char);
        });

        tr.querySelector(".btn-delete-char").addEventListener("click", (e) => {
          e.stopPropagation();
          selectedSlot = parseInt(char.cid);
          DebugPrint("Abriendo modal de borrado desde opciones para el slot: " + selectedSlot);
          document.getElementById("delete-modal").style.display = "flex";
        });

        // Drag handle — enganchamos mousedown SOLO al handle
        const handle = tr.querySelector(".drag-handle");
        handle.addEventListener("mousedown", (e) => {
          e.preventDefault();
          e.stopPropagation();

          // Asignamos el tr a una variable temporal ANTES de llamar
          dragSrcRow = tr;
          handleDragStart.call(tr, e);
        });

        frag.appendChild(tr);
      });

      els.tbody.appendChild(frag);

      // Actualizar iconos de sort en headers
      $$(".characters-table th[data-sort]").forEach((th) => {
        // Limpiar clases y resetear icono a neutro
        th.classList.remove("sort-asc", "sort-desc");
        const icon = th.querySelector(".sort-icon");
        if (icon) {
          icon.classList.remove("fa-sort", "fa-sort-up", "fa-sort-down");
          icon.classList.add("fa-sort"); // por defecto, neutro
        }

        // Marcar la columna activa y poner su icono correcto
        if (th.dataset.sort === sortState.key) {
          if (sortState.dir === "asc") {
            th.classList.add("sort-asc");
            if (icon) {
              icon.classList.remove("fa-sort");
              icon.classList.add("fa-sort-up");
            }
          } else {
            th.classList.add("sort-desc");
            if (icon) {
              icon.classList.remove("fa-sort");
              icon.classList.add("fa-sort-down");
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

      dragSrcRow.classList.add("dragging");

      // Crear "fantasma" flotante
      dragGhostEl = dragSrcRow.cloneNode(true);
      dragGhostEl.style.position = "fixed";
      dragGhostEl.style.pointerEvents = "none";
      dragGhostEl.style.opacity = "0.85";
      dragGhostEl.style.zIndex = "9999";
      dragGhostEl.style.width = dragSrcRow.offsetWidth + "px";
      dragGhostEl.style.background = "rgba(20, 20, 20, 0.95)";
      dragGhostEl.style.transform = "translate(-50%, -50%)";
      dragGhostEl.style.left = e.clientX + "px";
      dragGhostEl.style.top = e.clientY + "px";
      document.body.appendChild(dragGhostEl);

      // Bloquear selección de texto mientras arrastramos
      document.body.style.userSelect = "none";

      // Enlazar listeners globales
      document.addEventListener("mousemove", handleDragMove);
      document.addEventListener("mouseup", handleDragEnd);
    }

    function handleDragMove(e) {
      if (!isDragging || !dragGhostEl) return;

      // Mover el fantasma
      dragGhostEl.style.left = e.clientX + "px";
      dragGhostEl.style.top = e.clientY + "px";

      // Detectar sobre qué fila está el cursor
      const rows = Array.from(els.tbody.querySelectorAll("tr"));
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
        lastDragOverRow.classList.remove("drag-over");
      }

      if (hoveredRow && hoveredRow !== dragSrcRow) {
        hoveredRow.classList.add("drag-over");
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

      document.body.style.userSelect = "";

      // Quitar clases visuales
      if (dragSrcRow) dragSrcRow.classList.remove("dragging");
      els.tbody.querySelectorAll("tr").forEach((tr) => tr.classList.remove("drag-over"));

      // Ejecutar el reordenamiento si soltamos sobre otra fila
      if (lastDragOverRow && dragSrcRow && lastDragOverRow !== dragSrcRow) {
        const targetCid = parseInt(lastDragOverRow.dataset.cid);
        DebugPrint(`Drag & Drop: mover CID ${dragSrcCid} → antes de CID ${targetCid}`);

        const srcIndex = charactersData.findIndex((c) => c.cid === dragSrcCid);
        const dstIndex = charactersData.findIndex((c) => c.cid === targetCid);

        if (srcIndex !== -1 && dstIndex !== -1) {
          const [moved] = charactersData.splice(srcIndex, 1);
          charactersData.splice(dstIndex, 0, moved);

          // Reasignar CID según el nuevo orden 1..N
          charactersData.forEach((c, i) => {
            c.cid = i + 1;
          });

          // Refrescar UI
          render();

          // Persistir en Lua
          const orderPayload = charactersData.map((c) => ({
            cid: c.cid,
            citizenid: c.citizenid,
          }));

          // Bloqueamos la tabla visualmente mientras carga, y la UI entera
          // para evitar acciones contradictorias mientras se persiste el orden.
          els.tbody.style.opacity = "0.5";
          els.tbody.style.pointerEvents = "none";
          lockUI();

          axios
            .post(
              `https://${resName}/reorderCharacters`,
              JSON.stringify({
                order: orderPayload,
              }),
            )
            .then(() => {
              DebugPrint(
                "Reorden guardado. Solicitando setupCharacters para refrescar datos...",
              );
              setTimeout(() => {
                axios.post(`https://${resName}/setupCharacters`, JSON.stringify({}));
              }, 250);
            })
            .catch(() => {
              DebugPrint("Aviso: el endpoint /reorderCharacters no respondió.");
            })
            .finally(() => {
              // Desbloqueamos la tabla
              els.tbody.style.opacity = "1";
              els.tbody.style.pointerEvents = "auto";
              unlockUI();
            });
        }
      }

      // Reset
      dragSrcRow = null;
      dragSrcCid = null;
      lastDragOverRow = null;

      // Quitar listeners globales
      document.removeEventListener("mousemove", handleDragMove);
      document.removeEventListener("mouseup", handleDragEnd);
    }

    // ==========================================
    // ORDENACIÓN POR CABECERA
    // ==========================================
    function handleSortClick(e) {
      const th = e.currentTarget;
      const key = th.dataset.sort;
      if (!key) return;

      if (sortState.key === key) {
        sortState.dir = sortState.dir === "asc" ? "desc" : "asc";
      } else {
        sortState.key = key;
        sortState.dir = "asc";
      }

      DebugPrint(`Ordenando por "${key}" (${sortState.dir})`);
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
      els.tbody = document.getElementById("options-characters-tbody");
      els.emptyState = document.getElementById("table-empty-state");
      els.searchInput = document.getElementById("table-search");

      if (!els.tbody) {
        DebugPrint("OptionsTable: no se encontró #options-characters-tbody.");
        return;
      }

      // Headers de ordenación
      $$(".characters-table th[data-sort]").forEach((th) => {
        th.addEventListener("click", handleSortClick);
      });

      // Buscador
      if (els.searchInput) {
        els.searchInput.addEventListener("input", handleSearch);
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
        searchQuery = "";
        sortState = { key: "cid", dir: "asc" };
        if (els.searchInput) els.searchInput.value = "";
        render();
      },
      setData() {
        // Llamado cuando charactersData cambia (ej: tras borrar)
        render();
      },
    };
  })();

  // Inicializar cuando el DOM esté listo
  OptionsTable.init();

  // Alias de compatibilidad (por si lo usas desde otros sitios)
  function renderOptionsCharactersTable() {
    OptionsTable.render();
  }

  // ==========================================
  // BOTONES DE LA PANTALLA DE OPCIONES (Y DEMOS)
  // ==========================================
  (() => {
    // --- Importar / Exportar Múltiples (top bar) ---
    const btnImportMulti = document.getElementById("btn-import-multi");
    const btnExportMulti = document.getElementById("btn-export-multi");
    if (btnImportMulti)
      btnImportMulti.addEventListener("click", () =>
        showAlert(
          "Esta función estará disponible en futuras actualizaciones.",
          "PRÓXIMAMENTE",
          "info",
        ),
      );
    if (btnExportMulti)
      btnExportMulti.addEventListener("click", () =>
        showAlert(
          "Esta función estará disponible en futuras actualizaciones.",
          "PRÓXIMAMENTE",
          "info",
        ),
      );

    // ==========================================
    // INYECCIÓN DE CONTENIDO DEMO PARA LOS MODALES
    // ==========================================
    const dummyData = {
      "modal-buy-slots": `<div style="padding: 15px; background: rgba(0,0,0,0.3); border: 1px dashed rgba(255,255,255,0.1); color: #ccc; border-radius: 4px; text-align: left;">
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                    <span>Slots Actuales:</span> <strong style="color: #fff;">4 / 7</strong>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span>Precio del 5º Slot:</span> <strong style="color: #00ff88; font-size: 16px;">1,500 Coins</strong>
                </div>
            </div>`,

      "modal-spawn-pref": `<div style="padding: 15px; background: rgba(0,0,0,0.3); border: 1px dashed rgba(255,255,255,0.1); color: #ccc; border-radius: 4px; text-align: left;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; padding: 8px 0;">
                    <input type="radio" name="spawn_type" checked style="accent-color: #fff; transform: scale(1.2);"> 
                    <span>Usar mi última ubicación (Si es posible)</span>
                </label>
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; padding: 8px 0; border-top: 1px solid rgba(255,255,255,0.05);">
                    <input type="radio" name="spawn_type" style="accent-color: #fff; transform: scale(1.2);"> 
                    <span>Forzar selector de aparición (qb-spawn)</span>
                </label>
            </div>`,

      "modal-report-bug": `<div style="padding: 15px; background: rgba(0,0,0,0.3); border: 1px dashed rgba(255,255,255,0.1); color: #ccc; border-radius: 4px; text-align: left;">
                <p style="font-size: 12px; margin-bottom: 8px; margin-top:0;">Describe el fallo con el mayor detalle posible:</p>
                <textarea style="width: 100%; height: 80px; padding: 10px; background: rgba(0,0,0,0.6); border: 1px solid rgba(255,255,255,0.1); color: #fff; border-radius: 4px; outline: none; resize: none;" placeholder="Estaba intentando cargar el personaje 2 y..."></textarea>
            </div>`,

      "modal-report-bug": `<div style="padding: 15px; background: rgba(0,0,0,0.3); border: 1px dashed rgba(255,255,255,0.1); color: #ccc; border-radius: 4px; text-align: left;">
                <p style="font-size: 12px; margin-bottom: 8px; margin-top:0;">Describe el fallo con el mayor detalle posible:</p>
                <textarea style="width: 100%; height: 80px; padding: 10px; background: rgba(0,0,0,0.6); border: 1px solid rgba(255,255,255,0.1); color: #fff; border-radius: 4px; outline: none; resize: none;" placeholder="Estaba intentando cargar el personaje 2 y..."></textarea>
            </div>`,
    };

    // Inyectar el HTML generado en los respectivos modals
    for (const [modalId, htmlContent] of Object.entries(dummyData)) {
      const modalEl = document.getElementById(modalId);
      if (modalEl) {
        const bodyEl = modalEl.querySelector(".modal-body");
        if (bodyEl) bodyEl.innerHTML = htmlContent;
      }
    }

    // ==========================================
    // EVENTOS DE APERTURA DE MODALS
    // ==========================================
    const modalBindings = {
      "btn-buy-slot": "modal-buy-slots",
      "btn-spawn-pref": "modal-spawn-pref",
      "btn-report-bug": "modal-report-bug",
      // 'btn-discord' se maneja aparte porque necesita renderizado dinámico
    };

    for (const [btnId, modalId] of Object.entries(modalBindings)) {
      const btn = document.getElementById(btnId);
      if (btn) {
        btn.addEventListener("click", () => {
          DebugPrint("Abriendo modal: " + modalId);
          const modal = document.getElementById(modalId);
          if (modal) {
            modal.style.display = "flex";
          }
        });
      }
    }

    // ==========================================
    // 🌐 DISCORD / AYUDA — RENDERIZADO DINÁMICO SEGÚN helpConfig
    // ==========================================
    function renderDiscordModal(config) {
      helpConfig = config || {
        enableWeb: false,
        webURL: "",
        enableDiscord: false,
        discordURL: "",
      };
      const webBlock = document.getElementById("discord-web-block");
      const discordBlock = document.getElementById("discord-discord-block");
      const emptyMsg = document.getElementById("discord-empty-msg");
      const webUrlEl = document.getElementById("discord-web-url");
      const discordUrlEl = document.getElementById("discord-discord-url");

      if (!webBlock || !discordBlock || !emptyMsg) return;

      // Reset
      webBlock.style.display = "none";
      discordBlock.style.display = "none";
      emptyMsg.style.display = "none";

      let hasAny = false;

      if (helpConfig.enableWeb && helpConfig.webURL) {
        webBlock.style.display = "block";
        webUrlEl.textContent = helpConfig.webURL;
        hasAny = true;
      }
      if (helpConfig.enableDiscord && helpConfig.discordURL) {
        discordBlock.style.display = "block";
        discordUrlEl.textContent = helpConfig.discordURL;
        hasAny = true;
      }
      if (!hasAny) {
        emptyMsg.style.display = "flex";
      }
    }

    const discordBtn = document.getElementById("btn-discord");
    if (discordBtn) {
      discordBtn.addEventListener("click", () => {
        DebugPrint("Abriendo modal: modal-discord (con helpConfig dinámico)");
        renderDiscordModal(helpConfig);
        const modal = document.getElementById("modal-discord");
        if (modal) {
          modal.style.display = "flex";
        }
      });
    }

    // Botones COPIAR
    function setupCopyBtn(copyBtnId, urlElId) {
      const copyBtn = document.getElementById(copyBtnId);
      const urlEl = document.getElementById(urlElId);
      if (copyBtn && urlEl) {
        copyBtn.addEventListener("click", () => {
          const text = urlEl.textContent;
          if (!text) return;

          // FIX para FiveM CEF: Usar un textarea temporal
          const textArea = document.createElement("textarea");
          textArea.value = text;
          textArea.style.top = "0";
          textArea.style.left = "0";
          textArea.style.position = "fixed";
          textArea.style.opacity = "0"; // Que no se vea en pantalla
          document.body.appendChild(textArea);

          textArea.focus();
          textArea.select();

          try {
            document.execCommand("copy");
            copyBtn.classList.add("copied");
            copyBtn.innerHTML = '<i class="fas fa-check"></i> COPIADO';
            setTimeout(() => {
              copyBtn.classList.remove("copied");
              copyBtn.innerHTML = '<i class="fas fa-copy"></i> COPIAR';
            }, 1500);
          } catch (err) {
            DebugPrint("No se pudo copiar al portapapeles.");
          }

          // Limpiamos el DOM
          document.body.removeChild(textArea);
        });
      }
    }

    setupCopyBtn("discord-web-copy", "discord-web-url");
    setupCopyBtn("discord-discord-copy", "discord-discord-url");

    // Botón CERRAR del modal Discord
    const discordCloseBtn = document.getElementById("btn-discord-close");
    if (discordCloseBtn) {
      discordCloseBtn.addEventListener("click", () => {
        const modal = document.getElementById("modal-discord");
        if (modal) {
          modal.style.display = "none";
        }
      });
    }

    // ==========================================
    // EVENTOS DE CIERRE DE MODALS (Click fuera y botones)
    // ==========================================
    document.querySelectorAll(".modal-overlay").forEach((modal) => {
      // Cerrar al hacer click en el overlay oscuro exterior
      modal.addEventListener("mousedown", (e) => {
        if (e.target === modal) {
          // El modal de ocultar bloqueados descarta los cambios sin guardar
          if (
            modal.id === "modal-hide-locked" &&
            typeof window.closeHideLockedModal === "function"
          ) {
            window.closeHideLockedModal(true);
            return;
          }
          modal.style.display = "none";
        }
      });

      // Si es el de borrado, exportar/importar, sonidos, ocultar bloqueados o Discord/Ayuda,
      // saltamos los botones porque tienen lógica propia
      if (
        modal.id === "delete-modal" ||
        modal.id === "modal-export-import" ||
        modal.id === "modal-sound-toggle" ||
        modal.id === "modal-hide-locked" ||
        modal.id === "modal-discord"
      )
        return;

      // Funciones de botones cancelar / confirmar genéricas para las DEMOS
      const closeBtns = modal.querySelectorAll(".btn-modal-cancel, .btn-modal-primary");
      closeBtns.forEach((btn) => {
        btn.addEventListener("click", () => {
          modal.style.display = "none";
          if (btn.classList.contains("btn-modal-cancel")) {
          } else {
            DebugPrint("Acción de demostración confirmada en " + modal.id);
          }
        });
      });
    });

    // ==========================================
    // 🔊 SONIDOS DE INTERFAZ — SLIDER CUSTOM + PERSISTENCIA BD
    // ==========================================
    // El volumen se aplica en tiempo real a los sonidos WebAudio (sounds.js)
    // y se persiste por jugador en la BD (tabla dp_multicharacter_settings)
    // a través de Lua. localStorage queda solo como arranque rápido.

    function loadInterfaceVolume() {
      const stored = localStorage.getItem(VOLUME_STORAGE_KEY);
      const value = stored !== null ? parseInt(stored) : 100;
      return isNaN(value) ? 100 : Math.max(0, Math.min(100, value));
    }

    function saveInterfaceVolume(value) {
      interfaceVolume = Math.max(0, Math.min(100, parseInt(value) || 0));
      localStorage.setItem(VOLUME_STORAGE_KEY, String(interfaceVolume));
      DebugPrint("Volumen de interfaz guardado: " + interfaceVolume + "%");
      // Persistencia real en BD vía Lua (por jugador, tabla dp_multicharacter_settings)
      axios
        .post(
          `https://${resName}/setInterfaceVolume`,
          JSON.stringify({ volume: interfaceVolume }),
        )
        .catch(() => DebugPrint("Aviso: el endpoint /setInterfaceVolume no respondió."));
    }

    const soundToggleBtn = document.getElementById("btn-sound-toggle");
    const soundModal = document.getElementById("modal-sound-toggle");
    const sndSlider = document.getElementById("snd-slider");
    const sndNotches = document.getElementById("snd-notches");
    const sndFill = document.getElementById("snd-fill");
    const sndThumb = document.getElementById("snd-thumb");
    const sndValueLabel = document.getElementById("snd-volume-value");
    const soundSaveBtn = document.getElementById("btn-sound-save");
    const soundCancelBtn = document.getElementById("btn-sound-cancel");
    const sndTestBtn = document.getElementById("snd-test-btn");
    const sndPreviewBars = document.getElementById("snd-preview-bars");

    // Índices escalonados para la animación de las barras del preview
    if (sndPreviewBars) {
      sndPreviewBars.querySelectorAll(".snd-bar").forEach((bar, i) => {
        bar.style.setProperty("--i", i % 4);
      });
    }

    // --- Constructores de notches (20 celdas) ---
    function buildNotches() {
      if (!sndNotches) return;
      sndNotches.innerHTML = "";
      for (let i = 0; i < 20; i++) {
        const notch = document.createElement("div");
        notch.className = "snd-notch";
        sndNotches.appendChild(notch);
      }
    }

    // --- Refresco visual del slider según un valor 0-100 ---
    window.refreshSoundSlider = function refreshSoundSlider(value) {
      const v = Math.max(0, Math.min(100, value));
      interfaceVolume = v;

      if (sndValueLabel) sndValueLabel.innerText = v + "%";

      // % -> posición del thumb y ancho del fill
      if (sndThumb) sndThumb.style.left = v + "%";
      if (sndFill) sndFill.style.width = v + "%";

      // Rellenar notches activos (20 celdas = pasos de 5%)
      if (sndNotches) {
        const notches = sndNotches.querySelectorAll(".snd-notch");
        const activeCount = Math.round((v / 100) * notches.length);
        notches.forEach((n, i) => {
          n.classList.toggle("active", i < activeCount);
        });
      }

      // Subtexto del sidebar coherente
      const subEl = document.getElementById("sound-toggle-sub");
      if (subEl) {
        subEl.innerText =
          v <= 0
            ? Translate("ui_sound_off", "Sonidos desactivados")
            : Translate("ui_sound_level", "Volumen al %s%").replace("%s", v);
      }
    };

    // Convierte una posición X (click/arrastre) en valor 0-100
    function valueFromPointer(e) {
      if (!sndSlider) return interfaceVolume;
      const rect = sndSlider.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const pct = (x / rect.width) * 100;
      return Math.max(0, Math.min(100, Math.round(pct)));
    }

    // Arrastre con el ratón sobre el slider
    function initSliderDrag() {
      if (!sndSlider) return;

      let dragging = false;

      const updateFromEvent = (e) => {
        const v = valueFromPointer(e);
        window.refreshSoundSlider(v);
      };

      sndSlider.addEventListener("mousedown", (e) => {
        e.preventDefault();
        dragging = true;
        updateFromEvent(e);
      });

      document.addEventListener("mousemove", (e) => {
        if (dragging) updateFromEvent(e);
      });

      document.addEventListener("mouseup", () => {
        if (dragging) {
          dragging = false;
          // Sonido de prueba al soltar, para que el usuario escuche el nivel elegido
          if (interfaceVolume > 0 && typeof Sounds !== "undefined") Sounds.playTest();
        }
      });
    }

    // Inicial con los 20 notches
    buildNotches();

    if (soundToggleBtn && soundModal && sndSlider) {
      soundToggleBtn.addEventListener("click", () => {
        DebugPrint("Abriendo modal de Sonidos de Interfaz.");
        window.refreshSoundSlider(interfaceVolume);
        soundModal.style.display = "flex";
      });

      // Sonido de prueba (botón + barras animadas)
      if (sndTestBtn) {
        sndTestBtn.addEventListener("click", () => {
          if (typeof Sounds !== "undefined") Sounds.playTest();
          if (sndPreviewBars) {
            sndPreviewBars.classList.remove("play");
            void sndPreviewBars.offsetWidth; // reinicia la animación
            sndPreviewBars.classList.add("play");
            setTimeout(() => sndPreviewBars.classList.remove("play"), 900);
          }
        });
      }

      if (soundSaveBtn) {
        soundSaveBtn.addEventListener("click", () => {
          saveInterfaceVolume(interfaceVolume);
          soundModal.style.display = "none";
          if (sndPreviewBars) sndPreviewBars.classList.remove("play");
        });
      }

      if (soundCancelBtn) {
        soundCancelBtn.addEventListener("click", () => {
          // Descartar cambios: restaurar valor persistido
          window.refreshSoundSlider(loadInterfaceVolume());
          soundModal.style.display = "none";
          if (sndPreviewBars) sndPreviewBars.classList.remove("play");
        });
      }

      initSliderDrag();
    }

    // Inicializa el subtexto del sidebar de sonidos con el volumen actual
    if (typeof window.refreshSoundSlider === "function") {
      window.refreshSoundSlider(interfaceVolume);
    }

    // ==========================================
    // 👁️ OCULTAR BLOQUEADOS — SWITCH CUADRICULADO
    // ==========================================
    // Controla si los slots vacíos ("bloqueados" / de crear personaje) se
    // muestran en la vista principal del selector. La preferencia se guarda
    // en localStorage (solo-UI) y se envía a Lua para que persista en KVP.
    const hlModal = document.getElementById("modal-hide-locked");
    const hlBtn = document.getElementById("btn-hide-locked");
    const hlGridSwitch = document.getElementById("hl-grid-switch");
    const hlSwitchValue = document.getElementById("hl-switch-value");
    const hlSaveBtn = document.getElementById("hl-save-btn");
    const hlPreview = document.querySelector(".hl-preview");

    // Valor temporal del modal: se edita al tocar el switch y SOLO se aplica
    // a hideLockedSlots (y se persiste) al pulsar "ACTUALIZAR". Si se cierra
    // sin guardar, se descarta y se restaura el valor persistido.
    let hlTempValue = false;

    // Actualiza el estado visual del switch + la vista previa según el valor indicado.
    // Se usa un parámetro para poder mostrar el valor temporal del modal sin
    // modificar todavía hideLockedSlots (la preferencia persistida).
    // (global para que el listener de 'toggleUI' también pueda refrescarla)
    window.refreshHideLockedUI = function refreshHideLockedUI(useValue) {
      const value = useValue !== undefined ? useValue : hideLockedSlots;
      if (hlGridSwitch) hlGridSwitch.dataset.active = String(value);
      if (hlSwitchValue) {
        hlSwitchValue.innerText = Translate(
          value ? "ui_hidden" : "ui_visible",
          value ? "OCULTO" : "VISIBLE",
        );
        hlSwitchValue.classList.toggle("active", value);
      }
      if (hlPreview) hlPreview.classList.toggle("hide-locked", value);
      DebugPrint("UI del switch 'Ocultar Bloqueados' sincronizada (valor: " + value + ")");
    };

    // Abrir el modal con el estado persistido como base (sin aplicar cambios aún)
    if (hlBtn && hlModal) {
      hlBtn.addEventListener("click", () => {
        DebugPrint(
          "Abriendo modal 'Ocultar Bloqueados'. Estado persistido: " + hideLockedSlots,
        );
        hlTempValue = hideLockedSlots;
        refreshHideLockedUI(hlTempValue);
        hlModal.style.display = "flex";
      });
    }

    // Botón "CERRAR" del modal (descartar cambios sin guardar)
    const hlCancelBtn = hlModal ? hlModal.querySelector(".btn-modal-cancel") : null;

    // Cierre centralizado del modal. Si keepValue es false (descartar),
    // se restaura el valor persistido; si es true (tras guardar) solo se oculta.
    window.closeHideLockedModal = function closeHideLockedModal(discardChanges) {
      if (discardChanges !== false) {
        // Descartar: restaurar el valor persistido
        hlTempValue = hideLockedSlots;
        refreshHideLockedUI(hideLockedSlots);
      }
      hlModal.style.display = "none";
    };

    if (hlCancelBtn) {
      hlCancelBtn.addEventListener("click", () => {
        DebugPrint("Cerrando modal 'Ocultar Bloqueados' sin guardar. Descartando cambios.");
        window.closeHideLockedModal(true);
      });
    }

    // Al hacer clic en el switch, cambiamos la selección temporal (sin persistir aún)
    if (hlGridSwitch) {
      hlGridSwitch.addEventListener("click", (e) => {
        const option = e.target.closest(".hl-grid-option");
        if (!option) return;

        const newValue = option.dataset.value === "true";
        if (newValue === hlTempValue) return; // Ya está en ese estado

        hlTempValue = newValue;
        refreshHideLockedUI(hlTempValue);
      });
    }

    // Botón "ACTUALIZAR": aplica la preferencia (localStorage + Lua) y re-renderiza
    if (hlSaveBtn) {
      hlSaveBtn.addEventListener("click", () => {
        DebugPrint("Guardando preferencia 'Ocultar Bloqueados': " + hlTempValue);
        hideLockedSlots = hlTempValue; // Aplicar el valor decidido

        // 1) localStorage (solo-UI, arranque rápido)
        localStorage.setItem(HIDE_LOCKED_STORAGE_KEY, String(hideLockedSlots));

        // 2) Lua (KVP persistente por jugador + recálculo de peds)
        axios
          .post(
            `https://${resName}/setHideLocked`,
            JSON.stringify({ hideLocked: hideLockedSlots }),
          )
          .catch(() => DebugPrint("Aviso: el endpoint /setHideLocked no respondió."));

        // 3) Re-renderizar los slots para aplicar el filtro al momento
        renderSlots();

        // 4) Texto del subtítulo en el sidebar
        const subEl = document.getElementById("hide-locked-sub");
        if (subEl) {
          subEl.innerText = hideLockedSlots
            ? Translate("ui_hide_locked_on", "Solo personajes creados")
            : Translate("ui_hide_locked_off", "Slots vacíos fuera del selector");
        }

        hlModal.style.display = "none";
      });
    }

    // ==========================================
    // 📤📥 EXPORTAR / IMPORTAR PERSONAJE
    // ==========================================
    const expimpModal = document.getElementById("modal-export-import");
    const expimpIcon = document.getElementById("expimp-icon");
    const expimpTitle = document.getElementById("expimp-title");
    const expimpSubtitle = document.getElementById("expimp-subtitle");
    const expimpConfirmBtn = document.getElementById("expimp-confirm-btn");
    const expimpSharedOutput = document.getElementById("expimp-shared-output");
    const expimpOutputLabel = document.getElementById("expimp-output-label");
    const expimpCodeBlock = document.getElementById("expimp-export-code");
    const expimpCodeContent = document.getElementById("expimp-export-code-content");
    const expimpTextarea = document.getElementById("expimp-import-textarea");
    const expimpCopyBtn = document.getElementById("expimp-copy-btn");

    // Cada toggle (export/import) es independiente: solo activa botones DENTRO de su
    // propio bloque (data-scope), nunca los del otro bloque.
    const expimpExportToggle = expimpModal
      ? expimpModal.querySelector('.expimp-format-toggle[data-scope="export"]')
      : null;
    const expimpImportToggle = expimpModal
      ? expimpModal.querySelector('.expimp-format-toggle[data-scope="import"]')
      : null;

    let expimpExportFormat = "json"; // Formato elegido en el bloque Exportar
    let expimpImportFormat = "json"; // Formato elegido en el bloque Importar
    let expimpCurrentCharData = null; // Personaje sobre el que se está exportando (null en modo import)

    // Genera el texto de ejemplo/placeholder para el bloque de código en modo Export.
    // Cuando exista la lógica real de Lua, esta función es el único punto a sustituir
    // por el JSON/XML real que devuelva el servidor para ese personaje.
    function buildExportPreview(format, charData) {
      const cid = charData ? charData.cid : "?";
      const citizenid = charData ? charData.citizenid || "---" : "---";
      const fullName =
        charData && charData.charinfo
          ? `${charData.charinfo.firstname || ""} ${charData.charinfo.lastname || ""}`.trim()
          : "Personaje";

      if (format === "xml") {
        return `<?xml version="1.0" encoding="UTF-8"?>\n<character>\n    <cid>${cid}</cid>\n    <citizenid>${citizenid}</citizenid>\n    <name>${fullName}</name>\n</character>`;
      }

      return JSON.stringify(
        {
          cid: cid,
          citizenid: citizenid,
          name: fullName,
        },
        null,
        4,
      );
    }

    // Actualiza el panel derecho compartido según cuál scope (export/import) esté activo
    // en ese momento (expimpSharedOutput.dataset.activeScope), no según el modo con el que
    // se abrió el modal — así, aunque se abra en modo "import", si el usuario toca el
    // toggle de Exportar, el panel derecho cambia a mostrar el código generado, y viceversa.
    function refreshExpimpOutput() {
      const activeScope = expimpSharedOutput.dataset.activeScope;

      if (activeScope === "export") {
        expimpCodeBlock.style.display = "block";
        expimpTextarea.style.display = "none";
        expimpOutputLabel.innerText = "Código generado";
        expimpCodeContent.textContent = buildExportPreview(
          expimpExportFormat,
          expimpCurrentCharData,
        );
      } else {
        expimpCodeBlock.style.display = "none";
        expimpTextarea.style.display = "block";
        expimpOutputLabel.innerText = "Pegar código";
        expimpTextarea.placeholder =
          expimpImportFormat === "xml"
            ? "Pega aquí tu código XML..."
            : "Pega aquí tu código JSON...";
      }
    }

    // Abre el modal en el modo indicado ('export' o 'import').
    // charData es opcional: si se abre desde la fila de un personaje concreto en la
    // tabla, se usa para generar la vista previa de export con sus datos reales.
    window.openExportImportModal = function (mode, charData) {
      if (!expimpModal) return;

      // Defensa en profundidad: si Config.ExportCharacters/ImportCharacters está en false,
      // no se abre el modal aunque algo dispare esta función (los botones ya están ocultos
      // por CSS, pero esto cubre cualquier otro punto de entrada, ej. la tabla de Opciones).
      if (mode === "export" && !exportCharactersEnabled) {
        DebugPrint(
          "Intento de abrir Exportar Personaje con Config.ExportCharacters = false. Bloqueado.",
        );
        return;
      }
      if (mode === "import" && !importCharactersEnabled) {
        DebugPrint(
          "Intento de abrir Importar Personaje con Config.ImportCharacters = false. Bloqueado.",
        );
        return;
      }

      expimpModal.dataset.mode = mode; // Solo decide título/subtítulo/botón inferior
      expimpCurrentCharData = charData || null;
      expimpExportFormat = "json";
      expimpImportFormat = "json";

      // Resetear el estado visual: solo el botón JSON del bloque correspondiente al modo
      // de apertura queda activo (nunca los dos a la vez, solo puede haber 1 de los 4).
      const activeToggle = mode === "export" ? expimpExportToggle : expimpImportToggle;
      const otherToggle = mode === "export" ? expimpImportToggle : expimpExportToggle;
      if (activeToggle) {
        activeToggle.querySelectorAll(".expimp-format-btn").forEach((btn) => {
          btn.classList.toggle("active", btn.dataset.format === "json");
        });
      }
      if (otherToggle) {
        otherToggle.querySelectorAll(".expimp-format-btn").forEach((btn) => {
          btn.classList.remove("active");
        });
      }

      // El panel derecho arranca mostrando el bloque correspondiente al modo de apertura
      expimpSharedOutput.dataset.activeScope = mode;

      if (mode === "export") {
        expimpIcon.className = "fas fa-file-export modal-icon";
        expimpTitle.innerText = "EXPORTAR PERSONAJE";
        expimpSubtitle.innerText = "Guarda un backup individual.";
        expimpConfirmBtn.innerHTML = '<i class="fas fa-check"></i> EXPORTAR';
        expimpTextarea.value = "";
      } else {
        expimpIcon.className = "fas fa-file-import modal-icon";
        expimpTitle.innerText = "IMPORTAR PERSONAJE";
        expimpSubtitle.innerText = "Restaura un backup previo.";
        expimpConfirmBtn.innerHTML = '<i class="fas fa-check"></i> IMPORTAR';
      }

      refreshExpimpOutput();
      expimpModal.style.display = "flex";
    };

    // Botón del sidebar: "Exportar Personaje" (sin personaje concreto asociado)
    const btnExportSidebar = document.getElementById("btn-export-char");
    if (btnExportSidebar) {
      btnExportSidebar.addEventListener("click", () =>
        window.openExportImportModal("export", lastCharacter),
      );
    }

    // Botón del sidebar: "Importar Personaje"
    const btnImportSidebar = document.getElementById("btn-import-char");
    if (btnImportSidebar) {
      btnImportSidebar.addEventListener("click", () =>
        window.openExportImportModal("import", null),
      );
    }

    // Todos los botones de formato de AMBOS bloques juntos: se usa para que solo pueda
    // haber 1 único botón ".active" entre los 4 en todo momento (no 1 por bloque).
    const expimpAllFormatBtns = expimpModal
      ? expimpModal.querySelectorAll(".expimp-format-btn")
      : [];

    // Toggle de formato del bloque EXPORTAR: al elegir uno, se desactivan los OTROS 3
    // botones (los de su propio bloque Y los del bloque Importar), y marca el panel
    // derecho como "export" (muestra el código generado).
    if (expimpExportToggle) {
      expimpExportToggle.querySelectorAll(".expimp-format-btn").forEach((btn) => {
        btn.addEventListener("click", () => {
          expimpExportFormat = btn.dataset.format;
          expimpAllFormatBtns.forEach((b) => b.classList.toggle("active", b === btn));
          expimpSharedOutput.dataset.activeScope = "export";
          refreshExpimpOutput();
        });
      });
    }

    // Toggle de formato del bloque IMPORTAR: al elegir uno, se desactivan los OTROS 3
    // botones (los de su propio bloque Y los del bloque Exportar), y marca el panel
    // derecho como "import" (muestra el textarea para pegar).
    if (expimpImportToggle) {
      expimpImportToggle.querySelectorAll(".expimp-format-btn").forEach((btn) => {
        btn.addEventListener("click", () => {
          expimpImportFormat = btn.dataset.format;
          expimpAllFormatBtns.forEach((b) => b.classList.toggle("active", b === btn));
          expimpSharedOutput.dataset.activeScope = "import";
          refreshExpimpOutput();
        });
      });
    }

    // Botón de copiar el código generado (solo tiene sentido cuando el panel muestra Export;
    // el CSS ya lo oculta visualmente en modo import, esto es la fuente de verdad del dato)
    if (expimpCopyBtn) {
      expimpCopyBtn.addEventListener("click", () => {
        const textToCopy =
          expimpSharedOutput.dataset.activeScope === "export"
            ? expimpCodeContent.textContent
            : expimpTextarea.value;

        if (!textToCopy) return;

        navigator.clipboard
          .writeText(textToCopy)
          .then(() => {
            expimpCopyBtn.classList.add("copied");
            expimpCopyBtn.innerHTML = '<i class="fas fa-check"></i>';
            setTimeout(() => {
              expimpCopyBtn.classList.remove("copied");
              expimpCopyBtn.innerHTML = '<i class="fas fa-copy"></i>';
            }, 1200);
          })
          .catch(() => {
            DebugPrint("No se pudo copiar al portapapeles.");
          });
      });
    }

    // Cierre (botón "CERRAR")
    if (expimpModal) {
      const expimpCancelBtn = expimpModal.querySelector(".btn-modal-cancel");
      if (expimpCancelBtn) {
        expimpCancelBtn.addEventListener("click", () => {
          expimpModal.style.display = "none";
        });
      }

      // Confirmar (Exportar / Importar). Por ahora solo demo/placeholder:
      // aquí es donde, al conectar con Lua, se mandará axios.post con el
      // JSON/XML generado (export) o el contenido pegado (import).
      expimpConfirmBtn.addEventListener("click", () => {
        const mode = expimpModal.dataset.mode;
        if (mode === "export") {
          DebugPrint(
            "Confirmar exportación en formato " +
              expimpCurrentFormat +
              " (demo, aún sin conectar a Lua).",
          );
        } else {
          if (!expimpTextarea.value.trim()) {
            DebugPrint("Intento de importar sin pegar ningún código.");
            return;
          }
          DebugPrint(
            "Confirmar importación en formato " +
              expimpCurrentFormat +
              " (demo, aún sin conectar a Lua).",
          );
        }
        expimpModal.style.display = "none";
      });
    }

    // ==========================================
    // 📜 HISTORIAL DE ACTIVIDAD DEL PERSONAJE
    // ==========================================
    window.openHistoryModal = function (charData) {
      const modal = document.getElementById("modal-char-history");
      if (!modal) return;

      document.getElementById("history-subtitle").innerText =
        `${charData.charinfo.firstname} ${charData.charinfo.lastname} (${charData.citizenid})`;

      // Formatear Tiempo Jugado
      let rawPlaytime =
        charData.metadata && charData.metadata.playtime
          ? parseInt(charData.metadata.playtime)
          : 0;
      if (isNaN(rawPlaytime)) rawPlaytime = 0;
      let hours = Math.floor(rawPlaytime / 3600);
      let mins = Math.floor((rawPlaytime % 3600) / 60);

      // Formatear Fechas (Creación y Última vez)
      let lastSeen = charData.last_updated
        ? formatDateTime(charData.last_updated)
        : "Desconocido";
      // Si tu base de datos envía un created_at, o si lo guardas en metadata, lo lee aquí:
      let createdAt =
        charData.metadata && charData.metadata.created_at
          ? formatDateTime(charData.metadata.created_at)
          : charData.created_at
            ? formatDateTime(charData.created_at)
            : "Desconocido";

      document.getElementById("history-val-created").innerText = createdAt;
      document.getElementById("history-val-playtime").innerText = `${hours}h ${mins}m`;
      document.getElementById("history-val-lastseen").innerText = lastSeen;

      // Renderizar Timeline (Log de Eventos)
      const timeline = document.getElementById("history-timeline-list");
      timeline.innerHTML = "";

      // Si el servidor envía un array de eventos en metadata.activityLog, lo pintamos.
      let logs =
        charData.metadata && charData.metadata.activityLog
          ? charData.metadata.activityLog
          : [];

      if (logs.length === 0) {
        timeline.innerHTML =
          '<div class="history-item-empty">No hay eventos recientes registrados para este personaje.</div>';
      } else {
        logs.forEach((log) => {
          const icon = log.icon || "fa-info";
          timeline.innerHTML += `
                        <div class="history-item">
                            <div class="history-item-icon"><i class="fas ${icon}"></i></div>
                            <div class="history-item-content">
                                <span class="history-item-date">${log.date || "Desconocido"}</span>
                                <span class="history-item-text">${log.text}</span>
                            </div>
                        </div>
                    `;
        });
      }

      modal.style.display = "flex";
    };

    // ==========================================
    // ♻️ RESTAURAR PERSONAJE (Papelera)
    // ==========================================
    // NOTA: renderRestoreList() y formatDaysRemaining() viven en scope global
    // (fuera de este IIFE), porque el listener de window.addEventListener('message')
    // que recibe la respuesta de Lua ('deletedCharactersList') está también fuera
    // de este bloque y necesita poder llamarlas.
    const restoreBtn = document.getElementById("btn-restore-char");
    const restoreModal = document.getElementById("modal-restore-char");

    if (restoreBtn && restoreModal) {
      restoreBtn.addEventListener("click", () => {
        DebugPrint("Abriendo modal de Restaurar Personaje. Solicitando lista al servidor.");
        restoreModal.style.display = "flex";

        // Estado inicial: cargando
        document.getElementById("restore-loading-state").style.display = "flex";
        document.getElementById("restore-empty-state").style.display = "none";
        const listEl = document.getElementById("restore-list");
        listEl.style.display = "none";
        listEl.innerHTML = "";

        axios.post(`https://${resName}/getDeletedCharacters`, JSON.stringify({})).catch(() => {
          DebugPrint("Error al pedir la lista de personajes en papelera.");
          document.getElementById("restore-loading-state").style.display = "none";
          document.getElementById("restore-empty-state").style.display = "flex";
        });
      });
    }
  })();

  // ==========================================
  // 🛒 TIENDA INICIAL (STARTER ITEMS)
  // ==========================================

  // Calcula el precio de un item con el +25% de recargo y redondea hacia arriba sin decimales.
  function getModifiedPrice(basePrice) {
    if (!basePrice || basePrice <= 0) return 0;
    return Math.ceil(basePrice * 1.25);
  }

  function renderStarterItems() {
    const grid = document.getElementById("starter-items-grid");
    grid.innerHTML = "";
    cartItems = {};
    cartTotal = 0;

    document.getElementById("starter-receipt-list").innerHTML =
      '<div class="receipt-empty">El carrito está vacío.</div>';
    document.getElementById("starter-receipt-total").innerText = "$0";

    startingItemsData.forEach((item) => {
      // Inicializamos la cantidad a su mínimo (o 0 si no tiene)
      const minQty = item.min !== undefined ? item.min : 0;
      cartItems[item.name] = minQty;

      const finalPrice = getModifiedPrice(item.price);
      const card = document.createElement("div");
      card.className = "starter-card";
      const imageName = item.name.toLowerCase();

      // Usamos item.label si existe, si no, fallback al name técnico
      const displayName = item.label || item.name;

      card.innerHTML = `
                <div class="starter-img-box">
                    <i class="fas fa-box-open starter-img-fallback" style="display: none;"></i>
                    <img src="items/${imageName}.png" class="starter-img" alt="${displayName}" 
                         onerror="this.style.display='none'; this.previousElementSibling.style.display='block';">
                </div>
                <div class="starter-item-name">${displayName}</div>
                <div class="starter-controls">
                    <button class="starter-qty-btn btn-minus" data-item="${item.name}"><i class="fas fa-minus"></i></button>
                    <button class="starter-qty-btn btn-plus" data-item="${item.name}"><i class="fas fa-plus"></i></button>
                </div>
            `;
      grid.appendChild(card);
    });

    // Actualizamos la UI inmediatamente para reflejar los mínimos obligatorios (Ej: id_card a 1)
    updateStarterUI();

    // Listeners para los botones + y -
    document.querySelectorAll(".btn-minus").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        const itemName = e.currentTarget.dataset.item;
        const itemData = startingItemsData.find((i) => i.name === itemName);
        const minQty = itemData.min !== undefined ? itemData.min : 0;

        if (cartItems[itemName] > minQty) {
          cartItems[itemName]--;
          updateStarterUI();
        }
      });
    });

    document.querySelectorAll(".btn-plus").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        const itemName = e.currentTarget.dataset.item;
        const itemData = startingItemsData.find((i) => i.name === itemName);
        const maxQty = itemData.max !== undefined ? itemData.max : 10;
        const finalPrice = getModifiedPrice(itemData.price);

        if (cartItems[itemName] < maxQty) {
          if (cartTotal + finalPrice <= startingBudget) {
            cartItems[itemName]++;
            updateStarterUI();
          } else {
            const budgetEl = document.getElementById("starter-budget");
            budgetEl.style.color = "#ff4747";
            setTimeout(() => (budgetEl.style.color = "#ffffff"), 300);
          }
        }
      });
    });
  }

  function updateStarterUI() {
    cartTotal = 0;
    let totalItemsInCart = 0;
    const receiptList = document.getElementById("starter-receipt-list");
    receiptList.innerHTML = "";

    startingItemsData.forEach((item) => {
      const qty = cartItems[item.name];
      totalItemsInCart += qty;

      const btnMinus = document.querySelector(
        `.starter-qty-btn.btn-minus[data-item="${item.name}"]`,
      );
      const btnPlus = document.querySelector(
        `.starter-qty-btn.btn-plus[data-item="${item.name}"]`,
      );

      const minQty = item.min !== undefined ? item.min : 0;
      const maxQty = item.max !== undefined ? item.max : 10;
      const finalPrice = getModifiedPrice(item.price);

      if (btnMinus) btnMinus.disabled = qty <= minQty;
      if (btnPlus) btnPlus.disabled = qty >= maxQty || cartTotal + finalPrice > startingBudget;

      // Rellenar el tíquet de compra a la derecha si hay más de 0
      if (qty > 0) {
        const lineTotal = qty * finalPrice;
        const priceDisplay = finalPrice === 0 ? "GRATIS" : `$${lineTotal.toLocaleString()}`;
        const displayName = item.label || item.name;

        receiptList.innerHTML += `
                    <div class="receipt-item">
                        <div class="receipt-item-info">
                            <span class="receipt-item-qty">${qty}x</span>
                            <span class="receipt-item-name">${displayName}</span>
                        </div>
                        <span class="receipt-item-price">${priceDisplay}</span>
                    </div>
                `;
      }

      cartTotal += qty * finalPrice;
    });

    if (totalItemsInCart === 0) {
      receiptList.innerHTML = '<div class="receipt-empty">El carrito está vacío.</div>';
    }

    document.getElementById("starter-receipt-total").innerText =
      `$${cartTotal.toLocaleString()}`;
    updateStarterFooter(totalItemsInCart);
  }

  function updateStarterFooter(totalItems) {
    document.getElementById("starter-budget").innerText =
      `$${startingBudget.toLocaleString()}`;
    document.getElementById("starter-total").innerText = `$${cartTotal.toLocaleString()}`;

    const purchaseBtn = document.getElementById("btn-starter-purchase");
    // Si hay ALGÚN ítem en el carrito (aunque sea el DNI gratis), consideramos que es una "Compra"
    if (totalItems > 0) {
      purchaseBtn.innerText = Translate("ui_starter_purchase", "CONFIRMAR");
      purchaseBtn.classList.add("ready-to-buy");
    } else {
      purchaseBtn.innerText = Translate("ui_starter_skip", "OMITIR");
      purchaseBtn.classList.remove("ready-to-buy");
    }

    // Botón VOLVER desde la tienda de ítems de vuelta al formulario de registro
    const btnStarterBack = document.getElementById("btn-starter-back");
    if (btnStarterBack) {
      btnStarterBack.addEventListener("click", () => {
        DebugPrint("Volviendo al formulario de creación de personaje manteniendo los datos.");

        // Volvemos a mostrar la pantalla de registro
        showScreen("character-register");
      });
    }
  }

  // Acción del botón inferior de la Tienda (Purchase / Skip)
  document.getElementById("btn-starter-purchase").addEventListener("click", () => {
    let totalItemsInCart = 0;
    for (const qty of Object.values(cartItems)) {
      totalItemsInCart += qty;
    }

    if (totalItemsInCart > 0) {
      const summaryList = document.getElementById("starter-summary-list");
      summaryList.innerHTML = "";

      startingItemsData.forEach((item) => {
        const qty = cartItems[item.name];
        if (qty > 0) {
          const price = getModifiedPrice(item.price);
          const lineTotal = price * qty;
          const priceDisplay = price === 0 ? "GRATIS" : `$${lineTotal.toLocaleString()}`;
          const imageName = item.name.toLowerCase();
          const displayName = item.label || item.name;

          summaryList.innerHTML += `
                        <div class="starter-summary-item">
                            <span class="starter-summary-item-name">
                                <img src="items/${imageName}.png" onerror="this.style.display='none';">
                                ${qty}x ${displayName}
                            </span>
                            <span>${priceDisplay}</span>
                        </div>
                    `;
        }
      });
      document.getElementById("starter-summary-price").innerText =
        `$${cartTotal.toLocaleString()}`;
      document.getElementById("modal-starter-confirm").style.display = "flex";
    } else {
      submitFinalCharacterCreation(null);
    }
  });
});

// ===============================================
// === FUNCIONES DE APOYO (RUTEO DE PANTALLAS) ===
// ===============================================
// Función maestra para cambiar entre las secciones de la UI de forma limpia
// Limpia el estado visual de la pantalla "Personajes" (panel de detalle, botonera de
// acción, título superior y visibilidad de los slots) dejándolo exactamente como al
// primer arranque de la UI: nada seleccionado. Sin esto, si la UI se cierra y se vuelve
// a abrir sin recargar la página (p.ej. tras /logout), el panel seguía mostrando los
// datos y botones ("JUGAR"/"DETALLES") del último personaje seleccionado en la sesión
// anterior, aunque el jugador todavía no hubiera hecho clic en ningún slot.
function resetCharacterListState() {
  selectedSlot = null;
  isZoomed = false;

  const actionButtons = document.getElementById("action-buttons");
  if (actionButtons) actionButtons.style.display = "none";

  const panel = document.getElementById("detailed-char-info");
  if (panel) panel.classList.add("hidden");

  const topTitle = document.querySelector(".top-title");
  if (topTitle) topTitle.classList.remove("hidden");

  const slotsWrapper = document.getElementById("slots-wrapper");
  if (slotsWrapper) slotsWrapper.classList.remove("slots-hidden");

  document.querySelectorAll(".char-slot").forEach((el) => el.classList.remove("active"));

  setFooterZoomState(false);
}

function showScreen(screenId) {
  DebugPrint("Cambiando pantalla a: " + screenId);
  document.getElementById("landing-screen").style.display = "none";
  document.getElementById("character-list").style.display = "none";
  document.getElementById("character-register").style.display = "none";
  document.getElementById("options-screen").style.display = "none";
  document.getElementById("starter-items-screen").style.display = "none";

  document.getElementById(screenId).style.display =
    screenId === "landing-screen" ? "flex" : "block";

  if (screenId === "landing-screen") {
    document.querySelectorAll(".landing-bg").forEach((bg) => bg.classList.remove("show"));
    document.getElementById("bg-" + (currentLandingIndex + 1)).classList.add("show");
  } else if (screenId === "options-screen") {
    // Asegurar que el fondo de opciones tenga la clase show
    const bgOpt = document.getElementById("bg-options");
    if (bgOpt) bgOpt.classList.add("show");
  } else if (screenId === "character-list") {
    // Siempre que se entra a "Personajes" arrancamos sin ningún slot seleccionado,
    // para no arrastrar el panel/botonera del último personaje de una sesión anterior.
    resetCharacterListState();
  }
}

// === SELECCIONAR / ENFOCAR UN SLOT (click inicial o navegación con flechas) ===
// animateDirection: 0 = sin animación (primer click), 1 = siguiente (derecha), -1 = anterior (izquierda)
function selectSlot(slotId, animateDirection = 0) {
  DebugPrint("Ejecutando selectSlot para el slot: " + slotId);
  document.querySelectorAll(".char-slot").forEach((el) => el.classList.remove("active"));
  const slotEl = document.querySelector(`.char-slot[data-slot="${slotId}"]`);
  if (slotEl) slotEl.classList.add("active");

  selectedSlot = slotId;
  const charData = charactersData.find((c) => c.cid === slotId);

  // Ocultar el título superior al seleccionar un personaje
  document.querySelector(".top-title").classList.add("hidden");

  // Mostrar botonera de acción principal
  document.getElementById("action-buttons").style.display = "flex";

  // Ocultar los contenedores de los slots mientras la cámara se enfoca
  document.getElementById("slots-wrapper").classList.add("slots-hidden");

  isZoomed = true;
  setFooterZoomState(true); // Al enfocar un personaje mostramos indicaciones de MOVER + SELECCIONAR + SALIR

  // El zoom/pan de cámara ya se anima suavemente en el cliente Lua.
  axios.post(`https://${resName}/focusCharacter`, JSON.stringify({ slot: slotId }));

  const panel = document.getElementById("detailed-char-info");
  const panelBody = panel.querySelector(".panel-body");
  const panelWasVisible = !panel.classList.contains("hidden");

  // Aplica el contenido correspondiente (datos del personaje o pantalla de "crear")
  function applyContent() {
    if (charData) {
      DebugPrint("Slot ocupado. Renderizando estadísticas del personaje.");
      document.getElementById("action-header-text").innerText = Translate(
        "ui_selected_character",
        "PERSONAJE SELECCIONADO",
      );
      document.getElementById("action-btn-text").innerText = Translate("ui_play", "JUGAR");
      updateDetailedPanel(charData);
    } else {
      DebugPrint("Slot vacío. Preparando interfaz de Nuevo Personaje.");
      document.getElementById("detailed-char-info").classList.add("hidden");
      document.getElementById("action-header-text").innerText = Translate(
        "ui_new_character",
        "NUEVO PERSONAJE",
      );
      document.getElementById("action-btn-text").innerText = Translate("ui_create", "CREAR");

      // --- DETECTAR Y MARCAR EL GÉNERO ALEATORIO DE ESTE SLOT ---
      // Aseguramos que leemos la clave como número o string, dependiendo de cómo llegó
      let currentSavedGender =
        randomSlotGenders[slotId] !== undefined
          ? randomSlotGenders[slotId]
          : randomSlotGenders[String(slotId)];
      let rGender = currentSavedGender === 1 ? "Femenino" : "Masculino";
      selectedGender = rGender;

      document.querySelectorAll(".gender-btn").forEach((el) => el.classList.remove("active"));
      const btnNode = document.querySelector(`.gender-btn[data-gender="${rGender}"]`);
      if (btnNode) btnNode.classList.add("active");

      // Se solicita la previsualización del ped respetando el género que le tocó
      axios.post(
        `https://${resName}/previewPed`,
        JSON.stringify({
          gender: selectedGender,
          slot: slotId,
        }),
      );
    }
  }

  if (animateDirection !== 0 && panelBody && panelWasVisible && charData) {
    // Navegando con flechas y el panel ya está visible con un personaje:
    // solo cambiamos el contenido interno con un crossfade (desvanecimiento), el panel NO se oculta.
    panelBody.classList.add("content-fading");
    setTimeout(() => {
      applyContent();
      panelBody.classList.remove("content-fading");
    }, 140);
  } else {
    // Primera selección (o pasamos a un slot vacío): comportamiento normal de aparición del panel completo
    applyContent();
  }
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

  // Si "Ocultar Bloqueados" está activo, la navegación con flechas salta
  // SOLO entre los slots que tienen personajes creados (los vacíos no existen en la vista).
  if (hideLockedSlots) {
    const occupiedSlots = charactersData.map((c) => c.cid).sort((a, b) => a - b);
    if (occupiedSlots.length <= 1) {
      // Solo hay un personaje: no hay a dónde navegar
      DebugPrint(
        "Navegación bloqueada: solo existe un personaje con 'Ocultar Bloqueados' activo.",
      );
      isNavigating = false;
      navQueue = [];
      return;
    }
    const currentIndex = occupiedSlots.indexOf(selectedSlot);
    const nextIndex = (currentIndex + direction + occupiedSlots.length) % occupiedSlots.length;
    newSlot = occupiedSlots[nextIndex];
  } else {
    // Navegación cíclica normal por todos los slots (ocupados y vacíos)
    if (newSlot < 1) newSlot = maxSlots;
    if (newSlot > maxSlots) newSlot = 1;
  }

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
  const el = document.querySelector(
    direction > 0 ? ".action-arrows-right" : ".action-arrows-left",
  );
  if (!el) return;
  el.classList.add("pressed");
  setTimeout(() => el.classList.remove("pressed"), 180);
}

// === FUNCIÓN PARA ACTUALIZAR EL PANEL DE ESTADÍSTICAS DEL PERSONAJE ===
function updateDetailedPanel(charData) {
  if (!charData) {
    document.getElementById("detailed-char-info").classList.add("hidden");
    return;
  }

  // 1. Identidad básica
  document.getElementById("det-name").innerText =
    `${charData.charinfo.firstname} ${charData.charinfo.lastname}`;
  document.getElementById("det-dob").innerText = charData.charinfo.birthdate;
  const nationalityId = String(charData.charinfo.nationality || "").toLowerCase();
  const nationality = nationalitiesData.find(
    (item) => String(item.id).toLowerCase() === nationalityId,
  );
  document.getElementById("det-nat").innerText = nationality
    ? nationality.label
    : charData.charinfo.nationality || "---";
  document.getElementById("det-gender").innerText =
    charData.charinfo.gender === 0 ? "Masculino" : "Femenino";

  // 2. Economía y Teléfono
  document.getElementById("det-cash").innerText =
    `$${(charData.money.cash || 0).toLocaleString()}`;
  document.getElementById("det-bank").innerText =
    `$${(charData.money.bank || 0).toLocaleString()}`;

  let phone = charData.charinfo.phone;
  if (!phone && charData.metadata && charData.metadata.phonedata) {
    // Fallback por si usan otro sistema de teléfono basado en metadata
    phone = charData.metadata.phonedata.SerialNumber;
  }
  document.getElementById("det-phone").innerText = phone || "No asignado";

  // 3. Trabajo civil/oficial
  let rowJob = document.getElementById("row-job");
  const hasJob = charData.job && charData.job.name !== "unemployed";
  if (hasJob) {
    let badge = charData.job.isboss ? `<span class="boss-badge">JEFE</span>` : "";
    document.getElementById("det-job").innerHTML =
      `${charData.job.label} - ${charData.job.grade.name} ${badge}`;
    rowJob.style.display = "flex";
  } else {
    rowJob.style.display = "none";
  }

  // 4. Banda/Gang ilegal
  let rowGang = document.getElementById("row-gang");
  const hasGang = charData.gang && charData.gang.name !== "none";
  if (hasGang) {
    let badge = charData.gang.isboss ? `<span class="boss-badge">LÍDER</span>` : "";
    document.getElementById("det-gang").innerHTML =
      `${charData.gang.label} - ${charData.gang.grade.name} ${badge}`;
    rowGang.style.display = "flex";
  } else {
    rowGang.style.display = "none";
  }
  document.getElementById("group-factions").style.display =
    hasJob || hasGang ? "block" : "none";

  // 5. Tiempo jugado (Metadatos)
  let rawPlaytime =
    charData.metadata && charData.metadata.playtime ? parseInt(charData.metadata.playtime) : 0;
  if (isNaN(rawPlaytime)) rawPlaytime = 0;
  let hours = Math.floor(rawPlaytime / 3600);
  let mins = Math.floor((rawPlaytime % 3600) / 60);
  document.getElementById("det-playtime").innerText = `${hours}h ${mins}m`;

  // 6. Última visita al servidor
  let lastSeen = charData.last_updated ? formatDateTime(charData.last_updated) : "Desconocido";
  document.getElementById("det-lastseen").innerText = lastSeen;

  // 7. Sistema de Skills/Habilidades (Dinámico)
  let skillsContainer = document.getElementById("det-skills-container");
  let groupSkills = document.getElementById("group-skills");
  skillsContainer.innerHTML = "";

  let skillsObj =
    (charData.metadata && (charData.metadata.skills || charData.metadata.Skills)) || null;
  // Si viene como string escapado, intentar parsear
  if (typeof skillsObj === "string") {
    try {
      skillsObj = JSON.parse(skillsObj);
    } catch (e) {
      skillsObj = null;
    }
  }

  if (skillsObj && Object.keys(skillsObj).length > 0) {
    groupSkills.style.display = "block";
    // Iconografía base para las habilidades típicas de FiveM
    const skillIcons = {
      strength: "fa-dumbbell",
      cardio: "fa-heart-pulse",
      driving: "fa-car",
      shooting: "fa-crosshairs",
      farming: "fa-seedling",
      fishing: "fa-fish",
      mining: "fa-hammer",
      crafting: "fa-screwdriver-wrench",
      gathering: "fa-boxes-stacked",
    };

    for (const [skillName, skillData] of Object.entries(skillsObj)) {
      let pct = Math.min(Math.max(skillData.Current || 0, 0), 100);
      let icon = skillData.icon || skillIcons[skillName.toLowerCase()] || "fa-star";

      const skillDiv = document.createElement("div");
      skillDiv.className = "skill-item";
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
      const fills = skillsContainer.querySelectorAll(".skill-bar-fill");
      const skills = Object.values(skillsObj);
      fills.forEach((fill, index) => {
        if (skills[index]) {
          let pct = Math.min(Math.max(skills[index].Current || 0, 0), 100);
          fill.style.width = `${pct}%`;
        }
      });
    }, 100);
  } else {
    groupSkills.style.display = "none"; // Si no hay habilidades, ocultar panel
  }

  // Mostrar panel lateral completo
  document.getElementById("detailed-char-info").classList.remove("hidden");
}

// Configura la visibilidad y texto dinámico del Landing Screen en base a los personajes existentes
function updateLandingScreen() {
  const playBtn = document.getElementById("btn-land-play");
  const textSpan = document.getElementById("text-last-char");
  const nameSpan = document.getElementById("last-character-name");

  if (lastCharacter) {
    playBtn.classList.remove("disabled");
    textSpan.innerText = Translate("ui_continue_button", "CONTINÚA CON TU HISTORIA");
    nameSpan.innerText = `${lastCharacter.charinfo.firstname} ${lastCharacter.charinfo.lastname}`;
  } else {
    playBtn.classList.add("disabled");
    textSpan.innerText = Translate("ui_continue_button", "CONTINÚA CON TU HISTORIA");
    nameSpan.innerText = "";
    currentLandingIndex = 1; // Forzar foco de inicio a la lista "Personajes" si no hay ninguno creado
  }
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  const pad = (number) => String(number).padStart(2, "0");
  return (
    `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()}, ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  );
}

// Formatea los días restantes de un personaje en papelera en un texto legible
function formatDaysRemaining(days) {
  if (days <= 0) return "Menos de 1 día";
  if (days === 1) return "1 día";
  return days + " días";
}

// Pinta la lista de personajes en papelera (Restaurar Personaje) recibida del servidor.
// Se llama desde el listener de window.addEventListener('message') al recibir
// la acción 'deletedCharactersList', por eso vive en scope global igual que renderSlots().
function renderRestoreList(characters) {
  const loadingState = document.getElementById("restore-loading-state");
  const emptyState = document.getElementById("restore-empty-state");
  const listContainer = document.getElementById("restore-list");
  if (!loadingState || !emptyState || !listContainer) return;

  loadingState.style.display = "none";

  if (!characters || characters.length === 0) {
    emptyState.style.display = "flex";
    listContainer.style.display = "none";
    listContainer.innerHTML = "";
    return;
  }

  emptyState.style.display = "none";
  listContainer.style.display = "flex";
  listContainer.innerHTML = "";

  characters.forEach((char) => {
    const fullName = char.charinfo
      ? `${char.charinfo.firstname || ""} ${char.charinfo.lastname || ""}`.trim()
      : "Personaje";

    const row = document.createElement("div");
    row.className = "restore-row";
    row.innerHTML = `
            <div class="restore-row-info">
                <span class="restore-row-name">${fullName}</span>
                <span class="restore-row-meta">CitizenID: ${char.citizenid || "---"} &middot; Se elimina definitivamente en ${formatDaysRemaining(char.daysRemaining)}</span>
            </div>
            <button type="button" class="btn-restore-row" data-citizenid="${char.citizenid}">
                <i class="fas fa-clock-rotate-left"></i> Restaurar
            </button>
        `;
    listContainer.appendChild(row);

    row.querySelector(".btn-restore-row").addEventListener("click", (e) => {
      const citizenid = char.citizenid;
      DebugPrint("Solicitando restaurar personaje CitizenID: " + citizenid);
      setButtonLoading(e.currentTarget, true);

      axios
        .post(`https://${resName}/restoreCharacter`, JSON.stringify({ citizenid }))
        .catch(() => DebugPrint("Error al solicitar la restauración del personaje."))
        .finally(() => {
          setButtonLoading(e.currentTarget, false);
          const modal = document.getElementById("modal-restore-char");
          if (modal) modal.style.display = "none";
        });
    });
  });
}

// Aplica (u oculta) la visibilidad de todo lo relacionado con Exportar/Importar Personaje,
// según Config.ExportCharacters / Config.ImportCharacters enviados desde Lua. Se usan clases
// en <body> en vez de ocultar elementos uno a uno, porque el botón de exportar de cada fila
// se regenera dinámicamente cada vez que la tabla de Opciones se vuelve a renderizar (el CSS
// ligado a estas clases se encarga de ocultarlo también en las filas futuras automáticamente).
function applyExportImportVisibility() {
  document.body.classList.toggle("export-chars-disabled", !exportCharactersEnabled);
  document.body.classList.toggle("import-chars-disabled", !importCharactersEnabled);
  DebugPrint(
    "Visibilidad Exportar/Importar aplicada. Exportar: " +
      exportCharactersEnabled +
      ", Importar: " +
      importCharactersEnabled,
  );
}

// Construye e inyecta los contenedores (slots) HTML para cada ranura de personaje permitida
function renderSlots() {
  DebugPrint(
    "Renderizando HTML de slots (" +
      maxSlots +
      " totales). Ocultar vacíos: " +
      hideLockedSlots,
  );
  const wrapper = document.getElementById("slots-wrapper");
  wrapper.innerHTML = "";

  for (let i = 1; i <= maxSlots; i++) {
    const char = charactersData.find((c) => c.cid === i);

    if (char) {
      // Slot ocupado
      wrapper.innerHTML += `
                <div class="char-slot" data-slot="${i}">
                    <div class="slot-details">
                        <span class="slot-name">${char.charinfo.firstname} ${char.charinfo.lastname}</span>
                    </div>
                </div>
            `;
    } else if (!hideLockedSlots || charactersData.length === 0) {
      // Slot vacío (con icono de más).
      // Si "Ocultar Bloqueados" está activo, los slots vacíos NO se pintan...
      // EXCEPTO si el usuario no tiene ningún personaje creado: en ese caso
      // se muestra al menos el primer slot para que pueda crear el primero
      // (evita un callejón sin salida en el selector).
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
  document.getElementById("reg-firstname").value = "";
  document.getElementById("reg-lastname").value = "";

  // Resetear Flatpickr correctamente
  const dobInput = document.getElementById("reg-dob");
  if (dobInput._flatpickr) {
    dobInput._flatpickr.clear();
    applyAgeLimitsToFlatpickr(dobInput._flatpickr);
    if (dobInput._flatpickr.calendarContainer) {
      dobInput._flatpickr.calendarContainer.classList.remove("fp-panel-open");
    }
  } else {
    dobInput.value = "";
  }

  // Si los paneles custom de mes/año quedaron abiertos, los cerramos también
  document
    .querySelectorAll(".fp-month-picker.visible, .fp-year-picker.visible")
    .forEach((panel) => {
      panel.classList.remove("visible");
    });

  selectedNationality = null;
  document.getElementById("nationality-text").innerText = Translate(
    "ui_search_country",
    "Selecciona un país de nacimiento",
  );
  document.getElementById("nationality-display").classList.remove("selected");
  document.getElementById("nationality-search").value = "";
  document.querySelectorAll(".dropdown-option").forEach((option) => {
    option.style.display = "flex";
  });

  // Resetear el selector custom
  selectedNationality = null;
  document.getElementById("nationality-text").innerText = Translate(
    "ui_search_country",
    "Selecciona un país de nacimiento",
  );
  document.getElementById("nationality-display").classList.remove("selected");
  document.getElementById("nationality-search").value = "";
  document.querySelectorAll(".dropdown-option").forEach((opt) => (opt.style.display = "flex"));

  DebugPrint("Formulario de registro reseteado.");
}
