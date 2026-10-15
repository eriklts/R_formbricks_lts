"""
Cálculos estatísticos.

Espelha as funções de reativos.R e os agregados usados em
relatorio_pdf.Rmd / graficos.R:
  - calcular_media_geral
  - calcular_distribuicao_respostas   (gráfico global de barras)
  - calcular_percentual_pergunta      (gráfico por pergunta)
  - calcular_respostas_por_data       (gráfico de linha temporal)
  - calcular_resumo_bloco             (total de respondentes por bloco)
  - calcular_media_por_setor          (gráfico de média por setor)
  - calcular_respostas_por_setor      (gráfico de contagem por setor)
"""

from __future__ import annotations

import pandas as pd

from python.processing.data_processing import (
    NORMALIZAR_RESPOSTA,
    ORDEM_RESPOSTAS,
    VALOR_RESPOSTA,
)

# Escala completa para garantir que todas as 5 categorias sempre apareçam
_ESCALA_DF = pd.DataFrame({
    "resposta_normalizada": ORDEM_RESPOSTAS,
    "ordem": range(len(ORDEM_RESPOSTAS)),
})


# ---------------------------------------------------------------------------
# calcular_media_geral — espelha calcular_media_geral() de reativos.R
# ---------------------------------------------------------------------------

def calcular_media_geral(df_respostas_quantitativas: pd.DataFrame) -> str:
    """
    Retorna a média geral no formato "X.XX / 10".
    Usa resposta_normalizada → VALOR_RESPOSTA, igual ao R.
    Retorna "-" quando não há dados.
    """
    if df_respostas_quantitativas is None or df_respostas_quantitativas.empty:
        return "-"

    col = "resposta_normalizada" if "resposta_normalizada" in df_respostas_quantitativas.columns else "resposta"
    valores = df_respostas_quantitativas[col].map(VALOR_RESPOSTA).dropna()

    if valores.empty:
        return "-"

    return f"{round(valores.mean(), 2)} / 10"


def calcular_media_geral_numerica(df_respostas_quantitativas: pd.DataFrame) -> float | None:
    """Versão numérica de calcular_media_geral para uso em células Excel."""
    if df_respostas_quantitativas is None or df_respostas_quantitativas.empty:
        return None

    col = "resposta_normalizada" if "resposta_normalizada" in df_respostas_quantitativas.columns else "resposta"
    valores = df_respostas_quantitativas[col].map(VALOR_RESPOSTA).dropna()

    return round(float(valores.mean()), 2) if not valores.empty else None


# ---------------------------------------------------------------------------
# calcular_nota_pesquisa — converte avaliação por estrelas (1–5) em nota 0–10
# ---------------------------------------------------------------------------

def calcular_nota_pesquisa(df_respostas_rating: pd.DataFrame) -> str:
    """
    Calcula a nota da pesquisa com base nas avaliações por estrelas (1–5).

    Conversão: nota = (média_estrelas - 1) / 4 * 10
      1★ → 0,0 | 3★ → 5,0 | 5★ → 10,0

    Retorna string no formato "X.X / 10" ou "-" se sem dados.
    """
    if df_respostas_rating is None or df_respostas_rating.empty:
        return "-"

    col = "valor_rating" if "valor_rating" in df_respostas_rating.columns else "resposta"
    valores = pd.to_numeric(df_respostas_rating[col], errors="coerce").dropna()

    if valores.empty:
        return "-"

    nota = round((valores.mean() - 1) / 4 * 10, 1)
    return f"{nota} / 10"


def calcular_nota_pesquisa_numerica(df_respostas_rating: pd.DataFrame) -> float | None:
    """Versão numérica de calcular_nota_pesquisa para uso em células Excel."""
    if df_respostas_rating is None or df_respostas_rating.empty:
        return None

    col = "valor_rating" if "valor_rating" in df_respostas_rating.columns else "resposta"
    valores = pd.to_numeric(df_respostas_rating[col], errors="coerce").dropna()

    if valores.empty:
        return None

    return round((float(valores.mean()) - 1) / 4 * 10, 1)


# ---------------------------------------------------------------------------
# calcular_distribuicao_respostas — espelha renderizar_grafico_respostas()
# ---------------------------------------------------------------------------

