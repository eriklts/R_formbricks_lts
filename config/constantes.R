# Constantes e mapeamentos globais

valor_resposta <- c(
  "Discordo totalmente" = 1,
  "Discordo" = 2,
  "Neutro" = 3,
  "Concordo" = 4,
  "Concordo totalmente" = 5
)

normalizar_resposta <- c(
  "Discordo totalmente" = "Discordo totalmente",
  "Estoy totalmente en desacuerdo" = "Discordo totalmente",
  "Discordo" = "Discordo",
  "Estoy en desacuerdo" = "Discordo",
  "Neutro" = "Neutro",
  "Neutral" = "Neutro",
  "Concordo" = "Concordo",
  "Estoy de acuerdo" = "Concordo",
  "Concordo totalmente" = "Concordo totalmente",
  "Estoy totalmente de acuerdo" = "Concordo totalmente"
)

# Padrão para validação de nomes genéricos
PADRAO_BLOCO_GENERICO <- "^(Block|Bloco)\\s*[0-9]+$"

# Configurações de UI
CONFIG_UI <- list(
  titulo = "Dashboard - Pesquisa de Clima Organizacional",
  altura_grafico = "380px",
  intervalo_atualizacao = 10000
)
