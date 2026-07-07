"""Coleta (scraping) do CUB a partir dos sites dos SINDUSCONs.

Responsável por:
  * baixar o HTML de cada fonte estadual (com retry e timeout);
  * despachar para a estratégia de parsing correta (``html_table``, ``pdf`` ou
    ``custom:<uf>``);
  * devolver ``CubRecord`` normalizados.

O download é isolado em ``fetch`` para permitir testes offline (basta injetar
``html_override``). Nenhuma rede é tocada nos testes de unidade — eles usam as
fixtures em ``tests/fixtures``.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Callable, Optional

import requests

from .models import CubRecord
from .parsers import extrair_registros_de_tabela
from .states import STATE_SOURCES, StateSource, get_source

logger = logging.getLogger("cub.scraper")

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; CUB-Automatico/1.0; +olist-ativacao-t06) "
        "Python-requests"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9",
}


@dataclass
class ResultadoColeta:
    """Resultado da coleta de uma UF."""

    uf: str
    registros: list[CubRecord]
    ok: bool
    erro: Optional[str] = None


def fetch(url: str, timeout: int = 30, tentativas: int = 3) -> str:
    """Baixa o conteúdo de uma URL com retry e backoff exponencial (2s, 4s, 8s)."""
    ultimo_erro: Optional[Exception] = None
    for i in range(tentativas):
        try:
            resp = requests.get(url, headers=_HEADERS, timeout=timeout)
            resp.raise_for_status()
            resp.encoding = resp.apparent_encoding or resp.encoding
            return resp.text
        except requests.RequestException as exc:  # rede/HTTP
            ultimo_erro = exc
            espera = 2 ** (i + 1)
            logger.warning("Falha ao baixar %s (tentativa %d/%d): %s",
                           url, i + 1, tentativas, exc)
            if i < tentativas - 1:
                time.sleep(espera)
    raise RuntimeError(f"Não foi possível baixar {url}: {ultimo_erro}")


# ---------------------------------------------------------------------------
# Estratégias de parsing por estado.
#
# Cada estratégia recebe (html, source) e devolve List[CubRecord]. Estados com
# layout próprio registram uma função em CUSTOM_PARSERS sob a chave "custom:<UF>".
# ---------------------------------------------------------------------------
ParserFn = Callable[[str, StateSource], list[CubRecord]]


def _parse_html_table(html: str, source: StateSource) -> list[CubRecord]:
    return extrair_registros_de_tabela(html, source.uf, source.cub_url)


def _parse_pdf(html: str, source: StateSource) -> list[CubRecord]:
    # Placeholder: estados que só publicam PDF exigem extração via pdfplumber.
    # Mantido explícito para não mascarar a limitação (ver docs > "Fontes em PDF").
    raise NotImplementedError(
        f"{source.uf}: fonte em PDF ainda não suportada — implementar parser pdf."
    )


def _parse_sp(html: str, source: StateSource) -> list[CubRecord]:
    """SindusCon-SP: a planilha usa a mesma estrutura de tabela; reaproveitamos o
    parser genérico, mas o hook existe para tratar particularidades futuras
    (ex.: CUB desonerado vs. não desonerado em colunas distintas)."""
    return extrair_registros_de_tabela(html, source.uf, source.cub_url)


CUSTOM_PARSERS: dict[str, ParserFn] = {
    "custom:SP": _parse_sp,
}


def _resolver_parser(source: StateSource) -> ParserFn:
    if source.estrategia == "html_table":
        return _parse_html_table
    if source.estrategia == "pdf":
        return _parse_pdf
    if source.estrategia in CUSTOM_PARSERS:
        return CUSTOM_PARSERS[source.estrategia]
    raise ValueError(f"Estratégia desconhecida para {source.uf}: {source.estrategia}")


def coletar_uf(uf: str, html_override: Optional[str] = None) -> ResultadoColeta:
    """Coleta o CUB de uma UF.

    ``html_override`` permite injetar HTML (testes / reprocessamento offline) sem
    tocar a rede.
    """
    source = get_source(uf)
    try:
        html = html_override if html_override is not None else fetch(source.cub_url)
        parser = _resolver_parser(source)
        registros = parser(html, source)
        return ResultadoColeta(uf=source.uf, registros=registros, ok=True)
    except Exception as exc:  # noqa: BLE001 — queremos degradar por UF, não abortar tudo
        logger.error("Erro ao coletar %s: %s", uf, exc)
        return ResultadoColeta(uf=source.uf, registros=[], ok=False, erro=str(exc))


def coletar_todos(ufs: Optional[list[str]] = None) -> list[ResultadoColeta]:
    """Coleta o CUB de todas as UFs (ou de um subconjunto)."""
    alvos = ufs or [s.uf for s in STATE_SOURCES]
    resultados: list[ResultadoColeta] = []
    for uf in alvos:
        logger.info("Coletando CUB de %s...", uf)
        resultados.append(coletar_uf(uf))
    return resultados
