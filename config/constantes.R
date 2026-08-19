# Constantes e mapeamentos globais

valor_resposta <- c(
  "Discordo totalmente" = 2,
  "Discordo" = 4,
  "Neutro" = 6,
  "Concordo" = 8,
  "Concordo totalmente" = 10
)

normalizar_resposta <- c(
  "Discordo totalmente" = "Discordo totalmente",
  "Estoy totalmente en desacuerdo" = "Discordo totalmente",
  "Je suis tout à fait en désaccord" = "Discordo totalmente",
  "Discordo" = "Discordo",
  "Estoy en desacuerdo" = "Discordo",
  "Je ne suis pas d'accord" = "Discordo",
  "Neutro" = "Neutro",
  "Neutral" = "Neutro",
  "Neutre" = "Neutro",
  "Concordo" = "Concordo",
  "Estoy de acuerdo" = "Concordo",
  "Je suis d'accord" = "Concordo",
  "Concordo totalmente" = "Concordo totalmente",
  "Estoy totalmente de acuerdo" = "Concordo totalmente",
  "Je suis tout à fait d'accord" = "Concordo totalmente"
)

# Padrão para validação de nomes genéricos
PADRAO_BLOCO_GENERICO <- "^(Block|Bloco)\\s*[0-9]+$"

# Cores por nível de resposta
cores_resposta <- c(
  "Discordo totalmente" = "#D32F2F",
  "Discordo"            = "#FF8C00",
  "Neutro"              = "#FDD835",
  "Concordo"            = "#43A047",
  "Concordo totalmente" = "#1B5E20"
)

# Configurações de UI
CONFIG_UI <- list(
  titulo = "Dashboard - Pesquisa de Clima Organizacional",
  altura_grafico = "380px",
  intervalo_atualizacao = 10000
)