def calcular_distribuicao_respostas(df_respostas_quantitativas: pd.DataFrame) -> pd.DataFrame:
    """
    Distribuição global das respostas normalizadas.

    Retorna DataFrame com colunas:
      resposta_normalizada | quantidade | percentual | ordem
    Todas as 5 categorias sempre presentes (quantidade=0 quando ausente).
    """
    if df_respostas_quantitativas is None or df_respostas_quantitativas.empty:
        return _escala_vazia()

    col = "resposta_normalizada" if "resposta_normalizada" in df_respostas_quantitativas.columns else "resposta"
    df = df_respostas_quantitativas.copy()
    df["_resp_norm"] = df[col].map(NORMALIZAR_RESPOSTA).fillna(df[col])

    total = len(df)

    contagem = (
        df.groupby("_resp_norm", observed=True)
        .size()
        .reset_index(name="quantidade")
        .rename(columns={"_resp_norm": "resposta_normalizada"})
    )

    resultado = _ESCALA_DF.merge(contagem, on="resposta_normalizada", how="left")
    resultado["quantidade"] = resultado["quantidade"].fillna(0).astype(int)
    resultado["percentual"] = (resultado["quantidade"] / total * 100).round(1) if total > 0 else 0.0

    return resultado.sort_values("ordem").reset_index(drop=True)


# ---------------------------------------------------------------------------
# calcular_percentual_pergunta — espelha renderizar_grafico_percentual()
# ---------------------------------------------------------------------------

def calcular_percentual_pergunta(
    df_estruturado: pd.DataFrame,
    pergunta_id: str,
    bloco: str,
) -> pd.DataFrame:
    """
    Distribuição de respostas de uma pergunta específica dentro de um bloco.

    Retorna DataFrame com colunas:
      resposta_normalizada | quantidade | percentual | ordem
    Todas as 5 categorias sempre presentes.
    """
    if df_estruturado is None or df_estruturado.empty:
        return _escala_vazia()

    dados = df_estruturado[
        (df_estruturado["bloco"] == bloco)
        & (df_estruturado["pergunta_id"] == pergunta_id)
        & df_estruturado["resposta_normalizada"].notna()
    ]

    if dados.empty:
        return _escala_vazia()

    total = len(dados)

    contagem = (
        dados.groupby("resposta_normalizada", observed=True)
        .size()
        .reset_index(name="quantidade")
    )

    resultado = _ESCALA_DF.merge(contagem, on="resposta_normalizada", how="left")
    resultado["quantidade"] = resultado["quantidade"].fillna(0).astype(int)
    resultado["percentual"] = (resultado["quantidade"] / total * 100).round(1) if total > 0 else 0.0

    return resultado.sort_values("ordem").reset_index(drop=True)


# ---------------------------------------------------------------------------
# calcular_respostas_por_data — espelha renderizar_grafico_tempo()
# ---------------------------------------------------------------------------

def calcular_respostas_por_data(df_filtrado: pd.DataFrame) -> pd.DataFrame:
    """
    Contagem diária de respondentes únicos (por id) ao longo do tempo.

    Retorna DataFrame com colunas: data | quantidade
    """
    if df_filtrado is None or df_filtrado.empty:
        return pd.DataFrame(columns=["data", "quantidade"])

    df = df_filtrado.copy()
    df["data"] = pd.to_datetime(df["created_at"]).dt.date

    resultado = (
        df.drop_duplicates(subset=["id", "data"])
        .groupby("data")
        .size()
        .reset_index(name="quantidade")
        .sort_values("data")
    )

    return resultado.reset_index(drop=True)


# ---------------------------------------------------------------------------
# calcular_resumo_bloco — espelha total_bloco do relatorio_pdf.Rmd
# ---------------------------------------------------------------------------

def calcular_resumo_bloco(df_estruturado: pd.DataFrame, bloco: str) -> int:
    """
    Total de respondentes únicos (por id) que responderam ao bloco,
    contando apenas respostas com resposta_normalizada não nula.

    Espelha o cálculo total_bloco do relatorio_pdf.Rmd e do dashboard.R.
    """
    if df_estruturado is None or df_estruturado.empty:
        return 0

    return int(
        df_estruturado[
            (df_estruturado["bloco"] == bloco)
            & df_estruturado["resposta_normalizada"].notna()
        ]
        ["id"]
        .nunique()
    )


