-- ==========================================
-- 🛠️ DEBUG FUNCTION[cite: 1]
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- We initialize the texts for the Spanish language within the global Local table
Locales['en'] = {
    ['ui_continue_story_title'] = 'CONTINUE YOUR STORY',
    ['ui_continue_story_desc'] = 'Immediate load of your last session • Status, location, and saved assets ready to resume roleplay without waiting.',
    ['ui_characters_title'] = 'CHARACTERS',
    ['ui_characters_desc'] = 'Multiple identity selector • Create new citizens, review professions, bank accounts, and manage your records.',
    ['ui_options_title'] = 'OPTIONS',
    ['ui_options_desc'] = 'System control panel • Customize graphics, audio volume, sound effects, and client preferences.',
    ['ui_continue_button'] = 'CONTINUE YOUR STORY',
    ['ui_characters_button'] = 'CHARACTERS',
    ['ui_options_button'] = 'OPTIONS',
    ['ui_move'] = 'MOVE',
    ['ui_select'] = 'SELECT',
    ['ui_exit'] = 'EXIT',
    ['ui_select_character'] = 'SELECT A CHARACTER/SLOT',
    ['ui_profile'] = 'PROFILE',
    ['ui_online'] = 'ONLINE',
    ['ui_identity'] = 'IDENTITY',
    ['ui_economy_contact'] = 'ECONOMY & CONTACT',
    ['ui_affiliations'] = 'AFFILIATIONS',
    ['ui_skills'] = 'SKILLS',
    ['ui_activity'] = 'ACTIVITY',
    ['ui_playtime'] = 'Playtime:',
    ['ui_last_seen'] = 'Last seen:',
    ['ui_new_character'] = 'NEW CHARACTER',
    ['ui_selected_character'] = 'SELECTED CHARACTER',
    ['ui_create'] = 'CREATE',
    ['ui_create_character_title'] = 'CREATE CHARACTER',
    ['ui_firstname'] = 'FIRST NAME',
    ['ui_lastname'] = 'LAST NAME',
    ['ui_birthdate'] = 'BIRTH DATE',
    ['ui_gender'] = 'GENDER',
    ['ui_male'] = 'MALE',
    ['ui_female'] = 'FEMALE',
    ['ui_placeholder_firstname'] = 'Ex: John',
    ['ui_placeholder_lastname'] = 'Ex: Doe Smith',
    ['ui_play'] = 'PLAY',
    ['ui_delete'] = 'DELETE',
    ['ui_cancel'] = 'CANCEL',
    ['ui_confirm'] = 'CONFIRM',
    ['ui_empty_slot'] = 'EMPTY SLOT',
    ['ui_delete_title'] = 'DELETE CHARACTER?',
    ['ui_delete_warning'] = 'This action cannot be undone.',
    ['ui_delete_confirm_btn'] = 'YES, DELETE',
    ['char_deleted'] = 'Character deleted from the database.',
    ['invalid_name'] = 'The first or last name contains invalid characters.',
    ['profanity_detected'] = 'A banned word has been detected in your name.',
    ['loading_data'] = 'Loading player information...',
    ['ui_visible'] = 'VISIBLE',
    ['ui_hidden'] = 'HIDDEN',
    ['ui_hide_locked_preview'] = 'Character selector preview',
    ['ui_hide_locked_switch'] = 'Hide empty slots',
    ['ui_hide_locked_hint'] = 'Empty slots will be hidden from the selector and you will only see your created characters.',
    ['ui_hide_locked_on'] = 'Only created characters',
    ['ui_hide_locked_off'] = 'Empty slots outside the selector',
    ['ui_sound_volume'] = 'Interface volume',
    ['ui_sound_test'] = 'Test sound',
    ['ui_sound_off'] = 'Sounds disabled',
    ['ui_sound_level'] = 'Volume at %s%'
}

DebugPrint("English dictionary ('en') registered successfully.")
