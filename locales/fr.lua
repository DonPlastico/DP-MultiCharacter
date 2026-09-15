-- ==========================================
-- 🛠️ FONCTION DE DÉBOGAGE[cite: 1]
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Nous initialisons les textes pour la langue espagnole au sein de la table locale globale
Locales['fr'] = {
    ['ui_continue_story_title'] = 'CONTINUEZ VOTRE HISTOIRE',
    ['ui_continue_story_desc'] = 'Chargement immédiat de votre dernière session • Statut, position et ressources sauvegardés prêts pour reprendre le RP sans attente.',
    ['ui_characters_title'] = 'PERSONNAGES',
    ['ui_characters_desc'] = 'Sélecteur d\'identités multiples • Créez de nouveaux citoyens, consultez les professions, comptes bancaires et gérez vos registres.',
    ['ui_options_title'] = 'OPTIONS',
    ['ui_options_desc'] = 'Panneau de contrôle du système • Personnalisez les graphismes, le volume audio, les effets sonores et les préférences du client.',
    ['ui_continue_button'] = 'CONTINUEZ VOTRE HISTOIRE',
    ['ui_characters_button'] = 'PERSONNAGES',
    ['ui_options_button'] = 'OPTIONS',
    ['ui_move'] = 'DÉPLACER',
    ['ui_select'] = 'SÉLECTIONNER',
    ['ui_exit'] = 'QUITTER',
    ['ui_select_character'] = 'SÉLECTIONNEZ UN PERSONNAGE/SLOT',
    ['ui_profile'] = 'PROFIL',
    ['ui_online'] = 'EN LIGNE',
    ['ui_identity'] = 'IDENTITÉ',
    ['ui_economy_contact'] = 'ÉCONOMIE ET CONTACT',
    ['ui_affiliations'] = 'AFFILIATIONS',
    ['ui_skills'] = 'COMPÉTENCES',
    ['ui_activity'] = 'ACTIVITÉ',
    ['ui_playtime'] = 'Temps de jeu :',
    ['ui_last_seen'] = 'Dernière visite :',
    ['ui_new_character'] = 'NOUVEAU PERSONNAGE',
    ['ui_selected_character'] = 'PERSONNAGE SÉLECTIONNÉ',
    ['ui_create'] = 'CRÉER',
    ['ui_create_character_title'] = 'CRÉER UN PERSONNAGE',
    ['ui_firstname'] = 'PRÉNOM',
    ['ui_lastname'] = 'NOM DE FAMILLE',
    ['ui_birthdate'] = 'DATE DE NAISSANCE',
    ['ui_gender'] = 'GENRE',
    ['ui_male'] = 'MASCULIN',
    ['ui_female'] = 'FÉMININ',
    ['ui_placeholder_firstname'] = 'Ex : John',
    ['ui_placeholder_lastname'] = 'Ex : Doe Smith',
    ['ui_play'] = 'JOUER',
    ['ui_delete'] = 'SUPPRIMER',
    ['ui_cancel'] = 'ANNULER',
    ['ui_confirm'] = 'CONFIRMER',
    ['ui_empty_slot'] = 'EMPLACEMENT VIDE',
    ['ui_delete_title'] = 'SUPPRIMER LE PERSONNAGE ?',
    ['ui_delete_warning'] = 'Cette action est irréversible.',
    ['ui_delete_confirm_btn'] = 'OUI, SUPPRIMER',
    ['char_deleted'] = 'Personnage supprimé de la base de données.',
    ['invalid_name'] = 'Le prénom ou le nom contient des caractères invalides.',
    ['profanity_detected'] = 'Un mot interdit a été détecté dans votre nom.',
    ['loading_data'] = 'Chargement des informations du joueur...',
    ['ui_visible'] = 'VISIBLE',
    ['ui_hidden'] = 'MASQUÉ',
    ['ui_hide_locked_preview'] = 'Aperçu du sélecteur',
    ['ui_hide_locked_switch'] = 'Masquer les emplacements vides',
    ['ui_hide_locked_hint'] = 'Les emplacements vides seront masqués du sélecteur et vous ne verrez que vos personnages créés.',
    ['ui_hide_locked_on'] = 'Seuls les personnages créés',
    ['ui_hide_locked_off'] = 'Emplacements vides hors sélecteur',
    ['ui_sound_volume'] = 'Volume de l\'interface',
    ['ui_sound_test'] = 'Tester le son',
    ['ui_sound_off'] = 'Sons désactivés',
    ['ui_sound_level'] = 'Volume à %s%'
}

DebugPrint("Dictionnaire français ('fr') enregistré avec succès.")