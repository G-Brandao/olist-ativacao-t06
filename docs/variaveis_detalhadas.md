# Variáveis do modelo de ativação de sellers Olist — guia detalhado

> Documento-bíblia do projeto. Explica, **uma a uma**, as variáveis de
> [`variaveis.md`](../variaveis.md) (convenção `[prefixo][Qualificador][Metrica][Periodo]`),
> com fórmula, premissas, escolha de datas, casos de borda, sinal para o modelo e
> mini-exemplo. Cada família de variável tem um script validado em **SQLite**
> (`features_sqlite/`) e o equivalente em **Spark SQL / Databricks**
> (`features_spark/`, namespace `workspace.olist.`). São **13 scripts por dialeto**
> (12 das 7 seções de `variaveis.md` + 1 de variáveis extras da revisão externa;
> `09`/`10` também ganharam colunas `Ajustado`).

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

- tamanho/diversidade do portfólio (§1 — catálogo);
- pressão competitiva ao redor do seller (§2 — concorrência);
- qualidade do cadastro (§3 — descrição, fotos);
- perfil físico dos produtos vendidos (§4 peso, §5 cubagem);
- economia das vendas (§6 — R$/kg de preço e frete);
- especialização do seller (§7 — top categorias e concentração).

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

Notas relevantes verificadas no `olist.db` local (**corte 2018-07-01**, janela
definida pelo Téo):
- **2.750 sellers** têm ≥1 venda antes do corte — é o universo de saída (todas as
  12 features retornam 2.750 linhas).
- **98.309** itens vendidos antes do corte.
- **87 pedidos** (< corte) têm `order_approved_at` NULL — motivo central de
  usarmos `order_purchase_timestamp` como data de venda (ver Premissa 3.2).
- Produtos distintos vendidos: **580** com `product_category_name`/descrição NULL;
  **2** com `product_weight_g` NULL.
