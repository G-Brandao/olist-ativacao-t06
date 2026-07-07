"""Modelo de dados canônico do CUB (Custo Unitário Básico da Construção Civil).

O CUB é divulgado mensalmente por cada SINDUSCON estadual, seguindo a norma
ABNT NBR 12721. Cada divulgação traz, para um conjunto de *projetos-padrão*
(tipos de obra), o custo por metro quadrado em diferentes *padrões de
acabamento* (níveis alto / normal / baixo).

Este módulo define a estrutura normalizada (``CubRecord``) para a qual todos os
parsers estaduais convergem, independentemente do formato original (HTML, PDF,
planilha) de cada site.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict, field
from datetime import date
from enum import Enum
from typing import Optional


class NivelPadrao(str, Enum):
    """Padrão de acabamento do projeto-padrão, normalizado em três níveis.

    Mapeamento a partir do sufixo usado pela NBR 12721:
      - ``-B`` (Baixo)  -> BAIXO
      - ``-N`` (Normal) -> MEDIO   (o "meio" pedido na tarefa)
      - ``-A`` (Alto)   -> ALTO

    Projetos-padrão de nível único (ex.: GI, PIS, RP1Q) recebem ``UNICO`` e são
    reclassificados para um dos três níveis pela regra de negócio documentada em
    :mod:`cub.classification`.
    """

    BAIXO = "baixo"
    MEDIO = "medio"
    ALTO = "alto"
    UNICO = "unico"


class CategoriaObra(str, Enum):
    """Categoria (finalidade) da obra do projeto-padrão."""

    RESIDENCIAL = "residencial"
    COMERCIAL = "comercial"
    INDUSTRIAL = "industrial"
    POPULAR = "popular"  # interesse social / habitação popular
    OUTRO = "outro"


@dataclass(frozen=True)
class CubRecord:
    """Uma observação de CUB: um valor de R$/m² para (UF, mês, projeto, nível).

    Chave natural: ``(uf, ano_mes, projeto_padrao)``. O ``projeto_padrao`` já
    embute o padrão de acabamento (ex.: ``R1-A``), portanto identifica
    unicamente a linha dentro de um mês/UF.
    """

    uf: str                       # sigla do estado (ex.: "SP")
    ano_mes: str                  # competência no formato "YYYY-MM"
    projeto_padrao: str           # sigla NBR (ex.: "R1-A", "CSL16-N", "GI")
    categoria: CategoriaObra      # residencial / comercial / industrial / popular
    nivel: NivelPadrao            # alto / medio / baixo (nível efetivo já classificado)
    valor_m2: float               # custo unitário básico em R$/m²
    fonte_url: str                # URL de onde o dado foi extraído
    coletado_em: date = field(default_factory=date.today)
    descricao: Optional[str] = None  # descrição textual do projeto-padrão

    def to_dict(self) -> dict:
        d = asdict(self)
        d["categoria"] = self.categoria.value
        d["nivel"] = self.nivel.value
        d["coletado_em"] = self.coletado_em.isoformat()
        return d


# Ordem canônica das colunas na saída tabular (CSV / parquet / SQL).
CUB_COLUMNS = [
    "uf",
    "ano_mes",
    "projeto_padrao",
    "categoria",
    "nivel",
    "valor_m2",
    "descricao",
    "fonte_url",
    "coletado_em",
]
