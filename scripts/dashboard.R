library(shiny)
library(dplyr)
library(plotly)
library(jsonlite)

ui <- fluidPage(
  titlePanel("Dashboard - Pesquisa de Clima Organizacional"),

  fluidRow(
    column(6, selectizeInput("filtro_setor", "Filtrar por setor (deixe vazio para ver todos):", choices = character(0), selected = character(0), multiple = TRUE)),
    column(6, selectInput("filtro_survey", "Selecione a pesquisa:", choices = character(0)))
  ),

  fluidRow(
    column(12, h4(textOutput("pesquisa_selecionada")))) ,

  fluidRow(
    column(4, wellPanel(h3("Total de respostas"), h2(textOutput("total_respostas")))),
    column(4, wellPanel(h3("Setores"), h2(textOutput("total_setores")))),
    column(4, wellPanel(h3("Média geral"), h2(textOutput("media_geral"))))) ,

  hr(),
  h3("Respostas por setor"),
  plotlyOutput("grafico_setor"),
  hr(),
  h3("Distribuição das respostas"),
  plotlyOutput("grafico_respostas"),
  hr(),
  h3("Respostas ao longo do tempo"),
  plotlyOutput("grafico_tempo"),
  hr(),
  h3("Média por setor"),
  plotlyOutput("grafico_media"),
  hr(),
  h3("Últimas respostas"),
  tableOutput("tabela"),
  hr(),
  hr(),
  h3("Análise por bloco e pergunta"),

fluidRow(

  column(
    4,

    selectInput(
      "filtro_bloco",
      "Selecione o bloco:",
      choices = character(0)
    )
  ),

  column(
    8,

    selectizeInput(
      "filtro_pergunta",
      "Selecione a pergunta:",
      choices = character(0),
      multiple = FALSE
    )
  )
),

uiOutput(
  "blocos_perguntas_ui"
),
  hr(),
  textOutput("ultima_atualizacao")
)

