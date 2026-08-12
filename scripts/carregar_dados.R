library(dplyr)
library(jsonlite)

valor_json_para_texto <- function(valor) {

  if (
    is.null(valor) ||
    length(valor) == 0
  ) {
    return(NA_character_)
  }

  if (is.atomic(valor)) {

    return(
      paste(
        as.character(valor),
        collapse = " | "
      )
    )
  }

  jsonlite::toJSON(
    valor,
    auto_unbox = TRUE
  )
}

extrair_respostas <- function(json_data) {

  tryCatch({

    dados <- jsonlite::fromJSON(
      json_data,
      simplifyVector = FALSE
    )

    if (
      !is.list(dados) ||
      length(dados) == 0
    ) {
      return(character(0))
    }

    respostas <- vapply(
      dados,
      valor_json_para_texto,
      character(1)
    )

    respostas <- unname(respostas)

    respostas[
      !is.na(respostas) &
      trimws(respostas) != ""
    ]

  }, error = function(e) {

    character(0)
  })
}

extrair_respostas_por_hash <- function(json_data) {

  tryCatch({

    dados <- jsonlite::fromJSON(
      json_data,
      simplifyVector = FALSE
    )

    if (
      !is.list(dados) ||
      length(dados) == 0 ||
      is.null(names(dados))
    ) {
      return(data.frame())
    }

    respostas <- vapply(
      dados,
      valor_json_para_texto,
      character(1)
    )

    data.frame(

      pergunta_id = names(dados),

      resposta = unname(respostas),

      stringsAsFactors = FALSE
    ) |>

      dplyr::filter(
        !is.na(resposta),
        trimws(resposta) != ""
      )

  }, error = function(e) {

    data.frame()
  })
}

buscar_respostas_incrementais <- function(
  con,
  ultima_atualizacao
) {

  sql <- "
    SELECT
      r.id,
      r.\"surveyId\" AS survey_id,
      r.created_at,
      r.updated_at,
      r.finished,
      r.data::text AS data,
      r.meta ->> 'url' AS meta_url
    FROM \"Response\" r
    WHERE r.updated_at > $1
    ORDER BY r.updated_at ASC
  "

  DBI::dbGetQuery(
    con,
    sql,
    params = list(
      ultima_atualizacao
    )
  )
}

buscar_blocos_pesquisas <- function(con) {

  sql <- '
    SELECT
      s.id AS survey_id,
      s.name AS survey_name,
      s.updated_at AS survey_updated_at,
      to_jsonb(s.blocks)::text AS blocks_json
    FROM "Survey" s
    WHERE s.blocks IS NOT NULL
      AND cardinality(s.blocks) > 0
      AND EXISTS (
        SELECT 1
        FROM "Response" r
        WHERE r."surveyId" = s.id
      )
    ORDER BY s.id
  '

  DBI::dbGetQuery(
    con,
    sql
  )
}
