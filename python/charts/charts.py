"""
Gráficos nativos do Excel via XlsxWriter.

Cada função recebe um workbook/worksheet XlsxWriter e um DataFrame
de dados já calculado (vindo de statistics.py), escreve os dados de
suporte em colunas auxiliares e insere o gráfico nativo do Excel.

Isso garante gráficos 100% editáveis no Excel — sem capturas de tela
ou imagens PNG externas.

Paleta de cores espelha cores_resposta de config/constantes.R:
  Discordo totalmente → #D32F2F
  Discordo            → #FF8C00
  Neutro              → #FDD835
  Concordo            → #43A047
  Concordo totalmente → #1B5E20
"""

from __future__ import annotations

from typing import Optional

import pandas as pd
import xlsxwriter
from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from python.processing.data_processing import ORDEM_RESPOSTAS

# ---------------------------------------------------------------------------
# Paleta de cores (espelha cores_resposta de constantes.R)
# ---------------------------------------------------------------------------

CORES_RESPOSTA: dict[str, str] = {
    "Discordo totalmente": "#D32F2F",
    "Discordo":            "#FF8C00",
    "Neutro":              "#FDD835",
    "Concordo":            "#43A047",
    "Concordo totalmente": "#1B5E20",
}

# Cor neutra para gráficos sem escala de resposta
COR_AZUL   = "#1565C0"
COR_CINZA  = "#757575"
COR_VERDE  = "#2E7D32"


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------

def _hex_to_xlsxwriter(hex_color: str) -> str:
    """Remove o '#' do hex para usar no XlsxWriter."""
    return hex_color.lstrip("#")


def _escrever_dados_aux(
    ws: Worksheet,
    df: pd.DataFrame,
    start_row: int,
    start_col: int,
    include_header: bool = False,
) -> tuple[int, int]:
    """
    Escreve um DataFrame em uma área auxiliar da planilha (fora da área visível).
    Retorna (última_linha, última_coluna) escritas.
    """
    row = start_row
    if include_header:
        for c, col_name in enumerate(df.columns):
            ws.write(row, start_col + c, col_name)
        row += 1

    for _, data_row in df.iterrows():
        for c, val in enumerate(data_row):
            ws.write(row, start_col + c, val)
        row += 1

    return row - 1, start_col + len(df.columns) - 1


# ---------------------------------------------------------------------------
# 1. Gráfico de distribuição global das respostas (barras verticais)
#    Espelha renderizar_grafico_respostas() de graficos.R
# ---------------------------------------------------------------------------

def inserir_grafico_distribuicao_respostas(
    workbook: Workbook,
    worksheet: Worksheet,
    df_dist: pd.DataFrame,          # saída de calcular_distribuicao_respostas()
    cell_insert: str = "B20",       # célula onde o gráfico será inserido
    aux_start_row: int = 200,       # linha de início dos dados auxiliares
    aux_start_col: int = 20,        # coluna de início dos dados auxiliares (T)
    sheet_name: str = "Resumo",
) -> None:
    """
    Gráfico de colunas com a distribuição global das respostas.
    Uma série por categoria de resposta (cores diferentes).
    """
    if df_dist is None or df_dist.empty:
        return

    # Garante a ordem canônica
    df = df_dist.copy()
    df["resposta_normalizada"] = pd.Categorical(
        df["resposta_normalizada"], categories=ORDEM_RESPOSTAS, ordered=True
    )
    df = df.sort_values("resposta_normalizada").reset_index(drop=True)

    # Escreve categorias (col aux) e quantidades (col aux+1)
    r = aux_start_row
    c = aux_start_col
    ws = worksheet

    ws.write(r, c,     "Resposta")
    ws.write(r, c + 1, "Quantidade")
    ws.write(r, c + 2, "Percentual")
    r += 1

    data_start = r
    for _, row in df.iterrows():
        ws.write(r, c,     str(row["resposta_normalizada"]))
        ws.write(r, c + 1, int(row["quantidade"]))
        ws.write(r, c + 2, float(row["percentual"]))
        r += 1
    data_end = r - 1

    chart = workbook.add_chart({"type": "column"})

    # Uma série por categoria para aplicar cor individual
    for i, resp in enumerate(ORDEM_RESPOSTAS):
        row_idx = data_start + i
        cor = _hex_to_xlsxwriter(CORES_RESPOSTA.get(resp, "#888888"))

        chart.add_series({
            "name":       resp,
            "categories": [sheet_name, data_start, c, data_end, c],
            "values":     [sheet_name, row_idx, c + 1, row_idx, c + 1],
            "fill":       {"color": f"#{cor}"},
            "border":     {"none": True},
            "data_labels": {
                "value":    True,
                "position": "outside_end",
                "font":     {"size": 9},
            },
        })

    chart.set_title({"name": "Distribuição das Respostas"})
    chart.set_x_axis({"name": "Resposta"})
    chart.set_y_axis({"name": "Quantidade", "min": 0})
    chart.set_legend({"none": True})
    chart.set_size({"width": 480, "height": 300})
    chart.set_style(10)

    worksheet.insert_chart(cell_insert, chart, {"x_offset": 0, "y_offset": 0})