server <- function(
  input,
  output,
  session
) {

  cache_dados <-
    reactiveVal(
      data.frame()
    )

  cache_mapa_perguntas <-
    reactiveVal(
      data.frame()
    )

  cache_survey_nomes <-
    reactiveVal(
      data.frame()
    )

  ultima_busca <-
    reactiveVal(
      as.POSIXct(
        "1970-01-01 00:00:00",
        tz = "UTC"
      )
    )

  observe({

  invalidateLater(
    10000,
    session
  )

  tryCatch({

    momento_ultima_busca <-
      isolate(
        ultima_busca()
      )

    novos <-
      buscar_respostas_incrementais(
        con = con,
        ultima_atualizacao =
          momento_ultima_busca
      )

    surveys_db <-
      buscar_blocos_pesquisas(
        con
      )

    novo_mapa <-
      montar_mapa_perguntas(
        surveys_db
      )

    cache_mapa_perguntas(
      novo_mapa
    )

    cache_survey_nomes(
      surveys_db
    )

    if (
      nrow(novos) == 0
    ) {
      return(
        invisible(NULL)
      )
    }

    novos$setor <-
      vapply(
        novos$meta_url,
        extrair_setor,
        character(1),
        USE.NAMES = FALSE
      )

    novos$respostas <-
      lapply(
        novos$data,
        extrair_respostas
      )

    atual <-
      isolate(
        cache_dados()
      )

    if (
      nrow(atual) > 0
    ) {

      atual <-
        atual[
          !(
            atual$id %in%
              novos$id
          ),
        ]

      atual <-
        bind_rows(
          atual,
          novos
        )

    } else {

      atual <- novos
    }

    atual <-
      atual |>

      arrange(
        created_at
      )

    cache_dados(
      atual
    )

    ultima_busca(

      max(
        novos$updated_at,
        na.rm = TRUE
      )
    )

  }, error = function(e) {

    warning(
      paste(
        "Erro na atualização automática:",
        conditionMessage(e)
      )
    )}
  )
})

  dados_tratados <- reactive({ cache_dados() })

  observeEvent(dados_tratados(), {
    df <- dados_tratados()
    setores <- if (nrow(df) == 0) character(0) else sort(unique(df$setor))
    atual <- isolate(input$filtro_setor)
    selecionado <- intersect(atual, setores)

    updateSelectizeInput(session, "filtro_setor", choices = setores, selected = selecionado, server = FALSE)
  })

  observeEvent(cache_survey_nomes(), {
    surveys <- cache_survey_nomes()
    if (nrow(surveys) == 0) {
      updateSelectInput(session, "filtro_survey", choices = character(0), selected = character(0))
      return()
    }

    survey_choices <- setNames(
      as.character(surveys$survey_id),
      surveys$survey_name
    )

    selecionado <- isolate(input$filtro_survey)
    if (is.null(selecionado) || !selecionado %in% as.character(surveys$survey_id)) {
      selecionado <- as.character(surveys$survey_id[1])
    }

    updateSelectInput(
      session,
      "filtro_survey",
      choices = survey_choices,
      selected = selecionado
    )
  })

  output$pesquisa_selecionada <- renderText({
    surveys <- cache_survey_nomes()
    selecionado <- input$filtro_survey
    if (is.null(selecionado) || length(selecionado) == 0 || nrow(surveys) == 0) {
      return("Pesquisa selecionada: nenhuma")
    }

    survey <- surveys |> filter(as.character(survey_id) == selecionado)
    if (nrow(survey) == 0) {
      return(paste0("Pesquisa selecionada: ", selecionado))
    }

    paste0(
      "Pesquisa selecionada: ",
      survey$survey_name[1],
      " (", survey$survey_id[1], ")"
    )
  })

  dados_filtrados <- reactive({
    df <- dados_tratados()
    if (nrow(df) == 0) return(df)

    survey_selecionada <- as.character(input$filtro_survey)
    if (!is.null(survey_selecionada) && nzchar(survey_selecionada)) {
      df <- df |> filter(as.character(.data$survey_id) == survey_selecionada)
    }

    setores_selecionados <- input$filtro_setor
    if (is.null(setores_selecionados) || length(setores_selecionados) == 0) return(df)
    df |> filter(.data$setor %in% setores_selecionados)
  })

respostas_estruturadas <- reactive({

  df <-
    dados_filtrados()

  mapa <-
    cache_mapa_perguntas()

  if (
    nrow(df) == 0 ||
    nrow(mapa) == 0
  ) {
    return(
      data.frame()
    )
  }

  partes <- lapply(
    seq_len(
      nrow(df)
    ),
    function(i) {

      vinculadas <-
        vincular_respostas(
          json_data =
            df$data[[i]],
          survey_id =
            df$survey_id[[i]],
          mapa_perguntas =
            mapa
        )

      if (
        nrow(vinculadas) == 0
      ) {
        return(NULL)
      }

      vinculadas |>
        mutate(
          id =
            df$id[[i]],
          created_at =
            df$created_at[[i]],
          updated_at =
            df$updated_at[[i]],
          setor =
            df$setor[[i]],
          finished =
            df$finished[[i]]
        ) |>
        select(
          id,
          survey_id,
          created_at,
          updated_at,
          setor,
          finished,
          bloco_numero,
          bloco_hash,
          bloco,
          bloco_nome_original,
          pergunta_numero,
          pergunta_id,
          pergunta,
          tipo_pergunta,
          resposta,
          resposta_limpa,
          resposta_normalizada,
          valor
        )
    }
  )

  resultado <-
    bind_rows(
      partes
    )

  if (
    nrow(resultado) == 0
  ) {
    return(
      data.frame()
    )
  }

  resultado |>
    arrange(
      bloco_numero,
      pergunta_numero,
      created_at
    )
})

  respostas_longas <- reactive({
    df <- dados_filtrados()
    if (nrow(df) == 0) return(data.frame())
    n_respostas <- lengths(df$respostas)
    tem_resposta <- n_respostas > 0
    if (!any(tem_resposta)) return(data.frame())
    df <- df[tem_resposta, ]
    n_respostas <- n_respostas[tem_resposta]

    resultado <- data.frame(
      id = rep(df$id, n_respostas),
      created_at = rep(df$created_at, n_respostas),
      setor = rep(df$setor, n_respostas),
      resposta = unlist(df$respostas, use.names = FALSE),
      stringsAsFactors = FALSE
    )

    resultado |> mutate(
      resposta_original = resposta,
      resposta_limpa = trimws(resposta),
      resposta_normalizada = unname(normalizar_resposta[resposta_limpa])
    )
  })

  respostas_quantitativas <- reactive({
    df <- respostas_longas()
    if (nrow(df) == 0) return(data.frame())
    df |> filter(!is.na(resposta_normalizada)) |> mutate(resposta = resposta_normalizada)
  })

  output$total_respostas <- renderText({ nrow(dados_filtrados()) })

  output$total_setores <- renderText({
    df <- dados_filtrados()
    if (nrow(df) == 0) return("0")
    length(unique(df$setor))
  })

  output$media_geral <- renderText({
    df <- respostas_quantitativas()
    if (nrow(df) == 0) return("-")
    valores <- unname(valor_resposta[df$resposta])
    paste0(round(mean(valores, na.rm = TRUE), 2), " / 5")
  })

  output$grafico_setor <- renderPlotly({
    df <- respostas_quantitativas()
    if (nrow(df) == 0) return(NULL)
    dados_setor <- df |> count(setor, name = "quantidade") |> arrange(desc(quantidade))
    plot_ly(data = dados_setor, x = ~setor, y = ~quantidade, type = "bar")
  })

  output$grafico_respostas <- renderPlotly({
    df <- respostas_quantitativas()

    if (nrow(df) == 0) return(NULL)

    dados_respostas <- df |> count(resposta, name = "quantidade") |> arrange(desc(quantidade))

    plot_ly(
      data = dados_respostas,
      x = ~resposta,
      y = ~quantidade,
      type = "bar"
    ) |> layout(
      xaxis = list(title = "Resposta"),
      yaxis = list(title = "Quantidade")
    )
  })

  output$grafico_tempo <- renderPlotly({
    df <- respostas_quantitativas()
    if (nrow(df) == 0) return(NULL)
    dados_tempo <- df |> mutate(data = as.Date(created_at)) |> count(data, name = "quantidade")
    plot_ly(data = dados_tempo, x = ~data, y = ~quantidade, type = "scatter", mode = "lines+markers")
  })

  output$grafico_media <- renderPlotly({
    df <- respostas_quantitativas()
    if (nrow(df) == 0) return(NULL)
    dados_media <- df |> mutate(valor = unname(valor_resposta[resposta])) |> group_by(setor) |> summarise(media = mean(valor, na.rm = TRUE), .groups = "drop") |> arrange(desc(media)
    )
    plot_ly(data = dados_media, x = ~setor, y = ~media, type = "bar")
  })

  output$tabela <- renderTable({
    df <- dados_filtrados()
    if (nrow(df) == 0) return(data.frame())
    df |> select(id, created_at, setor, finished) |> head(20)
  })

  observe({

  df <- respostas_estruturadas()

  if (nrow(df) == 0) {
    return()
  }

  blocos <- df |>
  filter(
    !is.na(bloco),
    bloco != "",
    !grepl(
      "^(Block|Bloco)\\s*[0-9]+$",
      bloco,
      ignore.case = TRUE
    )
  ) |>
  distinct(
    bloco_numero,
    bloco
  ) |>
  arrange(
    bloco_numero
  ) |>
  pull(
    bloco
  ) |>
  unique()

  bloco_atual <- isolate(
    input$filtro_bloco
  )

  if (
    is.null(bloco_atual) ||
    length(bloco_atual) == 0 ||
    !(bloco_atual %in% blocos)
  ) {
    bloco_atual <- blocos[1]
  }

  updateSelectInput(
    session,
    "filtro_bloco",
    choices = blocos,
    selected = bloco_atual
  )
})

observe({

  df <- respostas_estruturadas()

  req(
    nrow(df) > 0,
    input$filtro_bloco
  )

  perguntas <- df |>
    filter(
      bloco == input$filtro_bloco
    ) |>
    distinct(
      pergunta_numero,
      pergunta_id,
      pergunta
    ) |>
    arrange(
      pergunta_numero
    )

  if (nrow(perguntas) == 0) {
    return()
  }

  opcoes <- c(
    "Todas as perguntas" = "__TODAS__",
    setNames(
      perguntas$pergunta_id,
      perguntas$pergunta
    )
  )

  pergunta_atual <- isolate(
    input$filtro_pergunta
  )

  if (
    is.null(pergunta_atual) ||
    length(pergunta_atual) == 0 ||
    !(pergunta_atual %in% unname(opcoes))
  ) {
    pergunta_atual <- "__TODAS__"
  }

  updateSelectizeInput(
    session,
    "filtro_pergunta",
    choices = opcoes,
    selected = pergunta_atual,
    server = FALSE
  )
})

perguntas_visiveis <- reactive({

  df <- respostas_estruturadas()

  req(
    nrow(df) > 0,
    input$filtro_bloco,
    input$filtro_pergunta
  )

  perguntas <- df |>
    filter(
      bloco == input$filtro_bloco
    ) |>
    distinct(
      pergunta_numero,
      pergunta_id,
      pergunta
    ) |>
    arrange(
      pergunta_numero
    )

  if (
    identical(
      input$filtro_pergunta,
      "__TODAS__"
    )
  ) {
    return(perguntas)
  }

  perguntas |>
    filter(
      pergunta_id ==
        input$filtro_pergunta
    )
})

output$blocos_perguntas_ui <-
  renderUI({

    df <-
      respostas_estruturadas()

    if (
      nrow(df) == 0
    ) {

      return(
        p(
          "Nenhuma resposta disponível."
        )
      )
    }

    perguntas <-
      perguntas_visiveis()

    if (
      nrow(perguntas) == 0
    ) {

      return(
        p(
          "Nenhuma pergunta encontrada."
        )
      )
    }

    tagList(
      lapply(
        seq_len(
          nrow(perguntas)
        ),
        function(i) {
          pergunta_id <-
            perguntas$pergunta_id[i]

          pergunta_texto <-
            perguntas$pergunta[i]

          tagList(
            h4(
              paste0(
                perguntas$pergunta_numero[i],
                ". ",
                pergunta_texto
              )
            ),
            plotlyOutput(
              paste0(
                "pct_plot_",
                pergunta_id
              ),
              height =
                "380px"
            ),
            hr()
          )
        }
      )
    )
  })

  observe({

  perguntas <-
    perguntas_visiveis()

  if (
    nrow(perguntas) == 0
  ) {
    return()
  }

  for (
    i in seq_len(
      nrow(perguntas)
    )
  ) {

    local({

      pergunta_id_local <-
        perguntas$pergunta_id[i]

      bloco_local <-
        input$filtro_bloco

      id_plot <-
        paste0(
          "pct_plot_",
          pergunta_id_local
        )

      output[[id_plot]] <-
        renderPlotly({

          df <-
            respostas_estruturadas() |>
            filter(
              bloco ==
                bloco_local,

              pergunta_id ==
                pergunta_id_local,

              !is.na(
                resposta_normalizada
              )
            )

          if (
            nrow(df) == 0
          ) {
            return(NULL)
          }
          escala <-
            data.frame(
              resposta_normalizada =
                names(
                  valor_resposta
                ),
              ordem =
                seq_along(
                  valor_resposta
                ),
              stringsAsFactors =
                FALSE
            )

          dados_pct <-
            df |>
            count(
              resposta_normalizada,
              name = "quantidade"
            ) |>
            right_join(
              escala,
              by =
                "resposta_normalizada"
            ) |>
            mutate(
              quantidade =
                coalesce(
                  quantidade,
                  0L
                )
            ) |>
            arrange(
              ordem
            )

          total <-
            sum(
              dados_pct$quantidade
            )

          if (
            total == 0
          ) {
            return(NULL)
          }

          dados_pct <-
            dados_pct |>
            mutate(
              percentual =
                round(
                  100 *
                  quantidade /
                  total,
                  1
                ),
              texto =
                paste0(
                  resposta_normalizada,
                  "<br>",
                  percentual,
                  "%"
                )
            )

          plot_ly(
            data = dados_pct,
            x = ~resposta_normalizada,
            y = ~quantidade,
            text = ~texto,
            type = "bar",
            textposition = "auto",
            hovertemplate =
              paste0(
                "%{x}<br>",
                "Quantidade: %{y}<br>",
                "Percentual: %{text}",
                "<extra></extra>"
              )
          ) |> layout(
            xaxis = list(title = "Resposta"),
            yaxis = list(title = "Quantidade")
          )
        })
    })
  }
})

  output$ultima_atualizacao <- renderText({
  paste(
    "Última atualização:",
    format(
      Sys.time(),
      "%d/%m/%Y %H:%M:%S"
    )
  )
})

}

app <- shinyApp(
  ui,
  server
)

app <- shinyApp(ui, server)
