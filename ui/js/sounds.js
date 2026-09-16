// ==========================================
// 🔊 SOUNDS DE INTERFAZ (VOLUMEN PROPORCIONAL REAL)
// ==========================================
// Los sonidos se generan localmente con WebAudio (AudioContext) para poder
// aplicar el volumen REAL en proporción al % elegido por el jugador.
// Se usa una síntesis sencilla de tonos (bip) para cada tipo de sonido:
//   - playNav    : navegación / hover   (tono corto agudo)
//   - playSelect : confirmación         (tono medio)
//   - playCancel : cancelación          (tono grave descendente)
// Nota: antes se enviaba un NUI callback a Lua con PlaySoundFrontend, que NO
// permite controlar el volumen. Con WebAudio el volumen se respeta al 100%.

const Sounds = (() => {
    let audioCtx = null;

    // Crea (o reutiliza) el AudioContext. Se crea bajo demanda para respetar
    // el autoplay policy del navegador CEF (necesita un gesto del usuario)
    function getCtx() {
        if (!audioCtx) {
            try {
                audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            } catch (e) {
                if (typeof DebugPrint !== 'undefined') DebugPrint("WebAudio no disponible: " + e.message);
                return null;
            }
        }
        if (audioCtx.state === 'suspended') {
            audioCtx.resume().catch(() => { });
        }
        return audioCtx;
    }

    // Toca un tono con la frecuencia / duración indicadas y el volumen global actual
    function beep(freqStart, freqEnd, duration, type = 'sine', volumeScale = 1) {
        const ctx = getCtx();
        if (!ctx) return;

        // Volumen proporcional real (0-100 -> 0-1)
        const vol = (interfaceVolume !== undefined ? interfaceVolume : 100) / 100;
        const peak = Math.max(0.0001, vol * 0.25 * volumeScale); // pico moderado

        const t0 = ctx.currentTime;
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();

        osc.type = type;
        osc.frequency.setValueAtTime(freqStart, t0);
        if (freqEnd && freqEnd !== freqStart) {
            osc.frequency.exponentialRampToValueAtTime(freqEnd, t0 + duration);
        }

        // Envolvente suave para evitar "clicks" bruscos
        gain.gain.setValueAtTime(0.0001, t0);
        gain.gain.exponentialRampToValueAtTime(peak, t0 + 0.012);
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(t0);
        osc.stop(t0 + duration + 0.05);
    }

    // Si el volumen es 0, no se emite ningún sonido (comportamiento esperado)
    function muted() {
        return interfaceVolume !== undefined && interfaceVolume <= 0;
    }

    return {
        // Hover / navegación entre elementos
        playNav: function () {
            if (muted()) return;
            beep(620, 780, 0.07, 'sine', 0.6);
        },
        // Confirmación / selección
        playSelect: function () {
            if (muted()) return;
            beep(440, 660, 0.11, 'sine', 0.9);
        },
        // Cancelación / retroceso
        playCancel: function () {
            if (muted()) return;
            beep(520, 260, 0.14, 'sine', 0.8);
        },
        // Sonido de prueba del modal (melodía corta)
        playTest: function () {
            if (muted()) return;
            beep(392, 392, 0.09, 'sine', 0.8);
            setTimeout(() => beep(523, 523, 0.09, 'sine', 0.8), 110);
            setTimeout(() => beep(659, 659, 0.14, 'sine', 0.9), 220);
        }
    };
})();

// ==========================================
// 🖱️ LISTENER GLOBAL DELEGADO (cubre TODO lo clicable automáticamente)
// ==========================================
// En vez de llamar a Sounds.playX() manualmente en cada botón (frágil: cualquier
// botón nuevo se queda mudo si alguien se olvida de añadir la llamada), delegamos
// en document.body un único listener de 'mouseover' (nav) y 'click' (select/cancel)
// que cubre CUALQUIER elemento clicable presente o que se añada dinámicamente más
// adelante (filas de tabla regeneradas, modales nuevos, etc.), sin mantenimiento.
document.addEventListener('DOMContentLoaded', () => {
    // Selector de "cualquier cosa que se pueda pulsar" en esta UI. Se amplía aquí
    // si en el futuro se añade un nuevo tipo de elemento clicable con otra clase.
    const CLICKABLE_SELECTOR = [
        'button',
        'a',
        '.char-slot',
        '.gender-btn',
        '.landing-image-card',
        '.land-btn',
        '.sidebar-item',
        '.expimp-format-btn',
        '.table-btn',
        '.grid-switch',
        '[role="switch"]',
        '[role="button"]',
        '.dropdown-option',
        '.gs-thumb',
        'input[type="range"]',
        'input[type="radio"]',
        'input[type="checkbox"]'
    ].join(', ');

    // Clases/IDs que se consideran "acción destructiva o de cancelación" (suenan distinto)
    const CANCEL_SELECTOR = [
        '.btn-danger',
        '.btn-modal-cancel',
        '#btn-cancel-reg',
        '.btn-delete-char',
        '.btn-restore-cancel'
    ].join(', ');

    // El hover (mouseover) burbujea con CADA hijo que el cursor cruza dentro del propio
    // botón (p.ej. el icono "+" de un slot vacío, o los <span> de título/subtítulo de un
    // .sidebar-item). Sin control, eso dispara un segundo "ping" cada vez que el cursor
    // pasa de un hijo a otro DENTRO del mismo elemento clicable. Para evitarlo, comparamos
    // de dónde viene el cursor (e.relatedTarget): si ya estaba dentro del mismo contenedor
    // clicable, es un movimiento interno y no debe volver a sonar; solo suena al entrar
    // al contenedor por primera vez desde fuera.
    document.body.addEventListener('mouseover', (e) => {
        const target = e.target.closest(CLICKABLE_SELECTOR);
        if (!target || typeof Sounds === 'undefined') return;

        // ¿El cursor ya estaba dentro de ESTE MISMO contenedor clicable? Si es así, es un
        // movimiento interno entre hijos (texto, icono, etc.) y no debe volver a sonar.
        if (e.relatedTarget && target.contains(e.relatedTarget)) return;

        Sounds.playNav();
    });

    document.body.addEventListener('click', (e) => {
        const target = e.target.closest(CLICKABLE_SELECTOR);
        if (!target || typeof Sounds === 'undefined') return;

        if (target.closest(CANCEL_SELECTOR)) {
            Sounds.playCancel();
        } else {
            Sounds.playSelect();
        }
    });
});