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

  ordem_niveis <- names(valor_resposta)
  total <- nrow(df)

  dados <- df |>
    mutate(resposta_norm = coalesce(unname(normalizar_resposta[resposta]), resposta)) |>
    count(resposta_norm, name = "quantidade") |>
    mutate(
      resposta_norm = factor(resposta_norm, levels = ordem_niveis),
      pct           = round(100 * quantidade / total, 1)
    ) |>
    arrange(resposta_norm)

  plot_ly(
    data = dados,
    x = ~resposta_norm,
    y = ~quantidade,
    type = "bar",
    text = ~paste0(pct, "%"),
    textposition = "outside",
    customdata = ~paste0(quantidade, " respostas (", pct, "%)"),
    hovertemplate = "%{x}<br>%{customdata}<extra></extra>",
    marker = list(color = unname(cores_resposta[as.character(dados$resposta_norm)]))
  ) |> layout(
    xaxis = list(
      title = "Resposta",
      categoryorder = "array",
      categoryarray = ordem_niveis
    ),
    yaxis = list(
      title = "Quantidade",
      gridcolor = "#bbbbbb",
      gridwidth = 1
    ),
    uniformtext = list(minsize = 10, mode = "show")
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
      yaxis = list(title = "Quantidade de links respondidos"),
      annotations = list(
        list(
          text = "\u2191",   # seta para cima ↑
          x = 1,
          y = 1,
          xref = "paper",
          yref = "paper",
          xanchor = "right",
          yanchor = "top",
          showarrow = FALSE,
          font = list(size = 28, color = "#333333")
        )
      )
    )
}

renderizar_grafico_media <- function(df) {
  if (nrow(df) == 0) return(NULL)
  dados <- df |>
    mutate(valor = unname(valor_resposta[resposta])) |>
    group_by(setor) |>
    summarise(media = round(mean(valor, na.rm = TRUE), 2), .groups = "drop") |>
    arrange(desc(media))
  
  plot_ly(data = dados, x = ~setor, y = ~media, type = "bar") |>
    layout(
      xaxis = list(title = "Setor"),
      yaxis = list(title = "Média de respostas", range = c(0, 10)),
      annotations = list(
        list(
          text = "\u2191",
          x = 1,
          y = 1,
          xref = "paper",
          yref = "paper",
          xanchor = "right",
          yanchor = "top",
          showarrow = FALSE,
          font = list(size = 28, color = "#333333")
        )
      )
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
  
  escala <- data.frame(
    resposta_normalizada = names(valor_resposta),
    ordem = seq_along(valor_resposta),
    stringsAsFactors = FALSE
  )

  total <- nrow(dados)

  ordem_niveis <- names(valor_resposta)

  dados_pct <- dados |>
    count(resposta_normalizada, name = "quantidade") |>
    right_join(escala, by = "resposta_normalizada") |>
    mutate(
      quantidade           = coalesce(quantidade, 0L),
      percentual           = round(100 * quantidade / total, 1),
      resposta_normalizada = factor(resposta_normalizada, levels = ordem_niveis)
    ) |>
    arrange(resposta_normalizada)

  plot_ly(
    data = dados_pct,
    x = ~resposta_normalizada,
    y = ~quantidade,
    text = ~if_else(quantidade > 0, paste0(percentual, "%"), ""),
    type = "bar",
    textposition = "outside",
    marker = list(color = unname(cores_resposta[as.character(dados_pct$resposta_normalizada)])),
    customdata = ~paste0(quantidade, " respostas (", percentual, "%)"),
    hovertemplate = "%{x}<br>%{customdata}<extra></extra>"
  ) |> layout(
    xaxis = list(
      title = "Resposta",
      categoryorder = "array",
      categoryarray = ordem_niveis
    ),
    yaxis = list(
      title = "Quantidade",
      gridcolor = "#bbbbbb",
      gridwidth = 1
    ),
    uniformtext = list(minsize = 10, mode = "show")
  )
}