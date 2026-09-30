library(shiny)
library(dplyr)
library(plotly)
library(jsonlite)

# ===== UI - Interface do usuário =====
ui <- fluidPage(
  titlePanel(CONFIG_UI$titulo),

  fluidRow(
    #column(6, selectizeInput("filtro_setor", "Filtrar por setor (deixe vazio para ver todos):", choices = character(0), selected = character(0), multiple = TRUE)),
    column(6, selectInput("filtro_survey", "Selecione a pesquisa:", choices = character(0))),
    column(6, div(style = "margin-top: 25px;",
      checkboxInput("filtro_finished", "Exibir apenas respostas finalizadas", value = FALSE),
      checkboxInput("filtro_notFinished", "Exibir apenas respostas NÃO finalizadas", value = FALSE)
    ))
  ),

  fluidRow(column(12, h4(textOutput("pesquisa_selecionada")))),

  fluidRow(
    column(4, wellPanel(h3("Total de respostas"), h2(textOutput("total_respostas")))),
    #column(4, wellPanel(h3("Setores"), h2(textOutput("total_setores")))),
    column(4, wellPanel(h3("Média geral"), h2(textOutput("media_geral"))))
  ),

  uiOutput("painel_grafico_setor"),
  hr(),
  h3("Distribuição das respostas"),
  plotlyOutput("grafico_respostas"),
  hr(),
  h3("Respostas ao longo do tempo"),
  plotlyOutput("grafico_tempo"),
  uiOutput("painel_grafico_media"),
  hr(), hr(),
  h3("Análise por bloco e pergunta"),
  
  fluidRow(
    column(4, selectInput("filtro_bloco", "Selecione o bloco:", choices = character(0))),
    column(8, selectizeInput("filtro_pergunta", "Selecione a pergunta:", choices = character(0), multiple = FALSE))
  ),
  
  uiOutput("blocos_perguntas_ui"),
  hr(), hr(),
  h3("Respostas descritivas"),
  uiOutput("descritivas_ui"),
  hr(),
  textOutput("ultima_atualizacao")
)

