# Comparação consolidada das Features — **José Mauro × Brandão × Pierre**

> **Objetivo:** confrontar, variável a variável e seller a seller, as três
> implementações da Feature Store de produtos (Olist) — **José Mauro**, **Brandão**
> e **Pierre** — apontando onde os números **fecham** e onde **divergem**, com a
> **análise das causas**. Este arquivo unifica as comparações que antes estavam
> separadas (Brandão × Pierre e José Mauro × demais).
>
> 📊 A **planilha consolidada** (`Comparacao_FeatureStore_JM_Brandao_Pierre.xlsx`,
> com os valores dos três lado a lado por seller, a versão empilhada para agregação
> e o detalhe das células divergentes) **não é versionada** — é entregue pelo chat.

## Insumos

| Pessoa | Fonte | Observação |
| --- | --- | --- |
| **Brandão** | `ativacaoOlistProdutos` (tabelão no `featureStore-gabriel.ipynb`) | Query única que monta toda a feature store (§1–§8) por `seller_id`. |
| **Pierre** | `Feature Store - Pierre.ipynb` (branch `feat/pierre`) | Notebook Spark, query única. |
| **José Mauro** | `FS_Produtos_JoseMauro.xlsx` (arquivo dele) | 2.750 sellers × 79 variáveis, `datareferencia = 2018-06-30`. A branch `feat/josemauro` está **vazia**; o trabalho real veio só por este arquivo. |

As três implementações foram re-executadas **sobre a mesma base** (`dados/olist_*`)
e o **mesmo universo** — **2.750 sellers, sem duplicidade, corte 2018-06-30** — e
comparadas por `seller_id`.

## Método (alinhamento de janelas)

O arquivo do José Mauro está fixo em `datareferencia = 2018-06-30`. A convenção de
janela dele foi descoberta empiricamente (0 divergências em `vlProdutosDistintos` em
**todas** as janelas):

```
janela N  ⇒  order_purchase_timestamp ∈ [ datetime('2018-06-30', '-N dias') ; '2018-07-01' )
```

ou seja, **janelas ancoradas na data de referência (2018-06-30)** e universo/Vida até
**2018-06-30 inclusive**. Brandão e Pierre, no código nativo, ancoram as janelas em
`deploy_date = 2018-07-01`. Para a comparação de **valor**, Brandão e Pierre foram
alinhados à convenção do José Mauro, de modo que a divergência restante seja de
**lógica / unidade / definição**, e não artefato de calendário.

> ⚠️ **Divergência de convenção (registrada à parte):** rodando cada um com a sua
> própria data-parâmetro, as variáveis janeladas (D14/D28/D56/D365) divergem ~1 dia
> na borda inferior, porque **o José Mauro ancora as janelas na data de referência e
> Brandão/Pierre na data de deploy (referência + 1 dia)**. Vida e universo não mudam.

Legenda: ✅ idêntico · 🟢 igual a menos de detalhe pontual · 🟡 diverge por
**definição** · 🟠 diverge por **unidade** · ⚪ não calculado por um dos três.

---

## 1. Resumo executivo (os três)

| # | Família | JM × Brandão | JM × Pierre | Brandão × Pierre | Causa principal |
| - | ------- | ------------ | ----------- | ---------------- | --------------- |
| 01 | **Categorias distintas** | 🟡 diverge (Vida: 250 sellers) | 🟡 diverge (idem) | ✅ idêntico | **Categoria ausente:** JM **não** conta o NULL como categoria; Brandão (`sem_categoria`) e Pierre (`NA`) contam +1. |
| 02 | Produtos distintos | ✅ idêntico | ✅ idêntico | ✅ idêntico | — |
| 03 | Peso do produto vendido (dist. + total) | ✅ idêntico | ✅ idêntico (arred.) | 🟠 unidade | **Unidade:** Brandão em **gramas**; JM e Pierre em **kg** (÷1000 = idêntico). Totais já em kg batem. |
| 04 | Cubagem (média/total) | ✅ idêntico | ✅ idêntico (arred.) | ✅ idêntico | — (cm³ nos três) |
| 05 | **Preço/kg e Frete/kg** | 🟢 2.748/2.750 | ✅ idêntico (arred.) | 🟢 borda | **2 sellers sem peso:** JM e Pierre mantêm `price`/`frete` do item no numerador (peso = 0 no denominador); Brandão exclui o item. |
| 06 | Caracteres da descrição + fotos | ✅ idêntico | ✅ idêntico (arred.) | ✅ idêntico | — (NULL → 0, produto distinto) |
| 07 | **Peso do portfólio** | 🟢 2.748/2.750 | ⚪ Pierre não calcula | ⚪ Pierre não calcula | **2 sellers sem peso:** JM conta o SKU sem peso como **0 kg**; Brandão ignora. `Total`/`Max` batem. |
| 08 | **Concorrência (cat/prod)** | ⚪ JM não calcula | ⚪ JM não calcula | 🔴 **diverge muito** | **Definição:** Pierre **soma** exposições por categoria/produto (double-count); Brandão conta **sellers distintos**. |
| 09 | **Top 3 categorias + share** | ⚪ JM não calcula | ⚪ JM não calcula | 🔴 **diverge** | **Critério:** Pierre ranqueia por **receita**; Brandão por **unidades vendidas**. + rótulo do NULL (`NA` vs `sem_categoria`). |

