"""
Tratamento, normalização e estruturação dos dados.

Espelha:
  - transformacoes.R  → limpar_texto, limpar_setor, extrair_setor_url,
                        normalizar_e_valorizar_resposta, desambiguar_labels
  - vincular_respostas.R → montar_mapa_perguntas, vincular_respostas,
                           montar_mapa_perguntas_descritivas,
                           vincular_respostas_descritivas
  - reativos.R        → estruturar_respostas, estruturar_respostas_descritivas,
                        processar_respostas_longas
"""

from __future__ import annotations

import json
import re
import unicodedata
from typing import Optional
from urllib.parse import unquote_plus

import pandas as pd

from python.database.queries import extrair_respostas_por_hash

# ---------------------------------------------------------------------------
# Constantes (espelham config/constantes.R)
# ---------------------------------------------------------------------------

VALOR_RESPOSTA: dict[str, float] = {
    "Discordo totalmente": 0.0,
    "Discordo":            2.5,
    "Neutro":              5.0,
    "Concordo":            7.5,
    "Concordo totalmente": 10.0,
}

NORMALIZAR_RESPOSTA: dict[str, str] = {
    "Discordo totalmente":             "Discordo totalmente",
    "Estoy totalmente en desacuerdo":  "Discordo totalmente",
    "Je suis tout à fait en désaccord":"Discordo totalmente",
    "Discordo":                        "Discordo",
    "Estoy en desacuerdo":             "Discordo",
    "Je ne suis pas d'accord":         "Discordo",
    "Neutro":                          "Neutro",
    "Neutral":                         "Neutro",
    "Neutre":                          "Neutro",
    "Concordo":                        "Concordo",
    "Estoy de acuerdo":                "Concordo",
    "Je suis d'accord":                "Concordo",
    "Concordo totalmente":             "Concordo totalmente",
    "Estoy totalmente de acuerdo":     "Concordo totalmente",
    "Je suis tout à fait d'accord":    "Concordo totalmente",
}

# Regex que identifica nomes genéricos de bloco (Block 1, Bloco 2 …)
PADRAO_BLOCO_GENERICO = re.compile(r"^(Block|Bloco)\s*[0-9]+$", re.IGNORECASE)

ORDEM_RESPOSTAS = list(VALOR_RESPOSTA.keys())  # ordem canônica das 5 categorias

# ---------------------------------------------------------------------------
# transformacoes.R — limpeza de texto
# ---------------------------------------------------------------------------

def limpar_texto(texto: Optional[str]) -> str:
    """
    Espelha limpar_texto() de transformacoes.R.
    Remove underscores, caracteres especiais, normaliza espaços e capitaliza.
    """
    if not texto:
        return ""

    s = str(texto)
    s = s.replace("_", " ")

    # Remove tudo que não seja letra Unicode, dígito ou espaço
    s = re.sub(r"[^\w\s]", "", s)
    # Remove underscores remanescentes (foram incluídos em \w)
    s = s.replace("_", "")
    s = " ".join(s.split())
    s = s.strip().title()

    return s if s else "Sem definição"


def limpar_setor(setor: Optional[str]) -> str:
    """Espelha limpar_setor() de transformacoes.R."""
    s = limpar_texto(setor)
    return "HRO" if s == "Sem definição" else s


def desambiguar_labels(labels: list[str]) -> list[str]:
    """
    Espelha desambiguar_labels() de transformacoes.R.
    Se dois labels forem iguais, sufixar com (1), (2) …
    """
    if len(labels) == len(set(labels)):
        return labels

    result = labels.copy()
    from collections import defaultdict
    groups: dict[str, list[int]] = defaultdict(list)
    for i, lbl in enumerate(labels):
        groups[lbl].append(i)

    for lbl, idxs in groups.items():
        if len(idxs) > 1:
            for k, idx in enumerate(idxs, start=1):
                result[idx] = f"{lbl} ({k})"

    return result


def extrair_setor_url(url: Optional[str]) -> str:
    """
    Extrai o setor a partir do parâmetro ?setor= da URL.
    Espelha extrair_setor_url() de transformacoes.R.
    """
    if not url:
        return "HRO"

    match = re.search(r"[?&]setor=([^&]+)", url)
    if not match:
        return "HRO"

    setor_raw = unquote_plus(match.group(1))
    return limpar_setor(setor_raw)


# ---------------------------------------------------------------------------
# vincular_respostas.R — parsing de blocos JSON
# ---------------------------------------------------------------------------

