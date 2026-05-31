# Variáveis do modelo de ativação de sellers Olist — guia detalhado

> Documento-bíblia do projeto. Explica, **uma a uma**, as 14 variáveis de
> `variaveis.md`, com fórmula, premissas, escolha de datas, casos de borda,
> sinal para o modelo e mini-exemplo numérico. Cada variável tem um script
> validado em **SQLite** (`features_sqlite/`) e o equivalente em **Spark SQL /
> Databricks** (`features_spark/`, namespace `workspace.olist.`).
>
> ⚠️ Este documento substitui o rascunho inicial (que descrevia um pipeline
> DuckDB nunca construído). As premissas abaixo são as **vigentes**.

---

## Sumário

1. [Objetivo de negócio](#1-objetivo-de-negócio)
2. [Visão geral do dataset](#2-visão-geral-do-dataset-olist)
3. [Premissas globais](#3-premissas-globais)
4. [Catálogo de variáveis](#4-catálogo-de-variáveis)
5. [Arquitetura de execução (SQLite ↔ Spark)](#5-arquitetura-de-execução-sqlite--spark)
6. [Dicionário consolidado das colunas](#6-dicionário-consolidado-das-colunas)

---

## 1. Objetivo de negócio

Queremos prever a **(in)ativação de sellers**: identificar antecipadamente os
vendedores que **não realizarão nenhuma venda no próximo mês (X+1)**. A previsão
roda no último dia útil do mês X; usamos todo o histórico **anterior ao corte**
para montar features e o comportamento em X+1 vira o alvo (alvo fora do escopo
desta entrega — aqui entregamos apenas as variáveis explicativas).

Cada variável tenta capturar um aspecto da **saúde da operação** do seller:

- tamanho/diversidade do portfólio (itens 1, 2);
- pressão competitiva ao redor do seller (itens 3, 4);
- qualidade do cadastro (itens 5, 10);
- perfil físico dos produtos vendidos (itens 6, 7, 8, 9);
- economia das vendas (itens 11, 12);
- especialização do seller (itens 13, 14).

A intuição central: **encolhimento** (de portfólio, volume, massa) e
**fragilidade** (concentração, alta concorrência) entre janelas longas (D365) e
curtas (D28) são pistas fortes de churn iminente.

---

## 2. Visão geral do dataset Olist

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce):
~100k pedidos de **set/2016 a out/2018**. Usamos a fato `order_items` conectada a
`orders`, `products` e `sellers`.

```
order_items (fato: 1 linha por unidade vendida)
  ├─ order_id   → orders   (status, datas: purchase, approved, delivered, ...)
  ├─ product_id → products (categoria, peso, dimensões, fotos, descrição)
  └─ seller_id  → sellers  (cidade, UF)
products.product_category_name → product_category_name_translation (pt → en)
```

Notas relevantes verificadas no `olist.db` local (cutoff 2018-09-01):
- `order_status`: `delivered` (96.478), `shipped` (1.107), `canceled` (625),
  `unavailable` (609), `invoiced` (314), `processing` (301), `created` (5),
  `approved` (2).
- **160 pedidos** têm `order_approved_at` NULL — motivo central de usarmos
  `order_purchase_timestamp` como data de venda (ver Premissa 3.2).
- `products`: **610** com `product_category_name` NULL e descrição/`lenght`
  NULL; **2** com `product_weight_g` NULL.
- Erros de grafia originais **mantidos**: `product_name_lenght`,
  `product_description_lenght`.
- Integridade: todo `seller_id`/`product_id` de `order_items` existe nas dims.

---

## 3. Premissas globais

Valem para **todas** as variáveis. Foram revisadas e confirmadas com o cliente.

### 3.1 Grão de saída

Cada script produz **1 linha por `seller_id`**, avaliada em **um único corte
parametrizado** (não há painel de snapshots). A previsão roda mensalmente trocando
o corte num só ponto: token `{data_corte}` no SQLite (via `run_feature_sqlite.py
--cutoff`) ou o widget `data_corte`/marker `:data_corte` no Databricks.

### 3.2 Data da venda e corte — `order_purchase_timestamp` (decisão travada)

A "venda" é datada por **`order_purchase_timestamp`** e o corte é **estrito**:
`order_purchase_timestamp < '{data_corte}'`.

- *Por que purchase e não `order_approved_at`?* O enunciado citava `approved_at`
  como exemplo, mas ele é **NULL em 160 pedidos** (que sumiriam do filtro) e
  representa a aprovação do pagamento, não o ato de vender. `purchase_timestamp`
  **nunca é nulo** e marca exatamente o momento em que o seller "fez a venda" —
  alinhado à definição de ativação. Menor risco de leakage.
- *Por que não `order_delivered_customer_date`?* A entrega ocorre dias/semanas
  depois, tem muitos NULLs e olharia para o futuro em relação ao corte
  (leakage); inadequada para um modelo que roda no fim do mês.

### 3.3 Definição de "venda" — sem filtro de status (decisão travada)

**Todo pedido realizado conta como venda**, independentemente de
`order_status` (inclusive `canceled`/`unavailable`). O que importa para
ativação é que houve um pedido atribuído ao seller. Não filtramos status.

### 3.4 Janelas temporais

Variáveis marcadas com `*` em `variaveis.md` são calculadas em 4 janelas
**semi-abertas à direita** (honrando `data_venda < corte`):

| Janela | Sufixo  | Intervalo de `order_purchase_timestamp`          |
| ------ | ------- | ------------------------------------------------- |
| D28    | `_d28`  | `[corte − 28 dias, corte)`                        |
| D56    | `_d56`  | `[corte − 56 dias, corte)`                        |
| D365   | `_d365` | `[corte − 365 dias, corte)`                       |
| Vida   | `_vida` | `(−∞, corte)` — todo o histórico                  |

As variáveis **sem** `*` (itens 5, 10, 13, 14) são calculadas só na **Vida**.
Como D28 ⊂ D56 ⊂ D365 ⊂ Vida, usamos **agregação condicional** numa única CTE
base (um `CASE WHEN dt_venda >= corte − N` por janela), o que traduz 1:1 entre
SQLite e Spark. Métricas de contagem são, por construção, monotônicas
(`d28 ≤ d56 ≤ d365 ≤ vida`) — usado como teste de sanidade.

### 3.5 "Produto/categoria do período" = o que o seller VENDEU

Não há tabela de "catálogo com datas" na Olist; o único sinal de que um seller
oferta um produto/categoria é **tê-lo vendido**. Logo "no período" = vendido na
janela. Catálogo declarado mas nunca vendido não entra.

### 3.6 Ponderação por unidade vendida

`order_items` tem 1 linha por unidade. Logo `AVG`/`SUM`/percentis sobre a fato
já vêm **ponderados por volume** — desejado para perfil físico (itens 6–9, 11,
12). **Exceção:** itens 5 e 10 (descrição, fotos) são propriedades de
**cadastro** → tomamos `DISTINCT product_id` para cada produto pesar 1.

### 3.7 Nulos e divisões por zero

- Universo = sellers com ≥1 venda com `purchase < corte`. Sem venda no histórico
  ⇒ seller nem aparece. No cutoff de teste (2018-09-01) os **3.095** sellers
  aparecem.
- **Contagens** (itens 1–4): janela sem venda ⇒ **0** (não há "desconhecido").
- **Estatísticas numéricas** (itens 6–9, 11, 12): janela sem venda ⇒ **NULL**
  (a ausência é sinal de churn; imputar 0 enviesaria).
- **Divisões** (itens 11, 12): denominador 0/NULL ⇒ **NULL** (`CASE WHEN`).
- `product_category_name` NULL ⇒ rótulo **`'sem_categoria'`** (para não sumir do
  `DISTINCT`). Peso/dimensões NULL são ignorados pelas agregações.

### 3.8 Desempate de rankings (itens 13, 14)

Top categorias ordenadas por: (1) maior **receita `SUM(price)`**; (2) maior nº
de **pedidos distintos**; (3) ordem **alfabética** (estabilidade determinística).

---

## 4. Catálogo de variáveis

Numeração igual à de [`variaveis.md`](../variaveis.md). Itens com `*` → 4 colunas
(uma por janela); sem `*` → 1 conjunto de colunas (Vida).

---

### 4.1 Categorias distintas no período `*`

| | |
| --- | --- |
| **Colunas** | `qtd_categorias_distintas_{d28,d56,d365,vida}` |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `features_sqlite/01_qtd_categorias_distintas.sql` · `features_spark/01_...` |

**Definição.** Nº de `product_category_name` distintos de produtos vendidos pelo
seller na janela.

**Fórmula.** `COUNT(DISTINCT categoria)` por janela, com
`categoria = COALESCE(product_category_name, 'sem_categoria')`.

**Origem.** `order_items ⋈ orders` (data) `⋈ products` (categoria).

**Premissas/decisões.** Categoria vem do cadastro do produto; NULL →
`'sem_categoria'`.

**Casos de borda.** Janela sem venda ⇒ `0`.

**Sinal p/ churn.** Estreitamento do leque entre D365 e D28 sugere liquidação de
estoque antes de sair.

**Mini-exemplo (validado).** Seller `289cdb32…`:
`d28=2, d56=2, d365=4, vida=4` — conferido à mão no `olist.db`.

---

### 4.2 Produtos distintos no período `*`

| | |
| --- | --- |
| **Colunas** | `qtd_produtos_distintos_{d28,d56,d365,vida}` |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `.../02_qtd_produtos_distintos.sql` |

**Definição.** Nº de `product_id` distintos vendidos na janela.

**Fórmula.** `COUNT(DISTINCT product_id)` por janela.

**Premissas.** "Produto" = SKU (`product_id`); não agrupamos por nome/categoria.

**Casos de borda.** Janela sem venda ⇒ `0`.

**Sinal p/ churn.** A razão `d28 / d365` baixa indica portfólio encolhendo.

**Mini-exemplo (validado).** Seller `289cdb32…`:
`d28=10, d56=15, d365=25, vida=25`.

---

### 4.3 Sellers concorrentes em mesma categoria `*`

| | |
| --- | --- |
| **Colunas** | `qtd_concorrentes_mesma_categoria_{d28,d56,d365,vida}` |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `.../03_concorrentes_mesma_categoria.sql` |

**Definição.** Para o seller A, nº de **outros** sellers (B≠A) que venderam em
**alguma categoria em comum** com A na mesma janela (concorrência **indireta**).

**Fórmula.** Sobre pares `DISTINCT (seller_id, categoria)` da janela:
```sql
COUNT(DISTINCT b.seller_id)
FROM sc a JOIN sc b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
GROUP BY a.seller_id
```

**Auto-crítica (duplicação?).** O `DISTINCT (seller, categoria)` antes do
self-join + `COUNT(DISTINCT b.seller_id)` garantem que um concorrente que
compartilha 2 categorias seja contado **uma vez**. Sem explosão de linhas.

**Premissas.** Medida simétrica; categoria NULL → `'sem_categoria'`. Estar numa
categoria popular gera centenas de concorrentes — é feature, não bug.

**Casos de borda.** Janela sem venda ⇒ `0` (não está no mercado).

**Sinal p/ churn.** Concorrência alta + receita caindo = saída por dificuldade
competitiva.

**Performance (Spark).** Self-join pode sofrer *skew* em categorias muito
populares; aceitável neste volume (dataset pequeno).

---

### 4.4 Sellers concorrentes no mesmo produto `*`

| | |
| --- | --- |
| **Colunas** | `qtd_concorrentes_mesmo_produto_{d28,d56,d365,vida}` |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `.../04_concorrentes_mesmo_produto.sql` |

**Definição.** Análoga à 4.3, trocando `categoria` por `product_id`: nº de
outros sellers que venderam o **mesmo SKU** na janela (concorrência **direta**).

**Premissas.** No dataset, **1.225 `product_id`** são vendidos por >1 seller, o
que torna a métrica informativa (o cliente teria a opção literal de comprar de
outro seller).

**Casos de borda.** Janela sem venda ⇒ `0`.

**Sinal p/ churn.** Muitos concorrentes no mesmo SKU ⇒ exposição a guerra de
preço ⇒ stress que antecipa churn.

---

### 4.5 Estatísticas de caracteres da descrição (sem `*`)

| | |
| --- | --- |
| **Colunas** | `desc_chars_media`, `desc_chars_p25`, `desc_chars_mediana`, `desc_chars_p75`, `desc_chars_min`, `desc_chars_max` |
| **Tipo** | numérico ≥ 0 (Vida) |
| **Scripts** | `.../05_desc_chars_estatisticas.sql` |

**Definição.** Média, percentis 25/50/75, mínimo e máximo de
`product_description_lenght` sobre os **produtos distintos** vendidos pelo seller.

**Premissas/decisões.** Cada **produto pesa 1** (`DISTINCT product_id`) — é
propriedade de **cadastro**, não de venda (premissa 3.6). Calculado só na Vida.

**Percentil — divergência de dialeto (documentada).** SQLite **não** tem
`percentile()`. Implementamos o percentil **contínuo tipo-7** (interpolação
linear) via funções de janela: `idx=(n-1)·p`, `valor=v[⌊idx⌋]+frac·(v[⌊idx⌋+1]−v[⌊idx⌋])`.
É **exatamente** o que o `percentile(col, p)` do Spark calcula — validado contra
`numpy.percentile` (5 sellers, 0 divergências). O arquivo Spark usa
`percentile(L, 0.25/0.5/0.75)`; a estrutura interna difere mas a lógica é idêntica.

**Casos de borda.** Descrição NULL ignorada; seller sem produto com descrição →
6 colunas `NULL` (linha mantida via `spine`).

**Sinal p/ churn.** Descrição curta (p25 baixo) ⇒ cadastro de baixa qualidade ⇒
menor conversão.

**Mini-exemplo (validado).** Seller com pesos de descrição
`[186, 226.5(p25)…]` reproduz `numpy.percentile` na vírgula.

---

### 4.6 Peso médio e mediana dos produtos (`*`)

| | |
| --- | --- |
| **Colunas** | `peso_medio_g_{d28,d56,d365,vida}`, `peso_mediana_g_{...}` |
| **Tipo** | numérico ≥ 0 (gramas) |
| **Scripts** | `.../06_peso_medio_mediana.sql` |

**Definição.** Média e mediana de `product_weight_g` das **unidades vendidas** na
janela (ponderado por venda — premissa 3.6, **sem** DISTINCT).

**Premissas.** Gramas (preserva precisão; o total vai a kg no item 7). A mediana
usa o mesmo percentil tipo-7 da 4.5, ranqueado **dentro de cada janela**. No
Spark é `percentile(CASE WHEN <janela> THEN w END, 0.5)` (ignora NULL).

**Casos de borda.** Peso NULL ignorado; janela sem venda → `NULL` (média e
mediana). Validado contra numpy (5 sellers × 4 janelas, incluindo casos `n=0`).

**Sinal p/ churn.** Sellers de itens leves (joias, vestuário) têm dinâmica
diferente de itens pesados (eletro) — o modelo pode segmentar por aqui.

---

### 4.7 Peso total dos produtos (`*`)

| | |
| --- | --- |
| **Colunas** | `peso_total_kg_{d28,d56,d365,vida}` |
| **Tipo** | numérico ≥ 0 (kg) |
| **Scripts** | `.../07_peso_total.sql` |

**Definição.** Massa total (kg) de todas as unidades vendidas na janela:
`SUM(product_weight_g)/1000`.

**Premissas.** Cada unidade soma uma vez (grão da fato). Conversão g→kg para
escala amigável.

**Casos de borda.** Peso NULL não contribui; janela sem venda → `NULL`.

**Sinal p/ churn.** Massa enviada/mês muito baixa ⇒ operação reduzida ⇒ possível
inatividade próxima.

---

### 4.8 Cubagem média dos produtos (`*`)

| | |
| --- | --- |
| **Colunas** | `cubagem_media_cm3_{d28,d56,d365,vida}` |
| **Tipo** | numérico ≥ 0 (cm³) |
| **Scripts** | `.../08_cubagem_media.sql` |

**Definição.** Volume médio das unidades vendidas, ponderado por venda.
`cubagem = product_length_cm × product_height_cm × product_width_cm`.

**Premissas.** É o volume da **caixa de envio** (paralelepípedo), que importa
para frete — não o volume real do produto.

**Casos de borda.** Qualquer dimensão `NULL` ⇒ cubagem `NULL` ⇒ ignorada no
`AVG`; janela sem venda → `NULL`.

**Sinal p/ churn.** Combinada com peso, distingue perfis logísticos (volumoso vs.
compacto) que influenciam custo e competitividade.

---

### 4.9 Cubagem total dos produtos (`*`)

| | |
| --- | --- |
| **Colunas** | `cubagem_total_cm3_{d28,d56,d365,vida}` |
| **Tipo** | numérico ≥ 0 (cm³) |
| **Scripts** | `.../09_cubagem_total.sql` |

**Definição.** Volume total enviado na janela: `SUM(cubagem)` por unidade.

**Premissas/bordas.** Idem 4.8; janela sem venda → `NULL`.

**Sinal p/ churn.** Pareada com `peso_total_kg`, é uma variável de **escala** da
operação — encolhimento entre D365 e D28 sinaliza desaceleração.

---

### 4.10 Quantidade média de fotos por produto (sem `*`)

| | |
| --- | --- |
| **Coluna** | `qtd_fotos_media_por_produto` |
| **Tipo** | numérico ≥ 0 (Vida) |
| **Scripts** | `.../10_fotos_media_por_produto.sql` |

**Definição.** Média de `product_photos_qty` entre os **produtos distintos**
vendidos pelo seller (cada produto pesa 1 — cadastro).

**Casos de borda.** Fotos NULL ignoradas; seller sem produto com fotos → `NULL`
(linha mantida via `spine`).

**Sinal p/ churn.** Poucas fotos ⇒ menor conversão ⇒ maior risco de churn por
baixa performance de vitrine.

---

### 4.11 Preço por kg (`*`)

| | |
| --- | --- |
| **Colunas** | `preco_por_kg_{d28,d56,d365,vida}` |
| **Tipo** | numérico ≥ 0 (R$/kg) |
| **Scripts** | `.../11_preco_por_kg.sql` |

**Definição.** Receita total / massa total no período = `SUM(price) / SUM(kg)`.

**Premissas/decisões.**
- Receita = `price` (NÃO inclui frete — frete é o item 12).
- Numerador e denominador restritos aos itens com **peso não-nulo** (mesma base),
  para que o quociente seja coerente.
- `price` é por unidade (grão da fato) ⇒ `SUM(price)` é a receita total.
- Denominador `0`/`NULL` ⇒ `NULL` (via `NULLIF`).

**Casos de borda.** Janela sem venda (com peso) → `NULL`.

**Sinal p/ churn.** Alto valor agregado (preço/kg alto) ⇒ dinâmica distinta de
commodities; o modelo pode segmentar perfis por aqui.

**Mini-exemplo.** D28: 3×R$100/2kg + 2×R$50/1kg ⇒ receita 400, massa 8kg ⇒
`preco_por_kg_d28 = 50,0`.

---

### 4.12 Custo de frete por kg (`*`)

| | |
| --- | --- |
| **Colunas** | `frete_por_kg_{d28,d56,d365,vida}` |
| **Tipo** | numérico ≥ 0 (R$/kg) |
| **Scripts** | `.../12_frete_por_kg.sql` |

**Definição.** Frete total / massa total = `SUM(freight_value) / SUM(kg)`.

**Premissas.** `freight_value` já vem **alocado por item** pela Olist — não
fazemos rateio próprio. Mesma base de peso não-nulo; denominador `0`/`NULL` →
`NULL`.

**Sinal p/ churn.** Frete/kg alto indica produtos com restrição de envio
(frágeis, regiões remotas) ⇒ menor competitividade ⇒ predispõe a churn.

---

### 4.13 Top 3 categorias do vendedor (sem `*`)

| | |
| --- | --- |
| **Colunas** | `top1_categoria`, `top2_categoria`, `top3_categoria` (texto, pt) |
| **Tipo** | string ou `NULL` (Vida) |
| **Scripts** | `.../13_top3_categorias.sql` |

**Definição.** As 3 categorias com maior **receita acumulada** (`SUM(price)`) até
`{data_corte}`.

**Premissas/decisões.**
- Critério primário: **receita** `SUM(price)`. Alternativas (unidades, nº de
  pedidos) dariam resultados similares na maioria dos casos.
- Desempate determinístico (premissa 3.8): receita DESC → pedidos distintos DESC
  → categoria ASC. Usamos `ROW_NUMBER()` (não `RANK`) para garantir 1 categoria
  por posição.
- Categoria NULL → `'sem_categoria'` (pode legitimamente figurar no top).

**Casos de borda.** Seller com <3 categorias → posições inexistentes `NULL`
(monoproduto ⇒ `top2 = top3 = NULL`). Validado.

**Sinal p/ churn.** A *identidade* das top categorias é sinal categórico forte:
verticais sazonais (moda) têm churn estrutural diferente de perenes (eletrônicos).

---

### 4.14 Share das top 3 categorias (sem `*`)

| | |
| --- | --- |
| **Colunas** | `share_top1`, `share_top2`, `share_top3` (float em [0,1]) |
| **Tipo** | float ou `NULL` (Vida) |
| **Scripts** | `.../14_share_top3_categorias.sql` |

**Definição.** Fração da receita total (Vida) concentrada em cada uma das top 3
categorias: `receita(topk) / receita_total`.

**Premissas.** Mesmo ranking/desempate do item 13. `share_top1 + share_top2 +
share_top3 ≤ 1` (o resto está na 4ª categoria em diante).

**Casos de borda.** Seller com 1 categoria → `share_top1 = 1.0`, demais `NULL`
(validado). `receita_total = 0` → `NULL` (via `NULLIF`).

**Sinal p/ churn.** Concentração alta (`share_top1 > 0.9`) ⇒ seller frágil a
abalos de demanda de uma única categoria.

---

## 5. Arquitetura de execução (SQLite ↔ Spark)

**Validação local (SQLite).** `python scripts/build_sqlite.py` gera `olist.db`
(9 tabelas com nomes-base `orders`, `order_items`, `products`, `sellers`, …).
Rode/inspecione qualquer feature com:
```bash
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --cutoff 2018-09-01
# a feature é o bloco 1; as provas (seção ANÁLISE / PROVAS) começam no bloco 2:
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --list
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --block 2
```

**Produção (Spark/Databricks).** Os scripts em `features_spark/` referenciam
`workspace.olist.<tabela>` e usam o dialeto Spark (`timestamp(:data_corte)`,
`- INTERVAL N DAYS`, `percentile(...)`). Diferem dos de SQLite **apenas** por
prefixo de namespace + funções de dialeto + parametrização.

**Parametrização (difere por dialeto).**
- **SQLite:** token `'{data_corte}'` substituído por `run_feature_sqlite.py`
  (`--cutoff`); janelas via `datetime('{data_corte}', '-N days')`.
- **Spark/Databricks:** um widget no topo de cada query alimenta o **parameter
  marker** `:data_corte` (caminho recomendado pelo Databricks; sem o aviso de
  depreciação do `${...}`):
  ```sql
  CREATE WIDGET TEXT data_corte DEFAULT '2018-09-01';
  -- ... WHERE order_purchase_timestamp < timestamp(:data_corte)
  -- janelas: timestamp(:data_corte) - INTERVAL 28 DAYS
  ```
  No SQL Editor (warehouse) remova o `CREATE WIDGET` — o `:data_corte` vira um
  parâmetro automático. Evite `'{data_corte}'` entre aspas no Spark: é string
  literal e NÃO é substituído (gera erro de cast para TIMESTAMP).

**Provas embutidas (ANÁLISE / PROVAS).** Cada feature `.sql` (nos 2 dialetos)
traz, abaixo da query principal, uma seção com 2–3 sub-queries que **comprovam as
decisões** — p.ex. existência de NULLs (justifica `COALESCE`/`WHERE ... IS NOT
NULL`), visão linha-a-linha antes do agrupamento, `DISTINCT` vs por unidade,
componentes de razão com `NULLIF`, ranking/desempate e SKUs disputados por vários
sellers. Servem para responder rápido a questionamentos do time de dados ("por que
`COALESCE`?"). No SQLite rode-as por `--block N`; no Spark rode cada `SELECT` numa
célula (o widget também alimenta o `:data_corte` das provas). As provas SQLite
foram executadas no `olist.db` e reconfirmam os fatos do dataset (610 sem
categoria/descrição, 2 sem peso, 1.225 SKUs multi-seller).

**Validação realizada.** Os 14 scripts SQLite foram executados contra `olist.db`
(cutoff `2018-09-01`): todos retornam **3.095 sellers**, **sem duplicidade** de
`seller_id`. Contagens (itens 1–4) têm monotonia `d28 ≤ d56 ≤ d365 ≤ vida`
(0 violações em 3.095 linhas). Médias/percentis/totais (itens 5–12) e top/share
(13–14) batem **na vírgula** com `numpy`/cálculo manual em amostras aleatórias.

---

## 6. Dicionário consolidado das colunas

Mapa item → colunas. Itens com `*` geram 4 colunas (sufixos `_d28/_d56/_d365/_vida`).

| Item | Variável | Script (sem extensão) | Colunas |
| ---- | -------- | --------------------- | ------- |
| 1  | Categorias distintas `*`        | `01_qtd_categorias_distintas`     | `qtd_categorias_distintas_{W}` |
| 2  | Produtos distintos `*`          | `02_qtd_produtos_distintos`       | `qtd_produtos_distintos_{W}` |
| 3  | Concorrentes mesma categoria `*`| `03_concorrentes_mesma_categoria` | `qtd_concorrentes_mesma_categoria_{W}` |
| 4  | Concorrentes mesmo produto `*`  | `04_concorrentes_mesmo_produto`   | `qtd_concorrentes_mesmo_produto_{W}` |
| 5  | Estat. de descrição             | `05_desc_chars_estatisticas`      | `desc_chars_media/_p25/_mediana/_p75/_min/_max` |
| 6  | Peso médio e mediana `*`        | `06_peso_medio_mediana`           | `peso_medio_g_{W}`, `peso_mediana_g_{W}` |
| 7  | Peso total `*`                  | `07_peso_total`                   | `peso_total_kg_{W}` |
| 8  | Cubagem média `*`               | `08_cubagem_media`                | `cubagem_media_cm3_{W}` |
| 9  | Cubagem total `*`               | `09_cubagem_total`                | `cubagem_total_cm3_{W}` |
| 10 | Fotos média por produto         | `10_fotos_media_por_produto`      | `qtd_fotos_media_por_produto` |
| 11 | Preço por kg `*`                | `11_preco_por_kg`                 | `preco_por_kg_{W}` |
| 12 | Frete por kg `*`                | `12_frete_por_kg`                 | `frete_por_kg_{W}` |
| 13 | Top 3 categorias                | `13_top3_categorias`              | `top1_categoria`, `top2_categoria`, `top3_categoria` |
| 14 | Share top 3                     | `14_share_top3_categorias`        | `share_top1`, `share_top2`, `share_top3` |

**Contagem de features:** 10 itens com `*` × 4 janelas + 2 colunas extras do item 6
(peso tem 2 métricas → 8 colunas) = … na prática: itens `*` geram
`qtd(1) + qtd(1) + conc(1) + conc(1) + peso_medio(1)+peso_mediana(1) + peso_total(1)
+ cub_media(1) + cub_total(1) + preco(1) + frete(1)` = 11 métricas × 4 janelas =
**44 colunas**; mais item 5 (6) + item 10 (1) + item 13 (3) + item 14 (3) = **13
colunas** de Vida. Total: **57 colunas** de feature (+ `seller_id`).

> **Montagem opcional da feature store.** Esta entrega são scripts *por variável*
> (pedido do cliente). Para uma tabela larga única, basta `LEFT JOIN` dos 14
> resultados por `seller_id` (todos compartilham o mesmo universo de 3.095
> sellers no cutoff de teste, então os joins são 1:1).
