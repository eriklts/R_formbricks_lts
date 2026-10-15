"""
Montagem e formatação do arquivo Excel (.xlsx).

Estrutura do relatório:
  - Resumo          : métricas gerais + gráficos de distribuição e tempo
  - <Bloco N>       : uma aba por bloco de perguntas quantitativas
  - Descritivas     : respostas abertas (openText), enumeradas por pergunta
  - Dados Brutos    : todas as respostas estruturadas em formato tabular

O nome das abas dos blocos reflete os nomes reais vindos do banco —
não são rótulos fixos (Credibilidade, Respeito…). O sistema se adapta
a qualquer survey carregada.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Optional

import pandas as pd
import xlsxwriter
from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from python.charts.charts import (
    inserir_grafico_distribuicao_respostas,
    inserir_grafico_media_setor,
    inserir_grafico_pergunta,
    inserir_grafico_tempo,
)
from python.processing.data_processing import ORDEM_RESPOSTAS, obter_blocos_unicos
from python.processing.statistics import (
    calcular_distribuicao_respostas,
    calcular_media_geral,
    calcular_media_por_setor,
    calcular_percentual_pergunta,
    calcular_respostas_por_data,
    calcular_resumo_bloco,
    calcular_tabela_completa_bloco,
)

# ---------------------------------------------------------------------------
# Helpers de formatação de nome de aba
# ---------------------------------------------------------------------------

_MAX_SHEET_NAME = 31  # limite do Excel


def _sanitizar_nome_aba(nome: str) -> str:
    """Remove caracteres inválidos em nomes de aba do Excel e trunca a 31 chars."""
    nome = re.sub(r"[:\\/?*\[\]]", "", nome)
    return nome[:_MAX_SHEET_NAME].strip()


def _nomes_abas_unicos(blocos: list[dict]) -> list[tuple[str, str]]:
    """
    Retorna lista de (bloco_nome_original, nome_aba_excel) garantindo
    unicidade e máximo de 31 caracteres.
    """
    vistos: dict[str, int] = {}
    resultado = []
    for b in blocos:
        base = _sanitizar_nome_aba(b["bloco"])
        if base in vistos:
            vistos[base] += 1
            nome_aba = _sanitizar_nome_aba(f"{base[:28]} ({vistos[base]})")
        else:
            vistos[base] = 1
            nome_aba = base
        resultado.append((b["bloco"], nome_aba))
    return resultado


# ---------------------------------------------------------------------------
# Fábrica de formatos XlsxWriter
# ---------------------------------------------------------------------------

class Formatos:
    """Centraliza todos os formatos do workbook para reutilização."""

    def __init__(self, wb: Workbook):
        self.titulo_relatorio = wb.add_format({
            "bold": True, "font_size": 18, "font_color": "#1565C0",
            "valign": "vcenter", "align": "left",
        })
        self.subtitulo = wb.add_format({
            "bold": True, "font_size": 13, "font_color": "#1565C0",
            "valign": "vcenter", "align": "left",
            "bottom": 2, "bottom_color": "#1565C0",
        })
        self.cabecalho_tabela = wb.add_format({
            "bold": True, "font_size": 11, "font_color": "white",
            "bg_color": "#1565C0", "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
        })
        self.celula_label = wb.add_format({
            "bold": True, "font_size": 10, "bg_color": "#EEF2FB",
            "border": 1, "border_color": "#BDBDBD",
            "align": "left", "valign": "vcenter", "text_wrap": True,
        })
        self.celula_valor = wb.add_format({
            "font_size": 10, "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
        })
        self.celula_pct = wb.add_format({
            "num_format": "0.0%", "font_size": 10,
            "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
        })
        self.celula_pct_texto = wb.add_format({
            "font_size": 10, "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
        })
        self.celula_texto = wb.add_format({
            "font_size": 10, "border": 1, "border_color": "#BDBDBD",
            "align": "left", "valign": "top", "text_wrap": True,
        })
        self.celula_numero = wb.add_format({
            "font_size": 10, "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
            "num_format": "#,##0",
        })
        self.celula_media = wb.add_format({
            "font_size": 11, "bold": True, "font_color": "#1B5E20",
            "border": 1, "border_color": "#BDBDBD",
            "align": "center", "valign": "vcenter",
        })
        self.info_label = wb.add_format({
            "bold": True, "font_size": 11, "bg_color": "#F5F5F5",
            "border": 1, "border_color": "#BDBDBD",
            "align": "left", "valign": "vcenter",
        })
        self.info_valor = wb.add_format({
            "font_size": 11, "border": 1, "border_color": "#BDBDBD",
            "align": "left", "valign": "vcenter",
        })
        self.titulo_bloco = wb.add_format({
            "bold": True, "font_size": 14, "font_color": "white",
            "bg_color": "#1565C0", "border": 1, "border_color": "#1565C0",
            "align": "left", "valign": "vcenter",
        })
        self.titulo_pergunta = wb.add_format({
            "bold": True, "font_size": 11, "font_color": "#1565C0",
            "bg_color": "#EEF2FB", "border": 1, "border_color": "#BDBDBD",
            "align": "left", "valign": "vcenter", "text_wrap": True,
        })
        self.resposta_num = wb.add_format({
            "bold": True, "font_size": 10, "font_color": "#757575",
            "align": "center", "valign": "top",
            "border": 1, "border_color": "#BDBDBD",
        })
        self.resposta_texto = wb.add_format({
            "font_size": 10, "font_color": "#333333",
            "align": "left", "valign": "top", "text_wrap": True,
            "border": 1, "border_color": "#BDBDBD",
            "bg_color": "#F8F9FA",
        })
        # Cores por categoria de resposta (para destacar células)
        self.cores_cat: dict[str, object] = {}
        cores_map = {
            "Discordo totalmente": "#FFEBEE",
            "Discordo":            "#FFF3E0",
            "Neutro":              "#FFFDE7",
            "Concordo":            "#E8F5E9",
            "Concordo totalmente": "#E8F5E9",
        }
        for cat, bg in cores_map.items():
            self.cores_cat[cat] = wb.add_format({
                "font_size": 10, "bg_color": bg,
                "border": 1, "border_color": "#BDBDBD",
                "align": "left", "valign": "vcenter",
            })


# ---------------------------------------------------------------------------
# Aba: Resumo
# ---------------------------------------------------------------------------

def _escrever_aba_resumo(
    wb: Workbook,
    fmt: Formatos,
    nome_pesquisa: str,
    total_respostas: int,
    media_geral: str,
    filtro_texto: str,
    data_exportacao: str,
    df_filtrado: pd.DataFrame,
    df_respostas_quantitativas: pd.DataFrame,
) -> None:
    ws: Worksheet = wb.add_worksheet("Resumo")
    ws.set_zoom(90)
    ws.set_column(0, 0, 28)
    ws.set_column(1, 5, 20)
    ws.set_row(0, 36)

    # Título
    ws.merge_range("A1:F1", "Relatório de Clima Organizacional", fmt.titulo_relatorio)
    ws.write("A2", nome_pesquisa, fmt.subtitulo)
    ws.set_row(1, 24)

    # Bloco de informações gerais
    r = 3
    info = [
        ("Pesquisa",           nome_pesquisa),
        ("Total de respostas", str(total_respostas)),
        ("Média geral",        media_geral),
        ("Filtro aplicado",    filtro_texto),
        ("Data de exportação", data_exportacao),
    ]
    for label, valor in info:
        ws.write(r, 0, label, fmt.info_label)
        ws.merge_range(r, 1, r, 4, valor, fmt.info_valor)
        r += 1

    r += 1  # linha em branco

    # Tabela: Distribuição global das respostas
    ws.write(r, 0, "Distribuição das Respostas", fmt.subtitulo)
    ws.merge_range(r, 0, r, 4, "Distribuição das Respostas", fmt.subtitulo)
    r += 1

    ws.write(r, 0, "Resposta",    fmt.cabecalho_tabela)
    ws.write(r, 1, "Quantidade",  fmt.cabecalho_tabela)
    ws.write(r, 2, "Percentual",  fmt.cabecalho_tabela)
    r += 1

    df_dist = calcular_distribuicao_respostas(df_respostas_quantitativas)
    dist_data_start = r
    for _, row in df_dist.iterrows():
        ws.write(r, 0, str(row["resposta_normalizada"]), fmt.celula_label)
        ws.write(r, 1, int(row["quantidade"]),           fmt.celula_numero)
        ws.write(r, 2, f"{row['percentual']:.1f}%",      fmt.celula_pct_texto)
        r += 1

    r += 1

    # Gráfico de distribuição global
    grafico_row = r
    inserir_grafico_distribuicao_respostas(
        workbook=wb, worksheet=ws,
        df_dist=df_dist,
        cell_insert=f"A{grafico_row + 1}",
        aux_start_row=200, aux_start_col=20,
        sheet_name="Resumo",
    )
    r += 17  # altura aproximada do gráfico em linhas

    # Tabela: Respostas ao longo do tempo
    ws.merge_range(r, 0, r, 4, "Respostas ao Longo do Tempo", fmt.subtitulo)
    r += 1

    ws.write(r, 0, "Data",        fmt.cabecalho_tabela)
    ws.write(r, 1, "Quantidade",  fmt.cabecalho_tabela)
    r += 1

    df_tempo = calcular_respostas_por_data(df_filtrado)
    for _, row in df_tempo.iterrows():
        ws.write(r, 0, str(row["data"]),       fmt.celula_label)
        ws.write(r, 1, int(row["quantidade"]), fmt.celula_numero)
        r += 1

    r += 1

    inserir_grafico_tempo(
        workbook=wb, worksheet=ws,
        df_tempo=df_tempo,
        cell_insert=f"A{r + 1}",
        aux_start_row=220, aux_start_col=20,
        sheet_name="Resumo",
    )
    r += 17

    # Congelamento de linha de cabeçalho
    ws.freeze_panes(1, 0)


# ---------------------------------------------------------------------------
# Aba: por bloco
# ---------------------------------------------------------------------------

def _escrever_aba_bloco(
    wb: Workbook,
    fmt: Formatos,
    nome_aba: str,
    bloco_nome: str,
    df_estruturado: pd.DataFrame,
) -> None:
    ws: Worksheet = wb.add_worksheet(nome_aba)
    ws.set_zoom(90)
    ws.set_column(0, 0, 40)   # pergunta
    ws.set_column(1, 6, 16)   # categorias de resposta
    ws.set_row(0, 30)

    # Cabeçalho do bloco
    ws.merge_range("A1:G1", bloco_nome.upper(), fmt.titulo_bloco)

    total_bloco = calcular_resumo_bloco(df_estruturado, bloco_nome)
    ws.write("A2", f"Total de respondentes neste bloco: {total_bloco}", fmt.info_label)
    ws.merge_range("A2:G2", f"Total de respondentes neste bloco: {total_bloco}", fmt.info_label)

    r = 3  # linha atual (0-indexed)

    # Cabeçalho da tabela de dados
    ws.write(r, 0, "Pergunta", fmt.cabecalho_tabela)
    for i, cat in enumerate(ORDEM_RESPOSTAS, start=1):
        ws.write(r, i, cat, fmt.cabecalho_tabela)
    ws.write(r, len(ORDEM_RESPOSTAS) + 1, "Total", fmt.cabecalho_tabela)
    ws.freeze_panes(r + 1, 1)
    r += 1

    # Perguntas do bloco
    df_bloco = df_estruturado[df_estruturado["bloco"] == bloco_nome]
    perguntas = (
        df_bloco[["pergunta_numero", "pergunta_id", "pergunta"]]
        .drop_duplicates()
        .sort_values("pergunta_numero")
    )

    # Área auxiliar para gráficos (coluna W em diante)
    aux_col = 22
    aux_row = 200

    for _, prow in perguntas.iterrows():
        pid    = prow["pergunta_id"]
        ptexto = prow["pergunta"]
        pnum   = int(prow["pergunta_numero"])

        df_pct = calcular_percentual_pergunta(df_estruturado, pid, bloco_nome)
        total  = int(df_pct["quantidade"].sum())

        # Linha de título da pergunta
        ws.merge_range(r, 0, r, len(ORDEM_RESPOSTAS) + 1,
                       f"{pnum}. {ptexto}", fmt.titulo_pergunta)
        ws.set_row(r, 40)
        r += 1

        # Linha de quantidades
        ws.write(r, 0, "Quantidade", fmt.celula_label)
        for i, cat in enumerate(ORDEM_RESPOSTAS, start=1):
            qty_row = df_pct[df_pct["resposta_normalizada"] == cat]
            qty = int(qty_row["quantidade"].iloc[0]) if not qty_row.empty else 0
            ws.write(r, i, qty, fmt.celula_numero)
        ws.write(r, len(ORDEM_RESPOSTAS) + 1, total, fmt.celula_media)
        r += 1

        # Linha de percentuais
        ws.write(r, 0, "Percentual (%)", fmt.celula_label)
        for i, cat in enumerate(ORDEM_RESPOSTAS, start=1):
            pct_row = df_pct[df_pct["resposta_normalizada"] == cat]
            pct = float(pct_row["percentual"].iloc[0]) if not pct_row.empty else 0.0
            ws.write(r, i, f"{pct:.1f}%", fmt.celula_pct_texto)
        ws.write(r, len(ORDEM_RESPOSTAS) + 1, "100%", fmt.celula_pct_texto)
        r += 1

        # Espaço para gráfico (14 linhas) + gráfico
        grafico_cell = f"A{r + 1}"
        aux_row = inserir_grafico_pergunta(
            workbook=wb, worksheet=ws,
            df_pct=df_pct,
            titulo_pergunta=ptexto,
            cell_insert=grafico_cell,
            aux_start_row=aux_row,
            aux_start_col=aux_col,
            sheet_name=nome_aba,
        )
        r += 15  # espaço vertical reservado para o gráfico

        # Separador visual entre perguntas
        r += 1


# ---------------------------------------------------------------------------
# Aba: Descritivas
# ---------------------------------------------------------------------------

def _escrever_aba_descritivas(
    wb: Workbook,
    fmt: Formatos,
    df_descritivas: pd.DataFrame,
    n_blocos_quantitativos: int,
) -> None:
    ws: Worksheet = wb.add_worksheet("Descritivas")
    ws.set_zoom(90)
    ws.set_column(0, 0, 8)    # nº
    ws.set_column(1, 1, 80)   # resposta
    ws.set_row(0, 30)

    ws.merge_range("A1:B1", "RESPOSTAS DESCRITIVAS", fmt.titulo_bloco)

    if df_descritivas is None or df_descritivas.empty:
        ws.write("A2", "Nenhuma resposta descritiva disponível.", fmt.info_valor)
        return

    perguntas_desc = (
        df_descritivas[["bloco_numero", "pergunta_numero", "bloco", "pergunta_id", "pergunta"]]
        .drop_duplicates()
        .sort_values(["bloco_numero", "pergunta_numero"])
    )

    # Adiciona subheader se existir
    if "subheader" in df_descritivas.columns:
        sub_map = (
            df_descritivas[["pergunta_id", "subheader"]]
            .drop_duplicates("pergunta_id")
            .set_index("pergunta_id")["subheader"]
            .to_dict()
        )
    else:
        sub_map = {}

    r = 1
    contador_global = 1

    # Calcula índice sequencial de bloco após os blocos quantitativos
    blocos_ordem = (
        perguntas_desc[["bloco_numero", "bloco"]]
        .drop_duplicates()
        .sort_values("bloco_numero")
        .reset_index(drop=True)
    )
    blocos_ordem["bloco_seq"] = blocos_ordem.index + n_blocos_quantitativos + 1

    perguntas_desc = perguntas_desc.merge(
        blocos_ordem, on=["bloco_numero", "bloco"], how="left"
    )

    for _, prow in perguntas_desc.iterrows():
        pid    = prow["pergunta_id"]
        ptexto = prow["pergunta"]
        pnum   = int(prow["pergunta_numero"])
        bloco  = prow["bloco"]
        bseq   = int(prow.get("bloco_seq", 0))
        psub   = sub_map.get(pid)

        # Título do bloco
        ws.merge_range(r, 0, r, 1, f"{bseq}. {bloco}", fmt.info_label)
        ws.set_row(r, 20)
        r += 1

        # Título da pergunta
        ws.merge_range(r, 0, r, 1, f"{pnum}. {ptexto}", fmt.titulo_pergunta)
        ws.set_row(r, 35)
        r += 1

        # Subheader (instrução complementar da pergunta)
        if psub and str(psub).strip() and str(psub) != "nan":
            ws.merge_range(r, 0, r, 1, str(psub), fmt.celula_texto)
            ws.set_row(r, 18)
            r += 1

        # Respostas da pergunta
        respostas_perg = (
            df_descritivas[
                (df_descritivas["pergunta_id"] == pid)
                & df_descritivas["resposta"].notna()
                & (df_descritivas["resposta"].str.strip() != "")
            ]
            .sort_values("created_at")
            ["resposta"]
            .tolist()
        )

        if not respostas_perg:
            ws.merge_range(r, 0, r, 1, "Nenhuma resposta.", fmt.celula_texto)
            r += 1
        else:
            for resp in respostas_perg:
                ws.write(r, 0, contador_global, fmt.resposta_num)
                ws.write(r, 1, str(resp),        fmt.resposta_texto)
                ws.set_row(r, max(18, min(80, len(str(resp)) // 3)))
                r += 1
                contador_global += 1

        r += 1  # espaço entre perguntas


# ---------------------------------------------------------------------------
# Aba: Dados Brutos
# ---------------------------------------------------------------------------

def _escrever_aba_dados_brutos(
    wb: Workbook,
    fmt: Formatos,
    df_estruturado: pd.DataFrame,
    df_filtrado: pd.DataFrame,
) -> None:
    ws: Worksheet = wb.add_worksheet("Dados Brutos")
    ws.set_zoom(85)

    if df_estruturado is None or df_estruturado.empty:
        ws.write("A1", "Sem dados disponíveis.", fmt.info_valor)
        return

    colunas_export = [
        "id", "survey_id", "created_at", "setor", "finished",
        "bloco", "pergunta_numero", "pergunta",
        "resposta", "resposta_normalizada", "valor",
    ]
    colunas_presentes = [c for c in colunas_export if c in df_estruturado.columns]
    df_export = df_estruturado[colunas_presentes].copy()

    # Larguras de coluna
    col_widths = {
        "id": 38, "survey_id": 30, "created_at": 20, "setor": 18,
        "finished": 10, "bloco": 30, "pergunta_numero": 10,
        "pergunta": 50, "resposta": 30, "resposta_normalizada": 25, "valor": 8,
    }
    for i, col in enumerate(colunas_presentes):
        ws.set_column(i, i, col_widths.get(col, 18))

    # Cabeçalho
    for i, col in enumerate(colunas_presentes):
        ws.write(0, i, col.replace("_", " ").title(), fmt.cabecalho_tabela)

    ws.freeze_panes(1, 0)
    ws.autofilter(0, 0, 0, len(colunas_presentes) - 1)

    # Dados
    for r_idx, (_, row) in enumerate(df_export.iterrows(), start=1):
        for c_idx, col in enumerate(colunas_presentes):
            val = row[col]
            if pd.isna(val):
                ws.write(r_idx, c_idx, "", fmt.celula_valor)
            elif col in ("pergunta", "resposta", "resposta_normalizada", "setor", "bloco"):
                ws.write(r_idx, c_idx, str(val), fmt.celula_texto)
            elif col == "valor":
                try:
                    ws.write(r_idx, c_idx, float(val), fmt.celula_valor)
                except (ValueError, TypeError):
                    ws.write(r_idx, c_idx, str(val), fmt.celula_valor)
            elif col == "created_at":
                ws.write(r_idx, c_idx, str(val), fmt.celula_valor)
            else:
                ws.write(r_idx, c_idx, str(val), fmt.celula_valor)


# ---------------------------------------------------------------------------
# Função principal pública
# ---------------------------------------------------------------------------

def gerar_relatorio_excel(
    arquivo_saida: str,
    nome_pesquisa: str,
    total_respostas: int,
    media_geral: str,
    df_filtrado: pd.DataFrame,
    df_respostas_quantitativas: pd.DataFrame,
    df_respostas_estruturadas: pd.DataFrame,
    df_respostas_descritivas: pd.DataFrame,
    filtro_finished: bool = False,
    filtro_not_finished: bool = False,
) -> None:
    """
    Gera o arquivo .xlsx completo.

    Parâmetros espelham exatamente os de gerar_relatorio_pdf() em exportar_pdf.R
    para facilitar a integração no dashboard.R.
    """

    # Texto do filtro (mesma lógica do relatorio_pdf.Rmd)
    if filtro_finished:
        filtro_texto = "Apenas respostas finalizadas"
    elif filtro_not_finished:
        filtro_texto = "Apenas respostas NÃO finalizadas"
    else:
        filtro_texto = "Todas as respostas"

    data_exportacao = datetime.now().strftime("%d/%m/%Y %H:%M")

    wb = xlsxwriter.Workbook(arquivo_saida, {"strings_to_urls": False})
    wb.set_properties({
        "title":   f"Relatório de Clima Organizacional – {nome_pesquisa}",
        "author":  "Dashboard Formbricks",
        "created": datetime.now(),
    })

    fmt = Formatos(wb)

    # ---- Aba Resumo ----
    _escrever_aba_resumo(
        wb=wb, fmt=fmt,
        nome_pesquisa=nome_pesquisa,
        total_respostas=total_respostas,
        media_geral=media_geral,
        filtro_texto=filtro_texto,
        data_exportacao=data_exportacao,
        df_filtrado=df_filtrado,
        df_respostas_quantitativas=df_respostas_quantitativas,
    )

    # ---- Abas por bloco ----
    blocos = obter_blocos_unicos(df_respostas_estruturadas) if df_respostas_estruturadas is not None else []
    nomes_abas = _nomes_abas_unicos(blocos)
    n_blocos_quantitativos = len(blocos)

    for bloco_info, nome_aba in nomes_abas:
        _escrever_aba_bloco(
            wb=wb, fmt=fmt,
            nome_aba=nome_aba,
            bloco_nome=bloco_info,
            df_estruturado=df_respostas_estruturadas,
        )

    # ---- Aba Descritivas ----
    _escrever_aba_descritivas(
        wb=wb, fmt=fmt,
        df_descritivas=df_respostas_descritivas,
        n_blocos_quantitativos=n_blocos_quantitativos,
    )

    # ---- Aba Dados Brutos ----
    _escrever_aba_dados_brutos(
        wb=wb, fmt=fmt,
        df_estruturado=df_respostas_estruturadas,
        df_filtrado=df_filtrado,
    )

    wb.close()