def _remover_prefixo_numerico(texto: str) -> str:
    """Espelha remover_prefixo_numerico() de vincular_respostas.R."""
    return re.sub(r"^\d+\.\s*", "", texto.strip()).strip()


def _limpar_headline_formbricks(headline: Optional[str]) -> list[str]:
    """
    Limpa o texto de uma headline do Formbricks (HTML → texto puro).
    Espelha limpar_headline_formbricks() de vincular_respostas.R.
    """
    if not headline:
        return []

    texto = str(headline)
    # <br> e </p> viram quebra de linha
    texto = re.sub(r"(?i)<br\s*/?>", "\n", texto)
    texto = re.sub(r"(?i)</p\s*>", "\n", texto)
    # Remove demais tags HTML
    texto = re.sub(r"<[^>]+>", "", texto)
    # Entidades HTML comuns
    texto = (texto
             .replace("&nbsp;", " ")
             .replace("\u00A0", " ")
             .replace("&amp;",  "&")
             .replace("&quot;", '"')
             .replace("&#39;",  "'"))

    linhas = [" ".join(l.split()).strip() for l in texto.split("\n")]
    return [l for l in linhas if l]


def _obter_headline(elemento: dict) -> Optional[str]:
    """
    Extrai o texto da headline de um elemento do bloco.
    Espelha obter_headline() de vincular_respostas.R.
    """
    headline = elemento.get("headline")
    if headline is None:
        return None
    if isinstance(headline, str):
        return headline
    if isinstance(headline, dict):
        if "default" in headline:
            return str(headline["default"])
        if headline:
            return str(next(iter(headline.values())))
    return None


def _montar_mapa_blocos_json_interno(
    blocks_json: str,
    survey_id: str,
    modo: str,  # "escala" ou "descritiva"
) -> pd.DataFrame:
    """
    Faz o parsing do JSON de blocos de uma survey.
    Espelha montar_mapa_blocos_json_interno() de vincular_respostas.R.

    modo='escala'     → inclui todas as perguntas exceto openText
    modo='descritiva' → inclui apenas perguntas openText
    """
    if not blocks_json:
        return pd.DataFrame()

    try:
        blocos = json.loads(blocks_json)
    except (json.JSONDecodeError, TypeError):
        return pd.DataFrame()

    if isinstance(blocos, str):
        try:
            blocos = json.loads(blocos)
        except Exception:
            return pd.DataFrame()

    # Normaliza: pode vir como dict único ou lista
    if isinstance(blocos, dict):
        if "id" in blocos and "elements" in blocos:
            blocos = [blocos]
        else:
            blocos = list(blocos.values())

    if not isinstance(blocos, list):
        return pd.DataFrame()

    # Desempacota strings internas
    parsed = []
    for b in blocos:
        if isinstance(b, str):
            try:
                b = json.loads(b)
            except Exception:
                continue
        if isinstance(b, dict) and "elements" in b:
            parsed.append(b)
    blocos = parsed

    if not blocos:
        return pd.DataFrame()

    rows = []

    for bloco_numero, bloco in enumerate(blocos, start=1):
        elementos = bloco.get("elements")
        if not elementos:
            continue

        bloco_nome_original = bloco.get("name", f"Bloco {bloco_numero}")
        bloco_hash = bloco.get("id")

        # O nome do bloco vem do headline do primeiro elemento
        primeiro = elementos[0]
        first_headline = _obter_headline(primeiro)
        primeiras_linhas = _limpar_headline_formbricks(first_headline)

        if not primeiras_linhas:
            continue

        bloco_nome = primeiras_linhas[0].strip()

        # Descarta blocos genéricos (Block 1, Bloco 2 …)
        if not bloco_nome or PADRAO_BLOCO_GENERICO.match(bloco_nome):
            continue

        bloco_nome = _remover_prefixo_numerico(bloco_nome)
        if not bloco_nome:
            continue

        for pergunta_numero, elemento in enumerate(elementos, start=1):
            if not elemento.get("id"):
                continue

            tipo_pergunta = elemento.get("type")

            # Filtro por modo
            if modo == "escala":
                if tipo_pergunta in ("openText", "rating"):
                    continue
            elif modo == "descritiva":
                if tipo_pergunta != "openText":
                    continue
            else:  # rating
                if tipo_pergunta != "rating":
                    continue

            pergunta_id = str(elemento["id"])
            headline    = _obter_headline(elemento)
            linhas      = _limpar_headline_formbricks(headline)

            # Remove o nome do bloco se repetido na primeira linha da primeira pergunta
            if (pergunta_numero == 1
                    and len(linhas) >= 2
                    and _remover_prefixo_numerico(linhas[0].strip()) == bloco_nome.strip()):
                linhas = linhas[1:]

            if modo == "descritiva":
                pergunta_texto = _remover_prefixo_numerico(" ".join(linhas))
            else:
                pergunta_texto = " ".join(linhas)

            row = {
                "survey_id":           str(survey_id),
                "bloco_numero":        bloco_numero,
                "bloco_hash":          bloco_hash,
                "bloco":               bloco_nome,
                "bloco_nome_original": bloco_nome_original,
                "pergunta_numero":     pergunta_numero,
                "pergunta_id":         pergunta_id,
                "pergunta":            pergunta_texto,
                "tipo_pergunta":       tipo_pergunta,
            }

            if modo == "descritiva":
                subheader_raw = elemento.get("subheader")
                if isinstance(subheader_raw, str):
                    sub = subheader_raw
                elif isinstance(subheader_raw, dict):
                    sub = str(subheader_raw.get("default", "") or next(iter(subheader_raw.values()), ""))
                else:
                    sub = ""
                # Remove tags HTML
                sub = re.sub(r"<[^>]+>", "", sub).strip()
                row["subheader"] = sub if sub else None

            rows.append(row)

    if not rows:
        return pd.DataFrame()

    return pd.DataFrame(rows)


