# Comparação — Feature Store de Produtos: **José Mauro × Brandão × Pierre**

> **Objetivo:** confrontar, variável a variável e seller a seller, as features
> calculadas pelo **José Mauro** com as minhas (**Brandão**) e as do **Pierre**,
> apontando onde os números **fecham** e onde **divergem** — com a **análise das
> causas** de cada divergência. É a contrapartida, agora incluindo o José Mauro, da
> [`comparacao.md`](comparacao.md) (que confrontou Brandão × Pierre).
>
> 📊 A **planilha consolidada** (`Comparacao_FeatureStore_JM_Brandao_Pierre.xlsx`,
> com os valores dos três lado a lado por seller e o detalhe das 508 células
> divergentes) **não está versionada** — foi entregue pelo chat.

## Insumos

| Pessoa | Fonte | Observação |
| --- | --- | --- |
| **José Mauro** | `FS_Produtos_JoseMauro.xlsx` (arquivo dele) | 2.750 sellers × 79 variáveis, `datareferencia = 2018-06-30`. A branch `feat/josemauro` está **vazia**; o trabalho real veio só por este arquivo. |
| **Brandão** | `features_spark/ativacaoOlistProdutos.sql` (esta branch) | Tabelão final; re-executado localmente sobre os CSVs Olist (DuckDB). |
| **Pierre** | `Feature Store - Pierre.ipynb` (branch `feat/pierre`) | Notebook Spark; re-executado localmente (DuckDB). |

As três implementações foram rodadas **sobre a mesma base** e o **mesmo universo**
(2.750 sellers, sem duplicidade, corte 2018-06-30), comparadas por `seller_id`.

## Como o teste foi feito (alinhamento de janelas)

O arquivo do José Mauro está fixo em `datareferencia = 2018-06-30`. A convenção de
janela dele foi descoberta empiricamente (0 divergências em `vlProdutosDistintos`
em **todas** as janelas):

```
janela N  ⇒  order_purchase_timestamp ∈ [ datetime('2018-06-30', '-N dias') ; '2018-07-01' )
```

isto é, **janelas ancoradas na própria data de referência (2018-06-30)** e
universo/Vida até **2018-06-30 inclusive**. Brandão e Pierre, no código nativo,
ancoram as janelas em `deploy_date = 2018-07-01`. Para a comparação de **valor**,
Brandão e Pierre foram alinhados à convenção do José Mauro — assim a divergência
restante é de **lógica / unidade / definição**, e não artefato de calendário.

> ⚠️ **Divergência de convenção (à parte):** rodando cada um com a sua própria
> data-parâmetro, as variáveis janeladas (D14/D28/D56/D365) divergiriam ~1 dia na
> borda inferior, pois **o José Mauro ancora as janelas na data de referência e
> Brandão/Pierre na data de deploy (referência + 1 dia)**. Vida e universo não mudam.

---

## Resumo executivo (tabelado)

Legenda: ✅ idêntico · 🟢 igual a menos de detalhe pontual · 🟡 diverge por
**definição** · 🟠 diverge por **unidade** · ⚪ não calculado por um dos três.

| # | Família | JM × Brandão | JM × Pierre | Causa |
| - | ------- | ------------ | ----------- | ----- |
| 01 | **Categorias distintas** | 🟡 **diverge** (D365: 198, Vida: 250 sellers) | 🟡 **diverge** (idem) | **Definição:** o JM **não conta a categoria ausente** como categoria; Brandão (`sem_categoria`) e Pierre (`NA`) rotulam o NULL e contam +1. Afeta os **250 sellers** com ≥1 produto sem categoria. |
| 02 | Produtos distintos | ✅ **idêntico** (100%) | ✅ **idêntico** | — |
| 03 | Peso do produto vendido (média/mediana/P25/P75/min/máx/total) | ✅ **idêntico** (100%) | ✅ idêntico (a menos do **arredondamento** do Pierre) | **Unidade:** Brandão reporta a distribuição em **gramas**; JM e Pierre em **kg** — após ÷1000 são idênticos. Totais já batem (kg). |
| 04 | Cubagem (média/total) | ✅ **idêntico** (100%) | ✅ idêntico (arredondamento) | — (cm³ nos três) |
| 05 | **Preço/kg e Frete/kg** | 🟢 **2.748/2.750 iguais** | ✅ idêntico (arredondamento) | **2 sellers sem peso:** JM mantém o `price`/`frete` do item sem peso no numerador (peso = 0 no denominador) — **igual ao Pierre**; Brandão **exclui** o item de numerador e denominador. |
| 06 | Caracteres da descrição + fotos | ✅ **idêntico** (100%) | ✅ idêntico (Pierre arredonda p/ 1 casa) | — (NULL → 0, produto distinto, nos três) |
| 07 | **Peso do portfólio** | 🟢 **2.748/2.750 iguais** | ⚪ **Pierre não calcula** | **2 sellers sem peso:** no portfólio o JM mantém o SKU sem peso e o conta como **0 kg** (puxa Min/Média/percentis); Brandão **ignora** SKUs sem peso. `Total` e `Max` batem. |
| — | Concorrência (cat/prod) | ⚪ **JM não calcula** | ⚪ JM não calcula | Existe só em Brandão/Pierre — ver `comparacao.md` (Brandão DISTINTO; Pierre SOMA). |
| — | Top 3 categorias + share | ⚪ **JM não calcula** | ⚪ JM não calcula | Existe só em Brandão/Pierre — Brandão por **unidades**, Pierre por **receita**. |

