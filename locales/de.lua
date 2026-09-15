-- ==========================================
-- 🛠️ DEBUG-FUNKTION[cite: 1]
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Wir initialisieren die Texte für die spanische Sprache innerhalb der globalen lokalen Tabelle
Locales['de'] = {
    ['ui_continue_story_title'] = 'GESCHICHTE FORTSETZEN',
    ['ui_continue_story_desc'] = 'Sofortiges Laden deiner letzten Sitzung • Status, Standort und Vermögen bereit, um das RP ohne Wartezeit fortzusetzen.',
    ['ui_characters_title'] = 'CHARAKTERE',
    ['ui_characters_desc'] = 'Auswahl mehrerer Identitäten • Erstelle neue Bürger, überprüfe Berufe, Bankkonten und verwalte deine Akten.',
    ['ui_options_title'] = 'OPTIONEN',
    ['ui_options_desc'] = 'Systemsteuerung • Passe Grafikeinstellungen, Lautstärke, Soundeffekte und Client-Präferenzen an.',
    ['ui_continue_button'] = 'GESCHICHTE FORTSETZEN',
    ['ui_characters_button'] = 'CHARAKTERE',
    ['ui_options_button'] = 'OPTIONEN',
    ['ui_move'] = 'BEWEGEN',
    ['ui_select'] = 'AUSWÄHLEN',
    ['ui_exit'] = 'VERLASSEN',
    ['ui_select_character'] = 'CHARAKTER/SLOT AUSWÄHLEN',
    ['ui_profile'] = 'PROFIL',
    ['ui_online'] = 'ONLINE',
    ['ui_identity'] = 'IDENTITÄT',
    ['ui_economy_contact'] = 'WIRTSCHAFT & KONTAKT',
    ['ui_affiliations'] = 'ZUGEHÖRIGKEITEN',
    ['ui_skills'] = 'FÄHIGKEITEN',
    ['ui_activity'] = 'AKTIVITÄT',
    ['ui_playtime'] = 'Spielzeit:',
    ['ui_last_seen'] = 'Zuletzt gesehen:',
    ['ui_new_character'] = 'NEUER CHARAKTER',
    ['ui_selected_character'] = 'AUSGEWÄHLTER CHARAKTER',
    ['ui_create'] = 'ERSTELLEN',
    ['ui_create_character_title'] = 'CHARAKTER ERSTELLEN',
    ['ui_firstname'] = 'VORNAME',
    ['ui_lastname'] = 'NACHNAME',
    ['ui_birthdate'] = 'GEBURTSDATUM',
    ['ui_gender'] = 'GESCHLECHT',
    ['ui_male'] = 'MÄNNLICH',
    ['ui_female'] = 'WEIBLICH',
    ['ui_placeholder_firstname'] = 'Bsp: John',
    ['ui_placeholder_lastname'] = 'Bsp: Doe Smith',
    ['ui_play'] = 'SPIELEN',
    ['ui_delete'] = 'LÖSCHEN',
    ['ui_cancel'] = 'ABBRECHEN',
    ['ui_confirm'] = 'BESTÄTIGEN',
    ['ui_empty_slot'] = 'LEERER SLOT',
    ['ui_delete_title'] = 'CHARAKTER LÖSCHEN?',
    ['ui_delete_warning'] = 'Diese Aktion kann nicht rückgängig gemacht werden.',
    ['ui_delete_confirm_btn'] = 'JA, LÖSCHEN',
    ['char_deleted'] = 'Charakter aus der Datenbank gelöscht.',
    ['invalid_name'] = 'Der Vor- oder Nachname enthält ungültige Zeichen.',
    ['profanity_detected'] = 'Es wurde ein unzulässiges Wort in deinem Namen gefunden.',
    ['loading_data'] = 'Spielerdaten werden geladen...',
    ['ui_visible'] = 'SICHTBAR',
    ['ui_hidden'] = 'VERSTECKT',
    ['ui_hide_locked_preview'] = 'Vorschau des Auswahlmenüs',
    ['ui_hide_locked_switch'] = 'Leere Slots ausblenden',
    ['ui_hide_locked_hint'] = 'Leere Slots werden aus dem Auswahlmenü ausgeblendet und du siehst nur deine erstellten Charaktere.',
    ['ui_hide_locked_on'] = 'Nur erstellte Charaktere',
    ['ui_hide_locked_off'] = 'Leere Slots außerhalb des Auswahlmenüs',
    ['ui_sound_volume'] = 'Interface-Lautstärke',
    ['ui_sound_test'] = 'Ton testen',
    ['ui_sound_off'] = 'Sounds deaktiviert',
    ['ui_sound_level'] = 'Lautstärke bei %s%'
}

DebugPrint("Deutsches Wörterbuch ('de') erfolgreich registriert.")
