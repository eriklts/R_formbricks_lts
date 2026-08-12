limpar_headline_formbricks <- function(headline) {
  if (
    is.null(headline) ||
    length(headline) == 0 ||
    is.na(headline) ||
    !nzchar(headline)
  ) {
    return(character(0))
  }

  texto <- as.character(headline)

  texto <- gsub("(?i)<br\\s*/?>", "\n", texto, perl = TRUE)
  texto <- gsub("(?i)</p\\s*>", "\n", texto, perl = TRUE)
  texto <- gsub("<[^>]+>", "", texto, perl = TRUE)
  texto <- gsub("&nbsp;", " ", texto, fixed = TRUE)
  texto <- gsub("\u00A0", " ", texto, fixed = TRUE)
  texto <- gsub("&amp;", "&", texto, fixed = TRUE)
  texto <- gsub("&quot;", '"', texto, fixed = TRUE)
  texto <- gsub("&#39;", "'", texto, fixed = TRUE)

  linhas <- unlist(strsplit(texto, "\n", fixed = TRUE))
  linhas <- trimws(linhas)
  linhas <- gsub("[[:space:]]+", " ", linhas)

  linhas[!is.na(linhas) & nzchar(linhas)]
}

obter_headline <- function(elemento) {
  if (is.null(elemento$headline)) return(NA_character_)

  headline <- elemento$headline

  if (is.character(headline) && length(headline) == 1) return(headline)

  if (is.list(headline) && !is.null(headline$default)) {
    return(as.character(headline$default))
  }

  if (is.list(headline) && length(headline) > 0) {
    return(as.character(headline[[1]]))
  }

  NA_character_
}

montar_mapa_blocos_json <- function(blocks_json, survey_id) {
  if (is.null(blocks_json) || length(blocks_json) == 0 || is.na(blocks_json) || !nzchar(blocks_json)) {
    return(data.frame())
  }

  blocos <- tryCatch(
    jsonlite::fromJSON(blocks_json, simplifyVector = FALSE),
    error = function(e) {
      warning(paste("Erro ao interpretar blocks da Survey", survey_id, ":", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(blocos) || length(blocos) == 0) return(data.frame())

  if (is.character(blocos)) blocos <- as.list(blocos)
  if (is.list(blocos) && !is.null(blocos$id) && !is.null(blocos$elements)) blocos <- list(blocos)

  blocos <- lapply(blocos, function(x) {
    if (is.character(x) && length(x) == 1) {
      return(tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE), error = function(e) NULL))
    }
    x
  })

  blocos <- Filter(function(x) is.list(x) && !is.null(x$elements), blocos)
  if (length(blocos) == 0) return(data.frame())

  resultado <- list()
  indice <- 1

  for (bloco_numero in seq_along(blocos)) {
    bloco <- blocos[[bloco_numero]]
    if (is.null(bloco$elements) || length(bloco$elements) == 0) next

    elementos <- bloco$elements

    bloco_nome_original <- if (!is.null(bloco$name)) as.character(bloco$name) else paste("Bloco", bloco_numero)
    primeiro_elemento <- elementos[[1]]
    primeiro_headline <- obter_headline(primeiro_elemento)
    primeiras_linhas <- limpar_headline_formbricks(primeiro_headline)
    bloco_nome <- bloco_nome_original

    if (length(primeiras_linhas) == 0) next

    bloco_nome <- trimws(primeiras_linhas[1])
    if (is.na(bloco_nome) || bloco_nome == "" || grepl("^(Block|Bloco)\\s*[0-9]+$", bloco_nome, ignore.case = TRUE)) next

    for (pergunta_numero in seq_along(elementos)) {
      elemento <- elementos[[pergunta_numero]]
      if (is.null(elemento$id)) next

      pergunta_id <- as.character(elemento$id)
      headline <- obter_headline(elemento)
      linhas <- limpar_headline_formbricks(headline)

      if (pergunta_numero == 1 && length(linhas) >= 2 && identical(trimws(linhas[1]), trimws(bloco_nome))) {
        linhas <- linhas[-1]
      }

      pergunta_texto <- paste(linhas, collapse = " ")

      bloco_hash <- if (!is.null(bloco$id)) as.character(bloco$id) else NA_character_
      tipo_pergunta <- if (!is.null(elemento$type)) as.character(elemento$type) else NA_character_

      resultado[[indice]] <- data.frame(
        survey_id = as.character(survey_id),
        bloco_numero = bloco_numero,
        bloco_hash = bloco_hash,
        bloco = bloco_nome,
        bloco_nome_original = bloco_nome_original,
        pergunta_numero = pergunta_numero,
        pergunta_id = pergunta_id,
        pergunta = pergunta_texto,
        tipo_pergunta = tipo_pergunta,
        stringsAsFactors = FALSE
      )

      indice <- indice + 1
    }
  }

  if (length(resultado) == 0) return(data.frame())
  dplyr::bind_rows(resultado)
}

montar_mapa_perguntas <- function(
  surveys_db
) {

  if (
    is.null(surveys_db) ||
    nrow(surveys_db) == 0
  ) {
    return(data.frame())
  }


  partes <- lapply(

    seq_len(
      nrow(surveys_db)
    ),

    function(i) {

      montar_mapa_blocos_json(

        blocks_json =
          surveys_db$blocks_json[[i]],

        survey_id =
          surveys_db$survey_id[[i]]
      )
    }
  )


  resultado <- dplyr::bind_rows(
    partes
  )


  if (nrow(resultado) == 0) {
    return(data.frame())
  }


  resultado |>

    dplyr::distinct(
      survey_id,
      pergunta_id,
      .keep_all = TRUE
    ) |>

    dplyr::arrange(
      survey_id,
      bloco_numero,
      pergunta_numero
    )
}

vincular_respostas <- function(json_data, survey_id, mapa_perguntas) {
  respostas <- extrair_respostas_por_hash(json_data)

  if (nrow(respostas) == 0 || nrow(mapa_perguntas) == 0) return(data.frame())

  survey_id_atual <- as.character(survey_id)
  mapa_survey <- mapa_perguntas |> dplyr::filter(.data$survey_id == survey_id_atual)
  if (nrow(mapa_survey) == 0) return(data.frame())

  resultado <- respostas |>
    dplyr::inner_join(mapa_survey, by = "pergunta_id") |>
    dplyr::mutate(
      resposta_limpa = trimws(as.character(resposta)),
      resposta_normalizada = unname(normalizar_resposta[resposta_limpa]),
      valor = unname(valor_resposta[resposta_normalizada])
    ) |>
    dplyr::arrange(bloco_numero, pergunta_numero)

  resultado
}