server <- function(input, output, session) {
  
  cache_dados <- reactiveVal(data.frame())
  cache_mapa_perguntas <- reactiveVal(data.frame())
  cache_mapa_descritivas <- reactiveVal(data.frame())
  cache_survey_nomes <- reactiveVal(data.frame())
  ultima_busca <- reactiveVal(as.POSIXct("1970-01-01 00:00:00", tz = "UTC"))
  
  observe({
    invalidateLater(CONFIG_UI$intervalo_atualizacao, session)
    
    tryCatch({
      momento_ultima_busca <- isolate(ultima_busca())
      
      novos <- buscar_respostas_incrementais(con = con, ultima_atualizacao = momento_ultima_busca)
      surveys_db <- buscar_blocos_pesquisas(con)
      
      novo_mapa <- montar_mapa_perguntas(surveys_db)
      cache_mapa_perguntas(novo_mapa)
      cache_mapa_descritivas(montar_mapa_perguntas_descritivas(surveys_db))
      cache_survey_nomes(surveys_db)
      
      if (nrow(novos) == 0) return(invisible(NULL))
      
      novos$setor <- vapply(novos$meta_url, extrair_setor_url, character(1), USE.NAMES = FALSE)
      novos$respostas <- lapply(novos$data, extrair_respostas)
      
      atual <- isolate(cache_dados())
      atual <- atualizar_dados_incrementais(atual, novos)
      atual <- atual |> arrange(created_at)
      cache_dados(atual)
      
      ultima_busca(max(novos$updated_at, na.rm = TRUE))
      
    }, error = function(e) {
      warning(paste("Erro na atualização automática:", conditionMessage(e)))
    })
  })
  
  dados_tratados <- reactive({
  df <- cache_dados()
  if (nrow(df) == 0) return(df)

  if (isTRUE(input$filtro_finished) && !isTRUE(input$filtro_notFinished)) {
    df <- df |> filter(finished == TRUE)
  } else if (isTRUE(input$filtro_notFinished) && !isTRUE(input$filtro_finished)) {
    df <- df |> filter(finished == FALSE)
  }
  df
})

  dados_por_survey <- reactive({
    df <- dados_tratados()
    if (nrow(df) == 0) return(df)
    filtrar_por_survey(df, input$filtro_survey)
  })
  
  dados_filtrados <- reactive({
    df <- dados_por_survey()
    if (nrow(df) == 0) return(df)
    filtrar_por_setores(df, input$filtro_setor)
  })
  
  respostas_estruturadas <- reactive({
    estruturar_respostas(dados_filtrados(), cache_mapa_perguntas())
  })
  
  respostas_longas <- reactive({
    processar_respostas_longas(dados_filtrados(), dados_filtrados()$respostas)
  })
  
  respostas_quantitativas <- reactive({
    df <- respostas_longas()
    if (nrow(df) == 0) return(data.frame())
    df |> filter(!is.na(resposta_normalizada)) |> mutate(resposta = resposta_normalizada)
  })
  
  observeEvent(dados_por_survey(), {
    raw_setores <- if (nrow(dados_por_survey()) == 0) character(0) else sort(unique(as.character(dados_por_survey()$setor)))
    selecionado <- isolate(input$filtro_setor)
    atualizar_filtro_setor(session, raw_setores, selecionado)
  })
  
  observeEvent(cache_survey_nomes(), {
    surveys <- cache_survey_nomes()
    selecionado <- isolate(input$filtro_survey)
    atualizar_filtro_survey(session, surveys, selecionado)
  })
  
  observeEvent(input$filtro_survey, {
    updateSelectizeInput(session, "filtro_setor", selected = character(0))
  })
  
  observeEvent(respostas_estruturadas(), {
    df <- respostas_estruturadas()
    if (nrow(df) == 0) return()
    
    blocos <- obter_blocos_unicos(df)
    selecionado <- isolate(input$filtro_bloco)
    atualizar_filtro_bloco(session, blocos, selecionado)
  })
  
  observeEvent(input$filtro_bloco, {
    df <- respostas_estruturadas()
    if (nrow(df) == 0) return()
    
    perguntas <- obter_perguntas_bloco(df, input$filtro_bloco)
    if (nrow(perguntas) == 0) return()
    
    selecionado <- isolate(input$filtro_pergunta)
    atualizar_filtro_pergunta(session, perguntas, selecionado)
  })
  
  output$pesquisa_selecionada <- renderText({
    surveys <- cache_survey_nomes()
    selecionado <- input$filtro_survey
    
    if (is.null(selecionado) || length(selecionado) == 0 || nrow(surveys) == 0) {
      return("Pesquisa selecionada: nenhuma")
    }
    
    if (identical(selecionado, "__TODAS__")) {
      return("Pesquisa selecionada: Todas as pesquisas")
    }
    
    survey <- surveys |> filter(as.character(survey_id) == selecionado)
    if (nrow(survey) == 0) return(paste0("Pesquisa selecionada: ", selecionado))
    
    paste0("Pesquisa selecionada: ", survey$survey_name[1])
  })
  
  output$total_respostas <- renderText({ nrow(dados_filtrados()) })
  
  #output$total_setores <- renderText({
  #  df <- dados_filtrados()
  #  if (nrow(df) == 0) return("0")
  #  length(unique(df$setor))
  #})
  
  output$media_geral <- renderText({
    calcular_media_geral(respostas_quantitativas())
  })
  
  # Gráficos condicionais: exibidos apenas quando 0 ou >= 2 setores estão selecionados
  #multiplos_setores <- reactive({
   # s <- input$filtro_setor
    #is.null(s) || length(s) == 0 || length(s) >= 2
  #})

  #output$painel_grafico_setor <- renderUI({
    #if (!multiplos_setores()) return(NULL)
    #tagList(
      #hr(),
      #h3("Respostas por setor"),
      #plotlyOutput("grafico_setor")
    #)
  #})

  #output$grafico_setor <- renderPlotly({ renderizar_grafico_setor(dados_filtrados()) })

  #output$painel_grafico_media <- renderUI({
    #if (!multiplos_setores()) return(NULL)
    #tagList(
      #hr(),
      #h3("Média por setor"),
      #plotlyOutput("grafico_media")
    #)
  #})

  #output$grafico_media <- renderPlotly({ renderizar_grafico_media(respostas_quantitativas()) })

  output$grafico_respostas <- renderPlotly({ renderizar_grafico_respostas(respostas_quantitativas()) })
  output$grafico_tempo <- renderPlotly({ renderizar_grafico_tempo(dados_filtrados()) })
  
  perguntas_visiveis <- reactive({
    df <- respostas_estruturadas()
    if (nrow(df) == 0) return(data.frame())
    
    perguntas <- obter_perguntas_bloco(df, input$filtro_bloco)
    if (nrow(perguntas) == 0) return(data.frame())
    
    if (identical(input$filtro_pergunta, "__TODAS__")) return(perguntas)
    perguntas |> filter(pergunta_id == input$filtro_pergunta)
  })
  
  output$blocos_perguntas_ui <- renderUI({
    if (nrow(respostas_estruturadas()) == 0) {
      return(p("Nenhuma resposta disponível."))
    }
    
    perguntas <- perguntas_visiveis()
    if (nrow(perguntas) == 0) {
      return(p("Nenhuma pergunta encontrada."))
    }
    
    total_bloco <- respostas_estruturadas() |>
      dplyr::filter(bloco == input$filtro_bloco, !is.na(resposta_normalizada)) |>
      dplyr::distinct(id) |>
      nrow()

    tagList(
      div(
        style = "margin-bottom: 16px;",
        tags$span(
          style = "font-size: 14px; color: #555; font-weight: 500;",
          paste0("Total de respostas neste bloco: "),
          tags$strong(total_bloco)
        )
      ),
      lapply(seq_len(nrow(perguntas)), function(i) {
        pergunta_id <- perguntas$pergunta_id[i]
        pergunta_texto <- perguntas$pergunta[i]

        tagList(
          h4(paste0(perguntas$pergunta_numero[i], ". ", pergunta_texto)),
          plotlyOutput(paste0("pct_plot_", pergunta_id), height = CONFIG_UI$altura_grafico),
          hr()
        )
      })
    )
  })
  
  observe({
    perguntas <- perguntas_visiveis()
    if (nrow(perguntas) == 0) return()
    
    for (i in seq_len(nrow(perguntas))) {
      local({
        pergunta_id_local <- perguntas$pergunta_id[i]
        bloco_local <- input$filtro_bloco
        id_plot <- paste0("pct_plot_", pergunta_id_local)
        
        output[[id_plot]] <- renderPlotly({
          renderizar_grafico_percentual(respostas_estruturadas(), pergunta_id_local, bloco_local)
        })
      })
    }
  })

  # ===== Respostas descritivas =====

  respostas_descritivas <- reactive({
    estruturar_respostas_descritivas(dados_filtrados(), cache_mapa_descritivas())
  })

  output$descritivas_ui <- renderUI({
    df <- respostas_descritivas()

    if (nrow(df) == 0) {
      return(p(
        style = "color: #888; font-style: italic;",
        "Nenhuma resposta descritiva disponível."
      ))
    }

    # Agrupa perguntas preservando a ordem original (bloco → pergunta)
    # bloco_numero é a posição física no JSON; reindexamos sequencialmente em R
    perguntas_desc <- df |>
      dplyr::distinct(bloco_numero, pergunta_numero, bloco, pergunta_id, pergunta, subheader) |>
      dplyr::arrange(bloco_numero, pergunta_numero)

    # Offset: quantidade de blocos únicos já exibidos na seção de múltipla escolha
    n_blocos_mc <- respostas_estruturadas() |>
      dplyr::filter(!is.na(bloco), bloco != "") |>
      dplyr::distinct(bloco_numero) |>
      nrow()

    # Índice sequencial por bloco continuando após os blocos de múltipla escolha
    blocos_ordem <- perguntas_desc |>
      dplyr::distinct(bloco_numero, bloco) |>
      dplyr::arrange(bloco_numero) |>
      dplyr::mutate(bloco_seq = seq_len(dplyr::n()) + n_blocos_mc)

    perguntas_desc <- perguntas_desc |>
      dplyr::left_join(blocos_ordem, by = c("bloco_numero", "bloco"))

    tagList(lapply(seq_len(nrow(perguntas_desc)), function(i) {
      pid    <- perguntas_desc$pergunta_id[i]
      ptexto <- perguntas_desc$pergunta[i]
      pnum   <- perguntas_desc$pergunta_numero[i]
      bloco  <- perguntas_desc$bloco[i]
      bseq   <- perguntas_desc$bloco_seq[i]
      psub   <- perguntas_desc$subheader[i]

      respostas_pergunta <- df |>
        dplyr::filter(pergunta_id == pid) |>
        dplyr::pull(resposta)

      itens <- lapply(seq_along(respostas_pergunta), function(j) {
        tags$li(
          style = paste(
            "display: flex;",
            "gap: 12px;",
            "padding: 10px 14px;",
            "margin-bottom: 6px;",
            "background: #f8f9fa;",
            "border-left: 3px solid #6c757d;",
            "border-radius: 4px;",
            "line-height: 1.5;"
          ),
          tags$span(
            style = paste(
              "min-width: 22px;",
              "font-size: 12px;",
              "font-weight: 600;",
              "color: #6c757d;",
              "padding-top: 1px;",
              "flex-shrink: 0;"
            ),
            paste0(j, ".")
          ),
          tags$span(
            style = "font-size: 14px; color: #333;",
            respostas_pergunta[[j]]
          )
        )
      })

      tagList(
        div(
          style = "margin-top: 24px;",
          tags$p(
            style = "font-size: 12px; color: #888; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.05em;",
            paste0(bseq, ". ", bloco)
          ),
          h4(
            style = "margin-top: 0; margin-bottom: 4px; color: #333;",
            paste0(pnum, ". ", ptexto)
          ),
          if (!is.na(psub) && nzchar(psub)) {
            tags$p(
              style = paste(
                "font-size: 13px;",
                "color: #666;",
                "margin-top: 4px;",
                "margin-bottom: 14px;",
                "font-style: italic;"
              ),
              psub
            )
          } else {
            div(style = "margin-bottom: 14px;")
          },
          tags$ul(
            style = "list-style: none; padding-left: 0; margin: 0;",
            tagList(itens)
          )
        ),
        hr()
      )
    }))
  })
  
  #output$ultima_atualizacao <- renderText({
    #paste("Última atualização:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"))
  #})
}

app <- shinyApp(ui, server)