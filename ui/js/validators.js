// Módulo independiente de validaciones de entrada para la creación del personaje
const Validator = {
    // Lista básica de palabras bloqueadas (ampliable según las normativas del servidor)
    profanityList: ["puta", "cabron", "mierda", "admin", "moderator", "nigger", "hitler"],

    validateName: function (name) {
        if (typeof DebugPrint === 'function') DebugPrint("Ejecutando validateName en: " + name);
        // Solo letras, sin espacios permitidos para el Nombre principal
        const regex = /^[a-zA-ZáéíóúÁÉÍÓÚñÑ]+$/;
        return regex.test(name) && name.length >= 2 && name.length <= 30;
    },

    validateLastName: function (lastName) {
        if (typeof DebugPrint === 'function') DebugPrint("Ejecutando validateLastName en: " + lastName);
        // Letras y espacios permitidos (Para apellidos compuestos como "Caballero Sanchez")
        const regex = /^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$/;
        return regex.test(lastName) && lastName.length >= 2 && lastName.length <= 40;
    },

    // Comprobador contra la lista negra de palabras
    checkProfanity: function (text) {
        const lowerText = text.toLowerCase();
        const hasProfanity = this.profanityList.some(word => lowerText.includes(word));
        if (hasProfanity && typeof DebugPrint === 'function') {
            DebugPrint("¡ADVERTENCIA! Se detectó lenguaje inapropiado en el texto: " + text);
        }
        return hasProfanity;
    },

    // Función principal para ser llamada desde app.js para evaluar todo el formulario
    validateForm: function (firstname, lastname, dob, gender, nationality) {
        if (typeof DebugPrint === 'function') DebugPrint("Iniciando validación global del formulario...");

        // "!nationality" a la comprobación
        if (!firstname || !lastname || !dob || !gender || !nationality) {
            return { valid: false, msg: "Todos los campos (incluyendo nacionalidad) son obligatorios." };
        }
        if (!this.validateName(firstname)) {
            return { valid: false, msg: "El nombre no es válido (solo letras, sin espacios)." };
        }
        if (!this.validateLastName(lastname)) {
            return { valid: false, msg: "El apellido no es válido (solo letras y espacios)." };
        }
        if (this.checkProfanity(firstname) || this.checkProfanity(lastname)) {
            return { valid: false, msg: "Se han detectado palabras no permitidas." };
        }

        if (typeof DebugPrint === 'function') DebugPrint("Validación del formulario completada con éxito.");
        return { valid: true };
    }
};