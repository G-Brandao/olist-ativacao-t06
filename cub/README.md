# CUB automático

Coleta automatizada do **Custo Unitário Básico da Construção Civil (CUB/m²,
ABNT NBR 12721)** divulgado mensalmente pelos SINDUSCONs de cada estado,
normalizado por **estado × tipo de obra × nível de padrão (alto / médio / baixo)**.

> As regras de classificação estão documentadas em
> [`../docs/regras_classificacao_cub.md`](../docs/regras_classificacao_cub.md).

## Estrutura

| Arquivo | Responsabilidade |
|---------|------------------|
| `models.py`         | Modelo de dados canônico (`CubRecord`, enums `CategoriaObra`/`NivelPadrao`). |
| `classification.py` | Catálogo NBR 12721 e regras de classificação (sigla → categoria + nível). |
| `states.py`         | Registro das 27 fontes estaduais (URL + estratégia de parsing). |
| `parsers.py`        | Parsing de valores (R$), competência e extração de tabelas HTML. |
| `scraper.py`        | Download (com retry) e despacho por estratégia de estado. |
| `pipeline.py`       | Consolidação, resumo de qualidade e escrita em CSV/SQL. |
| `cli.py`            | Interface de linha de comando. |
| `tests/`            | Testes de unidade offline (fixtures em `tests/fixtures/`). |

## Uso

```bash
# Todos os estados -> CSV
python -m cub.cli --out data/cub.csv

# Só SP e MG, gerando também SQL de carga
python -m cub.cli --ufs SP MG --out data/cub.csv --sql data/cub_insert.sql

# Validar acessibilidade das URLs das fontes
python -m cub.cli --check-urls
```

Uso programático:

```python
from cub.scraper import coletar_todos
from cub.pipeline import consolidar, escrever_csv

registros, resumo = consolidar(coletar_todos())
escrever_csv(registros, "data/cub.csv")
print(resumo.por_nivel)   # {'baixo': N, 'medio': N, 'alto': N}
```

## Dependências

```bash
pip install -r cub/requirements.txt
```

## Testes

```bash
python -m pytest cub/tests -q
```

Os testes rodam **offline** (injetam HTML via `html_override`), não tocam a rede.

## Estado da coleta ao vivo

O framework está completo e testado com fixtures. A **coleta ao vivo** depende
de acesso de rede aos sites dos SINDUSCONs e da revalidação periódica das URLs
e layouts (ver seção "Manutenção das fontes" na documentação de regras).
Estados que publicam o CUB apenas em PDF requerem a implementação do parser
`pdf` (hook já declarado em `scraper.py`).
