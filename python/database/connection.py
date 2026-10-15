"""
Conexão com o banco de dados PostgreSQL.

Lê as credenciais de variáveis de ambiente, com fallback para os
valores usados em config/conexao.R (ambiente de desenvolvimento local).
Não exponha este arquivo com credenciais em repositórios públicos.
"""

import os
import psycopg2
import psycopg2.extras


def get_connection_params() -> dict:
    """
    Retorna os parâmetros de conexão PostgreSQL.
    Prioridade: variáveis de ambiente > valores padrão do projeto.
    """
    return {
        "host":     os.environ.get("PG_HOST",     "179.124.146.8"),
        "port":     int(os.environ.get("PG_PORT", "5432")),
        "dbname":   os.environ.get("PG_DBNAME",   "formbricks"),
        "user":     os.environ.get("PG_USER",      "postgres"),
        "password": os.environ.get("PG_PASSWORD",  "postgres"),
    }


def get_connection() -> psycopg2.extensions.connection:
    """
    Abre e retorna uma conexão psycopg2 com o PostgreSQL.
    O chamador é responsável por fechar a conexão após o uso.
    """
    params = get_connection_params()
    conn = psycopg2.connect(**params)
    return conn


def get_cursor(conn: psycopg2.extensions.connection):
    """
    Retorna um cursor RealDictCursor (resultados como dicionários).
    """
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