**Conclusão em uma frase:** as três feature stores são, na prática,
**metodologicamente equivalentes** no núcleo de variáveis que têm em comum — fecham
em ~100% das células. As divergências reais e localizadas são: (1) contagem de
**categorias distintas** (categoria ausente), (2) tratamento de **peso ausente**
(2 sellers), além das diferenças cosméticas de **unidade** (Brandão em g) e
**arredondamento** (Pierre). As divergências grandes (concorrência e top-categoria)
existem **só entre Brandão e Pierre**, em variáveis que o José Mauro não calculou.

---

## 2. Detalhe por família

### 🟡 01 — Categorias distintas (DIVERGE — definição: categoria ausente)

`COUNT(DISTINCT categoria)` por janela. Divergência sistemática e pequena (sempre −1):

| Janela | Sellers que divergem | % igual | Direção |
| --- | --- | --- | --- |
| D14 | 6 | 99,78% | JM = Brandão − 1 |
| D28 | 13 | 99,53% | JM = Brandão − 1 |
| D56 | 28 | 98,98% | JM = Brandão − 1 |
| D365 | 198 | 92,80% | JM = Brandão − 1 |
| Vida | 250 | 90,91% | JM = Brandão − 1 |

**Causa:** quando o produto não tem `product_category_name`, Brandão troca por
`'sem_categoria'` e Pierre por `'NA'` — ambos **contam a "categoria ausente" como uma
categoria**. O José Mauro deixa o NULL como está e o `COUNT(DISTINCT)` o **descarta**
→ para os **250 sellers** com ≥1 produto sem categoria, o JM fica exatamente **1
abaixo**. Brandão e Pierre concordam entre si. Não é bug; é decisão de modelagem.

### ✅ 02 — Produtos distintos (BATE 100%)

`COUNT(DISTINCT product_id)` por janela: **0 divergências** nos três. Foi a variável
usada para **calibrar o alinhamento de janela** (0 diffs ⇒ convenção do JM
reproduzida corretamente).

### ✅/🟠 03 — Peso do produto vendido (BATE em lógica; difere só na UNIDADE)

Distribuição (média/mediana/P25/P75/mín/máx) por unidade vendida, janelada, + total.
**JM × Brandão = 100% idêntico após normalizar a unidade.** Brandão reporta a
distribuição em **gramas**; JM e Pierre em **kg**. Contra o Pierre, a única diferença
é o **arredondamento** (3 casas; `maxdif ≈ 0,0005`). Totais já batem (kg nos três).

### ✅ 04 — Cubagem (BATE 100%)

`length × height × width` (cm³), média e total por unidade, janeladas. Idêntico nos
três (Pierre arredonda a 1 casa).

### 🟢 05 — Preço/kg e Frete/kg (BATE em 2.748/2.750; 2 sellers de borda)

D14/D28/D56 batem **100%**. Em D365/Vida divergem **exatamente 2 sellers**
(`4e922959…`, `8b8cfc83…`) — os **únicos 2 da base com produto sem peso**:

| seller | JM | Pierre | Brandão |
| --- | --- | --- | --- |
| `4e922959…` (Preço/kg Vida) | 212,21 | 212,21 | 209,46 |
| `8b8cfc83…` (Preço/kg Vida) | 67,19 | 67,19 | 56,26 |