# ---------------------------------------------------------------------------
# 2. Gráfico de respostas ao longo do tempo (linha)
#    Espelha renderizar_grafico_tempo() de graficos.R
# ---------------------------------------------------------------------------

def inserir_grafico_tempo(
    workbook: Workbook,
    worksheet: Worksheet,
    df_tempo: pd.DataFrame,         # saída de calcular_respostas_por_data()
    cell_insert: str = "B38",
    aux_start_row: int = 220,
    aux_start_col: int = 20,
    sheet_name: str = "Resumo",
) -> None:
    """
    Gráfico de linha com quantidade de respostas por dia.
    """
    if df_tempo is None or df_tempo.empty:
        return

    r = aux_start_row
    c = aux_start_col
    ws = worksheet

    ws.write(r, c,     "Data")
    ws.write(r, c + 1, "Quantidade")
    r += 1

    data_start = r
    for _, row in df_tempo.iterrows():
        ws.write(r, c,     str(row["data"]))   # data como string
        ws.write(r, c + 1, int(row["quantidade"]))
        r += 1
    data_end = r - 1

    chart = workbook.add_chart({"type": "line"})
    chart.add_series({
        "name":       "Respostas por dia",
        "categories": [sheet_name, data_start, c, data_end, c],
        "values":     [sheet_name, data_start, c + 1, data_end, c + 1],
        "line":       {"color": f"#{_hex_to_xlsxwriter(COR_AZUL)}", "width": 2.0},
        "marker": {
            "type":    "circle",
            "size":    6,
            "fill":    {"color": f"#{_hex_to_xlsxwriter(COR_AZUL)}"},
            "border":  {"color": "white"},
        },
    })

    chart.set_title({"name": "Respostas ao Longo do Tempo"})
    chart.set_x_axis({"name": "Data", "num_font": {"rotation": -30}})
    chart.set_y_axis({"name": "Quantidade", "min": 0})
    chart.set_legend({"none": True})
    chart.set_size({"width": 480, "height": 280})
    chart.set_style(10)

    worksheet.insert_chart(cell_insert, chart, {"x_offset": 0, "y_offset": 0})


# ---------------------------------------------------------------------------
# 3. Gráfico por pergunta (barras verticais, uma cor por categoria)
#    Espelha renderizar_grafico_percentual() de graficos.R
# ---------------------------------------------------------------------------