**Conclusão em uma frase:** a feature store do José Mauro é, na prática,
**metodologicamente igual à do Brandão e à do Pierre** — fecham em ~100% das células.
As **únicas divergências reais** são (1) a contagem de **categorias distintas**, (2)
o tratamento de **peso ausente** em 2 sellers; o restante é **unidade** (Brandão em
g) e **arredondamento** (Pierre).

---

## Detalhamento e análise de causas

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

**Causa:** quando o produto não tem `product_category_name`, eu troco por
`'sem_categoria'` e o Pierre por `'NA'` — ambos **passam a contar a "categoria
ausente" como uma categoria**. O José Mauro deixa o NULL como está, e o
`COUNT(DISTINCT)` o **descarta** → para os **250 sellers** que venderam ≥1 produto
sem categoria, o JM fica exatamente **1 abaixo**. (Brandão e Pierre concordam entre
si aqui.) Não é bug — é decisão de modelagem: "ausência de categoria é uma
categoria?". O JM diz que não. **Ação sugerida:** alinhar a regra do NULL antes de
unir as feature stores (senão essa coluna fica deslocada em ~9% dos sellers).

### ✅ 02 — Produtos distintos (BATE 100%)

`COUNT(DISTINCT product_id)` por janela: **0 divergências** nos três. Foi a variável
usada para **calibrar o alinhamento de janela** (0 diffs ⇒ convenção do JM
reproduzida corretamente).

### ✅/🟠 03 — Peso do produto vendido (BATE em lógica; difere só na UNIDADE)

Distribuição por unidade vendida, janelada, + total. **JM × Brandão = 100% idêntico
após normalizar a unidade.** Brandão reporta a distribuição em **gramas**
(`product_weight_g`); JM e Pierre em **kg**. Multiplicando o JM por 1000 (ou
dividindo o Brandão), a divergência some. Contra o Pierre, a única diferença é o
**arredondamento** dele (3 casas; `maxdif ≈ 0,0005`). **Ação sugerida:** padronizar
a unidade (a convenção de `variaveis.md` é gramas na distribuição).

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
Eu (Brandão) **excluo** o item sem peso de numerador **e** denominador (razão sobre
a mesma população). **JM = Pierre**; ambos diferem de mim só nesses 2 sellers. A
minha razão é a metodologicamente mais consistente, mas o impacto é mínimo (2/2.750).

### ✅ 06 — Caracteres da descrição e fotos (BATE 100%)

Estáticas, por produto distinto, NULL → 0. Idênticas nos três (Pierre arredonda a 1
casa — `maxdif ≤ 0,05`, cosmético; ex.: `vlMediaFotosProdutos`).

### 🟢 07 — Peso do portfólio (BATE em 2.748/2.750; 2 sellers de borda) · Pierre não tem

SKU distinto, estático. **`Total` e `Max` batem 100%.** Em `Min/Média/Mediana/P25/P75`
divergem os **mesmos 2 sellers sem peso**:

| seller | métrica | JM | Brandão (kg) |
| --- | --- | --- | --- |
| `4e922959…` | Mín portfólio | **0,0** | 0,05 |
| `8b8cfc83…` | Mín portfólio | **0,0** | 7,75 |
| `8b8cfc83…` | Média portfólio | 12,33 | 14,80 |

**Causa:** no **portfólio**, o JM mantém o SKU sem peso e o trata como **0 kg**
(arrasta Min/Média/percentis); eu **descarto** SKUs sem peso. Curiosidade: na §3
(peso **vendido**) o próprio JM **ignora** o item sem peso (lá bate 100% comigo) — ou
seja, o JM trata "peso ausente" de forma **diferente entre §3 e §8**. O **Pierre não
implementou** o portfólio.

---

## Possíveis causas das diferenças — síntese

1. **Tratamento do NULL de categoria** (impacto maior): contar ou não a "categoria
   ausente" como categoria. → única divergência que atinge muitos sellers (250).
2. **Tratamento do peso ausente** (impacto mínimo, 2 sellers): manter o item como
   0 kg (JM/Pierre no R$/kg; JM no portfólio) vs. descartá-lo (Brandão). Há ainda uma
   **inconsistência interna no JM** (ignora na §3, mas mantém como 0 na §8).
3. **Unidade da distribuição de peso**: gramas (Brandão) vs. kg (JM/Pierre).
4. **Arredondamento** (Pierre): 3 casas em peso, 1 em cubagem/caracteres/fotos, 2 em
   R$/kg — diferença puramente cosmética.
5. **Convenção de janela** (calendário): ancoragem na data de referência (JM) vs.
   data de deploy (Brandão/Pierre) — neutralizada na comparação de valor.

Para **unificar** as três feature stores bastaria alinhar (1) a regra do NULL de
categoria, (2) o tratamento do peso ausente e (3) a unidade do peso.
