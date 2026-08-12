library(shiny)
library(dplyr)
library(plotly)
library(jsonlite)

# ===== UI - Interface do usuário =====
ui <- fluidPage(
  titlePanel(CONFIG_UI$titulo),

  fluidRow(
    column(6, selectizeInput("filtro_setor", "Filtrar por setor (deixe vazio para ver todos):", choices = character(0), selected = character(0), multiple = TRUE)),
    column(6, selectInput("filtro_survey", "Selecione a pesquisa:", choices = character(0)))
  ),

  fluidRow(column(12, h4(textOutput("pesquisa_selecionada")))),

  fluidRow(
    column(4, wellPanel(h3("Total de respostas"), h2(textOutput("total_respostas")))),
    column(4, wellPanel(h3("Setores"), h2(textOutput("total_setores")))),
    column(4, wellPanel(h3("Média geral"), h2(textOutput("media_geral"))))
  ),

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
  hr(), hr(),
  h3("Análise por bloco e pergunta"),
  
  fluidRow(
    column(4, selectInput("filtro_bloco", "Selecione o bloco:", choices = character(0))),
    column(8, selectizeInput("filtro_pergunta", "Selecione a pergunta:", choices = character(0), multiple = FALSE))
  ),
  
  uiOutput("blocos_perguntas_ui"),
  hr(),
  textOutput("ultima_atualizacao")
)

# ===== SERVER - Lógica da aplicação =====
server <- function(input, output, session) {
  
  # ===== CACHES E VARIÁVEIS REATIVAS =====
  cache_dados <- reactiveVal(data.frame())
  cache_mapa_perguntas <- reactiveVal(data.frame())
  cache_survey_nomes <- reactiveVal(data.frame())
  ultima_busca <- reactiveVal(as.POSIXct("1970-01-01 00:00:00", tz = "UTC"))
  
  # ===== ATUALIZAÇÃO INCREMENTAL DE DADOS =====
  observe({
    invalidateLater(CONFIG_UI$intervalo_atualizacao, session)
    
    tryCatch({
      momento_ultima_busca <- isolate(ultima_busca())
      
      # Busca dados novos
      novos <- buscar_respostas_incrementais(con = con, ultima_atualizacao = momento_ultima_busca)
      surveys_db <- buscar_blocos_pesquisas(con)
      
      # Monta mapa de perguntas
      novo_mapa <- montar_mapa_perguntas(surveys_db)
      cache_mapa_perguntas(novo_mapa)
      cache_survey_nomes(surveys_db)
      
      if (nrow(novos) == 0) return(invisible(NULL))
      
      # Processa setores e respostas
      novos$setor <- vapply(novos$meta_url, extrair_setor_url, character(1), USE.NAMES = FALSE)
      novos$respostas <- lapply(novos$data, extrair_respostas)
      
      # Atualiza cache de dados
      atual <- isolate(cache_dados())
      atual <- atualizar_dados_incrementais(atual, novos)
      atual <- atual |> arrange(created_at)
      cache_dados(atual)
      
      ultima_busca(max(novos$updated_at, na.rm = TRUE))
      
    }, error = function(e) {
      warning(paste("Erro na atualização automática:", conditionMessage(e)))
    })
  })
  
  # ===== REATIVAS PRINCIPAIS =====
  dados_tratados <- reactive({ cache_dados() })
  
  dados_filtrados <- reactive({
    df <- dados_tratados()
    if (nrow(df) == 0) return(df)
    
    df <- filtrar_por_survey(df, input$filtro_survey)
    df <- filtrar_por_setores(df, input$filtro_setor)
    df
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
  
  # ===== ATUALIZAÇÃO DE FILTROS =====
  observeEvent(dados_tratados(), {
    raw_setores <- if (nrow(dados_tratados()) == 0) character(0) else sort(unique(as.character(dados_tratados()$setor)))
    selecionado <- isolate(input$filtro_setor)
    atualizar_filtro_setor(session, raw_setores, selecionado)
  })
  
  observeEvent(cache_survey_nomes(), {
    surveys <- cache_survey_nomes()
    selecionado <- isolate(input$filtro_survey)
    atualizar_filtro_survey(session, surveys, selecionado)
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
  
  # ===== OUTPUTS - TEXTOS E MÉTRICAS =====
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
  
  output$total_setores <- renderText({
    df <- dados_filtrados()
    if (nrow(df) == 0) return("0")
    length(unique(df$setor))
  })
  
  output$media_geral <- renderText({
    calcular_media_geral(respostas_quantitativas())
  })
  
  # ===== OUTPUTS - GRÁFICOS =====
  output$grafico_setor <- renderPlotly({ renderizar_grafico_setor(dados_filtrados()) })
  output$grafico_respostas <- renderPlotly({ renderizar_grafico_respostas(respostas_quantitativas()) })
  output$grafico_tempo <- renderPlotly({ renderizar_grafico_tempo(dados_filtrados()) })
  output$grafico_media <- renderPlotly({ renderizar_grafico_media(respostas_quantitativas()) })
  
  # ===== OUTPUT - TABELA =====
  output$tabela <- renderTable({
    df <- dados_filtrados()
    if (nrow(df) == 0) return(data.frame())
    df |> select(id, created_at, setor, finished) |> head(20)
  })
  
  # ===== OUTPUTS - BLOCOS E PERGUNTAS =====
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
    
    tagList(lapply(seq_len(nrow(perguntas)), function(i) {
      pergunta_id <- perguntas$pergunta_id[i]
      pergunta_texto <- perguntas$pergunta[i]
      
      tagList(
        h4(paste0(perguntas$pergunta_numero[i], ". ", pergunta_texto)),
        plotlyOutput(paste0("pct_plot_", pergunta_id), height = CONFIG_UI$altura_grafico),
        hr()
      )
    }))
  })
  
  # ===== PLOTS DINÂMICOS - GRÁFICOS POR PERGUNTA =====
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
  
  # ===== OUTPUT - TIMESTAMP =====
  output$ultima_atualizacao <- renderText({
    paste("Última atualização:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"))
  })
}

# Criar e executar app
app <- shinyApp(ui, server)