def montar_mapa_perguntas_rating(surveys_db: pd.DataFrame) -> pd.DataFrame:
    """
    Constrói o mapa de perguntas de avaliação (rating, ex: estrelas).
    Análogo a montar_mapa_perguntas_descritivas(), mas para tipo 'rating'.
    """
    if surveys_db is None or surveys_db.empty:
        return pd.DataFrame()

    partes = []
    for _, row in surveys_db.iterrows():
        df = _montar_mapa_blocos_json_interno(
            blocks_json=row["blocks_json"],
            survey_id=row["survey_id"],
            modo="rating",
        )
        if not df.empty:
            partes.append(df)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)
    resultado = resultado.drop_duplicates(subset=["survey_id", "pergunta_id"])
    resultado = resultado.sort_values(["survey_id", "bloco_numero", "pergunta_numero"])
    return resultado.reset_index(drop=True)


def vincular_respostas_rating(
    json_data: str,
    survey_id: str,
    mapa_rating: pd.DataFrame,
) -> pd.DataFrame:
    """
    Vincula o JSON de uma resposta ao mapa de perguntas de avaliação (rating).
    Retorna DataFrame com colunas [pergunta_id, pergunta, resposta (numérica)].
    """
    respostas = extrair_respostas_por_hash(json_data)
    if respostas.empty or mapa_rating.empty:
        return pd.DataFrame()

    mapa_survey = mapa_rating[mapa_rating["survey_id"] == str(survey_id)].copy()
    if mapa_survey.empty:
        return pd.DataFrame()

    resultado = respostas.merge(mapa_survey, on="pergunta_id", how="inner")
    if resultado.empty:
        return pd.DataFrame()

    # Converte a resposta para numérico (estrelas: 1–5)
    resultado["valor_rating"] = pd.to_numeric(resultado["resposta"], errors="coerce")

    return resultado[resultado["valor_rating"].notna()].reset_index(drop=True)


def estruturar_respostas_rating(
    df_filtrado: pd.DataFrame,
    mapa_rating: pd.DataFrame,
) -> pd.DataFrame:
    """
    Estrutura todas as respostas de avaliação (rating).
    Retorna DataFrame com colunas [id, survey_id, created_at, setor,
    finished, pergunta_id, pergunta, resposta, valor_rating].
    """
    if df_filtrado is None or df_filtrado.empty:
        return pd.DataFrame()
    if mapa_rating is None or mapa_rating.empty:
        return pd.DataFrame()

    partes = []
    for _, row in df_filtrado.iterrows():
        vinculadas = vincular_respostas_rating(
            json_data=row["data"],
            survey_id=row["survey_id"],
            mapa_rating=mapa_rating,
        )
        if vinculadas.empty:
            continue

        vinculadas["id"]         = row["id"]
        vinculadas["created_at"] = row["created_at"]
        vinculadas["setor"]      = row.get("setor", "HRO")
        vinculadas["finished"]   = row["finished"]
        partes.append(vinculadas)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)
    return resultado.sort_values("created_at").reset_index(drop=True)


