# Funções auxiliares para exportação em PDF
# Gráficos recriados com ggplot2 — sem kaleido, sem plotly

# Tema base compartilhado por todos os gráficos do PDF
tema_pdf <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title        = ggplot2::element_blank(),   # título gerenciado pelo Rmd
      plot.background   = ggplot2::element_rect(fill = "white", color = NA),
      panel.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor  = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(color = "#bbbbbb", linewidth = 0.6),
      axis.text.x       = ggplot2::element_text(size = 11, color = "#333333"),
      axis.text.y       = ggplot2::element_text(size = 11, color = "#333333"),
      axis.title.x      = ggplot2::element_blank(),
      axis.title.y      = ggplot2::element_text(size = 11, color = "#555555"),
      plot.margin       = ggplot2::margin(t = 4, r = 8, b = 4, l = 8)
    )
}

# ----- Gráfico 1: Distribuição global das respostas ---------------------------------

ggplot_distribuicao_respostas <- function(df_respostas_quantitativas) {
  if (is.null(df_respostas_quantitativas) || nrow(df_respostas_quantitativas) == 0) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0.5, y = 0.5,
                          label = "Sem dados disponíveis",
                          size = 5, color = "#888888") +
        ggplot2::theme_void()
    )
  }

  ordem_niveis <- names(valor_resposta)

  dados <- df_respostas_quantitativas |>
    dplyr::mutate(
      resposta_norm = dplyr::coalesce(
        unname(normalizar_resposta[resposta]),
        resposta
      )
    ) |>
    dplyr::count(resposta_norm, name = "quantidade") |>
    dplyr::mutate(
      resposta_norm = factor(resposta_norm, levels = ordem_niveis),
      pct           = round(100 * quantidade / sum(quantidade), 1),
      rotulo        = paste0(pct, "%\n(", quantidade, ")")
    ) |>
    dplyr::arrange(resposta_norm)

  ggplot2::ggplot(
    dados,
    ggplot2::aes(x = resposta_norm, y = quantidade, fill = resposta_norm)
  ) +
    ggplot2::geom_col(width = 0.65, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(label = rotulo),
      vjust = -0.3, size = 3.8, color = "#333333", lineheight = 0.9
    ) +
    ggplot2::scale_fill_manual(values = cores_resposta) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
    ggplot2::labs(y = "Quantidade") +
    tema_pdf()
}

# ----- Gráfico 2: Respostas ao longo do tempo (linha) --------------------------------

ggplot_respostas_tempo <- function(df_filtrado) {
  if (is.null(df_filtrado) || nrow(df_filtrado) == 0) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0.5, y = 0.5,
                          label = "Sem dados disponíveis",
                          size = 5, color = "#888888") +
        ggplot2::theme_void()
    )
  }

  dados <- df_filtrado |>
    dplyr::mutate(data_dia = as.Date(created_at)) |>
    dplyr::distinct(id, data_dia) |>
    dplyr::count(data_dia, name = "quantidade") |>
    dplyr::arrange(data_dia)

  # Intervalo dinâmico de datas para não sobrecarregar o eixo X
  n_dias <- as.numeric(max(dados$data_dia) - min(dados$data_dia))
  intervalo <- dplyr::case_when(
    n_dias <= 14  ~ "1 day",
    n_dias <= 60  ~ "1 week",
    n_dias <= 180 ~ "2 weeks",
    TRUE          ~ "1 month"
  )

  ggplot2::ggplot(dados, ggplot2::aes(x = data_dia, y = quantidade)) +
    ggplot2::geom_line(color = "#1976D2", linewidth = 1.1) +
    ggplot2::geom_point(color = "#1976D2", size = 3, fill = "white",
                        shape = 21, stroke = 1.5) +
    ggplot2::scale_x_date(
      date_labels = "%d/%m/%Y",
      date_breaks = intervalo
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0.05, 0.15))
    ) +
    ggplot2::labs(y = "Qtd. de respostas") +
    tema_pdf() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 35, hjust = 1, size = 10)
    )
}

# ----- Gráfico 3: Percentual por pergunta (um gráfico por pergunta) ------------------
# O título da pergunta é renderizado pelo Rmd; o gráfico foca nos dados.

ggplot_percentual_pergunta <- function(df_estruturado, pergunta_id_local, bloco_local) {
  dados <- df_estruturado |>
    dplyr::filter(
      bloco       == bloco_local,
      pergunta_id == pergunta_id_local,
      !is.na(resposta_normalizada)
    )

  if (nrow(dados) == 0) return(NULL)

  # Garante que todas as 5 categorias apareçam, mesmo com zero respostas
  escala <- data.frame(
    resposta_normalizada = names(valor_resposta),
    ordem                = seq_along(valor_resposta),
    stringsAsFactors     = FALSE
  )

  total <- nrow(dados)

  dados_pct <- dados |>
    dplyr::count(resposta_normalizada, name = "quantidade") |>
    dplyr::right_join(escala, by = "resposta_normalizada") |>
    dplyr::mutate(
      quantidade           = dplyr::coalesce(quantidade, 0L),
      percentual           = round(100 * quantidade / total, 1),
      rotulo               = dplyr::if_else(
        quantidade > 0,
        paste0(percentual, "%\n(", quantidade, ")"),
        ""
      ),
      resposta_normalizada = factor(resposta_normalizada, levels = names(valor_resposta))
    ) |>
    dplyr::arrange(ordem)

  ggplot2::ggplot(
    dados_pct,
    ggplot2::aes(x = resposta_normalizada, y = quantidade, fill = resposta_normalizada)
  ) +
    ggplot2::geom_col(width = 0.62, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(label = rotulo),
      vjust       = -0.25,
      size        = 3.5,
      color       = "#333333",
      lineheight  = 0.88
    ) +
    ggplot2::scale_fill_manual(values = cores_resposta) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.22))
    ) +
    ggplot2::labs(y = "Quantidade") +
    tema_pdf()
}

# ----- Função principal: monta os parâmetros e chama rmarkdown::render ---------------

gerar_relatorio_pdf <- function(
  arquivo_saida,
  nome_pesquisa,
  total_respostas,
  media_geral,
  nota_pesquisa,
  df_filtrado,
  df_respostas_quantitativas,
  df_respostas_estruturadas,
  df_respostas_descritivas,
  filtro_finished,
  filtro_notFinished
) {
  params <- list(
    nome_pesquisa              = nome_pesquisa,
    total_respostas            = total_respostas,
    media_geral                = media_geral,
    nota_pesquisa              = nota_pesquisa,
    df_filtrado                = df_filtrado,
    df_respostas_quantitativas = df_respostas_quantitativas,
    df_respostas_estruturadas  = df_respostas_estruturadas,
    df_respostas_descritivas   = df_respostas_descritivas,
    filtro_finished            = filtro_finished,
    filtro_notFinished         = filtro_notFinished,
    data_exportacao            = format(Sys.time(), "%d/%m/%Y %H:%M")
  )

  rmd_path <- file.path(getwd(), "scripts", "relatorio_pdf.Rmd")

  rmarkdown::render(
    input       = rmd_path,
    output_file = arquivo_saida,
    params      = params,
    envir       = new.env(parent = globalenv()),
    quiet       = TRUE
  )
}
