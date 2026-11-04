// ui/js/dev.js
// Simulador de entorno de FiveM para desarrollo en el navegador local.
// NO interfiere con el juego. Si detecta que estás dentro de FiveM, se apaga solo.

if (!window.invokeNative) {
  console.log("🌐 MODO DESARROLLADOR: Simulador de FiveM activado.");

  // 1. SOLUCIÓN AL CRASHEO DE LA LÍNEA 1: Simulamos la función nativa de FiveM
  window.GetParentResourceName = function () {
    return "DP-MultiCharacter";
  };

  // 2. SOLUCIÓN A LA PANTALLA BLANCA: Forzamos un fondo oscuro en el body para el navegador
  document.body.style.backgroundColor = "#0b0c10";
  document.body.style.backgroundImage = "none";

  // 3. SIMULADOR DE RED (Opcional pero recomendado)
  // Engañamos a Axios para que las peticiones (Jugar, Crear, etc.) den "éxito"
  // y puedas ver las animaciones de carga de los botones sin que salte el modal de Error.
  if (window.axios) {
    axios.post = function (url, data) {
      console.log("📡 [Axios Mock] Petición enviada a:", url, " | Payload:", data);
      return new Promise((resolve) => {
        setTimeout(() => resolve({ data: "ok" }), 500); // Simulamos 500ms de ping
      });
    };
  }

  // Estilos del panel de control
  const devPanelStyle = `
        position: fixed; top: 10px; left: 10px; background: rgba(15, 15, 15, 0.95);
        border: 1px solid rgba(255, 255, 255, 0.1); padding: 15px; z-index: 9999999;
        display: flex; flex-direction: column; gap: 10px; border-radius: 6px;
        color: white; font-family: 'Poppins', sans-serif; font-size: 12px;
        box-shadow: 0 5px 25px rgba(0,0,0,0.8); width: 250px;
    `;

  const btnStyle = `
        background: rgba(255,255,255,0.05); color: white; border: 1px solid rgba(255,255,255,0.1);
        padding: 8px 12px; cursor: pointer; border-radius: 4px; font-weight: 700;
        transition: all 0.2s; font-family: inherit; font-size: 11px; text-transform: uppercase;
    `;

  const panel = document.createElement("div");
  panel.style.cssText = devPanelStyle;
  panel.innerHTML = `<strong style="color: #ffffff; letter-spacing: 1px; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 8px; margin-bottom: 5px; text-align: center; display: block;"><i class="fas fa-code"></i> DevTools UI</strong>`;

  // Función que engaña a tu app.js haciéndole creer que Lua le ha hablado
  function sendLuaMessage(data) {
    window.dispatchEvent(new MessageEvent("message", { data: data }));
  }

  // Datos simulados (Puedes cambiar los nombres o el dinero para probar)
  const mockTranslations = {
    ui_continue_button: "CONTINÚA CON TU HISTORIA",
    ui_characters_button: "PERSONAJES",
    ui_options_button: "OPCIONES",
    ui_select_character: "SELECCIONA UN PERSONAJE",
    ui_create: "CREAR",
    ui_play: "JUGAR",
    ui_new_character: "NUEVO PERSONAJE",
    ui_my_characters: "MIS PERSONAJES",
    ui_characters_title: "TUS PERSONAJES",
    ui_characters_desc: "Elige tu vida en la ciudad.",
    ui_options_title: "OPCIONES",
    ui_options_desc: "Configuración del multicharacter.",
  };

  const mockCharacters = [
    {
      cid: 1,
      citizenid: "ABC12345",
      charinfo: {
        firstname: "Alessandro",
        lastname: "Vittorio",
        birthdate: "1992-11-14",
        gender: 0,
        nationality: "it",
        phone: "555-1234",
      },
      money: { cash: 500, bank: 25000 },
      job: { name: "police", label: "LSPD", grade: { name: "Oficial" }, isboss: false },
      gang: { name: "none", label: "Sin banda", grade: { name: "" } },
      metadata: {
        playtime: 36000,
        health: 200,
        armor: 50,
        created_at: Date.now(),
        skills: { stamina: { Current: 100 }, driving: { Current: 50 } },
      },
      last_updated: Date.now(),
    },
    {
      cid: 2,
      citizenid: "XYZ98765",
      charinfo: {
        firstname: "María",
        lastname: "García",
        birthdate: "1998-05-22",
        gender: 1,
        nationality: "es",
        phone: "555-9876",
      },
      money: { cash: 1200, bank: 150 },
      job: { name: "unemployed", label: "Desempleado", grade: { name: "" } },
      gang: { name: "cartel", label: "Cártel de Madrazo", grade: { name: "Sicario" } },
      metadata: {
        playtime: 7200,
        health: 150,
        armor: 0,
        created_at: Date.now(),
        skills: { stamina: { Current: 30 } },
      },
      last_updated: Date.now(),
    },
  ];

  const mockDeletedCharacters = [
    {
      citizenid: "QWE45678",
      charinfo: { firstname: "Juan", lastname: "Pérez" },
      daysRemaining: 3,
    },
  ];

  // ==========================================
  // BOTONES DE SIMULACIÓN PARA EL NAVEGADOR
  // ==========================================
  const buttons = [
    {
      label: "1. Inicializar (ToggleUI)",
      action: () =>
        sendLuaMessage({
          action: "toggleUI",
          state: true,
          debug: true,
          translations: mockTranslations,
          nationalities: [
            { id: "es", label: "España" },
            { id: "it", label: "Italia" },
            { id: "us", label: "Estados Unidos" },
          ],
          minAge: 18,
          maxAge: 100,
          hideLocked: false,
          exportCharacters: true,
          importCharacters: true,
          startingItems: [
            { name: "water_bottle", label: "Agua", price: 10, min: 1, max: 5 },
            { name: "sandwich", label: "Bocadillo", price: 15, min: 0, max: 5 },
            { name: "phone", label: "Teléfono", price: 500, min: 1, max: 1 },
          ],
          startingBudget: 1000,
        }),
    },
    {
      label: "2. Cargar Personajes",
      action: () =>
        sendLuaMessage({
          action: "setupCharacters",
          characters: mockCharacters,
          slots: 5,
          lastCharacter: mockCharacters[0],
          trashedSlots: 1,
        }),
    },
    {
      label: "Abrir Menú Organización",
      action: () =>
        sendLuaMessage({
          action: "openOrganizationMenu",
          gang: "Cártel de Madrazo",
          rank: "Jefe",
          funds: 500000,
          ranks: [
            { level: 3, name: "Jefe", isboss: true },
            { level: 2, name: "Sicario", isboss: false },
            { level: 1, name: "Recluta", isboss: false },
          ],
        }),
    },
    {
      label: "Ver Papelera (Restaurar)",
      action: () =>
        sendLuaMessage({
          action: "deletedCharactersList",
          characters: mockDeletedCharacters,
        }),
    },
    {
      label: "Probar Taxi HUD",
      action: () =>
        sendLuaMessage({
          action: "introTaxiHud",
          show: true,
          destination: "Comisaría Central (MRPD)",
          status: "El taxista va con prisa.",
        }),
    },
    {
      label: "Ocultar Taxi HUD",
      action: () => sendLuaMessage({ action: "introTaxiHud", show: false }),
    },
  ];

  buttons.forEach((b) => {
    const btn = document.createElement("button");
    btn.style.cssText = btnStyle;
    btn.innerText = b.label;
    btn.onmouseover = () => (btn.style.background = "rgba(255,255,255,0.15)");
    btn.onmouseout = () => (btn.style.background = "rgba(255,255,255,0.05)");
    btn.onclick = b.action;
    panel.appendChild(btn);
  });

  document.body.appendChild(panel);
}
