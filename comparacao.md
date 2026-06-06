# Comparação — Feature Store do Pierre × Features locais

> **Objetivo:** confrontar as variáveis construídas no notebook
> [`Feature Store - Pierre.ipynb`](Feature%20Store%20-%20Pierre.ipynb) com as features
> locais validadas em [`features_sqlite/`](features_sqlite/), rodando **as duas
> implementações sobre o mesmo `olist.db`** (cutoff **2018-07-01**, 2.750 sellers) e
> medindo, coluna a coluna, onde os números batem e onde divergem — com o **motivo**
> de cada divergência.

## Como o teste foi feito

A query do notebook do Pierre (um único pipeline de CTEs em Spark SQL) foi
**re-implementada fielmente em SQLite** no script
[`scripts/compare_pierre.py`](scripts/compare_pierre.py), traduzindo só o dialeto:

| Spark (Pierre) | SQLite (teste) |
| --- | --- |
| `MEAN` | `AVG` |
| `MEDIAN` / `PERCENTILE(x,p)` | UDF agregada tipo-7 (interpolação linear) — a mesma usada nas nossas features |
| `DATE_SUB(deploy_date, N)` | `datetime('2018-07-01','-N days')` |
| `IFNULL` / `COALESCE` | `COALESCE` |
| filtro de safra `< deploy_date` | `< '2018-07-01'` (corte estrito, idêntico ao nosso) |

Cada família foi executada lado a lado com o bloco principal do `.sql` local
correspondente e comparada **por `seller_id`** (tolerância numérica `1e-6`). Ambos os
lados retornam **2.750 sellers, sem duplicidade** — o universo é idêntico.

---

## Resumo executivo

| # | Família | `.sql` local | Resultado | Causa da divergência |
| - | ------- | ------------ | --------- | -------------------- |
| 01 | Categorias distintas | `01_vlCategoriasDistintas` | ✅ **idêntico** | — |
| 02 | Produtos distintos | `02_vlProdutosDistintos` | ✅ **idêntico** | — |
| 03 | Concorrentes por categoria | `03_vlContagemCategoriaConcorrentes` | 🔴 **diverge muito** | **definição diferente** — Pierre **soma** concorrentes por categoria (double-count); nós contamos **sellers distintos** |
| 04 | Concorrentes por produto | `04_vlContagemProdutosConcorrentes` | 🔴 **diverge** | idem (soma vs distinto) |
| 05 | Descrição (caracteres) | `05_vlCaracteresDescricao` | ✅ **idêntico** | — |
| 06 | Fotos do produto | `06_vlMediaFotosProduto` | ✅ **idêntico** | — |
| 07 | Peso do produto vendido | `07_vlPesoProduto` | 🟠 **diverge por unidade** | Pierre em **kg**, nós em **gramas** (totais batem) |
| 08 | Cubagem | `08_vlCubagemProdutos` | ✅ **idêntico** | — |
| 09 | Preço por kg | `09_vlPrecoKg` | 🟡 **quase idêntico** | tratamento do **peso NULL no numerador** (2 sellers) |
| 10 | Frete por kg | `10_vlFreteKg` | 🟡 **quase idêntico** | idem (2 sellers) |
| 11 | Top categorias | `11_descTopCategoria` | 🔴 **diverge** | **critério de ranking**: Pierre por **receita** (`SUM(price)`), nós por **unidades vendidas** + rótulo do NULL |
| 12 | Share da top categoria | `12_vlShareTopCategoria` | 🔴 **diverge** | idem (receita vs unidades) |
| 08b | Portfólio (peso do catálogo) | `13_vlPesoPortfolio` | ⚪ **só existe localmente** | Pierre não tem a família §8 |

**Legenda:** ✅ bate · 🟡 diverge em pouquíssimos sellers (caso de borda) · 🟠 diverge
de forma sistemática mas por motivo trivial (unidade) · 🔴 diverge por **decisão de
modelagem diferente**.

---

## Detalhamento por família

### ✅ 01 / 02 — Categorias e produtos distintos (BATE)

`COUNT(DISTINCT product_category_name)` e `COUNT(DISTINCT product_id)` por janela.
**0 divergências** nas 5 janelas. As duas implementações usam o mesmo grão (seller),
o mesmo corte e o mesmo `COUNT(DISTINCT … CASE WHEN janela)`. Nada a observar.

> Nota: o rótulo de categoria NULL difere (Pierre usa `'NA'`, nós `'sem_categoria'`),
> mas isso **não** afeta a *contagem* de categorias distintas — só os top categoria
> (§11). Aqui ambos contam o NULL como uma categoria a mais, identicamente.

---

### 🔴 03 / 04 — Contagem de concorrentes (DIVERGE — definição diferente)

Esta é a divergência **conceitual mais importante**.

