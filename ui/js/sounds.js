// Este archivo maneja la emisión de sonidos enviando el request a la capa cliente de Lua.
const Sounds = {
    playNav: function () {
        axios.post(`https://${resName}/playSound`, JSON.stringify({ sound: "NAV_UP_DOWN" })).catch(() => { });
    },
    playSelect: function () {
        axios.post(`https://${resName}/playSound`, JSON.stringify({ sound: "SELECT" })).catch(() => { });
    },
    playCancel: function () {
        axios.post(`https://${resName}/playSound`, JSON.stringify({ sound: "CANCEL" })).catch(() => { });
    }
};

document.addEventListener('DOMContentLoaded', () => {
    // Escucha universal para emitir sonido de navegación al pasar el ratón por botones
    document.body.addEventListener('mouseover', (e) => {
        const target = e.target.closest('button, .char-slot, .gender-btn');
        if (target) Sounds.playNav();
    });

    // Escucha universal para emitir sonido de confirmación o cancelación al hacer clic
    document.body.addEventListener('click', (e) => {
        const target = e.target.closest('button, .char-slot, .gender-btn');
        if (target) {
            // Evaluamos si el botón presionado es destructivo/cancelación o de continuación
            if (target.classList.contains('btn-danger') || target.id === 'btn-cancel-reg' || target.id === 'btn-modal-cancel') {
                Sounds.playCancel();
            } else {
                Sounds.playSelect();
            }
        }
    });
});