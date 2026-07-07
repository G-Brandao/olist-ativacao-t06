"""Testes de parsing e coleta offline (cub.parsers / cub.scraper / cub.pipeline)."""

from pathlib import Path

import pytest

from cub.parsers import parse_valor_brl, parse_competencia, extrair_registros_de_tabela
from cub.scraper import coletar_uf
from cub.pipeline import consolidar, escrever_csv, escrever_sql
from cub.models import NivelPadrao

FIXTURE = Path(__file__).parent / "fixtures" / "cub_generico.html"


@pytest.mark.parametrize("txt,esperado", [
    ("R$ 2.345,67", 2345.67),
    ("2.345,67", 2345.67),
    ("1234,5", 1234.5),
    ("1.234", 1234.0),
    ("0,42%", 0.42),
    ("abc", None),
    ("", None),
])
def test_parse_valor_brl(txt, esperado):
    assert parse_valor_brl(txt) == esperado


@pytest.mark.parametrize("txt,esperado", [
    ("competência julho/2026", "2026-07"),
    ("07/2026", "2026-07"),
    ("2026-07", "2026-07"),
    ("nada aqui", None),
])
def test_parse_competencia(txt, esperado):
    assert parse_competencia(txt) == esperado


def test_extrai_todos_os_projetos_da_fixture():
    html = FIXTURE.read_text(encoding="utf-8")
    registros = extrair_registros_de_tabela(html, "SP", "http://exemplo/cub")

    siglas = {r.projeto_padrao for r in registros}
    # 19 projetos-padrão válidos na fixture (linhas de ruído descartadas).
    esperadas = {
        "R1-B", "R1-N", "R1-A", "PP4-B", "PP4-N",
        "R8-B", "R8-N", "R8-A", "R16-N", "R16-A",
        "CAL8-N", "CAL8-A", "CSL8-N", "CSL8-A", "CSL16-N", "CSL16-A",
        "GI", "PIS", "RP1Q",
    }
    assert siglas == esperadas


def test_competencia_extraida_da_pagina():
    html = FIXTURE.read_text(encoding="utf-8")
    registros = extrair_registros_de_tabela(html, "SP", "http://exemplo/cub")
    assert all(r.ano_mes == "2026-07" for r in registros)


def test_ruido_descartado():
    html = FIXTURE.read_text(encoding="utf-8")
    registros = extrair_registros_de_tabela(html, "SP", "http://exemplo/cub")
    # "16" (pavimentos) e "0,42%" (variação) não podem virar CUB.
    valores = [r.valor_m2 for r in registros]
    assert 16.0 not in valores
    assert 0.42 not in valores
    assert all(v >= 100 for v in valores)


def test_coletar_uf_offline_com_override():
    html = FIXTURE.read_text(encoding="utf-8")
    resultado = coletar_uf("SP", html_override=html)
    assert resultado.ok
    assert len(resultado.registros) == 19


def test_pipeline_consolida_e_escreve(tmp_path):
    html = FIXTURE.read_text(encoding="utf-8")
    resultados = [coletar_uf("SP", html_override=html)]
    registros, resumo = consolidar(resultados)

    assert resumo.total_registros == 19
    assert resumo.ufs_ok == ["SP"]
    assert resumo.por_nivel[NivelPadrao.ALTO.value] > 0
    assert resumo.por_nivel[NivelPadrao.MEDIO.value] > 0
    assert resumo.por_nivel[NivelPadrao.BAIXO.value] > 0

    csv_path = escrever_csv(registros, tmp_path / "cub.csv")
    assert csv_path.exists()
    conteudo = csv_path.read_text(encoding="utf-8")
    assert "R1-A" in conteudo and "valor_m2" in conteudo

    sql_path = escrever_sql(registros, tmp_path / "cub.sql")
    assert "INSERT INTO" in sql_path.read_text(encoding="utf-8")
