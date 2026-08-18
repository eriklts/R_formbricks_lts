# Funções de transformação e limpeza de dados

limpar_texto <- function(texto, tipo = "padrao") {
  if (is.null(texto) || !nzchar(as.character(texto))) return("")
  
  s <- as.character(texto)
  
  s <- gsub("_", " ", s)
  
  s <- gsub("[^\\p{L}0-9 ]+", "", s, perl = TRUE)
  
  s <- trimws(gsub("\\s+", " ", s))
  
  s <- tools::toTitleCase(tolower(s))
  
  if (nchar(s) == 0) return("Sem definição")
  s
}

limpar_setor <- function(setor) {
  s <- limpar_texto(setor)
  if (s == "Sem definição") return("Sem setor")
  s
}

desambiguar_labels <- function(labels) {
  if (!any(duplicated(labels))) return(labels)
  
  result <- labels
  groups <- split(seq_along(labels), labels)
  
  for (g in groups) {
    if (length(g) > 1) {
      for (k in seq_along(g)) {
        result[g[k]] <- paste0(labels[g[k]], " (", k, ")")
      }
    }
  }
  result
}

limpar_resposta <- function(resposta) {
  trimws(as.character(resposta))
}

normalizar_e_valorizar_resposta <- function(resposta_limpa) {
  resposta_norm <- unname(normalizar_resposta[resposta_limpa])
  valor <- unname(valor_resposta[resposta_norm])
  list(normalizada = resposta_norm, valor = valor)
}

extrair_setor_url <- function(url) {
  if (is.na(url) || url == "") return("Sem setor")
  
  m <- regmatches(
    url,
    regexpr("(?<=[?&]setor=)[^&]+", url, perl = TRUE)
  )
  
  if (length(m) == 0) return("Sem setor")
  
  m <- gsub("\\+", " ", m)
  setor_limpo <- utils::URLdecode(m)
  limpar_setor(setor_limpo)
}