* **Nossa definição** (`03`/`04`): para o seller A, **número de _outros sellers
  distintos_** (B ≠ A) que atuam em **alguma** categoria/produto em comum com A na
  janela. Usamos `COUNT(DISTINCT b.seller_id)` — um concorrente que divide **3**
  categorias com A conta **1 vez**.

* **Definição do Pierre** (`tb_category_competitity` / `tb_product_competitity`):
  `SUM(ctDistinctCatSellers − hadCatSale)` somando **sobre cada categoria do seller**.
  Isso conta, para cada categoria de A, quantos sellers (menos o próprio) vendem nela,
  e **soma** esses totais. Um concorrente que divide 3 categorias com A é contado
  **3 vezes**. É, na prática, uma **soma de exposições por categoria**, não uma
  contagem de concorrentes únicos.

**Evidência (D14, exemplos do teste):**

| seller | Pierre (soma) | Nosso (distinto) |
| --- | --- | --- |
| `834f8533…` | 222 | 44 |
| `ba6b4a23…` | 79 | 0 |
| `1b8b75e2…` | 22 | 0 |

`2.383 / 2.750` sellers divergem em D14 (cat). O valor do Pierre é **sempre ≥** o
nosso, e a diferença encolhe nas janelas longas (D365/Vida) porque lá quase todo seller
já tem muitas categorias e o efeito de double-count se dilui menos — mas continua.

> Os casos `nosso=0 / pierre>0` (ex. `ba6b4a23`) acontecem quando o seller **não teve
> venda na janela curta**: no nosso modelo ele "não está no mercado" → 0 concorrentes;
> no do Pierre, a flag `hadCatSale14d=0` mas `ctDistinctCatSellers14d` da categoria
> ainda traz os concorrentes daquela janela, gerando contagem positiva mesmo sem o
> seller ter vendido. **São duas leituras de negócio distintas**, não um bug de um lado
> só — mas **não são intercambiáveis**.

`04` (produto) tem o mesmo mecanismo, com magnitude bem menor (`135–250` sellers),
porque poucos sellers vendem o mesmo `product_id` (concorrência direta é rara).

---

### ✅ 05 / 06 — Descrição (caracteres) e fotos (BATE)

`0 divergências` em todas as 6 estatísticas de descrição (média, min, P25, mediana,
P75, max) e na média de fotos. As duas implementações concordam em **tudo** que
importa aqui:

* grão = **produto distinto** (`DISTINCT seller_id, product_id`) — o SKU não repete;
* **NULL → 0** (`COALESCE`) tanto em descrição quanto em fotos (nossa decisão D12);
* percentil tipo-7 idêntico ao `PERCENTILE`/`MEDIAN` do Spark.

Convergência total — inclusive os 580 produtos de cadastro vazio entram como 0 dos
dois lados.

---

### 🟠 07 — Peso do produto vendido (DIVERGE só na UNIDADE: g × kg)

A **lógica é idêntica** (peso por **unidade vendida**, sem DISTINCT, janelado; mesma
distribuição média/mediana/P25/P75/min/max + total). A única diferença:

* **Pierre:** `product_weight_g / 1000` → reporta a distribuição em **quilogramas**.
* **Nós:** mantemos a distribuição em **gramas** (só o `vlTotalPesoProdutos` é convertido
  para kg).

**Prova:** ao multiplicar a média do Pierre por 1000, a divergência cai para **0
sellers** (`vlMediaPesoProdutoVida`). Exemplos: `pierre=6.92 kg` ↔ `nosso=6920.5 g`;
`pierre=0.1375 kg` ↔ `nosso=137.5 g`. **O `vlTotalPeso` já bate (ambos em kg): 0
divergências.**

> Não é erro — é escolha de unidade. **Ação sugerida:** padronizar (a convenção de
> `variaveis.md` é reportar a distribuição em gramas; o Pierre converteu tudo para kg).
> Se o tabelão for unir os dois, a coluna de distribuição precisa estar na **mesma
> unidade** ou o modelo verá escalas 1000× diferentes.

---

### ✅ 08 — Cubagem (BATE)

`product_length_cm × height × width`, média e total **por unidade vendida**, janelado,
em **cm³** dos dois lados. Mesma fórmula, mesma unidade, mesmo grão → convergente.

---

### 🟡 09 / 10 — Preço e frete por kg (DIVERGE em 1–2 sellers — caso de borda)

Praticamente idênticos: D14/D28/D56 batem **100%**; só **D365 (1 seller)** e
**Vida (2 sellers)** divergem. Causa:

* **Nós:** a base de `vlPrecoKg` **filtra `product_weight_g IS NOT NULL` já na origem**
  — itens sem peso ficam **fora do numerador e do denominador**. A razão é coerente
  (mesma base em cima e embaixo).
