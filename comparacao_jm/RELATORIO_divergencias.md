# Comparação — Feature Store de Produtos: **José Mauro × Brandão × Pierre**

> **Objetivo:** consolidar, no mesmo formato, as variáveis calculadas pelos três e
> apontar, **variável a variável e seller a seller**, onde os números **fecham** e
> onde **divergem** — com o **motivo** de cada divergência. É a contrapartida, agora
> incluindo o José Mauro, da [`comparacao.md`](../comparacao.md) que confrontou
> Brandão × Pierre.

## Insumos

| Pessoa | Fonte | Observação |
| --- | --- | --- |
| **José Mauro** | `FS_Produtos_JoseMauro.xlsx` (anexo dele) | 2.750 sellers × 79 variáveis, `datareferencia = 2018-06-30`. A branch `feat/josemauro` está **vazia** — o trabalho real veio só por este arquivo. |
| **Brandão** | `features_spark/ativacaoOlistProdutos.sql` (branch `feat/brandao`) | Tabelão final; re-executado localmente sobre os CSVs Olist via DuckDB. |
| **Pierre** | `Feature Store - Pierre.ipynb` (branch `feat/pierre`) | Notebook Spark; re-executado localmente via DuckDB. |

As três implementações foram rodadas **sobre a mesma base** (`dados/olist_*`,
corte/universo de 2018-06-30) para uma comparação coluna a coluna por `seller_id`.
**Universo idêntico nos três: 2.750 sellers, sem duplicidade.**

## Como o teste foi feito (alinhamento de janelas)

O arquivo do José Mauro está fixo em `datareferencia = 2018-06-30`. Descobrimos
empiricamente a convenção de janela dele (0 divergências em `vlProdutosDistintos`
em **todas** as janelas):

```
janela N  ⇒  order_purchase_timestamp ∈ [ datetime('2018-06-30', '-N dias') ; '2018-07-01' )
```

ou seja, **janelas ancoradas na própria data de referência (2018-06-30)** e
universo/Vida até **2018-06-30 inclusive**. O Brandão e o Pierre, no código nativo,
ancoram as janelas em `deploy_date = 2018-07-01` (um dia "mais apertado"). Para a
comparação de **valor**, alinhamos Brandão e Pierre à convenção do José Mauro
(ancoragem em 2018-06-30) — assim qualquer divergência restante é de **lógica /
unidade / definição**, e não um artefato de calendário.

> ⚠️ **Divergência de convenção (registrada à parte):** se cada um rodar com a sua
> própria data-parâmetro, as variáveis janeladas (D14/D28/D56/D365) divergem por
> ~1 dia na borda inferior, porque **o José Mauro ancora as janelas na data de
> referência e Brandão/Pierre na data de deploy (referência + 1 dia)**. Vida e
> universo não são afetados.

---

## Resumo executivo

Legenda: ✅ idêntico · 🟢 igual a menos de detalhe pontual · 🟡 diverge por
**definição** · 🟠 diverge por **unidade** · ⚪ não calculado por um dos três.

| # | Família | JM × Brandão | JM × Pierre | Causa |
| - | ------- | ------------ | ----------- | ----- |
| 01 | **Categorias distintas** | 🟡 **diverge** (D365: 198, Vida: 250 sellers) | 🟡 **diverge** (idem) | **Definição:** o JM **não conta a categoria ausente** como categoria; Brandão (`sem_categoria`) e Pierre (`NA`) rotulam o NULL e contam +1. Afeta os **250 sellers** com ≥1 produto sem categoria. |
| 02 | Produtos distintos | ✅ **idêntico** (100%) | ✅ **idêntico** | — |
| 03 | Peso do produto vendido (média/mediana/P25/P75/min/max/total) | ✅ **idêntico** (100%) | ✅ idêntico (a menos do **arredondamento** do Pierre) | **Unidade:** Brandão reporta a distribuição em **gramas**; JM e Pierre em **kg** — após ÷1000 são idênticos. Totais já batem (kg). |
| 04 | Cubagem (média/total) | ✅ **idêntico** (100%) | ✅ idêntico (arredondamento) | — (cm³ nos três) |
| 05 | **Preço/kg e Frete/kg** | 🟢 **2.748/2.750 iguais** | ✅ idêntico (arredondamento) | **2 sellers sem peso:** JM mantém o `price`/`frete` do item sem peso no numerador (peso vira 0 no denominador) — **igual ao Pierre**; Brandão **exclui** o item de numerador e denominador. |
| 06 | Caracteres da descrição + fotos | ✅ **idêntico** (100%) | ✅ idêntico (Pierre arredonda p/ 1 casa) | — (NULL → 0, produto distinto, nos três) |
| 07 | **Peso do portfólio** | 🟢 **2.748/2.750 iguais** | ⚪ **Pierre não calcula** | **2 sellers sem peso:** no portfólio (§8) o JM mantém o SKU sem peso e o conta como **0 kg** (puxa Min/Média/percentis); Brandão **ignora** SKUs sem peso. `Total` e `Max` batem. |
| — | Concorrência (cat/prod) | ⚪ **JM não calcula** | ⚪ JM não calcula | Existe só em Brandão/Pierre — ver `comparacao.md` (Brandão conta DISTINTO; Pierre SOMA). |
| — | Top 3 categorias + share | ⚪ **JM não calcula** | ⚪ JM não calcula | Existe só em Brandão/Pierre — Brandão por **unidades**, Pierre por **receita**. |

