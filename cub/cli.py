"""Interface de linha de comando do CUB automático.

Exemplos
--------
Coletar todos os estados e gravar CSV::

    python -m cub.cli --out data/cub.csv

Coletar apenas SP e MG e também gerar o SQL de carga::

    python -m cub.cli --ufs SP MG --out data/cub.csv --sql data/cub_insert.sql

Verificar acessibilidade das URLs sem baixar o CUB::

    python -m cub.cli --check-urls
"""

from __future__ import annotations

import argparse
import logging
import sys

from .pipeline import consolidar, escrever_csv, escrever_sql
from .scraper import coletar_todos, fetch
from .states import STATE_SOURCES, all_ufs


def _check_urls(ufs: list[str]) -> int:
    falhas = 0
    for source in STATE_SOURCES:
        if source.uf not in ufs:
            continue
        try:
            fetch(source.cub_url, tentativas=1, timeout=15)
            print(f"[OK]    {source.uf}: {source.cub_url}")
        except Exception as exc:  # noqa: BLE001
            falhas += 1
            print(f"[FALHA] {source.uf}: {source.cub_url} -> {exc}")
    return 1 if falhas else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="CUB automático — coleta o CUB de todos os SINDUSCONs estaduais.")
    parser.add_argument("--ufs", nargs="*", help="Subconjunto de UFs (padrão: todas).")
    parser.add_argument("--out", default="data/cub.csv", help="Caminho do CSV de saída.")
    parser.add_argument("--sql", help="Se informado, gera também um script SQL de INSERT.")
    parser.add_argument("--check-urls", action="store_true", help="Só valida as URLs das fontes.")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    ufs = [u.upper() for u in args.ufs] if args.ufs else all_ufs()

    if args.check_urls:
        return _check_urls(ufs)

    resultados = coletar_todos(ufs)
    registros, resumo = consolidar(resultados)

    csv_path = escrever_csv(registros, args.out)
    print(f"CSV gravado em: {csv_path}  ({resumo.total_registros} registros)")
    if args.sql:
        sql_path = escrever_sql(registros, args.sql)
        print(f"SQL gravado em: {sql_path}")

    print("\nResumo da coleta")
    print(f"  UFs coletadas com sucesso: {len(resumo.ufs_ok)}/{resumo.total_ufs}")
    if resumo.ufs_falha:
        print(f"  UFs com falha: {', '.join(resumo.ufs_falha)}")
    print(f"  Por categoria: {resumo.por_categoria}")
    print(f"  Por nível:     {resumo.por_nivel}")

    # Sucesso se pelo menos uma UF retornou dados.
    return 0 if resumo.total_registros > 0 else 2


if __name__ == "__main__":
    sys.exit(main())
