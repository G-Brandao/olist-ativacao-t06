"""Monta o banco SQLite de VALIDAÇÃO LOCAL a partir dos CSVs em ``dados/``.

Este banco existe apenas para validar as regras de negócio das features antes de
traduzi-las para Spark SQL (Databricks). Cada CSV vira uma tabela com o mesmo
nome-base que será usado em produção sob ``workspace.olist.<tabela>`` — assim a
tradução SQLite -> Spark é, na maioria dos arquivos, só prefixo + dialeto.

Uso:
    python scripts/build_sqlite.py            # gera ./olist.db
    python scripts/build_sqlite.py --db x.db  # destino alternativo

Requisitos: apenas a biblioteca padrão do Python (csv + sqlite3). Sem dependências.
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from pathlib import Path

# Raiz do repositório (este arquivo vive em scripts/).
ROOT = Path(__file__).resolve().parent.parent
DADOS = ROOT / "dados"

# Mapa: arquivo CSV  ->  nome-base da tabela (igual ao usado em workspace.olist.*).
CSV_TO_TABLE = {
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "olist_customers_dataset.csv": "customers",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_geolocation_dataset.csv": "geolocation",
    "product_category_name_translation.csv": "product_category_name_translation",
}

# Tipos explícitos só para colunas numéricas (o resto vira TEXT, inclusive datas,
# que ficam no formato 'YYYY-MM-DD HH:MM:SS' e são comparáveis lexicograficamente).
# Os erros de grafia 'lenght' são MANTIDOS de propósito (espelham o schema do Kaggle).
COLUMN_TYPES: dict[str, dict[str, str]] = {
    "order_items": {"order_item_id": "INTEGER", "price": "REAL", "freight_value": "REAL"},
    "products": {
        "product_name_lenght": "INTEGER",
        "product_description_lenght": "INTEGER",
        "product_photos_qty": "INTEGER",
        "product_weight_g": "INTEGER",
        "product_length_cm": "INTEGER",
        "product_height_cm": "INTEGER",
        "product_width_cm": "INTEGER",
    },
    "order_payments": {
        "payment_sequential": "INTEGER",
        "payment_installments": "INTEGER",
        "payment_value": "REAL",
    },
    "order_reviews": {"review_score": "INTEGER"},
    "geolocation": {"geolocation_lat": "REAL", "geolocation_lng": "REAL"},
}


def _convert(value: str, sql_type: str):
    """Normaliza um campo de texto do CSV para o tipo da coluna ('' -> NULL)."""
    if value is None or value == "":
        return None
    if sql_type == "INTEGER":
        try:
            return int(value)
        except ValueError:
            # alguns inteiros aparecem como '1.0'
            try:
                return int(float(value))
            except ValueError:
                return None
    if sql_type == "REAL":
        try:
            return float(value)
        except ValueError:
            return None
    return value


def load_table(conn: sqlite3.Connection, csv_path: Path, table: str) -> int:
    """Cria a tabela e carrega o CSV. Retorna o nº de linhas inseridas."""
    types = COLUMN_TYPES.get(table, {})
    # utf-8-sig remove o BOM (presente em product_category_name_translation.csv).
    with csv_path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        col_types = [types.get(col, "TEXT") for col in header]

        cols_ddl = ", ".join(f'"{c}" {t}' for c, t in zip(header, col_types))
        conn.execute(f'DROP TABLE IF EXISTS "{table}"')
        conn.execute(f'CREATE TABLE "{table}" ({cols_ddl})')

        placeholders = ", ".join("?" for _ in header)
        insert_sql = f'INSERT INTO "{table}" VALUES ({placeholders})'

        rows = (
            [_convert(v, t) for v, t in zip(record, col_types)]
            for record in reader
        )
        cur = conn.executemany(insert_sql, rows)
        # executemany não dá rowcount confiável em todas as versões; contamos depois.
    (count,) = conn.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description="Carrega os CSVs Olist em um SQLite.")
    parser.add_argument("--db", default=str(ROOT / "olist.db"), help="caminho do .db de saída")
    args = parser.parse_args()

    if not DADOS.is_dir():
        print(f"ERRO: pasta de dados não encontrada: {DADOS}", file=sys.stderr)
        return 1

    db_path = Path(args.db)
    conn = sqlite3.connect(db_path)
    try:
        print(f"Gerando {db_path} a partir de {DADOS}\n")
        total = 0
        for csv_name, table in CSV_TO_TABLE.items():
            csv_path = DADOS / csv_name
            if not csv_path.exists():
                print(f"  ! AVISO: {csv_name} ausente — pulando", file=sys.stderr)
                continue
            n = load_table(conn, csv_path, table)
            total += n
            print(f"  [ok] {table:<35} {n:>9,} linhas")
        conn.commit()
        print(f"\nConcluído. {total:,} linhas em {len(CSV_TO_TABLE)} tabelas.")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