**Conclusão de uma frase:** a feature store do José Mauro é, na prática,
**metodologicamente igual à do Brandão e à do Pierre** — fecham em ~100% das células.
As **únicas divergências reais** são: (1) a contagem de **categorias distintas**
(o JM não conta a categoria ausente), (2) o tratamento de **peso ausente** em 2
sellers (portfólio e R$/kg), além das diferenças cosméticas de **unidade** (Brandão
em g) e **arredondamento** (Pierre).

---

## Detalhamento por família

### 🟡 01 — Categorias distintas (DIVERGE — definição)

`COUNT(DISTINCT categoria)` por janela. Divergência **sistemática e numericamente
pequena (sempre −1)**:

| Janela | Sellers que divergem | % igual | Direção |
| --- | --- | --- | --- |
| D14 | 6 | 99,78% | JM = Brandão − 1 |
| D28 | 13 | 99,53% | JM = Brandão − 1 |
| D56 | 28 | 98,98% | JM = Brandão − 1 |
| D365 | 198 | 92,80% | JM = Brandão − 1 |
| Vida | 250 | 90,91% | JM = Brandão − 1 |

**Causa:** quando o produto não tem `product_category_name`, Brandão troca por
`'sem_categoria'` e Pierre por `'NA'` — ambos **passam a contar a "categoria
ausente" como uma categoria a mais**. O José Mauro deixa o NULL como está, e o
`COUNT(DISTINCT)` o **descarta** → para os **250 sellers** que venderam ≥1 produto
sem categoria, o JM fica exatamente **1 abaixo**. (O Brandão e o Pierre concordam
entre si nesta família.) Não é bug — é decisão de modelagem: "ausência de categoria
é uma categoria?" O JM diz que não.

### ✅ 02 — Produtos distintos (BATE 100%)

`COUNT(DISTINCT product_id)` por janela: **0 divergências** nas 5 janelas, nos três.
Foi inclusive a variável usada para **calibrar o alinhamento de janela** (0 diffs ⇒
convenção de janela do JM corretamente reproduzida).

### ✅/🟠 03 — Peso do produto vendido (BATE em lógica; difere só na UNIDADE)

Distribuição (média, mediana, P25, P75, mín, máx) **por unidade vendida**, janelada,
+ total. **JM × Brandão = 100% idêntico após normalizar a unidade.** O detalhe:

* **Brandão** reporta a distribuição em **gramas** (`product_weight_g`); só o
  `vlTotalPesoProdutos` é convertido para kg.
* **JM** e **Pierre** reportam **tudo em kg**.

Multiplicando o JM por 1000 (ou dividindo o Brandão), a divergência some. Contra
o Pierre, a única diferença é o **arredondamento** dele (3 casas) — `maxdif ≈ 0,0005`.

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

**Causa:** o JM (e o Pierre) somam o `price`/`freight_value` do item sem peso no
**numerador**, mas esse item entra com **peso 0** no denominador → infla o R$/kg.
O Brandão **exclui** o item sem peso de numerador **e** denominador. **JM = Pierre**;
ambos diferem do Brandão só nesses 2 sellers.

### ✅ 06 — Caracteres da descrição e fotos (BATE 100%)

Estáticas, por produto distinto, NULL → 0. Idênticas nos três (o Pierre arredonda a
1 casa — `maxdif ≤ 0,05`, puramente cosmético; ex.: `vlMediaFotosProdutos`).

### 🟢 07 — Peso do portfólio (BATE em 2.748/2.750; 2 sellers de borda) · Pierre não tem

SKU distinto, estático. **`Total` e `Max` batem 100%.** Em `Min/Média/Mediana/P25/P75`
divergem os **mesmos 2 sellers sem peso**:

| seller | métrica | JM | Brandão (kg) |
| --- | --- | --- | --- |
| `4e922959…` | Min portfólio | **0,0** | 0,05 |
| `8b8cfc83…` | Min portfólio | **0,0** | 7,75 |
| `8b8cfc83…` | Média portfólio | 12,33 | 14,80 |

**Causa:** no **portfólio**, o JM mantém o SKU sem peso e o trata como **0 kg**
(arrasta Min/Média/percentis para baixo); o Brandão **descarta** SKUs sem peso.
Curiosidade: na §3 (peso **vendido**) o próprio JM **ignora** o item sem peso (lá
bate 100% com o Brandão) — ou seja, o JM trata "peso ausente" de forma **diferente
entre §3 e §8**. O **Pierre não implementou** a família de portfólio.

---

## Arquivos entregues (`comparacao_jm/`)

| Arquivo | Conteúdo |
| --- | --- |
| `Comparacao_FeatureStore_JM_Brandao_Pierre.xlsx` | Planilha consolidada — 3 abas: **`resumo_variaveis`** (visão por variável: % iguais, divergem, maxdif, classificação e causa), **`consolidado_valores`** (2.750 sellers × cada variável lado a lado `__JM` / `__Brandao` / `__Pierre`, já em unidade comparável), **`divergencias_JM_Brandao_detalhe`** (as 508 células seller×variável que de fato divergem). |
| `FS_Produtos_JoseMauro.xlsx` | Arquivo-fonte do José Mauro (insumo). |
| `scripts/brandao_tabelao.sql`, `scripts/pierre.sql` | SQL nativo de cada um (extraído das branches). |
| `scripts/01_run_brandao_pierre.py` | Traduz Brandão e Pierre p/ DuckDB, alinha à janela do JM e roda sobre os CSVs. |
| `scripts/02_comparar_e_consolidar.py` | Faz o mapeamento de variáveis (nomes/unidades), compara e gera o `.xlsx`. |

**Reprodutível:** com os CSVs Olist em `dados/`, rode `01_run_brandao_pierre.py`
e depois `02_comparar_e_consolidar.py`.
