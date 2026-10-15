install.packages("DBI")
install.packages("RPostgres")
install.packages("dplyr")
install.packages("ggplot2")
install.packages("shiny")
install.packages("plotly")

# ===== Exportação em PDF =====
# rmarkdown: gera o relatório .Rmd → PDF
install.packages("rmarkdown")
# stringr: usado no Rmd para str_wrap nos títulos dos gráficos
install.packages("stringr")
# tinytex: distribuição LaTeX leve (necessária para compilar o PDF)
install.packages("tinytex")
tinytex::install_tinytex()   # instala o LaTeX — execute apenas uma vez