def inserir_grafico_pergunta(
    workbook: Workbook,
    worksheet: Worksheet,
    df_pct: pd.DataFrame,           # saída de calcular_percentual_pergunta()
    titulo_pergunta: str,
    cell_insert: str,
    aux_start_row: int,
    aux_start_col: int,
    sheet_name: str,
) -> int:
    """
    Gráfico de colunas para uma pergunta específica.
    Retorna a próxima linha auxiliar disponível após escrever os dados.
    """
    if df_pct is None or df_pct.empty:
        return aux_start_row

    r = aux_start_row
    c = aux_start_col
    ws = worksheet

    ws.write(r, c,     "Resposta")
    ws.write(r, c + 1, "Quantidade")
    ws.write(r, c + 2, "Percentual")
    r += 1

    data_start = r
    for _, row in df_pct.iterrows():
        ws.write(r, c,     str(row["resposta_normalizada"]))
        ws.write(r, c + 1, int(row["quantidade"]))
        ws.write(r, c + 2, float(row["percentual"]))
        r += 1
    data_end = r - 1

    chart = workbook.add_chart({"type": "column"})

    for i, resp in enumerate(ORDEM_RESPOSTAS):
        row_idx = data_start + i
        cor = _hex_to_xlsxwriter(CORES_RESPOSTA.get(resp, "#888888"))

        chart.add_series({
            "name":       resp,
            "categories": [sheet_name, data_start, c, data_end, c],
            "values":     [sheet_name, row_idx, c + 1, row_idx, c + 1],
            "fill":       {"color": f"#{cor}"},
            "border":     {"none": True},
            "data_labels": {
                "value":    True,
                "position": "outside_end",
                "font":     {"size": 9},
            },
        })

    # Trunca título longo para caber no gráfico
    titulo_curto = (titulo_pergunta[:80] + "…") if len(titulo_pergunta) > 80 else titulo_pergunta

    chart.set_title({"name": titulo_curto, "name_font": {"size": 10}})
    chart.set_x_axis({"name": "Resposta"})
    chart.set_y_axis({"name": "Quantidade", "min": 0})
    chart.set_legend({"none": True})
    chart.set_size({"width": 460, "height": 280})
    chart.set_style(10)

    worksheet.insert_chart(cell_insert, chart, {"x_offset": 0, "y_offset": 0})

    return r  # próxima linha auxiliar livre


# ---------------------------------------------------------------------------
# 4. Gráfico de média por setor (barras horizontais)
#    Espelha renderizar_grafico_media() de graficos.R
# ---------------------------------------------------------------------------

def inserir_grafico_media_setor(
    workbook: Workbook,
    worksheet: Worksheet,
    df_media: pd.DataFrame,         # saída de calcular_media_por_setor()
    cell_insert: str,
    aux_start_row: int,
    aux_start_col: int,
    sheet_name: str,
) -> int:
    """
    Gráfico de barras horizontais com a média por setor.
    Retorna a próxima linha auxiliar disponível.
    """
    if df_media is None or df_media.empty:
        return aux_start_row

    r = aux_start_row
    c = aux_start_col
    ws = worksheet

    ws.write(r, c,     "Setor")
    ws.write(r, c + 1, "Média")
    r += 1

    data_start = r
    for _, row in df_media.iterrows():
        ws.write(r, c,     str(row["setor"]))
        ws.write(r, c + 1, float(row["media"]))
        r += 1
    data_end = r - 1

    chart = workbook.add_chart({"type": "bar"})
    chart.add_series({
        "name":       "Média",
        "categories": [sheet_name, data_start, c, data_end, c],
        "values":     [sheet_name, data_start, c + 1, data_end, c + 1],
        "fill":       {"color": f"#{_hex_to_xlsxwriter(COR_VERDE)}"},
        "border":     {"none": True},
        "data_labels": {
            "value":    True,
            "position": "outside_end",
            "font":     {"size": 9},
        },
    })

    chart.set_title({"name": "Média por Setor"})
    chart.set_x_axis({"name": "Média (0–10)", "min": 0, "max": 10})
    chart.set_y_axis({"name": "Setor"})
    chart.set_legend({"none": True})
    chart.set_size({"width": 460, "height": 300})
    chart.set_style(10)

    worksheet.insert_chart(cell_insert, chart, {"x_offset": 0, "y_offset": 0})

    return r
