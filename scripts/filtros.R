# Funções para gerenciamento de filtros e inputs

atualizar_filtro_setor <- function(session, raw_setores, selecionado_atual) {
  display <- sapply(raw_setores, limpar_setor, USE.NAMES = FALSE)
  display <- desambiguar_labels(display)
  
  choices <- setNames(as.character(raw_setores), display)
  selecionado <- intersect(selecionado_atual, raw_setores)
  
  updateSelectizeInput(
    session,
    "filtro_setor",
    choices = choices,
    selected = selecionado,
    server = FALSE
  )
}

atualizar_filtro_survey <- function(session, surveys, selecionado_atual) {
  if (nrow(surveys) == 0) {
    updateSelectInput(session, "filtro_survey", choices = character(0), selected = character(0))
    return(NULL)
  }
  
  survey_choices <- c(
    "Todas as pesquisas" = "__TODAS__",
    setNames(as.character(surveys$survey_id), surveys$survey_name)
  )
  
  if (is.null(selecionado_atual) || !(selecionado_atual %in% c("__TODAS__", as.character(surveys$survey_id)))) {
    selecionado_atual <- as.character(surveys$survey_id[1])
  }
  
  updateSelectInput(
    session,
    "filtro_survey",
    choices = survey_choices,
    selected = selecionado_atual
  )
  
  invisible(NULL)
}

atualizar_filtro_bloco <- function(session, blocos, selecionado_atual) {
  if (is.null(selecionado_atual) || length(selecionado_atual) == 0 || !(selecionado_atual %in% blocos)) {
    selecionado_atual <- blocos[1]
  }
  
  updateSelectInput(
    session,
    "filtro_bloco",
    choices = blocos,
    selected = selecionado_atual
  )
}

atualizar_filtro_pergunta <- function(session, perguntas, selecionado_atual) {
  opcoes <- c(
    "Todas as perguntas" = "__TODAS__",
    setNames(perguntas$pergunta_id, perguntas$pergunta)
  )
  
  if (is.null(selecionado_atual) || length(selecionado_atual) == 0 || !(selecionado_atual %in% unname(opcoes))) {
    selecionado_atual <- "__TODAS__"
  }
  
  updateSelectizeInput(
    session,
    "filtro_pergunta",
    choices = opcoes,
    selected = selecionado_atual,
    server = FALSE
  )
}

obter_blocos_unicos <- function(df) {
  df |>
    filter(
      !is.na(bloco),
      bloco != "",
      !grepl(PADRAO_BLOCO_GENERICO, bloco, ignore.case = TRUE)
    ) |>
    distinct(bloco_numero, bloco) |>
    arrange(bloco_numero) |>
    pull(bloco) |>
    unique()
}

obter_perguntas_bloco <- function(df, bloco_nome) {
  df |>
    filter(bloco == bloco_nome) |>
    distinct(pergunta_numero, pergunta_id, pergunta) |>
    arrange(pergunta_numero)
}
