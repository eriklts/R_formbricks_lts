"""
Consultas SQL ao PostgreSQL.

Espelha as funções de carregar_dados.R e vincular_respostas.R:
  - buscar_respostas_incrementais  → fetch_responses
  - buscar_blocos_pesquisas        → fetch_surveys_with_blocks
  - (filtros de survey/finished)   → aplicados aqui ou no chamador
"""

from __future__ import annotations

import json
from typing import Optional

import pandas as pd
import psycopg2.extensions

from python.database.connection import get_cursor


# ---------------------------------------------------------------------------
# Respostas
# ---------------------------------------------------------------------------

def fetch_responses(
    conn: psycopg2.extensions.connection,
    survey_id: Optional[str] = None,
    only_finished: bool = False,
    only_not_finished: bool = False,
) -> pd.DataFrame:
    """
    Busca todas as respostas da tabela Response, com filtros opcionais.

    Equivale a buscar_respostas_incrementais (sem corte de data) +
    filtros de survey/finished aplicados em dados_tratados / dados_por_survey
    do dashboard.R.

    Parâmetros
    ----------
    survey_id        : ID da pesquisa, ou None / '__TODAS__' para todas.
    only_finished    : True → apenas respostas com finished = TRUE.
    only_not_finished: True → apenas respostas com finished = FALSE.
                       Se ambos forem True, nenhum filtro é aplicado
                       (mesmo comportamento do observe() do dashboard.R).
    """
    # Quando ambos marcados, cancela os dois (ver observe() do dashboard.R)
    if only_finished and only_not_finished:
        only_finished = False
        only_not_finished = False

    conditions = []
    params: list = []

    if survey_id and survey_id != "__TODAS__":
        conditions.append('r."surveyId" = %s')
        params.append(survey_id)

    if only_finished:
        conditions.append("r.finished = TRUE")
    elif only_not_finished:
        conditions.append("r.finished = FALSE")

    where_clause = ("WHERE " + " AND ".join(conditions)) if conditions else ""

    sql = f"""
        SELECT
            r.id,
            r."surveyId"    AS survey_id,
            r.created_at,
            r.updated_at,
            r.finished,
            r.data::text    AS data,
            r.meta ->> 'url' AS meta_url
        FROM "Response" r
        {where_clause}
        ORDER BY r.created_at ASC
    """

    with get_cursor(conn) as cur:
        cur.execute(sql, params if params else None)
        rows = cur.fetchall()

    if not rows:
        return pd.DataFrame(columns=[
            "id", "survey_id", "created_at", "updated_at",
            "finished", "data", "meta_url",
        ])

    return pd.DataFrame([dict(r) for r in rows])


# ---------------------------------------------------------------------------
# Surveys / Blocos
# ---------------------------------------------------------------------------

def fetch_surveys_with_blocks(
    conn: psycopg2.extensions.connection,
) -> pd.DataFrame:
    """
    Busca surveys que possuem blocos e ao menos uma resposta.

    Equivale a buscar_blocos_pesquisas() de carregar_dados.R.
    """
    sql = """
        SELECT
            s.id            AS survey_id,
            s.name          AS survey_name,
            s.updated_at    AS survey_updated_at,
            to_jsonb(s.blocks)::text AS blocks_json
        FROM "Survey" s
        WHERE s.blocks IS NOT NULL
          AND cardinality(s.blocks) > 0
          AND EXISTS (
              SELECT 1
              FROM "Response" r
              WHERE r."surveyId" = s.id
          )
        ORDER BY s.id
    """

    with get_cursor(conn) as cur:
        cur.execute(sql)
        rows = cur.fetchall()

    if not rows:
        return pd.DataFrame(columns=[
            "survey_id", "survey_name", "survey_updated_at", "blocks_json",
        ])

    return pd.DataFrame([dict(r) for r in rows])


# ---------------------------------------------------------------------------
# Helpers de parsing JSON (equivalem a extrair_respostas_por_hash de carregar_dados.R)
# ---------------------------------------------------------------------------

def _valor_json_para_texto(valor) -> Optional[str]:
    """
    Converte um valor JSON em texto legível.
    Espelha valor_json_para_texto() de carregar_dados.R.
    """
    if valor is None:
        return None

    if isinstance(valor, (str, int, float, bool)):
        return str(valor).strip()

    if isinstance(valor, list):
        parts = [str(v).strip() for v in valor if v is not None]
        return " | ".join(parts) if parts else None

    # dict ou outro objeto
    return json.dumps(valor, ensure_ascii=False)


def extrair_respostas_por_hash(json_data: str) -> pd.DataFrame:
    """
    Extrai pares {pergunta_id: resposta} do campo data (JSON) de uma Response.

    Equivale a extrair_respostas_por_hash() de carregar_dados.R.
    Retorna DataFrame com colunas [pergunta_id, resposta].
    """
    if not json_data:
        return pd.DataFrame(columns=["pergunta_id", "resposta"])

    try:
        dados = json.loads(json_data)
    except (json.JSONDecodeError, TypeError):
        return pd.DataFrame(columns=["pergunta_id", "resposta"])

    if not isinstance(dados, dict) or not dados:
        return pd.DataFrame(columns=["pergunta_id", "resposta"])

    rows = []
    for pid, val in dados.items():
        texto = _valor_json_para_texto(val)
        if texto and texto.strip():
            rows.append({"pergunta_id": pid, "resposta": texto.strip()})

    if not rows:
        return pd.DataFrame(columns=["pergunta_id", "resposta"])

    return pd.DataFrame(rows)
