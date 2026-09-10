-- ==========================================
-- 🛠️ FUNZIONE DI DEBUG[cite: 1]
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Inizializziamo i testi per la lingua spagnola all'interno della tabella locale globale
Locales['it'] = {
    ['ui_continue_story_title'] = 'CONTINUA LA TUA STORIA',
    ['ui_continue_story_desc'] = 'Caricamento immediato dell\'ultima sessione • Stato, posizione e risorse salvate pronte per riprendere il roleplay senza attese.',
    ['ui_characters_title'] = 'PERSONAGGI',
    ['ui_characters_desc'] = 'Selettore di identità multiple • Crea nuovi cittadini, controlla professioni, conti bancari e gestisci i tuoi registri.',
    ['ui_options_title'] = 'OPZIONI',
    ['ui_options_desc'] = 'Pannello di controllo del sistema • Personalizza parametri grafici, volume audio, effetti sonori e preferenze del client.',
    ['ui_continue_button'] = 'CONTINUA LA TUA STORIA',
    ['ui_characters_button'] = 'PERSONAGGI',
    ['ui_options_button'] = 'OPZIONI',
    ['ui_move'] = 'MUOVI',
    ['ui_select'] = 'SELEZIONA',
    ['ui_exit'] = 'ESCI',
    ['ui_select_character'] = 'SELEZIONA UN PERSONAGGIO/SLOT',
    ['ui_profile'] = 'PROFILO',
    ['ui_online'] = 'ONLINE',
    ['ui_identity'] = 'IDENTITÀ',
    ['ui_economy_contact'] = 'ECONOMIA E CONTATTI',
    ['ui_affiliations'] = 'AFFILIAZIONI',
    ['ui_skills'] = 'ABILITÀ',
    ['ui_activity'] = 'ATTIVITÀ',
    ['ui_playtime'] = 'Tempo di gioco:',
    ['ui_last_seen'] = 'Ultimo accesso:',
    ['ui_new_character'] = 'NUOVO PERSONAGGIO',
    ['ui_selected_character'] = 'PERSONAGGIO SELEZIONATO',
    ['ui_create'] = 'CREA',
    ['ui_create_character_title'] = 'CREA PERSONAGGIO',
    ['ui_firstname'] = 'NOME',
    ['ui_lastname'] = 'COGNOME',
    ['ui_birthdate'] = 'DATA DI NASCITA',
    ['ui_gender'] = 'GENERE',
    ['ui_male'] = 'MASCHIO',
    ['ui_female'] = 'FEMMINA',
    ['ui_placeholder_firstname'] = 'Es: John',
    ['ui_placeholder_lastname'] = 'Es: Doe Smith',
    ['ui_play'] = 'GIOCA',
    ['ui_delete'] = 'ELIMINA',
    ['ui_cancel'] = 'ANNULLA',
    ['ui_confirm'] = 'CONFERMA',
    ['ui_empty_slot'] = 'SLOT VUOTO',
    ['ui_delete_title'] = 'ELIMINARE PERSONAGGIO?',
    ['ui_delete_warning'] = 'Questa azione non può essere annullata.',
    ['ui_delete_confirm_btn'] = 'SÌ, ELIMINA',
    ['char_deleted'] = 'Personaggio eliminato dal database.',
    ['invalid_name'] = 'Il nome o il cognome contiene caratteri non validi.',
    ['profanity_detected'] = 'È stata rilevata una parola non consentita nel tuo nome.',
    ['loading_data'] = 'Caricamento informazioni giocatore...'
}

DebugPrint("Dizionario italiano ('it') registrato correttamente.")
