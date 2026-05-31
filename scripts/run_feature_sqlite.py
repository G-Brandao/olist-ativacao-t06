"""Executa um script de feature em ``features_sqlite/`` contra o ``olist.db`` local.

Substitui o token ``{data_corte}`` (sem aspas — as aspas já estão no .sql), roda a
query e imprime: colunas, nº de linhas, checagem de duplicidade de seller_id e uma
amostra. Serve para validar cada feature antes de traduzir para Spark.

O .sql pode ter VÁRIOS statements separados por ``;`` (a feature principal + as
"Sub-queries de explicação" da seção ANÁLISE / PROVAS). Por padrão roda o bloco 1
(a feature). Use ``--list`` para enumerar os blocos e ``--block N`` para rodar outro.

Uso:
    python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql
    python scripts/run_feature_sqlite.py <arquivo.sql> --cutoff 2018-09-01 --limit 8
    python scripts/run_feature_sqlite.py <arquivo.sql> --list
    python scripts/run_feature_sqlite.py <arquivo.sql> --block 2
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _codigo(linha: str) -> str:
    """Parte de código de uma linha (antes de um comentário '--').

    Os .sql do projeto têm ';' DENTRO de comentários (ex.: '...todo pedido conta;'),
    então só consideramos ';' que aparecem fora de comentário. Pressupõe que não há
    '--' nem ';' dentro de literais de string (verdadeiro neste dataset).
    """
    return linha.split("--", 1)[0]


def split_blocos(texto: str) -> list[str]:
    """Divide o .sql em statements, terminando cada um no ';' de CÓDIGO (não em ';'
    de comentário). Descarta trechos que não contenham SQL real."""
    statements, cur = [], []
    for linha in texto.splitlines():
        cur.append(linha)
        if ";" in _codigo(linha):
            statements.append("\n".join(cur))
            cur = []
    if cur:
        statements.append("\n".join(cur))

    blocos = []
    for st in statements:
        if "".join(_codigo(l) for l in st.splitlines()).strip():
            blocos.append(st.strip())
    return blocos


def titulo_bloco(bloco: str) -> str:
    linhas = [l.strip() for l in bloco.splitlines() if l.strip()]
    # prioriza o rótulo "Prova X — ..."; senão, o 1º comentário com texto real
    titulo = next((l for l in linhas if "Prova" in l), None)
    if titulo is None:
        titulo = next(
            (l for l in linhas
             if l.startswith("--") and (set(l) - set("- =/"))), "",
        )
    titulo = titulo.lstrip("-").strip(" -")
    sqlhead = next((_codigo(l).strip() for l in linhas if _codigo(l).strip()), "")
    return f"{titulo[:74]}  |  {sqlhead[:42]}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--db", default=str(ROOT / "olist.db"))
    ap.add_argument("--cutoff", default="2018-09-01")
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--block", type=int, default=1, help="qual statement rodar (1 = feature)")
    ap.add_argument("--list", action="store_true", help="lista os blocos do arquivo e sai")
    args = ap.parse_args()

    texto = Path(args.sql_file).read_text(encoding="utf-8").replace("{data_corte}", args.cutoff)
    blocos = split_blocos(texto)

    if args.list:
        print(f"# {Path(args.sql_file).name}  — {len(blocos)} bloco(s)")
        for i, b in enumerate(blocos, 1):
            print(f"[{i}] {titulo_bloco(b)}")
        return 0

    if not 1 <= args.block <= len(blocos):
        print(f"--block {args.block} inválido; o arquivo tem {len(blocos)} bloco(s).")
        return 1
    sql = blocos[args.block - 1]

    conn = sqlite3.connect(args.db)
    cur = conn.execute(sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()

    print(f"# {Path(args.sql_file).name}  (cutoff={args.cutoff}, bloco={args.block}/{len(blocos)})")
    print(f"linhas: {len(rows):,} | colunas: {len(cols)}")
    print("colunas:", ", ".join(cols))

    if cols and cols[0] == "seller_id":
        ids = [r[0] for r in rows]
        dup = len(ids) - len(set(ids))
        print(f"seller_id duplicados: {dup}")

    print("\namostra:")
    print(" | ".join(cols))
    for r in rows[: args.limit]:
        print(" | ".join("NULL" if v is None else str(v) for v in r))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
