# Funções para renderização de gráficos

renderizar_grafico_setor <- function(df) {
  if (nrow(df) == 0) return(NULL)
  dados <- df |> 
    distinct(id, setor) |> 
    count(setor, name = "quantidade") |> 
    arrange(desc(quantidade))
  
  plot_ly(data = dados, x = ~setor, y = ~quantidade, type = "bar") |>
    layout(
      xaxis = list(title = "Setor"),
      yaxis = list(title = "Quantidade de links respondidos")
    )
}

renderizar_grafico_respostas <- function(df) {
  if (nrow(df) == 0) return(NULL)
  dados <- df |> 
    count(resposta, name = "quantidade") |> 
    arrange(desc(quantidade))
  
  plot_ly(
    data = dados,
    x = ~resposta,
    y = ~quantidade,
    type = "bar"
  ) |> layout(
    xaxis = list(title = "Resposta"),
    yaxis = list(title = "Quantidade")
  )
}

renderizar_grafico_tempo <- function(df) {
  if (nrow(df) == 0) return(NULL)
  dados <- df |>
    mutate(data = as.Date(created_at)) |>
    distinct(id, data) |>
    count(data, name = "quantidade") |>
    arrange(data)
  
  plot_ly(data = dados, x = ~data, y = ~quantidade, type = "scatter", mode = "lines+markers") |>
    layout(
      xaxis = list(title = "Data"),
      yaxis = list(title = "Quantidade de links respondidos")
    )
}

renderizar_grafico_media <- function(df) {
  if (nrow(df) == 0) return(NULL)
  dados <- df |>
    mutate(valor = unname(valor_resposta[resposta])) |>
    group_by(setor) |>
    summarise(media = mean(valor, na.rm = TRUE), .groups = "drop") |>
    arrange(desc(media))
  
  plot_ly(data = dados, x = ~setor, y = ~media, type = "bar") |>
    layout(
      xaxis = list(title = "Setor"),
      yaxis = list(title = "Média de respostas")
    )
}

renderizar_grafico_percentual <- function(df, pergunta_id_local, bloco_local) {
  dados <- df |>
    filter(
      bloco == bloco_local,
      pergunta_id == pergunta_id_local,
      !is.na(resposta_normalizada)
    )
  
  if (nrow(dados) == 0) return(NULL)
  
  # Cria escala com todas as respostas possíveis
  escala <- data.frame(
    resposta_normalizada = names(valor_resposta),
    ordem = seq_along(valor_resposta),
    stringsAsFactors = FALSE
  )
  
  dados_pct <- dados |>
    count(resposta_normalizada, name = "quantidade") |>
    right_join(escala, by = "resposta_normalizada") |>
    mutate(quantidade = coalesce(quantidade, 0L)) |>
    arrange(ordem)
  
  total <- sum(dados_pct$quantidade)
  if (total == 0) return(NULL)
  
  dados_pct <- dados_pct |>
    mutate(
      percentual = round(100 * quantidade / total, 1),
      texto = paste0(resposta_normalizada, "<br>", percentual, "%")
    )
  
  plot_ly(
    data = dados_pct,
    x = ~resposta_normalizada,
    y = ~quantidade,
    text = ~texto,
    type = "bar",
    textposition = "auto",
    hovertemplate = paste0(
      "%{x}<br>",
      "Quantidade: %{y}<br>",
      "Percentual: %{text}",
      "<extra></extra>"
    )
  ) |> layout(
    xaxis = list(title = "Resposta"),
    yaxis = list(title = "Quantidade")
  )
}