def montar_mapa_perguntas(surveys_db: pd.DataFrame) -> pd.DataFrame:
    """
    Constrói o mapa de perguntas (escala) a partir dos surveys.
    Espelha montar_mapa_perguntas() de vincular_respostas.R.
    """
    if surveys_db is None or surveys_db.empty:
        return pd.DataFrame()

    partes = []
    for _, row in surveys_db.iterrows():
        df = _montar_mapa_blocos_json_interno(
            blocks_json=row["blocks_json"],
            survey_id=row["survey_id"],
            modo="escala",
        )
        if not df.empty:
            partes.append(df)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)
    resultado = resultado.drop_duplicates(subset=["survey_id", "pergunta_id"])
    resultado = resultado.sort_values(["survey_id", "bloco_numero", "pergunta_numero"])
    return resultado.reset_index(drop=True)


def montar_mapa_perguntas_descritivas(surveys_db: pd.DataFrame) -> pd.DataFrame:
    """
    Constrói o mapa de perguntas descritivas (openText).
    Espelha montar_mapa_perguntas_descritivas() de vincular_respostas.R.
    """
    if surveys_db is None or surveys_db.empty:
        return pd.DataFrame()

    partes = []
    for _, row in surveys_db.iterrows():
        df = _montar_mapa_blocos_json_interno(
            blocks_json=row["blocks_json"],
            survey_id=row["survey_id"],
            modo="descritiva",
        )
        if not df.empty:
            partes.append(df)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)
    resultado = resultado.drop_duplicates(subset=["survey_id", "pergunta_id"])
    resultado = resultado.sort_values(["survey_id", "bloco_numero", "pergunta_numero"])
    return resultado.reset_index(drop=True)


# ---------------------------------------------------------------------------
# reativos.R + vincular_respostas.R — vinculação e estruturação
# ---------------------------------------------------------------------------

def vincular_respostas(
    json_data: str,
    survey_id: str,
    mapa_perguntas: pd.DataFrame,
) -> pd.DataFrame:
    """
    Vincula o JSON de uma resposta ao mapa de perguntas (escala).
    Espelha vincular_respostas() de vincular_respostas.R.
    """
    respostas = extrair_respostas_por_hash(json_data)
    if respostas.empty or mapa_perguntas.empty:
        return pd.DataFrame()

    mapa_survey = mapa_perguntas[mapa_perguntas["survey_id"] == str(survey_id)].copy()
    if mapa_survey.empty:
        return pd.DataFrame()

    resultado = respostas.merge(mapa_survey, on="pergunta_id", how="inner")
    if resultado.empty:
        return pd.DataFrame()

    resultado["resposta_limpa"]        = resultado["resposta"].str.strip()
    resultado["resposta_normalizada"]  = resultado["resposta_limpa"].map(NORMALIZAR_RESPOSTA)
    resultado["valor"]                 = resultado["resposta_normalizada"].map(VALOR_RESPOSTA)

    return resultado.sort_values(["bloco_numero", "pergunta_numero"]).reset_index(drop=True)


def vincular_respostas_descritivas(
    json_data: str,
    survey_id: str,
    mapa_descritivas: pd.DataFrame,
) -> pd.DataFrame:
    """
    Vincula o JSON de uma resposta ao mapa de perguntas descritivas.
    Espelha vincular_respostas_descritivas() de vincular_respostas.R.
    """
    respostas = extrair_respostas_por_hash(json_data)
    if respostas.empty or mapa_descritivas.empty:
        return pd.DataFrame()

    mapa_survey = mapa_descritivas[mapa_descritivas["survey_id"] == str(survey_id)].copy()
    if mapa_survey.empty:
        return pd.DataFrame()

    resultado = respostas.merge(mapa_survey, on="pergunta_id", how="inner")
    if resultado.empty:
        return pd.DataFrame()

    resultado["resposta"] = resultado["resposta"].str.strip()
    resultado = resultado[resultado["resposta"].notna() & (resultado["resposta"] != "")]

    return resultado.sort_values(["bloco_numero", "pergunta_numero"]).reset_index(drop=True)


