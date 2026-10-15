# Funções auxiliares para reativas

processar_respostas_longas <- function(df, respostas_lista) {
  n_respostas <- lengths(respostas_lista)
  tem_resposta <- n_respostas > 0
  
  if (!any(tem_resposta)) return(data.frame())
  
  df_com_resposta <- df[tem_resposta, ]
  n_respostas_filtrado <- n_respostas[tem_resposta]
  
  data.frame(
    id = rep(df_com_resposta$id, n_respostas_filtrado),
    created_at = rep(df_com_resposta$created_at, n_respostas_filtrado),
    setor = rep(df_com_resposta$setor, n_respostas_filtrado),
    resposta = unlist(respostas_lista[tem_resposta], use.names = FALSE),
    stringsAsFactors = FALSE
  ) |>
    mutate(
      resposta_original = resposta,
      resposta_limpa = limpar_resposta(resposta),
      resposta_normalizada = unname(normalizar_resposta[resposta_limpa])
    )
}

estruturar_respostas <- function(df_filtrado, mapa_perguntas) {
  if (nrow(df_filtrado) == 0 || nrow(mapa_perguntas) == 0) {
    return(data.frame())
  }
  
  partes <- lapply(
    seq_len(nrow(df_filtrado)),
    function(i) {
      vinculadas <- vincular_respostas(
        json_data = df_filtrado$data[[i]],
        survey_id = df_filtrado$survey_id[[i]],
        mapa_perguntas = mapa_perguntas
      )
      
      if (nrow(vinculadas) == 0) return(NULL)
      
      vinculadas |>
        mutate(
          id = df_filtrado$id[[i]],
          created_at = df_filtrado$created_at[[i]],
          updated_at = df_filtrado$updated_at[[i]],
          setor = df_filtrado$setor[[i]],
          finished = df_filtrado$finished[[i]]
        ) |>
        select(
          id, survey_id, created_at, updated_at, setor, finished,
          bloco_numero, bloco_hash, bloco, bloco_nome_original,
          pergunta_numero, pergunta_id, pergunta, tipo_pergunta,
          resposta, resposta_limpa, resposta_normalizada, valor
        )
    }
  )
  
  resultado <- bind_rows(partes)
  
  if (nrow(resultado) == 0) return(data.frame())
  
  resultado |> arrange(bloco_numero, pergunta_numero, created_at)
}

filtrar_por_survey <- function(df, survey_id_selecionado) {
  if (is.null(survey_id_selecionado) || !nzchar(survey_id_selecionado) || survey_id_selecionado == "__TODAS__") {
    return(df)
  }
  df |> filter(as.character(survey_id) == survey_id_selecionado)
}

filtrar_por_setores <- function(df, setores_selecionados) {
  if (is.null(setores_selecionados) || length(setores_selecionados) == 0) {
    return(df)
  }
  df |> filter(setor %in% setores_selecionados)
}

atualizar_dados_incrementais <- function(dados_atuais, dados_novos) {
  if (nrow(dados_novos) == 0) return(dados_atuais)
  
  if (nrow(dados_atuais) > 0) {
    dados_atuais <- dados_atuais[!(dados_atuais$id %in% dados_novos$id), ]
    bind_rows(dados_atuais, dados_novos)
  } else {
    dados_novos
  }
}

calcular_media_geral <- function(df_respostas_quantitativas) {
  if (nrow(df_respostas_quantitativas) == 0) return("-")
  
  valores <- unname(valor_resposta[df_respostas_quantitativas$resposta])
  paste0(round(mean(valores, na.rm = TRUE), 2), " / 10")
}

# ---------------------------------------------------------------------------
# calcular_nota_pesquisa — converte avaliação por estrelas (1–5) em nota 0–10
# ---------------------------------------------------------------------------

calcular_nota_pesquisa <- function(df_respostas_rating) {
  # Conversão: nota = (média_estrelas - 1) / 4 * 10
  # 1★ → 0.0  |  3★ → 5.0  |  5★ → 10.0
  if (is.null(df_respostas_rating) || nrow(df_respostas_rating) == 0) return("-")

  col <- if ("valor_rating" %in% names(df_respostas_rating)) "valor_rating" else "resposta"
  valores <- suppressWarnings(as.numeric(df_respostas_rating[[col]]))
  valores <- valores[!is.na(valores)]

  if (length(valores) == 0) return("-")

  nota <- round((mean(valores) - 1) / 4 * 10, 1)
  paste0(nota, " / 10")
}

# ===== Respostas de avaliação (rating) =====

estruturar_respostas_rating <- function(df_filtrado, mapa_rating) {
  if (nrow(df_filtrado) == 0 || nrow(mapa_rating) == 0) {
    return(data.frame())
  }

  partes <- lapply(
    seq_len(nrow(df_filtrado)),
    function(i) {
      respostas_brutas <- extrair_respostas_por_hash(df_filtrado$data[[i]])
      if (nrow(respostas_brutas) == 0) return(NULL)

      survey_id_atual <- as.character(df_filtrado$survey_id[[i]])
      mapa_survey <- mapa_rating |> dplyr::filter(.data$survey_id == survey_id_atual)
      if (nrow(mapa_survey) == 0) return(NULL)

      resultado <- respostas_brutas |>
        dplyr::inner_join(mapa_survey, by = "pergunta_id") |>
        dplyr::mutate(
          valor_rating = suppressWarnings(as.numeric(resposta))
        ) |>
        dplyr::filter(!is.na(valor_rating))

      if (nrow(resultado) == 0) return(NULL)

      resultado |>
        dplyr::mutate(
          id         = df_filtrado$id[[i]],
          created_at = df_filtrado$created_at[[i]],
          setor      = df_filtrado$setor[[i]],
          finished   = df_filtrado$finished[[i]]
        )
    }
  )

  resultado <- dplyr::bind_rows(partes)
  if (nrow(resultado) == 0) return(data.frame())
  resultado |> dplyr::arrange(created_at)
}

# ===== Respostas descritivas (openText) =====

estruturar_respostas_descritivas <- function(df_filtrado, mapa_descritivas) {
  if (nrow(df_filtrado) == 0 || nrow(mapa_descritivas) == 0) {
    return(data.frame())
  }

  partes <- lapply(
    seq_len(nrow(df_filtrado)),
    function(i) {
      vinculadas <- vincular_respostas_descritivas(
        json_data      = df_filtrado$data[[i]],
        survey_id      = df_filtrado$survey_id[[i]],
        mapa_descritivas = mapa_descritivas
      )

      if (nrow(vinculadas) == 0) return(NULL)

      vinculadas |>
        mutate(
          id         = df_filtrado$id[[i]],
          created_at = df_filtrado$created_at[[i]],
          setor      = df_filtrado$setor[[i]],
          finished   = df_filtrado$finished[[i]]
        ) |>
        select(
          id, survey_id, created_at, setor, finished,
          bloco_numero, bloco, pergunta_numero, pergunta_id, pergunta, subheader, resposta
        )
    }
  )

  resultado <- bind_rows(partes)

  if (nrow(resultado) == 0) return(data.frame())

  resultado |> arrange(bloco_numero, pergunta_numero, created_at)
}
