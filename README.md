# olist-ativacao-t06

Projeto de **predição de (in)ativação de vendedores (sellers) na Olist**.

Objetivo de negócio: identificar antecipadamente os sellers com alta
probabilidade de **não realizar nenhuma venda no próximo mês (X+1)**. A previsão
roda no último dia útil do mês X; as features usam todo o histórico com
`order_purchase_timestamp < {data_corte}`.

Esta entrega são os **scripts de feature engineering por variável** (lista e
convenção de nomenclatura em [`variaveis.md`](variaveis.md)), validados em
**SQLite** e traduzidos para **Spark SQL (Databricks)**. São **12 scripts** por
dialeto, um por família de variável, nomeados pelo nome oficial da variável
(ex.: `07_vlPesoProduto.sql`).

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
├── variaveis.md                   # lista de variáveis + convenção de nomes (input)
├── brazilian-ecommerce-metadata.json
├── dados/                         # 9 CSVs do Kaggle (cada CSV = uma tabela)
├── docs/
│   └── variaveis_detalhadas.md    # documentação detalhada (a "bíblia")
├── analise_variaveis.ipynb        # notebook: roda e mostra a tabela de cada variável
├── scripts/
│   ├── build_sqlite.py            # CSVs (dados/) -> olist.db
│   ├── run_feature_sqlite.py      # roda/valida um .sql contra olist.db
│   └── build_notebook.py          # (re)gera o analise_variaveis.ipynb a partir dos .sql
├── features_sqlite/               # 12 scripts validados (SQLite) — 1 por família
│   └── 01_vlCategoriasDistintas.sql … 12_vlShareTopCategoria.sql
└── features_spark/                # 12 scripts equivalentes (Spark SQL, workspace.olist.*)
    └── 01_vlCategoriasDistintas.sql … 12_vlShareTopCategoria.sql
```

Cada arquivo cobre **uma família de variável** com as **4 janelas**
(`D28/D56/D365/Vida`) e as colunas no nome oficial da convenção (`vl…`/`desc…`),
quando aplicável. São **estáticas** (só Vida, sem sufixo) as métricas de
**atributo imutável do produto**: descrição, fotos e a **distribuição** de peso e
cubagem. Os **totais** de peso/cubagem (massa/volume embarcado) e os demais
mantêm as 4 janelas.

## Como executar

### 1. Validação local (SQLite)

Pré-requisito: **Python 3** (usa só a biblioteca padrão — `csv` + `sqlite3`).
Os 9 CSVs do dataset já estão em [`dados/`](dados/).

```powershell
# monta o banco de validação (olist.db) a partir dos CSVs
python scripts/build_sqlite.py

# roda/inspeciona qualquer feature (substitui {data_corte} e valida)
python scripts/run_feature_sqlite.py features_sqlite/01_vlCategoriasDistintas.sql --cutoff 2018-07-01
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
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';   -- já vem no topo do script
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
corte equivale a "fotografar ao fim do mês X". Default de teste: `2018-07-01`
(janela definida pelo Téo; dados vão de set/2016 a out/2018). Nesse corte há
**2.750 sellers** com ≥1 venda no histórico.

## Decisões de modelagem (resumo)

- **Data da venda/corte:** `order_purchase_timestamp` (nunca nulo; é o evento de
  venda; sem leakage). *Não* `order_approved_at` (160 nulos) nem
  `order_delivered_customer_date` (futuro/leaky).
- **Definição de venda:** **todo pedido realizado conta** — sem filtro de
  `order_status`.
- **Grão:** 1 linha por `seller_id` em um `{data_corte}` parametrizado.
- **Universo:** sellers com ≥1 venda antes do corte.
- **Características de produto (descrição, fotos, peso, cubagem):** estatísticas
  de distribuição (média/mediana/percentis/min/max) usam **produtos distintos
  por seller** (`DISTINCT product_id`), para o mesmo SKU vendido em vários
  pedidos não enviesar. Como são **atributos imutáveis** do produto, a
  distribuição é **estática** (não varia no tempo → sem janela). Já **totais** de
  peso/cubagem e **razões R$/kg** somam por **unidade vendida** (massa/volume
  embarcados, receita e frete reais) e **mantêm as 4 janelas**. **Descrição e
  fotos NULL contam como 0** (produto sem cadastro entra e puxa média/mínimo).
- **Top 3 categorias e share:** ranking por **quantidade vendida** (unidades);
  share = unidades da categoria / unidades totais da janela.
- Demais premissas (janelas, nulos, percentis, desempates) em
  [docs/variaveis_detalhadas.md](docs/variaveis_detalhadas.md) §3.

## O que está / não está no escopo

**Está:** as variáveis de `variaveis.md` (12 scripts por dialeto) em SQLite +
Spark, documentadas e validadas localmente.

**Não está (próximos passos):** definição/cálculo do **alvo** de churn (vender ou
não em X+1), montagem da feature store larga, treino do modelo.
```
