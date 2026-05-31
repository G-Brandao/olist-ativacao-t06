# olist-ativacao-t06

Projeto de **predição de (in)ativação de vendedores (sellers) na Olist**.

Objetivo de negócio: identificar antecipadamente os sellers com alta
probabilidade de **não realizar nenhuma venda no próximo mês (X+1)**. A previsão
roda no último dia útil do mês X; as features usam todo o histórico com
`order_purchase_timestamp < {data_corte}`.

Esta entrega são os **scripts de feature engineering por variável** (lista em
[`variaveis.md`](variaveis.md)), validados em **SQLite** e traduzidos para
**Spark SQL (Databricks)**.

## Documentação principal

A explicação detalhada de **cada variável** (definição, fórmula, escolha de
datas, premissas, casos de borda, sinal para o modelo e mini-exemplo) está em
[**docs/variaveis_detalhadas.md**](docs/variaveis_detalhadas.md) — comece por lá.

Contexto persistente do projeto/assistente em [`CLAUDE.md`](CLAUDE.md).

## Arquitetura: desenvolvimento híbrido

| Camada | Onde | Para quê |
| ------ | ---- | -------- |
| **Validação local** | SQLite (`olist.db`, gerado dos CSVs em `dados/`) | testar a regra de negócio, JOINs e janelas de tempo sem alucinação |
| **Produção** | Spark SQL no Databricks, tabelas `workspace.olist.*` | execução real |

Os scripts Spark diferem dos de SQLite **apenas** por: (1) prefixo de namespace
`workspace.olist.`; (2) funções de dialeto (`timestamp()`, `INTERVAL N DAYS`,
`percentile()`).

## Estrutura do repositório

```
olist-ativacao-t06/
├── README.md                      # este arquivo
├── CLAUDE.md                      # contexto + planejamento/progresso
├── variaveis.md                   # lista original das 14 variáveis (input)
├── brazilian-ecommerce-metadata.json
├── dados/                         # 9 CSVs do Kaggle (cada CSV = uma tabela)
├── docs/
│   └── variaveis_detalhadas.md    # documentação detalhada (a "bíblia")
├── analise_variaveis.ipynb        # notebook: roda e mostra a tabela de cada variável
├── scripts/
│   ├── build_sqlite.py            # CSVs (dados/) -> olist.db
│   ├── run_feature_sqlite.py      # roda/valida um .sql contra olist.db
│   └── build_notebook.py          # (re)gera o analise_variaveis.ipynb a partir dos .sql
├── features_sqlite/               # 14 scripts validados (SQLite) — 1 por variável
│   └── 01_..._14_...sql
└── features_spark/                # 14 scripts equivalentes (Spark SQL, workspace.olist.*)
    └── 01_..._14_...sql
```

Cada arquivo cobre **uma variável** com as **4 janelas** (`_d28/_d56/_d365/_vida`)
no mesmo script, quando aplicável.

## Como executar

### 1. Validação local (SQLite)

Pré-requisito: **Python 3** (usa só a biblioteca padrão — `csv` + `sqlite3`).
Os 9 CSVs do dataset já estão em [`dados/`](dados/).

```powershell
# monta o banco de validação (olist.db) a partir dos CSVs
python scripts/build_sqlite.py

# roda/inspeciona qualquer feature (substitui {data_corte} e valida)
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --cutoff 2018-09-01
```

Ou abra **[`analise_variaveis.ipynb`](analise_variaveis.ipynb)** e rode célula a
célula: cada seção tem a explicação + o SQL e renderiza a tabela da variável
(`seller_id` × colunas). Troque `DATA_CORTE` na célula de setup para mudar o corte.
Requer `pandas` (`pip install pandas`).

### 2. Produção (Databricks / Spark SQL)

Em um notebook do Databricks, abra/cole o script desejado e rode — cada
`features_spark/NN_*.sql` **já cria o widget no topo** e usa o parameter marker
`:data_corte`:

```sql
CREATE WIDGET TEXT data_corte DEFAULT '2018-09-01';   -- já vem no topo do script
-- ... WHERE order_purchase_timestamp < timestamp(:data_corte)
```

Troque a data **num único ponto**: o widget (UI) ou o `DEFAULT`. No SQL Editor
(warehouse) remova a linha `CREATE WIDGET` — o `:data_corte` vira parâmetro
automático. (Não use `${data_corte}`: é a sintaxe legada que o Databricks pede
para abandonar.)

As tabelas devem existir como `workspace.olist.orders`,
`workspace.olist.order_items`, `workspace.olist.products`,
`workspace.olist.sellers`, etc.

## Parâmetro de corte

Ponto único de troca em cada dialeto: **SQLite** usa o token `'{data_corte}'`
(substituído pelo runner via `--cutoff`); **Spark/Databricks** usa o widget
`data_corte` lido por `:data_corte`. Semântica: **estrito**
`order_purchase_timestamp < <corte>`. Usar a **primeira data do mês X+1** como
corte equivale a "fotografar ao fim do mês X". Default de teste: `2018-09-01`
(dados vão de set/2016 a out/2018).

## Decisões de modelagem (resumo)

- **Data da venda/corte:** `order_purchase_timestamp` (nunca nulo; é o evento de
  venda; sem leakage). *Não* `order_approved_at` (160 nulos) nem
  `order_delivered_customer_date` (futuro/leaky).
- **Definição de venda:** **todo pedido realizado conta** — sem filtro de
  `order_status`.
- **Grão:** 1 linha por `seller_id` em um `{data_corte}` parametrizado.
- **Universo:** sellers com ≥1 venda antes do corte.
- Demais premissas (janelas, nulos, percentis, desempates) em
  [docs/variaveis_detalhadas.md](docs/variaveis_detalhadas.md) §3.

## O que está / não está no escopo

**Está:** as 14 variáveis de `variaveis.md` em SQLite + Spark, documentadas e
validadas localmente.

**Não está (próximos passos):** definição/cálculo do **alvo** de churn (vender ou
não em X+1), montagem da feature store larga, treino do modelo.
```
