"""Regras de classificação dos projetos-padrão do CUB (ABNT NBR 12721).

Este módulo é a *fonte da verdade* do CUB automático: ele converte a sopa de
siglas divulgada por cada SINDUSCON (``R1-A``, ``PP4-B``, ``CSL16-N``, ``GI``,
``PIS``, ``RP1Q`` ...) para um vocabulário fechado e normalizado de:

  * **categoria da obra**  -> residencial / comercial / industrial / popular
  * **nível de padrão**    -> alto / medio (normal) / baixo

As regras aqui codificadas estão descritas por extenso, com racional de negócio,
em ``docs/regras_classificacao_cub.md``. Sempre que uma regra mudar, os dois
arquivos devem ser atualizados juntos.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Optional

from .models import CategoriaObra, NivelPadrao


@dataclass(frozen=True)
class ProjetoPadrao:
    """Definição canônica de um projeto-padrão da NBR 12721."""

    sigla: str                 # sigla completa normalizada (ex.: "R1-A")
    base: str                  # projeto base sem o padrão (ex.: "R1")
    categoria: CategoriaObra
    nivel: NivelPadrao
    descricao: str


# ---------------------------------------------------------------------------
# Catálogo oficial de projetos-padrão (NBR 12721:2006).
#
# Cada projeto base admite um subconjunto de padrões de acabamento:
#   Baixo (B), Normal (N) e Alto (A). Projetos de finalidade social/industrial
#   têm padrão único.
# ---------------------------------------------------------------------------
_CATALOGO: list[ProjetoPadrao] = [
    # ----- Residenciais -----
    ProjetoPadrao("R1-B", "R1", CategoriaObra.RESIDENCIAL, NivelPadrao.BAIXO,
                  "Residência unifamiliar, 1 pavimento, padrão baixo"),
    ProjetoPadrao("R1-N", "R1", CategoriaObra.RESIDENCIAL, NivelPadrao.MEDIO,
                  "Residência unifamiliar, 1 pavimento, padrão normal"),
    ProjetoPadrao("R1-A", "R1", CategoriaObra.RESIDENCIAL, NivelPadrao.ALTO,
                  "Residência unifamiliar, 1 pavimento, padrão alto"),

    ProjetoPadrao("PP4-B", "PP4", CategoriaObra.RESIDENCIAL, NivelPadrao.BAIXO,
                  "Prédio popular, 4 pavimentos, padrão baixo"),
    ProjetoPadrao("PP4-N", "PP4", CategoriaObra.RESIDENCIAL, NivelPadrao.MEDIO,
                  "Prédio popular, 4 pavimentos, padrão normal"),

    ProjetoPadrao("R8-B", "R8", CategoriaObra.RESIDENCIAL, NivelPadrao.BAIXO,
                  "Residência multifamiliar, 8 pavimentos, padrão baixo"),
    ProjetoPadrao("R8-N", "R8", CategoriaObra.RESIDENCIAL, NivelPadrao.MEDIO,
                  "Residência multifamiliar, 8 pavimentos, padrão normal"),
    ProjetoPadrao("R8-A", "R8", CategoriaObra.RESIDENCIAL, NivelPadrao.ALTO,
                  "Residência multifamiliar, 8 pavimentos, padrão alto"),

    ProjetoPadrao("R16-N", "R16", CategoriaObra.RESIDENCIAL, NivelPadrao.MEDIO,
                  "Residência multifamiliar, 16 pavimentos, padrão normal"),
    ProjetoPadrao("R16-A", "R16", CategoriaObra.RESIDENCIAL, NivelPadrao.ALTO,
                  "Residência multifamiliar, 16 pavimentos, padrão alto"),

    # ----- Comerciais -----
    ProjetoPadrao("CAL8-N", "CAL8", CategoriaObra.COMERCIAL, NivelPadrao.MEDIO,
                  "Comercial andar livre, 8 pavimentos, padrão normal"),
    ProjetoPadrao("CAL8-A", "CAL8", CategoriaObra.COMERCIAL, NivelPadrao.ALTO,
                  "Comercial andar livre, 8 pavimentos, padrão alto"),

    ProjetoPadrao("CSL8-N", "CSL8", CategoriaObra.COMERCIAL, NivelPadrao.MEDIO,
                  "Comercial salas e lojas, 8 pavimentos, padrão normal"),
    ProjetoPadrao("CSL8-A", "CSL8", CategoriaObra.COMERCIAL, NivelPadrao.ALTO,
                  "Comercial salas e lojas, 8 pavimentos, padrão alto"),

    ProjetoPadrao("CSL16-N", "CSL16", CategoriaObra.COMERCIAL, NivelPadrao.MEDIO,
                  "Comercial salas e lojas, 16 pavimentos, padrão normal"),
    ProjetoPadrao("CSL16-A", "CSL16", CategoriaObra.COMERCIAL, NivelPadrao.ALTO,
                  "Comercial salas e lojas, 16 pavimentos, padrão alto"),

    # ----- Industrial (padrão único) -----
    ProjetoPadrao("GI", "GI", CategoriaObra.INDUSTRIAL, NivelPadrao.UNICO,
                  "Galpão industrial, padrão único"),

    # ----- Popular / interesse social (padrão único) -----
    ProjetoPadrao("PIS", "PIS", CategoriaObra.POPULAR, NivelPadrao.UNICO,
                  "Projeto de interesse social, padrão único"),
    ProjetoPadrao("RP1Q", "RP1Q", CategoriaObra.POPULAR, NivelPadrao.UNICO,
                  "Residência popular, 1 quarto, padrão único"),
]

# Índice por sigla canônica para consulta O(1).
_POR_SIGLA: dict[str, ProjetoPadrao] = {p.sigla: p for p in _CATALOGO}


def _strip_accents(texto: str) -> str:
    nfkd = unicodedata.normalize("NFKD", texto)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def _compact(texto: str) -> str:
    """Forma compacta para comparação: sem acento, maiúsculas, só alfanumérico.

    Ex.: "CSL 16 N" -> "CSL16N"; "R-1-A" -> "R1A"; "RP1Q" -> "RP1Q".
    """
    sem_acento = _strip_accents(texto or "").upper()
    return re.sub(r"[^A-Z0-9]", "", sem_acento)


# Índice compacto por sigla completa (ex.: "R1A" -> "R1-A").
_COMPACT_INDEX: dict[str, str] = {_compact(p.sigla): p.sigla for p in _CATALOGO}

# Índice compacto por projeto base (ex.: "R1" -> "R1", "CSL16" -> "CSL16").
_BASE_COMPACT: dict[str, str] = {_compact(p.base): p.base for p in _CATALOGO}


# ---------------------------------------------------------------------------
# Regra 1 — Nível efetivo de projetos de padrão único.
#
# A tarefa exige que TODA obra caia em um dos três níveis (alto/medio/baixo).
# Projetos de padrão único não têm sufixo B/N/A, então são reclassificados pela
# natureza da obra:
#   - PIS  (interesse social)  -> BAIXO  (menor especificação de acabamento)
#   - RP1Q (residência popular)-> BAIXO
#   - GI   (galpão industrial) -> MEDIO  (obra padronizada, sem acabamento fino;
#                                          tratada como referência "normal")
# ---------------------------------------------------------------------------
_NIVEL_UNICO: dict[str, NivelPadrao] = {
    "PIS": NivelPadrao.BAIXO,
    "RP1Q": NivelPadrao.BAIXO,
    "GI": NivelPadrao.MEDIO,
}


# ---------------------------------------------------------------------------
# Regra 2 — Normalização do padrão de acabamento a partir do texto do site.
#
# Os sites variam a nomenclatura do padrão. Mapeamos variantes textuais para o
# sufixo canônico B/N/A.
# ---------------------------------------------------------------------------
_PADRAO_TEXTO: dict[str, str] = {
    "baixo": "B", "b": "B", "economico": "B", "economico(baixo)": "B",
    "normal": "N", "n": "N", "medio": "N", "media": "N", "medio(normal)": "N",
    "alto": "A", "a": "A", "elevado": "A",
}


def normalizar_sigla(bruto: str) -> Optional[str]:
    """Normaliza uma sigla de projeto-padrão vinda do site para a forma canônica.

    Aceita variações comuns: espaços, hífen ausente, caixa, acentos, e as formas
    "R-1-A", "R 1 A", "CSL-16 N", "RP1Q" etc. Retorna a sigla canônica
    (ex.: ``R1-A``) ou ``None`` se não corresponder a um projeto-padrão completo.

    Observação: um projeto base que exige padrão de acabamento (ex.: ``R1``, sem
    sufixo B/N/A) retorna ``None`` aqui — a resolução com o padrão em coluna
    separada é feita por :func:`classificar`.
    """
    if not bruto:
        return None
    return _COMPACT_INDEX.get(_compact(bruto))


def classificar(sigla_bruta: str, padrao_texto: Optional[str] = None) -> Optional[ProjetoPadrao]:
    """Classifica uma linha de CUB em (categoria, nível) canônicos.

    Parameters
    ----------
    sigla_bruta:
        Sigla do projeto-padrão como aparece no site (ex.: ``"R1"``, ``"CSL 16"``).
    padrao_texto:
        Descrição textual do padrão de acabamento quando ele vem em coluna
        separada (ex.: ``"Alto"``, ``"Baixo"``). Opcional.

    Returns
    -------
    ProjetoPadrao | None
        Definição canônica com nível já resolvido para alto/medio/baixo
        (projetos de padrão único são convertidos pela Regra 1), ou ``None`` se
        a linha não puder ser classificada.
    """
    sigla = normalizar_sigla(sigla_bruta)

    # Caso o site traga o projeto base sem sufixo e o padrão numa coluna à parte.
    if sigla is None and padrao_texto:
        base = _BASE_COMPACT.get(_compact(sigla_bruta))
        chave_padrao = _strip_accents(padrao_texto).lower().replace(" ", "")
        sufixo = _PADRAO_TEXTO.get(chave_padrao)
        if base and sufixo:
            candidata = f"{base}-{sufixo}"
            sigla = candidata if candidata in _POR_SIGLA else None

    if sigla is None or sigla not in _POR_SIGLA:
        return None

    proj = _POR_SIGLA[sigla]

    # Regra 1: resolve nível efetivo dos projetos de padrão único.
    if proj.nivel is NivelPadrao.UNICO:
        nivel_efetivo = _NIVEL_UNICO.get(proj.base, NivelPadrao.MEDIO)
        return ProjetoPadrao(proj.sigla, proj.base, proj.categoria,
                             nivel_efetivo, proj.descricao)
    return proj


def catalogo() -> list[ProjetoPadrao]:
    """Retorna o catálogo completo de projetos-padrão conhecidos."""
    return list(_CATALOGO)