- **980** `product_id` vendidos por >1 seller antes do corte (torna a §2 de
  concorrência direta informativa).
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
--cutoff`, default `2018-07-01`) ou o widget `data_corte`/marker `:data_corte` no
Databricks.

### 3.2 Data da venda e corte — `order_purchase_timestamp` (decisão travada)

A "venda" é datada por **`order_purchase_timestamp`** e o corte é **estrito**:
`order_purchase_timestamp < '{data_corte}'`.

- *Por que purchase e não `order_approved_at`?* `approved_at` é **NULL em alguns
  pedidos** (87 antes do corte) e representa a aprovação do pagamento, não o ato
  de vender. `purchase_timestamp` **nunca é nulo** e marca exatamente o momento em
  que o seller "fez a venda". Menor risco de leakage.
- *Por que não `order_delivered_customer_date`?* A entrega ocorre dias/semanas
  depois, tem muitos NULLs e olharia para o futuro (leakage).

### 3.3 Definição de "venda" — sem filtro de status (decisão travada)

**Todo pedido realizado conta como venda**, independentemente de
`order_status` (inclusive `canceled`/`unavailable`). O que importa para
ativação é que houve um pedido atribuído ao seller.

### 3.4 Janelas temporais

A maioria das variáveis é calculada em 4 janelas **semi-abertas à direita**
(honrando `data_venda < corte`):

| Janela | Sufixo | Intervalo de `order_purchase_timestamp` |
| ------ | ------ | ---------------------------------------- |
| D28    | `D28`  | `[corte − 28 dias, corte)`               |
| D56    | `D56`  | `[corte − 56 dias, corte)`               |
| D365   | `D365` | `[corte − 365 dias, corte)`              |
| Vida   | `Vida` | `(−∞, corte)` — todo o histórico         |

São **estáticas** (só Vida, sem sufixo) todas as métricas que descrevem
**atributos imutáveis do produto** (`products` tem 1 linha por `product_id`):
**§3 (descrição + fotos)** e a **distribuição de §4/§5 (peso e cubagem:
média/mediana/percentis/mín/máx)**. Esses valores **não mudam no tempo** — uma
janela só alteraria *quais* SKUs entram, nunca o valor de cada um; calcular
D28/D56/D365 seria redundante (provado empiricamente: nenhum `product_id` tem >1
valor de peso ou cubagem). **Mantêm as 4 janelas** as métricas que dependem de
**vendas** (crescem no tempo): contagens (§1, §2), **totais** de peso/cubagem
(massa/volume embarcado), indicadores por kg (§6) e top categorias/share (§7).
Como D28 ⊂ D56 ⊂ D365 ⊂ Vida, contagens e totais são, por construção,
**monotônicos** (`D28 ≤ D56 ≤ D365 ≤ Vida`) — usado como teste de sanidade.

> *Mudança (revisão do colega):* na v2, peso e cubagem tinham as 4 janelas
> também na distribuição. Como o atributo é estático, isso foi revertido —
> distribuição volta a ser estática (alinha com descrição/fotos); só os
> **totais** seguem com janelas. Ver [decisão D5](../CLAUDE.md#5-decisões-travadas-não-reabrir-sem-o-cliente).

### 3.5 "Produto/categoria do período" = o que o seller VENDEU

Não há tabela de "catálogo com datas" na Olist; o único sinal de que um seller
oferta um produto/categoria é **tê-lo vendido**. Logo "no período" = vendido na
janela.

### 3.6 Grão da estatística — DISTINCT vs unidade (decisão travada, atualizada)

`order_items` tem 1 linha por unidade. Há **dois grãos** conforme a entidade
avaliada:

- **Característica de produto → produto distinto.** As **estatísticas de
  distribuição** (média, mediana, percentis 25/50/75, mín, máx) de **descrição,
  fotos, peso e cubagem** descrevem o *produto*, não a venda. Tomamos
  **`DISTINCT product_id` por seller** para que o mesmo SKU vendido em vários
  pedidos **pese 1** e não enviese a estatística. Como esses atributos são
  **imutáveis** (premissa 3.4), a distribuição é **estática** (toda a vida do
  seller < corte) — **sem desdobramento por janela**.
- **Volume/economia da operação → unidade vendida.** **Totais** (`vlTotalPesoProdutos`,
  `vlTotalCubagemProdutos`) e **razões R$/kg** (§6) medem massa/volume embarcados
  e receita/frete reais — somam por **unidade** (cada linha de `order_items`) e,
  por dependerem de vendas, **mantêm as 4 janelas**. Ranking de top categorias
  (§7) também é por **unidades vendidas**.

### 3.7 Nulos e divisões por zero

- Universo = sellers com ≥1 venda com `purchase < corte` (2.750 no corte de teste).
- **Contagens** (§1, §2): janela sem venda ⇒ **0**.
- **Descrição e fotos (§3): NULL ⇒ 0** (decisão do colega). O atributo de cadastro
  ausente vira **zero** (`COALESCE(.,0)`), não é descartado — o produto permanece
  na base e **puxa média/mínimo para baixo** (sinaliza catálogo fraco). É coerente
  porque não há "0 natural" no dataset (descrição vazia/foto ausente = NULL), então
  NULL é a única forma de "zero". Impacto medido (corte 2018-07-01): **190 sellers**
  mudam a média e **250 sellers** passam a ter mínimo 0.
- **Demais estatísticas numéricas** (peso, cubagem, R$/kg — §4–§6): valor
  **ausente é ignorado** (peso/dimensão NULL fora da agregação); janela/seller sem
  dado ⇒ **NULL** (a ausência é sinal; imputar 0 numa massa/preço enviesaria a
  escala física). *Contraste com §3:* lá "0" é semanticamente válido (texto vazio /
  zero fotos); aqui um peso 0 seria fisicamente falso.
- **Divisões** (§6): denominador 0/NULL ⇒ **NULL** (`NULLIF`).
- `product_category_name` NULL ⇒ rótulo **`'sem_categoria'`** (para não sumir do
  `DISTINCT`/ranking).

### 3.8 Ranking de top categorias (§7) — por unidades (decisão travada, atualizada)

Top categorias ordenadas por: (1) maior **quantidade vendida** = nº de itens
(`COUNT(*)` de `order_items`); (2) maior nº de **pedidos distintos**; (3) ordem
**alfabética** (estabilidade determinística). Usamos `ROW_NUMBER` (não `RANK`)
para garantir 1 categoria por posição. *(Mudança v2: antes o critério primário
era receita `SUM(price)`.)*

---

## 4. Catálogo de variáveis

Seções iguais às de [`variaveis.md`](../variaveis.md). Variáveis com janela geram
4 colunas (sufixos `D28/D56/D365/Vida`); §3 é estática (1 coluna por métrica).

---

### 4.1 Diversidade de catálogo — `vlCategoriasDistintas`, `vlProdutosDistintos`

| | |
| --- | --- |
| **Colunas** | `vlCategoriasDistintas{D28,D56,D365,Vida}` · `vlProdutosDistintos{...}` |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `01_vlCategoriasDistintas.sql` · `02_vlProdutosDistintos.sql` |

**Definição.** Nº de categorias (`product_category_name`) e de SKUs (`product_id`)
**distintos** vendidos pelo seller na janela.

**Fórmula.** `COUNT(DISTINCT categoria)` / `COUNT(DISTINCT product_id)` por janela,
com `categoria = COALESCE(product_category_name, 'sem_categoria')`.

**Grão.** A entidade é o seller; o `DISTINCT` garante que repetir produto/pedido
não infle a contagem.

**Casos de borda.** Janela sem venda ⇒ `0`.

**Sinal p/ churn.** Estreitamento do leque (razão `D28/D365` baixa) sugere
liquidação de estoque / portfólio encolhendo antes de sair.

---

### 4.2 Concorrência entre sellers — `vlContagemCategoriaConcorrentes`, `vlContagemProdutosConcorrentes`

| | |
| --- | --- |
| **Colunas** | `vlContagemCategoriaConcorrentes{W}` (indireta) · `vlContagemProdutosConcorrentes{W}` (direta) |
| **Tipo** | inteiro ≥ 0 |
| **Scripts** | `03_vlContagemCategoriaConcorrentes.sql` · `04_vlContagemProdutosConcorrentes.sql` |

**Definição.** Para o seller A, nº de **outros** sellers (B≠A) que venderam na
mesma **categoria** (concorrência indireta — substitutos) ou no mesmo
**`product_id`** (concorrência direta — SKU idêntico) na janela.

**Modelagem.** Em vez de um self-join opaco (`sc a JOIN sc b`), nomeamos os dois
papéis: `minhas_cat`/`meus_produtos` (onde o seller atua, com flags de janela) e a
mesma tabela como "roster". `COUNT(DISTINCT concorrente)` impede contar o mesmo B
duas vezes quando ele divide várias categorias/SKUs com A.

**Casos de borda.** Janela sem venda ⇒ `0` (mantido via `spine` + `COALESCE`).

**Sinal p/ churn.** Concorrência alta + receita caindo = saída por dificuldade
competitiva / guerra de preço.

---

### 4.3 Atributos de produto — `vlCaracteresDescricao`, `vlMediaFotosProduto` (estáticos)

| | |
| --- | --- |
| **Colunas** | `vlMediaCaracteresDescricao`, `vlMedianaCaracteresDescricao`, `vl25CaracteresDescricao`, `vl50CaracteresDescricao`, `vl75CaracteresDescricao`, `vlMinCaracteresDescricao`, `vlMaxCaracteresDescricao` · `vlMediaFotosProduto` |
| **Tipo** | numérico ≥ 0 (Vida) |
| **Scripts** | `05_vlCaracteresDescricao.sql` · `06_vlMediaFotosProduto.sql` |

**Definição.** Estatísticas de `product_description_lenght` e média de
`product_photos_qty`.

**Grão (importante).** Descrição e nº de fotos são propriedades de **cadastro** →
a entidade é o **produto**. Tomamos `DISTINCT product_id` por seller, então o SKU
vendido N vezes pesa 1 (premissa 3.6). Estáticos (só Vida). Nota: `vlMediana…` e
`vl50…` são o **mesmo valor** (mediana = percentil 50).

**NULL = 0 (decisão do colega).** Descrição e fotos ausentes contam como **zero**
(`COALESCE(product_description_lenght,0)`, `COALESCE(product_photos_qty,0)`), em
vez de serem descartadas. Justificativa: quantitativamente é o mesmo — "não
cadastrou" equivale a 0 caractere / 0 foto — e assim o produto **permanece na
base** e **influencia média e mínimo**, sinalizando catálogo mal preenchido
(menor conversão → maior risco de churn). Não há "0 natural" no dataset (o mínimo
real de fotos é 1; descrição vazia aparece como NULL), então o 0 só existe porque
o criamos. *Impacto (corte 2018-07-01):* 580 produtos distintos viram 0 → **190
sellers** mudam a média e **250** passam a ter mínimo 0. **Complementaridade:** a
variável extra `vlShareProdutosSem{Descricao,Foto}` (§4.8) ainda mede a *fração*
de produtos sem cadastro — sinal correlato mas distinto (intensidade vs.
prevalência).

**Percentil — divergência de dialeto (documentada).** SQLite **não** tem
`percentile()`. Implementamos o percentil **contínuo tipo-7** (interpolação
linear) via funções de janela — **exatamente** o que o `percentile(col, p)` do
Spark calcula (validado contra `numpy.percentile` **com os zeros incluídos**, 0
divergências).

**Casos de borda.** Com NULL→0, todo produto distinto entra; seller sem nenhum
produto seria `NULL`, mas isso não ocorre (todo seller do universo tem ≥1 venda).

**Sinal p/ churn.** Cadastro pobre (descrição curta/zero, poucas/zero fotos) ⇒
menor conversão ⇒ maior risco de churn por baixa performance de vitrine.

---

### 4.4 Peso dos produtos — `vlPesoProduto` (distribuição estática + total `*`)

| | |
| --- | --- |
| **Colunas** | `vl{Media,Mediana,25,50,75,Min,Max}PesoProduto` (gramas, **estático**) · `vlTotalPesoProdutos{W}` (kg, 4 janelas) |
| **Tipo** | numérico ≥ 0 |
| **Scripts** | `07_vlPesoProduto.sql` |

**Definição.** Distribuição (média/mediana/percentis/mín/máx) **estática** e total
**por janela** de `product_weight_g`.

**Grão — DOIS grãos no mesmo arquivo.**
- **Distribuição (estática):** peso é atributo **imutável** do **produto** (vem de
  `products`, 1 linha por `product_id`) → `DISTINCT product_id` por seller sobre
  toda a vida (< corte). **Sem janelas:** o peso não muda no tempo, então
  D28/D56/D365 dariam exatamente a mesma distribuição mudando só *quais* SKUs
  entram (prova A do script: 0 produtos com >1 valor de peso). O percentil é
  tipo-7 (interpolação linear) no SQLite e `percentile(w,p)` no Spark.
- **Total (`vlTotalPesoProdutos`, 4 janelas):** é a **massa embarcada** → soma por
  **unidade** vendida, convertida g→kg. Mantém D28/D56/D365/Vida porque **cresce
  com novas vendas** (mesma razão dos R$/kg de §6).

**Casos de borda.** Peso NULL ignorado (2 produtos sem peso); seller sem produto
com peso → distribuição `NULL`; janela sem venda → total `NULL`. Unidade:
distribuição em **gramas** (precisão), total em **kg** (escala).

**Sinal p/ churn.** Perfil leve (joias/vestuário) vs. pesado (eletro) tem dinâmica
distinta; massa embarcada/mês muito baixa (ou caindo entre janelas) ⇒ operação
reduzida.

> *Mudança (revisão do colega).* Na v2 a distribuição tinha as 4 janelas. Como o
> peso é estático, virou redundante — revertido para estático. O total continua
> com janelas (depende de vendas). Saída: de 33 → **12 colunas**.

---

### 4.5 Cubagem dos produtos — `vlCubagemProdutos` (média estática + total `*`)

| | |
| --- | --- |
| **Colunas** | `vlMediaCubagemProdutos` (cm³, produto distinto, **estático**) · `vlTotalCubagemProdutos{W}` (cm³, unidade, 4 janelas) |
| **Tipo** | numérico ≥ 0 |
| **Scripts** | `08_vlCubagemProdutos.sql` |

**Definição.** Volume da **caixa de envio**
(`product_length_cm × product_height_cm × product_width_cm`): **média estática**
(sobre produtos distintos, toda a vida) e **total por janela** (por unidade
embarcada).

**Grão (mesma lógica de §4.4).** Cubagem é atributo **imutável** do produto → a
**média** é estática (sem janelas; prova A: 0 produtos com >1 valor de cubagem). O
**total** (volume embarcado, soma por unidade) **mantém as 4 janelas** porque
cresce com vendas.

**Casos de borda.** Qualquer dimensão `NULL` ⇒ cubagem `NULL` ⇒ ignorada; seller
sem produto com cubagem → média `NULL`; janela sem venda → total `NULL`.

**Sinal p/ churn.** Combinada com peso, distingue perfis logísticos (volumoso vs.
compacto) que influenciam custo/competitividade; total é variável de **escala**.

> *Mudança (revisão do colega).* Média era por janela na v2 → revertida para
> estática (cubagem não muda no tempo). Total mantém janelas. Saída: de 9 → **6
> colunas**.

---

### 4.6 Indicadores por kg — `vlPrecoKg`, `vlFreteKg` (`*`)

| | |
| --- | --- |
| **Colunas** | `vlPrecoKg{W}`, `vlFreteKg{W}` (R$/kg) |
| **Tipo** | numérico ≥ 0 |
| **Scripts** | `09_vlPrecoKg.sql` · `10_vlFreteKg.sql` |

**Definição.** `SUM(price)/SUM(kg)` e `SUM(freight_value)/SUM(kg)` por janela.

**Grão/decisões.** É uma **razão de dois totais por unidade** (não DISTINCT):
- Numerador e denominador restritos aos itens com **peso não-nulo** (mesma base),
  para o quociente ser coerente.
- `price`/`freight_value` são por unidade (grão da fato); `freight_value` já vem
  **alocado por item** pela Olist (não rateamos).
- Denominador `0`/`NULL` ⇒ `NULL` (`NULLIF`).

**Mini-exemplo (preço/kg).** D28: 3×R$100/2kg + 2×R$50/1kg ⇒ receita 400, massa
8kg ⇒ `vlPrecoKgD28 = 50,0`.

**Sinal p/ churn.** Alto valor agregado (preço/kg alto) ⇒ dinâmica distinta de
commodities; frete/kg alto ⇒ produtos com restrição de envio ⇒ menor
competitividade.

**Versão ajustada (extra — crítica 9).** As colunas `vlPrecoKgAjustado{W}` e
`vlFreteKgAjustado{W}` = `log1p(razão)` (`ln(1+x)` no SQLite, `log1p()` no Spark)
são adicionadas no MESMO arquivo, ao lado das cruas. Motivo: a razão R$/kg tem
**cauda extremamente assimétrica** (produtos leves geram valores enormes — máx
~R$81 mil/kg no preço, ~R$17 mil/kg no frete; assimetria ~30–45). O `log1p`
comprime para assimetria ~0,45 (quase simétrica), o que ajuda modelos
lineares/distância e evita que outliers dominem. Mantemos a coluna crua (modelos
de árvore não precisam do log). Aplicado ao **valor agregado por seller** (a razão
já é SUM/SUM), uniformemente; `NULL → NULL`. Alternativa não adotada: winsorização
(capar no p99).

---

### 4.7 Top 3 categorias e share — `descTopCategoria`, `vlShareTopCategoria` (`*`)

| | |
| --- | --- |
| **Colunas** | `descTopCategoria{1,2,3}{W}` (texto pt ou `NULL`) · `vlShareTopCategoria{1,2,3}{W}` (float [0,1] ou `NULL`) |
| **Tipo** | string / float |
| **Scripts** | `11_descTopCategoria.sql` · `12_vlShareTopCategoria.sql` |

**Definição.** Nome da 1ª/2ª/3ª categoria **mais vendida** do seller na janela e a
**fração das unidades** concentrada em cada uma.

**Critério (premissa 3.8).** Ranking por **quantidade vendida** (unidades = linhas
de `order_items`); desempate: unidades DESC → pedidos distintos DESC → categoria
ASC. Share = `unidades(topk) / unidades_totais` da janela.

**Modelagem.** Agregação condicional por `(seller, categoria)` (unidades e pedidos
por janela) → `ROW_NUMBER` por janela → pivot para 3 posições × 4 janelas. O guard
`u_>0` evita rotular/pontuar uma posição inexistente (seller com <k categorias na
janela → `NULL`, **não** 0).

**Casos de borda.** Seller monoproduto ⇒ `descTopCategoria1=cat`, `top2/3 NULL` e
`vlShareTopCategoria1=1.0`, demais `NULL`. `soma dos 3 shares ≤ 1` (resto está na
4ª categoria em diante). Categoria NULL → `'sem_categoria'` pode figurar no top.

**Sinal p/ churn.** A *identidade* das top categorias é sinal categórico (verticais
sazonais vs. perenes). Concentração alta (`vlShareTopCategoria1 > 0.9`) ⇒ seller
frágil a abalos de demanda de uma única categoria.

> **Encoding (handoff).** São categóricas de cardinalidade alta (67 categorias no
> top1; `top2/top3` muito nulos) — o tratamento de encoding é da etapa de modelagem.
> Ver [`consideracoes_finais.md`](../consideracoes_finais.md) §2.

---

### 4.8 Missingness de cadastro — `vlShareProdutosSemCadastro` (extra, estática)

| | |
| --- | --- |
| **Colunas** | `vlShareProdutosSemCategoria`, `vlShareProdutosSemDescricao`, `vlShareProdutosSemFoto`, `vlShareProdutosSemPeso` (frações [0,1], Vida) |
| **Tipo** | float em [0,1] |
| **Scripts** | `13_vlShareProdutosSemCadastro.sql` |

**Definição.** Fração dos **produtos distintos** do seller com o atributo de
cadastro **ausente** (`NULL`): `AVG(CASE WHEN atributo IS NULL THEN 1 ELSE 0 END)`
sobre `DISTINCT product_id`.

**Por que existe (crítica 7).** A ausência de cadastro é **invisível à média**:
`AVG` descarta `NULL`, e `product_photos_qty` **não tem valor 0** (mín = 1) — quem
não tem foto tem o campo `NULL`. Logo `vlMediaFotosProduto`/`vlCaracteresDescricao`
**não enxergam** os produtos sem cadastro; o missingness é informação **ortogonal**
(provável proxy de operação de baixa qualidade/engajamento → churn).

**⚠ Achados nos dados (corte 2018-07-01) — fragilidades a registrar.**
- Os **580 produtos** sem categoria são **exatamente os mesmos** sem descrição e
  sem foto (cadastro vazio em bloco). Portanto `vlShareProdutosSemCategoria ≡
  vlShareProdutosSemDescricao ≡ vlShareProdutosSemFoto` são **colineares
  (idênticas)** neste dataset — mantidas as 3 porque a equivalência pode quebrar
  num refresh, mas **para o modelo uma só basta**.
- `vlShareProdutosSemPeso` é **quase constante** (só 2 produtos sem peso no dataset
  inteiro → 0,1% dos sellers) → **candidata a descarte**.
- Cobertura útil: **250 sellers (9,1%)** têm ≥1 produto sem cadastro; **60** têm o
  **catálogo inteiro** sem cadastro — esse é o sinal mais forte.

**Casos de borda.** Denominador (produtos distintos) sempre > 0 (seller tem ≥1
venda) → sem divisão por zero; todas as 2.750 linhas preenchidas (0 a 1).

---

## 5. Arquitetura de execução (SQLite ↔ Spark)

**Validação local (SQLite).** `python scripts/build_sqlite.py` gera `olist.db`
(9 tabelas). Rode/inspecione qualquer feature com:
```bash
python scripts/run_feature_sqlite.py features_sqlite/01_vlCategoriasDistintas.sql
# (default --cutoff 2018-07-01). A feature é o bloco 1; as provas começam no bloco 2:
python scripts/run_feature_sqlite.py features_sqlite/07_vlPesoProduto.sql --list
python scripts/run_feature_sqlite.py features_sqlite/07_vlPesoProduto.sql --block 2
```

**Produção (Spark/Databricks).** Os scripts em `features_spark/` referenciam
`workspace.olist.<tabela>` e usam o dialeto Spark (`timestamp(:data_corte)`,
`- INTERVAL N DAYS`, `percentile(...)`). Diferem dos de SQLite **apenas** por
prefixo de namespace + funções de dialeto + parametrização.

**Parametrização (difere por dialeto).**
- **SQLite:** token `'{data_corte}'` substituído por `run_feature_sqlite.py`
  (`--cutoff`); janelas via `datetime('{data_corte}', '-N days')`.
- **Spark/Databricks:** widget no topo de cada query alimenta o **parameter
  marker** `:data_corte`:
  ```sql
  CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';
  -- ... WHERE order_purchase_timestamp < timestamp(:data_corte)
  -- janelas: timestamp(:data_corte) - INTERVAL 28 DAYS
  ```
  No SQL Editor (warehouse) remova o `CREATE WIDGET` — o `:data_corte` vira um
  parâmetro automático. Evite `'{data_corte}'` entre aspas no Spark (string
  literal — não é substituído) e a sintaxe legada `${...}`.

**Provas embutidas (ANÁLISE / PROVAS).** Cada feature `.sql` traz, abaixo da query
principal, 2–3 sub-queries que **comprovam as decisões** — existência de NULLs
(justifica `COALESCE`/`IS NOT NULL`), `DISTINCT` vs por unidade (grãos diferentes),
componentes de razão com `NULLIF`, ranking/desempate por unidades, SKUs disputados,
monotonia. No SQLite rode por `--block N`; no Spark cada `SELECT` numa célula.

**Validação realizada (cutoff `2018-07-01`).** As 13 features SQLite retornam
**2.750 sellers**, **sem duplicidade**; contagens (§1, §2) e totais com monotonia
`D28 ≤ D56 ≤ D365 ≤ Vida`; percentis de descrição (**com NULL→0**) e de peso, e
média de cubagem, batem **na vírgula** com `numpy` **sobre produtos distintos**
(300 sellers amostrados × 6 estatísticas, 0 divergências); top categorias e share
conferidos vs. Python (120 sellers × 4 janelas × 3 posições, 0 divergências). A
natureza **estática** de peso/cubagem foi comprovada empiricamente (0 `product_id`
com mais de um valor de peso ou de cubagem). Os 13 Spark foram comparados aos
SQLite por **tradução de dialeto** (idênticos; o `percentile()` tipo-7 = cálculo
manual do SQLite).

---

## 6. Dicionário consolidado das colunas

Mapa família → script → colunas. `{W}` = `{D28,D56,D365,Vida}`.

| § | Família | Script (sem extensão) | Colunas |
| - | ------- | --------------------- | ------- |
| 1 | Categorias distintas `*`      | `01_vlCategoriasDistintas`            | `vlCategoriasDistintas{W}` |
| 1 | Produtos distintos `*`        | `02_vlProdutosDistintos`              | `vlProdutosDistintos{W}` |
| 2 | Concorrentes mesma categoria `*` | `03_vlContagemCategoriaConcorrentes` | `vlContagemCategoriaConcorrentes{W}` |
| 2 | Concorrentes mesmo produto `*`   | `04_vlContagemProdutosConcorrentes`  | `vlContagemProdutosConcorrentes{W}` |
| 3 | Caracteres da descrição (estático) | `05_vlCaracteresDescricao`         | `vl{Media,Mediana,25,50,75,Min,Max}CaracteresDescricao` |
| 3 | Fotos por produto (estático)  | `06_vlMediaFotosProduto`              | `vlMediaFotosProduto` |
| 4 | Peso (distrib. estática + total `*`) | `07_vlPesoProduto`             | `vl{Media,Mediana,25,50,75,Min,Max}PesoProduto` (estático), `vlTotalPesoProdutos{W}` |
| 5 | Cubagem (média estática + total `*`) | `08_vlCubagemProdutos`         | `vlMediaCubagemProdutos` (estático), `vlTotalCubagemProdutos{W}` |
| 6 | Preço por kg `*`              | `09_vlPrecoKg`                        | `vlPrecoKg{W}`, `vlPrecoKgAjustado{W}` |
| 6 | Frete por kg `*`              | `10_vlFreteKg`                        | `vlFreteKg{W}`, `vlFreteKgAjustado{W}` |
| 7 | Top 3 categorias `*`          | `11_descTopCategoria`                 | `descTopCategoria{1,2,3}{W}` |
| 7 | Share top 3 `*`               | `12_vlShareTopCategoria`              | `vlShareTopCategoria{1,2,3}{W}` |
| E | Missingness de cadastro (estático) | `13_vlShareProdutosSemCadastro`  | `vlShareProdutosSem{Categoria,Descricao,Foto,Peso}` |

**Contagem de colunas de feature (84 no total, + `seller_id`).**
- **Com janela (×4) = 64 colunas.** Contagens: `vlCategoriasDistintas`,
  `vlProdutosDistintos`, 2× concorrência (4 métricas). Razões: `vlPrecoKg`,
  `vlPrecoKgAjustado`, `vlFreteKg`, `vlFreteKgAjustado` (4). Totais (massa/volume
  embarcado): `vlTotalPesoProdutos`, `vlTotalCubagemProdutos` (2). Top/share:
  `descTopCategoria{1,2,3}`, `vlShareTopCategoria{1,2,3}` (6). → 16 métricas × 4 =
  **64**.
- **Estáticas (atributos imutáveis do produto + missingness) = 20 colunas.**
  Descrição 7 + fotos 1 + **peso distribuição 7** + **cubagem média 1** +
  missingness 4 = **20**.

> *Mudança (revisão do colega).* Antes eram 108 colunas. Tornar a distribuição de
> peso (−21) e a média de cubagem (−3) estáticas removeu 24 colunas redundantes
> (mesmo valor repetido em 4 janelas) → **84**. NULL→0 em descrição/fotos não muda
> a contagem, só os valores.

> **Montagem opcional da feature store.** Esta entrega são scripts *por família*
> (pedido do cliente). Para uma tabela larga única, basta `LEFT JOIN` dos 13
> resultados por `seller_id` (todos compartilham o universo de 2.750 sellers no
> cutoff de teste, então os joins são 1:1).

> **Variáveis extras (revisão externa).** Adotadas de [`criticas_codex.md`](../criticas_codex.md):
> missingness de cadastro (§4.8) e `…Ajustado` (log1p, §4.6). Outros pontos da
> revisão (cancelamento, flags de atividade, concorrência normalizada, HHI/entropia)
> **não** foram adotados nesta entrega; limitação de `product_id` e encoding das top
> categorias ficaram registrados em [`consideracoes_finais.md`](../consideracoes_finais.md).