# ---------------------------------------------------------------------------
# calcular_media_por_setor — espelha renderizar_grafico_media()
# ---------------------------------------------------------------------------

def calcular_media_por_setor(df_respostas_quantitativas: pd.DataFrame) -> pd.DataFrame:
    """
    Média de respostas por setor, arredondada a 2 casas.

    Retorna DataFrame com colunas: setor | media
    """
    if df_respostas_quantitativas is None or df_respostas_quantitativas.empty:
        return pd.DataFrame(columns=["setor", "media"])

    df = df_respostas_quantitativas.copy()
    col = "resposta_normalizada" if "resposta_normalizada" in df.columns else "resposta"
    df["_valor"] = df[col].map(VALOR_RESPOSTA)

    resultado = (
        df.groupby("setor", observed=True)["_valor"]
        .mean()
        .round(2)
        .reset_index()
        .rename(columns={"_valor": "media"})
        .sort_values("media", ascending=False)
    )

    return resultado.reset_index(drop=True)


# ---------------------------------------------------------------------------
# calcular_respostas_por_setor — espelha renderizar_grafico_setor()
# ---------------------------------------------------------------------------

def calcular_respostas_por_setor(df_filtrado: pd.DataFrame) -> pd.DataFrame:
    """
    Contagem de links respondidos por setor (id únicos por setor).

    Retorna DataFrame com colunas: setor | quantidade
    """
    if df_filtrado is None or df_filtrado.empty:
        return pd.DataFrame(columns=["setor", "quantidade"])

    resultado = (
        df_filtrado.drop_duplicates(subset=["id", "setor"])
        .groupby("setor", observed=True)
        .size()
        .reset_index(name="quantidade")
        .sort_values("quantidade", ascending=False)
    )

    return resultado.reset_index(drop=True)


# ---------------------------------------------------------------------------
# calcular_tabela_completa_bloco — para a aba de dados brutos / resumo
# ---------------------------------------------------------------------------

def calcular_tabela_completa_bloco(
    df_estruturado: pd.DataFrame,
    bloco: str,
) -> pd.DataFrame:
    """
    Para cada pergunta do bloco, retorna contagem e percentual de cada
    categoria de resposta. Útil para a aba de resumo do Excel.

    Retorna DataFrame com colunas:
      pergunta_numero | pergunta | resposta_normalizada | quantidade | percentual | total
    """
    if df_estruturado is None or df_estruturado.empty:
        return pd.DataFrame()

    dados_bloco = df_estruturado[
        (df_estruturado["bloco"] == bloco)
        & df_estruturado["resposta_normalizada"].notna()
    ]

    if dados_bloco.empty:
        return pd.DataFrame()

    perguntas = (
        dados_bloco[["pergunta_numero", "pergunta_id", "pergunta"]]
        .drop_duplicates()
        .sort_values("pergunta_numero")
    )

    partes = []
    for _, prow in perguntas.iterrows():
        pid       = prow["pergunta_id"]
        ptexto    = prow["pergunta"]
        pnum      = prow["pergunta_numero"]

        df_perg = calcular_percentual_pergunta(df_estruturado, pid, bloco)
        total   = int(df_perg["quantidade"].sum())

        df_perg["pergunta_numero"] = pnum
        df_perg["pergunta"]        = ptexto
        df_perg["pergunta_id"]     = pid
        df_perg["total"]           = total
        partes.append(df_perg)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)
    cols = ["pergunta_numero", "pergunta_id", "pergunta",
            "resposta_normalizada", "quantidade", "percentual", "total"]
    return resultado[[c for c in cols if c in resultado.columns]]


# ---------------------------------------------------------------------------
# helper interno
# ---------------------------------------------------------------------------

def _escala_vazia() -> pd.DataFrame:
    """Retorna a escala completa com quantidade=0 e percentual=0.0."""
    df = _ESCALA_DF.copy()
    df["quantidade"] = 0
    df["percentual"] = 0.0
    return df