* **Pierre:** o numerador (`vlReceitaTot`) soma **todo** `price` (sem filtro de peso),
  enquanto o denominador (`vlTotalPesoProduto`) trata peso NULL como 0. Logo, a
  **receita de itens sem peso entra no numerador mas não no denominador**, inflando o
  R$/kg.

**Evidência:** `seller 4e922959…`: `pierre=212.21` vs `nosso=209.46` (Vida).
`seller 8b8cfc83…`: `pierre=67.19` vs `nosso=56.26`. Afeta **só os 2 sellers que
venderam algum produto sem peso** (são 2 produtos sem peso na base inteira), por isso o
impacto é mínimo — mas a nossa razão é a metodologicamente correta (numerador e
denominador sobre a mesma população).

---

### 🔴 11 / 12 — Top categorias e share (DIVERGE — critério de ranking)

Duas causas somadas:

1. **Critério de ordenação (principal).**
   * **Pierre** ranqueia categoria por **receita**: `SUM(price)` (`tb_cat_receita` →
     `ROW_NUMBER ORDER BY vlReceitaCategoria DESC`). O share é **share de receita**.
   * **Nós** ranqueamos por **quantidade vendida = unidades** (`COUNT(*)` de linhas de
     `order_items`), desempate unidades→pedidos→categoria (decisão **D9** do cliente,
     que segue o texto de `variaveis.md` §6/§7). O share é **share de unidades**.
   * Resultado: a categoria líder muda quando o produto mais caro do seller **não** é o
     mais vendido em quantidade. Em `descTopCategoria1Vida`, **244 / 2.750** sellers
     trocam de top‑1 por esse motivo real.

2. **Rótulo da categoria NULL (secundário).** Pierre usa `'NA'`, nós usamos
   `'sem_categoria'`. Onde o top‑1 é a categoria ausente, o **nome** difere mesmo
   com a mesma posição: **86 / 2.750** sellers divergem só por isso (são 250 sellers
   com ≥1 item sem categoria).

Total em `descTopCategoria1Vida`: **330 sellers** divergem = **244 (ranking) + 86
(rótulo)**. O share (`12`) diverge em **1.196 / 2.750** sellers porque receita e
unidades quase nunca dão a mesma proporção.

**Exemplo:** `seller 834f8533…` — top‑1 por **receita** = `bebes`; por **unidades** =
`pet_shop` (vende muita unidade barata de pet, mas fatura mais em bebês). São
**narrativas diferentes**, ambas válidas; a nossa segue a especificação travada (D9).

---

### ⚪ 08b / §8 — Portfólio (peso do catálogo): só existe localmente

A família `13_vlPesoPortfolio` (peso do **catálogo** do seller, por **SKU distinto**,
**estática** — §8 de `variaveis.md`) **não tem contrapartida no notebook do Pierre**.
O Pierre só modela o **peso vendido** (por unidade, janelado = nossa §3/`07`). Não há o
que comparar — é uma feature a mais do nosso lado.

> ⚠ Lembrete de modelagem: **§3 (peso vendido, por unidade, janelado)** ≠ **§8
> (peso do portfólio, SKU distinto, estático)**. São duas famílias distintas; o Pierre
> só tem a primeira.

---

## Conclusão

* **Batem 100%:** diversidade de catálogo (01/02), descrição/fotos (05/06), cubagem
  (08). Aqui as duas implementações são intercambiáveis.
* **Divergência trivial (unidade):** peso (07) — só **g × kg**; os totais já batem.
  Padronizar a unidade resolve.
* **Divergência de borda:** preço/frete por kg (09/10) — 1–2 sellers, por causa do
  tratamento do peso NULL no numerador. Nossa razão é a mais consistente.
* **Divergência de DEFINIÇÃO (atenção):**
  * **Concorrência (03/04):** Pierre **soma exposições por categoria/produto**
    (double-count), nós contamos **sellers concorrentes distintos**. Valores e
    significado bem diferentes.
  * **Top categorias / share (11/12):** Pierre ranqueia por **receita**, nós por
    **unidades vendidas** (decisão travada D9). Lideranças e shares mudam para boa
    parte dos sellers.
* **Cobertura:** o Pierre **não** tem a família **§8 portfólio** (`13`).

As divergências 🔴 **não são bugs** — são escolhas de modelagem distintas. As nossas
seguem as decisões travadas em `CLAUDE.md`/`variaveis.md` (D7, D9, D12). Para unificar
as duas feature stores seria preciso alinhar: **(a)** unidade do peso, **(b)**
definição de concorrência (distinto vs soma) e **(c)** critério de ranking de categoria
(unidades vs receita).

---

*Teste reprodutível:* `python scripts/compare_pierre.py` (gera o diff coluna a coluna
sobre `olist.db`, cutoff 2018-07-01).
