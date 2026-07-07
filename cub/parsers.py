"""Utilitários de parsing e extração de tabelas de CUB.

Contém:
  * ``parse_valor_brl`` — converte "R$ 2.345,67" -> 2345.67
  * ``parse_competencia`` — extrai a competência (YYYY-MM) de um texto
  * ``extrair_registros_de_tabela`` — transforma uma <table> HTML de CUB numa
    lista de ``CubRecord`` já classificados.

A extração é deliberadamente tolerante: sites de SINDUSCON têm tabelas
irregulares (células mescladas, colunas de padrão à parte, cabeçalhos com
acento). O que não for reconhecido é silenciosamente ignorado — o objetivo é
capturar o máximo de linhas válidas sem quebrar por causa de uma célula suja.
"""

from __future__ import annotations

import re
from datetime import date
from typing import Iterable, Optional

from bs4 import BeautifulSoup

from .classification import classificar
from .models import CubRecord


_MESES = {
    "janeiro": 1, "fevereiro": 2, "marco": 3, "março": 3, "abril": 4,
    "maio": 5, "junho": 6, "julho": 7, "agosto": 8, "setembro": 9,
    "outubro": 10, "novembro": 11, "dezembro": 12,
}


def parse_valor_brl(texto: str) -> Optional[float]:
    """Converte um valor monetário em formato brasileiro para float.

    Aceita "R$ 2.345,67", "2.345,67", "1234,5", "1.234". Retorna ``None`` se não
    houver número reconhecível.
    """
    if texto is None:
        return None
    limpo = re.sub(r"[^0-9.,]", "", str(texto))
    if not limpo:
        return None
    # Formato BR: ponto é separador de milhar, vírgula é decimal.
    if "," in limpo:
        limpo = limpo.replace(".", "").replace(",", ".")
    else:
        # Sem vírgula: pontos podem ser milhar (2.345) — remove-os.
        limpo = limpo.replace(".", "")
    try:
        return float(limpo)
    except ValueError:
        return None


def parse_competencia(texto: str, fallback: Optional[str] = None) -> Optional[str]:
    """Extrai a competência no formato ``YYYY-MM`` de um texto livre.

    Reconhece "julho/2026", "07/2026", "2026-07", "jul 2026". Usa ``fallback``
    (ex.: mês corrente) quando nada é encontrado.
    """
    if texto:
        t = texto.lower()
        # mês por extenso + ano
        for nome, num in _MESES.items():
            m = re.search(rf"{nome}\s*[/\-de ]*\s*(\d{{4}})", t)
            if m:
                return f"{m.group(1)}-{num:02d}"
        # MM/AAAA
        m = re.search(r"\b(\d{1,2})[/\-](\d{4})\b", t)
        if m:
            return f"{m.group(2)}-{int(m.group(1)):02d}"
        # AAAA-MM
        m = re.search(r"\b(\d{4})[-/](\d{1,2})\b", t)
        if m:
            return f"{m.group(1)}-{int(m.group(2)):02d}"
    return fallback


def _texto_celula(cell) -> str:
    return re.sub(r"\s+", " ", cell.get_text(" ", strip=True)).strip()


def extrair_registros_de_tabela(
    html: str,
    uf: str,
    fonte_url: str,
    ano_mes: Optional[str] = None,
    coletado_em: Optional[date] = None,
) -> list[CubRecord]:
    """Extrai ``CubRecord`` de todas as tabelas de CUB dentro de um HTML.

    Estratégia: para cada linha de cada tabela, procura uma célula que pareça a
    sigla de um projeto-padrão e uma célula que pareça um valor em R$. Cada par
    (sigla, valor) reconhecido vira um registro classificado. Uma coluna textual
    de "padrão" (Baixo/Normal/Alto), quando presente, é passada ao classificador.
    """
    soup = BeautifulSoup(html, "lxml")
    coletado_em = coletado_em or date.today()
    ano_mes = parse_competencia(soup.get_text(" "), fallback=ano_mes)

    registros: list[CubRecord] = []
    vistos: set[tuple[str, str]] = set()  # dedupe (projeto_padrao) dentro da página

    for table in soup.find_all("table"):
        for row in table.find_all("tr"):
            celulas = [_texto_celula(c) for c in row.find_all(["td", "th"])]
            celulas = [c for c in celulas if c]
            if len(celulas) < 2:
                continue

            valor = _achar_valor(celulas)
            if valor is None:
                continue

            proj = _achar_projeto(celulas)
            if proj is None:
                continue

            if proj.sigla in {v[0] for v in vistos}:
                continue
            vistos.add((proj.sigla, str(valor)))

            registros.append(CubRecord(
                uf=uf.upper(),
                ano_mes=ano_mes or "",
                projeto_padrao=proj.sigla,
                categoria=proj.categoria,
                nivel=proj.nivel,
                valor_m2=valor,
                fonte_url=fonte_url,
                coletado_em=coletado_em,
                descricao=proj.descricao,
            ))
    return registros


def _achar_valor(celulas: Iterable[str]) -> Optional[float]:
    """Retorna o primeiro valor monetário plausível de uma linha.

    Considera plausível um CUB entre R$100 e R$100.000 por m² — filtra números
    espúrios (número de pavimentos, área, índice percentual).
    """
    for c in celulas:
        if "," not in c and "." not in c:
            continue  # CUB sempre tem casas decimais
        v = parse_valor_brl(c)
        if v is not None and 100.0 <= v <= 100_000.0:
            return v
    return None


def _achar_projeto(celulas: Iterable[str]):
    """Tenta classificar alguma célula da linha como projeto-padrão.

    Testa cada célula como sigla; se falhar, tenta o par (sigla base + coluna de
    padrão textual) usando a heurística do classificador.
    """
    celulas = list(celulas)
    for c in celulas:
        proj = classificar(c)
        if proj is not None:
            return proj
    # Tentativa com padrão em coluna separada.
    for i, c in enumerate(celulas):
        for outra in celulas:
            if outra is c:
                continue
            proj = classificar(c, padrao_texto=outra)
            if proj is not None:
                return proj
    return None
