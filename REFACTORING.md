# Refatoração do Projeto R formBricks LTS

## Estrutura Refatorada

O projeto foi reorganizado em módulos temáticos para melhor manutenibilidade e legibilidade:

### Configuração (`config/`)
- **`constantes.R`** - Constantes, mapeamentos e configurações da UI
  - `valor_resposta`: Escala de respostas de 1-5
  - `normalizar_resposta`: Mapeamento de respostas em português/espanhol
  - `CONFIG_UI`: Configurações da interface
  
- **`conexao.R`** - Conexão com banco de dados PostgreSQL
  
- **`globals.R`** - Variáveis globais para evitar warnings do R CMD CHECK

### Scripts (`scripts/`)

- **`carregar_dados.R`** - Funções de carregamento e processamento de JSON
  - `valor_json_para_texto()`: Converte valores JSON em texto
  - `extrair_respostas()`: Extrai respostas em JSON
  - `extrair_respostas_por_hash()`: Extrai respostas por ID
  - `buscar_respostas_incrementais()`: Busca respostas novas do banco
  - `buscar_blocos_pesquisas()`: Busca estrutura de blocos e perguntas

- **`transformacoes.R`** - Funções de limpeza e normalização de dados
  - `limpar_texto()`: Padroniza texto (remove _, caracteres especiais)
  - `limpar_setor()`: Limpeza específica para nomes de setores
  - `desambiguar_labels()`: Remove duplicatas adicionando índices
  - `extrair_setor_url()`: Extrai setor da URL
  - Reduz duplicação de lógica de limpeza

- **`vincular_respostas.R`** - Funções para processar estrutura JSON de perguntas
  - `limpar_headline_formbricks()`: Remove HTML de headlines
  - `obter_headline()`: Extrai headline de elemento
  - `montar_mapa_blocos_json()`: Mapeia blocos de um JSON
  - `montar_mapa_perguntas()`: Consolida mapa de todas as perguntas
  - `vincular_respostas()`: Associa respostas com perguntas

- **`graficos.R`** - Funções para renderizar gráficos
  - `renderizar_grafico_setor()`: Gráfico de links por setor
  - `renderizar_grafico_respostas()`: Distribuição de respostas
  - `renderizar_grafico_tempo()`: Série temporal de links
  - `renderizar_grafico_media()`: Média por setor
  - `renderizar_grafico_percentual()`: Percentual de respostas por pergunta
  - Centralizou lógica de gráficos, reduzindo código em dashboard.R

- **`filtros.R`** - Gerenciamento de inputs e filtros dinâmicos
  - `atualizar_filtro_setor()`: Atualiza seletor de setores
  - `atualizar_filtro_survey()`: Atualiza seletor de pesquisas
  - `atualizar_filtro_bloco()`: Atualiza seletor de blocos
  - `atualizar_filtro_pergunta()`: Atualiza seletor de perguntas
  - `obter_blocos_unicos()`: Extrai blocos do dataset
  - `obter_perguntas_bloco()`: Extrai perguntas de um bloco

- **`reativos.R`** - Lógica auxiliar para reativas do Shiny
  - `processar_respostas_longas()`: Transforma respostas em formato longo
  - `estruturar_respostas()`: Associa dados com mapa de perguntas
  - `filtrar_por_survey()`: Filtra por pesquisa selecionada
  - `filtrar_por_setores()`: Filtra por setores selecionados
  - `atualizar_dados_incrementais()`: Merge de dados novos com existentes
  - `calcular_media_geral()`: Calcula média de respostas

- **`dashboard.R`** - Interface e lógica principal do Shiny
  - **UI**: Mantém estrutura visual compacta
  - **Server**: Lógica refatorada e organizada em seções
    - Caches e variáveis reativas
    - Atualização incremental de dados
    - Reativas principais (dados tratados, filtrados, estruturados)
    - Atualização de filtros
    - Outputs (textos, gráficos, tabelas)
    - Plots dinâmicos por pergunta
  - **Redução**: ~200 linhas (de ~900)

### Raiz
- **`app.R`** - Entry point que carrega todos os módulos
  - Agora carrega 7 scripts + 2 configs (antes era 4 scripts + 2 configs)
  - Ordem de carregamento garante dependências

## Benefícios da Refatoração

✅ **Modularidade**: Cada arquivo tem responsabilidade única  
✅ **Manutenibilidade**: Fácil encontrar e modificar funcionalidades  
✅ **Testabilidade**: Funções isoladas são mais fáceis de testar  
✅ **Reusabilidade**: Funções podem ser usadas em outros contextos  
✅ **Legibilidade**: dashboard.R reduzido de ~900 para ~350 linhas  
✅ **Sem Perda de Funcionalidade**: Todas as features originais preservadas  

## Funcionalidades Mantidas

- ✅ Atualização incremental de dados a cada 10s
- ✅ Filtros por setor (com limpeza de nomes)
- ✅ Filtros por pesquisa
- ✅ Análise por bloco e pergunta
- ✅ 5 gráficos diferentes (setor, respostas, tempo, média, percentual)
- ✅ Tabela de últimas respostas
- ✅ Suporte para blocos com apenas nome (sem perguntas)
- ✅ Normalização de respostas (português/espanhol)
- ✅ Desambiguação de labels duplicados
- ✅ Timestamp de última atualização
- ✅ Contagem de links respondidos (não perguntas)

## Próximas Oportunidades de Melhoria

1. Criar testes unitários para funções
2. Adicionar cache com memória para datasets grandes
3. Criar tabela de rastreamento de performance
4. Extrair configs de banco de dados para arquivo `.env`
5. Adicionar modo offline com dados em cache