def estruturar_respostas(
    df_filtrado: pd.DataFrame,
    mapa_perguntas: pd.DataFrame,
) -> pd.DataFrame:
    """
    Estrutura todas as respostas quantitativas (escala).
    Espelha estruturar_respostas() de reativos.R.
    """
    if df_filtrado is None or df_filtrado.empty:
        return pd.DataFrame()
    if mapa_perguntas is None or mapa_perguntas.empty:
        return pd.DataFrame()

    partes = []
    for _, row in df_filtrado.iterrows():
        vinculadas = vincular_respostas(
            json_data=row["data"],
            survey_id=row["survey_id"],
            mapa_perguntas=mapa_perguntas,
        )
        if vinculadas.empty:
            continue

        vinculadas["id"]         = row["id"]
        vinculadas["created_at"] = row["created_at"]
        vinculadas["updated_at"] = row["updated_at"]
        vinculadas["setor"]      = row.get("setor", "HRO")
        vinculadas["finished"]   = row["finished"]
        partes.append(vinculadas)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)

    colunas = [
        "id", "survey_id", "created_at", "updated_at", "setor", "finished",
        "bloco_numero", "bloco_hash", "bloco", "bloco_nome_original",
        "pergunta_numero", "pergunta_id", "pergunta", "tipo_pergunta",
        "resposta", "resposta_limpa", "resposta_normalizada", "valor",
    ]
    colunas_presentes = [c for c in colunas if c in resultado.columns]
    resultado = resultado[colunas_presentes]

    return resultado.sort_values(["bloco_numero", "pergunta_numero", "created_at"]).reset_index(drop=True)


def estruturar_respostas_descritivas(
    df_filtrado: pd.DataFrame,
    mapa_descritivas: pd.DataFrame,
) -> pd.DataFrame:
    """
    Estrutura todas as respostas descritivas (openText).
    Espelha estruturar_respostas_descritivas() de reativos.R.

    Nota: no dashboard.R as descritivas usam dados_por_survey() em vez de
    dados_filtrados() — o chamador deve passar o DataFrame correto.
    """
    if df_filtrado is None or df_filtrado.empty:
        return pd.DataFrame()
    if mapa_descritivas is None or mapa_descritivas.empty:
        return pd.DataFrame()

    partes = []
    for _, row in df_filtrado.iterrows():
        vinculadas = vincular_respostas_descritivas(
            json_data=row["data"],
            survey_id=row["survey_id"],
            mapa_descritivas=mapa_descritivas,
        )
        if vinculadas.empty:
            continue

        vinculadas["id"]         = row["id"]
        vinculadas["created_at"] = row["created_at"]
        vinculadas["setor"]      = row.get("setor", "HRO")
        vinculadas["finished"]   = row["finished"]
        partes.append(vinculadas)

    if not partes:
        return pd.DataFrame()

    resultado = pd.concat(partes, ignore_index=True)

    colunas = [
        "id", "survey_id", "created_at", "setor", "finished",
        "bloco_numero", "bloco", "pergunta_numero", "pergunta_id",
        "pergunta", "subheader", "resposta",
    ]
    colunas_presentes = [c for c in colunas if c in resultado.columns]
    resultado = resultado[colunas_presentes]

    return resultado.sort_values(["bloco_numero", "pergunta_numero", "created_at"]).reset_index(drop=True)


def enriquecer_respostas(df_respostas: pd.DataFrame) -> pd.DataFrame:
    """
    Adiciona colunas setor e respostas_lista ao DataFrame bruto de respostas.
    Equivale ao bloco observe() do dashboard.R que processa meta_url → setor.
    """
    if df_respostas.empty:
        return df_respostas

    df = df_respostas.copy()
    df["setor"] = df["meta_url"].apply(extrair_setor_url)
    return df


def obter_blocos_unicos(df_estruturado: pd.DataFrame) -> list[dict]:
    """
    Retorna lista de {bloco_numero, bloco} únicos, ordenados.
    Espelha obter_blocos_unicos() de filtros.R (sem a parte do label UI).
    """
    if df_estruturado.empty:
        return []

    blocos = (
        df_estruturado[
            df_estruturado["bloco"].notna()
            & (df_estruturado["bloco"] != "")
            & ~df_estruturado["bloco"].str.match(PADRAO_BLOCO_GENERICO, na=False)
        ]
        [["bloco_numero", "bloco"]]
        .drop_duplicates()
        .sort_values("bloco_numero")
    )

    return blocos.to_dict("records")


def obter_perguntas_bloco(df_estruturado: pd.DataFrame, bloco_nome: str) -> pd.DataFrame:
    """
    Retorna as perguntas de um bloco específico, ordenadas.
    Espelha obter_perguntas_bloco() de filtros.R.
    """
    if df_estruturado.empty:
        return pd.DataFrame()

    return (
        df_estruturado[df_estruturado["bloco"] == bloco_nome]
        [["pergunta_numero", "pergunta_id", "pergunta"]]
        .drop_duplicates()
        .sort_values("pergunta_numero")
        .reset_index(drop=True)
    )
