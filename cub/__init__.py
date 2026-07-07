"""CUB automático — coleta e normalização do Custo Unitário Básico da Construção
Civil (ABNT NBR 12721) divulgado pelos SINDUSCONs estaduais.

Uso programático::

    from cub.scraper import coletar_todos
    from cub.pipeline import consolidar, escrever_csv

    resultados = coletar_todos()          # coleta todas as UFs
    registros, resumo = consolidar(resultados)
    escrever_csv(registros, "data/cub.csv")
"""

from .models import CategoriaObra, CubRecord, NivelPadrao
from .classification import classificar, catalogo, normalizar_sigla
from .states import STATE_SOURCES, get_source

__all__ = [
    "CubRecord",
    "CategoriaObra",
    "NivelPadrao",
    "classificar",
    "catalogo",
    "normalizar_sigla",
    "STATE_SOURCES",
    "get_source",
]