**Causa:** JM e Pierre somam o `price`/`freight_value` do item sem peso no
**numerador**, mas o item entra com **peso 0** no denominador → infla o R$/kg. Brandão
**exclui** o item de numerador e denominador (razão sobre a mesma população, mais
consistente). Impacto mínimo (2/2.750).

### ✅ 06 — Caracteres da descrição e fotos (BATE 100%)

Estáticas, por produto distinto, NULL → 0. Idênticas nos três (Pierre arredonda a 1
casa — `maxdif ≤ 0,05`, cosmético).

### 🟢 07 — Peso do portfólio (BATE em 2.748/2.750) · Pierre não calcula

SKU distinto, estático. **`Total` e `Max` batem 100%.** Em `Min/Média/Mediana/P25/P75`
divergem os **mesmos 2 sellers sem peso**:

| seller | métrica | JM | Brandão (kg) |
| --- | --- | --- | --- |
| `4e922959…` | Mín portfólio | **0,0** | 0,05 |
| `8b8cfc83…` | Média portfólio | 12,33 | 14,80 |

**Causa:** no portfólio, o JM mantém o SKU sem peso e o trata como **0 kg**; Brandão
**descarta** SKUs sem peso. Curiosidade: na §3 (peso **vendido**) o próprio JM ignora
o item sem peso (lá bate 100% com o Brandão) — ou seja, o JM trata "peso ausente" de
forma **diferente entre §3 e §8**. O **Pierre não implementou** o portfólio.

### 🔴 08 — Concorrência (só Brandão × Pierre — JM não calcula)

Divergência **conceitual**, a maior entre Brandão e Pierre:

* **Brandão:** para o seller A, nº de **outros sellers distintos** que atuam em alguma
  categoria/produto em comum (`COUNT(DISTINCT concorrente)` — um concorrente que
  divide 3 categorias conta **1**).
* **Pierre:** `SUM(ctDistinctCatSellers − hadCatSale)` somando **por categoria do
  seller** — um concorrente que divide 3 categorias conta **3** (soma de exposições,
  double-count). O valor do Pierre é sempre **≥** o do Brandão.

Em D14 (categoria), ~2.383/2.750 sellers divergem. Não é bug — são leituras de
negócio diferentes (concorrentes únicos vs exposição por categoria), **não
intercambiáveis**.

### 🔴 09 — Top 3 categorias e share (só Brandão × Pierre — JM não calcula)

Duas causas somadas:

1. **Critério de ranking (principal):** Pierre ranqueia por **receita** (`SUM(price)`,
   share = share de receita); Brandão por **unidades vendidas** (`COUNT(*)`, desempate
   unidades → pedidos → categoria). A líder muda quando o produto mais caro não é o
   mais vendido — em `descTopCategoria1Vida`, ~244/2.750 sellers trocam de top-1.
2. **Rótulo da categoria NULL (secundário):** Pierre usa `'NA'`, Brandão
   `'sem_categoria'` → onde o top-1 é a categoria ausente, o nome difere (~86 sellers).

---

## 3. Síntese das causas

1. **NULL de categoria** (impacto maior): contar ou não a "categoria ausente" como
   categoria. → única divergência que atinge muitos sellers (250) entre JM e os demais.
2. **Peso ausente** (impacto mínimo, 2 sellers): manter o item como 0 kg (JM/Pierre no
   R$/kg; JM no portfólio) vs. descartá-lo (Brandão). Há ainda uma **inconsistência
   interna no JM** (ignora na §3, mantém como 0 na §8).
3. **Unidade da distribuição de peso**: gramas (Brandão) vs. kg (JM/Pierre).
4. **Arredondamento** (Pierre): puramente cosmético.
5. **Convenção de janela** (calendário): ancoragem na data de referência (JM) vs. data
   de deploy (Brandão/Pierre) — neutralizada na comparação de valor.
6. **Definições divergentes Brandão × Pierre** (concorrência: distinto vs soma;
   top-categoria: unidades vs receita) — em variáveis que o José Mauro não calculou.

**Para unificar as três feature stores** bastaria alinhar: (a) regra do NULL de
categoria, (b) tratamento do peso ausente, (c) unidade do peso e — entre Brandão e
Pierre — (d) definição de concorrência e (e) critério de ranking de categoria.
