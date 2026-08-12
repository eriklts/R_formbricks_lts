utils::globalVariables(
  c(
    # Dados e IDs
    "id", "created_at", "updated_at", "finished", "data", "meta_url",
    "setor", "respostas", "resposta", "resposta_original", "resposta_limpa",
    "resposta_normalizada", "pergunta", "pergunta_id", "pergunta_numero",
    "bloco", "bloco_numero", "bloco_hash", "bloco_nome_original",
    "survey_id", "quantidade", "media", "valor", "data",
    
    # Transformações
    "ordem", "percentual", "texto", "tipo_pergunta",
    
    # Agregações
    "n",
    
    # Conexão
    "con",
    
    # Constantes
    "valor_resposta", "normalizar_resposta", "PADRAO_BLOCO_GENERICO", "CONFIG_UI"
  )
)

