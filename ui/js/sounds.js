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