-- ==========================================
-- 🛠️ FUNÇÃO DE DEPURAÇÃO[cite: 1]
-- ==========================================
local function DebugPrint(msg)
    if Config and Config.Debug then
        print("^5[DP-MultiCharacter Debug] ^7" .. msg)
    end
end

-- Inicializamos os textos para o idioma espanhol dentro da tabela local global
Locales['pt'] = {
    ['ui_continue_story_title'] = 'CONTINUE SUA HISTÓRIA',
    ['ui_continue_story_desc'] = 'Carregamento imediato da sua última sessão • Status, localização e ativos salvos prontos para retomar o roleplay sem esperas.',
    ['ui_characters_title'] = 'PERSONAGENS',
    ['ui_characters_desc'] = 'Seletor de múltiplas identidades • Crie novos cidadãos, revise profissões, contas bancárias e gerencie seus registros.',
    ['ui_options_title'] = 'OPÇÕES',
    ['ui_options_desc'] = 'Painel de controle do sistema • Personalize os gráficos, volume do áudio, efeitos sonoros e preferências do cliente.',
    ['ui_continue_button'] = 'CONTINUE SUA HISTÓRIA',
    ['ui_characters_button'] = 'PERSONAGENS',
    ['ui_options_button'] = 'OPÇÕES',
    ['ui_move'] = 'MOVER',
    ['ui_select'] = 'SELECIONAR',
    ['ui_exit'] = 'SAIR',
    ['ui_select_character'] = 'SELECIONE UM PERSONAGEM/SLOT',
    ['ui_profile'] = 'PERFIL',
    ['ui_online'] = 'ONLINE',
    ['ui_identity'] = 'IDENTIDADE',
    ['ui_economy_contact'] = 'ECONOMIA E CONTATO',
    ['ui_affiliations'] = 'AFILIAÇÕES',
    ['ui_skills'] = 'HABILIDADES',
    ['ui_activity'] = 'ATIVIDADE',
    ['ui_playtime'] = 'Tempo de jogo:',
    ['ui_last_seen'] = 'Última visita:',
    ['ui_new_character'] = 'NOVO PERSONAGEM',
    ['ui_selected_character'] = 'PERSONAGEM SELECIONADO',
    ['ui_create'] = 'CRIAR',
    ['ui_create_character_title'] = 'CRIAR PERSONAGEM',
    ['ui_firstname'] = 'NOME',
    ['ui_lastname'] = 'SOBRENOME',
    ['ui_birthdate'] = 'DATA DE NASCIMENTO',
    ['ui_gender'] = 'GÊNERO',
    ['ui_male'] = 'MASCULINO',
    ['ui_female'] = 'FEMININO',
    ['ui_placeholder_firstname'] = 'Ex: John',
    ['ui_placeholder_lastname'] = 'Ex: Doe Silva',
    ['ui_play'] = 'JOGAR',
    ['ui_delete'] = 'EXCLUIR',
    ['ui_cancel'] = 'CANCELAR',
    ['ui_confirm'] = 'CONFIRMAR',
    ['ui_empty_slot'] = 'SLOT VAZIO',
    ['ui_delete_title'] = 'EXCLUIR PERSONAGEM?',
    ['ui_delete_warning'] = 'Esta ação não pode ser desfeita.',
    ['ui_delete_confirm_btn'] = 'SIM, EXCLUIR',
    ['char_deleted'] = 'Personagem excluído do banco de dados.',
    ['invalid_name'] = 'O nome ou sobrenome contém caracteres inválidos.',
    ['profanity_detected'] = 'Uma palavra não permitida foi detectada em seu nome.',
    ['loading_data'] = 'Carregando informações do jogador...'
}

DebugPrint("Dicionário português ('pt') registrado com sucesso.")
