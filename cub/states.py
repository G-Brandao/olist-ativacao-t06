"""Registro das fontes de CUB por estado (SINDUSCON de cada UF).

Cada estado divulga o CUB no site do seu SINDUSCON. Os endereços e, sobretudo,
os *layouts* dessas páginas mudam com frequência (troca de CMS, migração de
tabela HTML para PDF, etc.). Por isso este registro carrega, além da URL, um
campo ``estrategia`` que indica qual parser usar e um campo ``verificado`` que
sinaliza se a URL foi confirmada recentemente.

IMPORTANTE: as URLs abaixo refletem os domínios oficiais conhecidos dos
SINDUSCONs, mas o *caminho exato* da página de CUB deve ser revalidado
periodicamente (ver ``docs/regras_classificacao_cub.md`` > "Manutenção das
fontes"). Rodar ``python -m cub.cli --check-urls`` valida a acessibilidade.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class StateSource:
    uf: str                 # sigla da UF (ex.: "SP")
    nome: str               # nome do estado
    sindicato: str          # nome do SINDUSCON
    base_url: str           # domínio oficial do sindicato
    cub_url: str            # página onde o CUB é divulgado
    estrategia: str = "html_table"   # parser a usar: "html_table" | "pdf" | "custom:<uf>"
    verificado: bool = False         # URL confirmada acessível na última checagem
    observacao: str = ""


# ---------------------------------------------------------------------------
# Registro das 27 unidades federativas.
#
# ``estrategia`` padrão é "html_table" (extração de <table>). Estados que
# publicam o CUB em PDF usam "pdf"; estados com layout idiossincrático usam
# "custom:<uf>" e um parser dedicado em cub.scraper.
# ---------------------------------------------------------------------------
STATE_SOURCES: list[StateSource] = [
    StateSource("AC", "Acre", "SINDUSCON-AC",
                "https://www.sindusconac.com.br",
                "https://www.sindusconac.com.br/cub"),
    StateSource("AL", "Alagoas", "SINDUSCON-AL",
                "https://sindusconalagoas.com.br",
                "https://sindusconalagoas.com.br/cub"),
    StateSource("AP", "Amapá", "SINDUSCON-AP",
                "https://sindusconap.com.br",
                "https://sindusconap.com.br/cub"),
    StateSource("AM", "Amazonas", "SINDUSCON-AM",
                "https://www.sindusconam.com.br",
                "https://www.sindusconam.com.br/cub"),
    StateSource("BA", "Bahia", "SINDUSCON-BA",
                "https://sinduscon-ba.com.br",
                "https://sinduscon-ba.com.br/cub"),
    StateSource("CE", "Ceará", "SINDUSCON-CE",
                "https://www.sindusconce.com.br",
                "https://www.sindusconce.com.br/cub"),
    StateSource("DF", "Distrito Federal", "SINDUSCON-DF",
                "https://sinduscondf.org.br",
                "https://sinduscondf.org.br/cub"),
    StateSource("ES", "Espírito Santo", "SINDUSCON-ES",
                "https://sinduscon-es.com.br",
                "https://sinduscon-es.com.br/cub"),
    StateSource("GO", "Goiás", "SINDUSCON-GO",
                "https://sinduscongoias.com.br",
                "https://sinduscongoias.com.br/cub"),
    StateSource("MA", "Maranhão", "SINDUSCON-MA",
                "https://sindusconma.com.br",
                "https://sindusconma.com.br/cub"),
    StateSource("MT", "Mato Grosso", "SINDUSCON-MT",
                "https://www.sindusconmt.org.br",
                "https://www.sindusconmt.org.br/cub"),
    StateSource("MS", "Mato Grosso do Sul", "SINDUSCON-MS",
                "https://sindusconms.org.br",
                "https://sindusconms.org.br/cub"),
    StateSource("MG", "Minas Gerais", "SINDUSCON-MG",
                "https://www.sinduscon-mg.org.br",
                "https://www.sinduscon-mg.org.br/cub-2",
                observacao="MG divulga série histórica; usar mês mais recente."),
    StateSource("PA", "Pará", "SINDUSCON-PA",
                "https://sindusconpa.org.br",
                "https://sindusconpa.org.br/cub"),
    StateSource("PB", "Paraíba", "SINDUSCON-PB",
                "https://sindusconjp.com.br",
                "https://sindusconjp.com.br/cub"),
    StateSource("PR", "Paraná", "SINDUSCON-PR",
                "https://sindusconpr.com.br",
                "https://sindusconpr.com.br/cub-419",
                observacao="PR publica CUB desonerado e não desonerado."),
    StateSource("PE", "Pernambuco", "SINDUSCON-PE",
                "https://sindusconpe.com.br",
                "https://sindusconpe.com.br/cub"),
    StateSource("PI", "Piauí", "SINDUSCON-PI",
                "https://sindusconpi.com.br",
                "https://sindusconpi.com.br/cub"),
    StateSource("RJ", "Rio de Janeiro", "SINDUSCON-RIO",
                "https://www.sindusconrio.com.br",
                "https://www.sindusconrio.com.br/cub"),
    StateSource("RN", "Rio Grande do Norte", "SINDUSCON-RN",
                "https://sindusconrn.com.br",
                "https://sindusconrn.com.br/cub"),
    StateSource("RS", "Rio Grande do Sul", "SINDUSCON-RS",
                "https://sindusconrs.com.br",
                "https://sindusconrs.com.br/cub",
                observacao="RS publica CUB médio ponderado além dos projetos-padrão."),
    StateSource("RO", "Rondônia", "SINDUSCON-RO",
                "https://sindusconro.com.br",
                "https://sindusconro.com.br/cub"),
    StateSource("RR", "Roraima", "SINDUSCON-RR",
                "https://sindusconrr.com.br",
                "https://sindusconrr.com.br/cub"),
    StateSource("SC", "Santa Catarina", "SINDUSCON-SC",
                "https://sinduscon-fpolis.org.br",
                "https://sinduscon-fpolis.org.br/cub",
                observacao="Grande Florianópolis; há também SINDUSCON regionais em SC."),
    StateSource("SP", "São Paulo", "SINDUSCON-SP",
                "https://www.sindusconsp.com.br",
                "https://www.sindusconsp.com.br/cub",
                estrategia="custom:SP",
                observacao="SindusCon-SP publica planilha detalhada (CUB/m2)."),
    StateSource("SE", "Sergipe", "SINDUSCON-SE",
                "https://sindusconse.com.br",
                "https://sindusconse.com.br/cub"),
    StateSource("TO", "Tocantins", "SINDUSCON-TO",
                "https://sindusconto.com.br",
                "https://sindusconto.com.br/cub"),
]

# Índice por UF.
STATE_BY_UF: dict[str, StateSource] = {s.uf: s for s in STATE_SOURCES}


def get_source(uf: str) -> StateSource:
    """Retorna a fonte de uma UF (ex.: ``get_source("SP")``)."""
    try:
        return STATE_BY_UF[uf.upper()]
    except KeyError as exc:
        raise KeyError(f"UF desconhecida: {uf!r}") from exc


def all_ufs() -> list[str]:
    return [s.uf for s in STATE_SOURCES]
