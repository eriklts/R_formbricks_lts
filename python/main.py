"""
Ponto de entrada da exportação Excel.

Chamado pelo dashboard.R via system2():

    python3 python/main.py \\
        --output /tmp/relatorio.xlsx \\
        --survey-id <id_ou___TODAS__> \\
        --nome-pesquisa "Nome da pesquisa" \\
        [--finished | --not-finished]

O script:
  1. Conecta diretamente ao PostgreSQL
  2. Busca surveys e respostas (respeitando os filtros recebidos)
  3. Processa e estrutura os dados (mesma lógica do R)
  4. Calcula estatísticas
  5. Gera o arquivo .xlsx
  6. Sai com código 0 (sucesso) ou 1 (erro)

Saída: imprime "OK:<caminho_do_arquivo>" em stdout no sucesso,
       ou "ERRO:<mensagem>" em stderr no fracasso.
"""

from __future__ import annotations

import argparse
import sys
import os
import traceback

# Garante que o diretório raiz do projeto está no sys.path,
# independentemente de onde o script é chamado.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from python.database.connection import get_connection
from python.database.queries import fetch_responses, fetch_surveys_with_blocks
from python.export.excel_export import gerar_relatorio_excel
from python.processing.data_processing import (
    enriquecer_respostas,
    estruturar_respostas,
    estruturar_respostas_descritivas,
    montar_mapa_perguntas,
    montar_mapa_perguntas_descritivas,
)
from python.processing.statistics import calcular_media_geral


# ---------------------------------------------------------------------------
# Argumentos CLI
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Gera relatório Excel a partir do PostgreSQL Formbricks."
    )
    parser.add_argument(
        "--output", required=True,
        help="Caminho completo do arquivo .xlsx a ser gerado.",
    )
    parser.add_argument(
        "--survey-id", default="__TODAS__",
        help="ID da survey filtrada, ou '__TODAS__' para todas.",
    )
    parser.add_argument(
        "--nome-pesquisa", default="Todas as pesquisas",
        help="Nome legível da pesquisa (usado no cabeçalho do relatório).",
    )
    parser.add_argument(
        "--finished", action="store_true", default=False,
        help="Incluir apenas respostas com finished=TRUE.",
    )
    parser.add_argument(
        "--not-finished", action="store_true", default=False,
        help="Incluir apenas respostas com finished=FALSE.",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Pipeline principal
# ---------------------------------------------------------------------------

def executar(args: argparse.Namespace) -> None:
    survey_id       = args.survey_id if args.survey_id != "__TODAS__" else None
    only_finished   = args.finished
    only_not_fin    = args.not_finished
    nome_pesquisa   = args.nome_pesquisa
    arquivo_saida   = args.output

    # 1. Conexão
    conn = get_connection()

    try:
        # 2. Busca dados brutos do banco
        df_respostas = fetch_responses(
            conn=conn,
            survey_id=survey_id,
            only_finished=only_finished,
            only_not_finished=only_not_fin,
        )

        surveys_db = fetch_surveys_with_blocks(conn)

    finally:
        conn.close()

    # 3. Enriquece com setor (extrai da meta_url, igual ao R)
    if not df_respostas.empty:
        df_respostas = enriquecer_respostas(df_respostas)

    # 4. Constrói mapas de perguntas
    mapa_perguntas   = montar_mapa_perguntas(surveys_db)
    mapa_descritivas = montar_mapa_perguntas_descritivas(surveys_db)

    # 5. Estrutura respostas quantitativas
    #    Nota: estruturar_respostas usa df_filtrado (com filtro de finished),
    #    exatamente como o R usa dados_filtrados().
    df_estruturado = estruturar_respostas(df_respostas, mapa_perguntas)

    # 6. Respostas quantitativas (apenas com resposta_normalizada válida)
    #    Espelha respostas_quantitativas() do dashboard.R.
    if not df_estruturado.empty:
        df_quant = df_estruturado[
            df_estruturado["resposta_normalizada"].notna()
        ].copy()
    else:
        import pandas as pd
        df_quant = pd.DataFrame()

    # 7. Respostas descritivas
    #    No dashboard.R, descritivas usam dados_por_survey() — sem filtro de
    #    finished — pois quem preenche campo aberto pode não ter finalizado.
    #    Aqui reproduzimos esse comportamento: re-buscamos sem filtro de
    #    finished/not_finished para as descritivas, mas aplicando o filtro
    #    de survey_id.
    if survey_id:
        conn2 = get_connection()
        try:
            df_para_descritivas = fetch_responses(
                conn=conn2,
                survey_id=survey_id,
                only_finished=False,
                only_not_finished=False,
            )
        finally:
            conn2.close()
        if not df_para_descritivas.empty:
            df_para_descritivas = enriquecer_respostas(df_para_descritivas)
    else:
        # Sem filtro de survey → reutiliza todas as respostas (sem filtro de finished)
        conn3 = get_connection()
        try:
            df_para_descritivas = fetch_responses(
                conn=conn3,
                survey_id=None,
                only_finished=False,
                only_not_finished=False,
            )
        finally:
            conn3.close()
        if not df_para_descritivas.empty:
            df_para_descritivas = enriquecer_respostas(df_para_descritivas)

    df_descritivas = estruturar_respostas_descritivas(df_para_descritivas, mapa_descritivas)

    # 8. Métricas de resumo
    total_respostas = len(df_respostas)
    media_geral     = calcular_media_geral(df_quant)

    # 9. Gera o Excel
    gerar_relatorio_excel(
        arquivo_saida              = arquivo_saida,
        nome_pesquisa              = nome_pesquisa,
        total_respostas            = total_respostas,
        media_geral                = media_geral,
        df_filtrado                = df_respostas,
        df_respostas_quantitativas = df_quant,
        df_respostas_estruturadas  = df_estruturado,
        df_respostas_descritivas   = df_descritivas,
        filtro_finished            = only_finished,
        filtro_not_finished        = only_not_fin,
    )

    print(f"OK:{arquivo_saida}", flush=True)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    args = _parse_args()
    try:
        executar(args)
    except Exception as exc:
        print(f"ERRO:{exc}", file=sys.stderr, flush=True)
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
