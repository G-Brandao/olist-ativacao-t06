"""Testes das regras de classificação (cub.classification)."""

import pytest

from cub.classification import classificar, normalizar_sigla, catalogo
from cub.models import CategoriaObra, NivelPadrao


@pytest.mark.parametrize("bruto,esperado", [
    ("R1-A", "R1-A"),
    ("r1 a", "R1-A"),
    ("R-1-A", "R1-A"),
    ("CSL 16 N", "CSL16-N"),
    ("csl16-a", "CSL16-A"),
    ("GI", "GI"),
    ("PIS", "PIS"),
    ("RP1Q", "RP1Q"),
])
def test_normalizar_sigla_reconhece_variacoes(bruto, esperado):
    assert normalizar_sigla(bruto) == esperado


@pytest.mark.parametrize("bruto", ["", "XPTO", "R99-A", "R1-Z", "Pavimentos"])
def test_normalizar_sigla_rejeita_invalidos(bruto):
    assert normalizar_sigla(bruto) is None


def test_niveis_alto_medio_baixo():
    assert classificar("R1-B").nivel is NivelPadrao.BAIXO
    assert classificar("R1-N").nivel is NivelPadrao.MEDIO
    assert classificar("R1-A").nivel is NivelPadrao.ALTO


def test_categorias():
    assert classificar("R8-N").categoria is CategoriaObra.RESIDENCIAL
    assert classificar("CSL16-A").categoria is CategoriaObra.COMERCIAL
    assert classificar("GI").categoria is CategoriaObra.INDUSTRIAL
    assert classificar("PIS").categoria is CategoriaObra.POPULAR


def test_padrao_unico_reclassificado():
    # Regra 1: projetos de padrão único caem em alto/medio/baixo.
    assert classificar("PIS").nivel is NivelPadrao.BAIXO
    assert classificar("RP1Q").nivel is NivelPadrao.BAIXO
    assert classificar("GI").nivel is NivelPadrao.MEDIO
    # Nunca deve sobrar o nível UNICO após classificar.
    for sigla in ("GI", "PIS", "RP1Q"):
        assert classificar(sigla).nivel is not NivelPadrao.UNICO


def test_padrao_em_coluna_separada():
    proj = classificar("R1", padrao_texto="Alto")
    assert proj is not None
    assert proj.sigla == "R1-A"
    assert proj.nivel is NivelPadrao.ALTO


def test_catalogo_cobre_tres_niveis():
    niveis = {p.nivel for p in catalogo()}
    assert {NivelPadrao.BAIXO, NivelPadrao.MEDIO, NivelPadrao.ALTO} <= niveis
