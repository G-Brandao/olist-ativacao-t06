"""Pipeline de consolidação do CUB coletado.

Junta os resultados de todas as UFs num único dataset normalizado e o persiste
em CSV (e, opcionalmente, em SQL de INSERT para carga na feature store). Também
produz um resumo de qualidade da coleta (quais UFs falharam, quantos registros
por nível/categoria).
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .models import CUB_COLUMNS, CubRecord
from .scraper import ResultadoColeta


@dataclass
class ResumoColeta:
    total_ufs: int
    ufs_ok: list[str]
    ufs_falha: list[str]
    total_registros: int
    por_categoria: dict[str, int]
    por_nivel: dict[str, int]


def consolidar(resultados: Iterable[ResultadoColeta]) -> tuple[list[CubRecord], ResumoColeta]:
    """Achata os resultados por UF em uma lista única e calcula o resumo."""
    registros: list[CubRecord] = []
    ok, falha = [], []
    for r in resultados:
        (ok if r.ok else falha).append(r.uf)
        registros.extend(r.registros)

    por_categoria: dict[str, int] = {}
    por_nivel: dict[str, int] = {}
    for rec in registros:
        por_categoria[rec.categoria.value] = por_categoria.get(rec.categoria.value, 0) + 1
        por_nivel[rec.nivel.value] = por_nivel.get(rec.nivel.value, 0) + 1

    resumo = ResumoColeta(
        total_ufs=len(ok) + len(falha),
        ufs_ok=ok,
        ufs_falha=falha,
        total_registros=len(registros),
        por_categoria=por_categoria,
        por_nivel=por_nivel,
    )
    return registros, resumo


def escrever_csv(registros: list[CubRecord], caminho: str | Path) -> Path:
    """Escreve os registros em CSV na ordem canônica de colunas."""
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with caminho.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=CUB_COLUMNS)
        writer.writeheader()
        for rec in registros:
            writer.writerow(rec.to_dict())
    return caminho


def escrever_sql(registros: list[CubRecord], caminho: str | Path,
                 tabela: str = "workspace.feature_store.fs_cub_estados") -> Path:
    """Gera um script de INSERT para carga na feature store (Delta/Spark SQL)."""
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)

    def _sql_val(v) -> str:
        if v is None:
            return "NULL"
        if isinstance(v, (int, float)):
            return repr(v)
        return "'" + str(v).replace("'", "''") + "'"

    linhas = []
    for rec in registros:
        d = rec.to_dict()
        valores = ", ".join(_sql_val(d[col]) for col in CUB_COLUMNS)
        linhas.append(f"  ({valores})")

    colunas = ", ".join(CUB_COLUMNS)
    corpo = ",\n".join(linhas) if linhas else "  -- nenhum registro coletado"
    sql = (
        f"-- CUB automático — carga gerada por cub.pipeline\n"
        f"INSERT INTO {tabela} ({colunas}) VALUES\n{corpo};\n"
    )
    caminho.write_text(sql, encoding="utf-8")
    return caminho
