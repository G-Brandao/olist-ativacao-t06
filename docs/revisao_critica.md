# Revisão crítica das 14 variáveis — ativação de sellers Olist

> Revisão adversarial (papel de revisor) das variáveis definidas em
> [`variaveis.md`](../variaveis.md) e implementadas em `features_sqlite/` /
> `features_spark/`. Para cada variável: **≥3 questionamentos** sobre forma de
> construção e decisões + **defesa da motivação** do jeito adotado.
>
> **Status (decisão do cliente):** após esta revisão, **NENHUMA alteração foi
> adotada**. As 14 variáveis permanecem como originalmente construídas e validadas
> (ver [`variaveis_detalhadas.md`](variaveis_detalhadas.md)). As recomendações no
> fim deste documento ficam como **backlog opcional**, não implementadas.

Números citados foram medidos no `olist.db` local com cutoff de teste `2018-09-01`.

---

## Críticas transversais (valem para várias variáveis)

Codificadas como **T1–T5** e referenciadas nas variáveis para evitar repetição.

- **T1 — "Sem filtro de status" mistura venda realizada com venda que não
  aconteceu.** Contamos `canceled`/`unavailable` como venda. Para o *target* (o
  seller transacionou?) é coerente; para features de **receita/massa/preço**
  (7, 9, 11, 12, 13, 14) o numerador inclui valor não realizado. *Medido:* só
  **0,72%** da receita (< cutoff) e **334** sellers tocados — impacto pequeno,
  porém concentrado em quem cancela muito (que é justamente sinal de risco).
  *Decisão travada com o cliente; mantida.*
- **T2 — Contagens absolutas confundem-se com porte/tenure.** Itens 1, 2, 3, 4
  crescem com volume e tempo de casa. Dois sellers igualmente "diversos" mas de
  portes diferentes recebem contagens diferentes; o modelo pode aprender razões,
  mas a feature crua carrega esse confundidor.
- **T3 — `product_id` é um SKU ruidoso.** Na Olist o mesmo item físico aparece
  com `product_id` distintos (sem SKU canônico). Isso **infla** "produtos
  distintos" (2) e **subestima** "concorrentes no mesmo produto" (4).
- **T4 — "Vida" não tem recência nem decaimento.** Um concorrente/categoria de
  2016 pesa igual a um de ontem; em 2 anos de mercado em expansão, métricas de
  Vida ficam "velhas".
- **T5 — Ponderação unidade vs produto distinto é uma escolha, não uma verdade.**
  Itens 6–9 ponderam por **unidade vendida**; 5 e 10 por **produto distinto**. A
  fronteira ("venda" vs "cadastro") é defensável, mas o nome "…dos produtos"
  sugeriria distinto.

---

## 01 — Categorias distintas `*`
**Questionamentos**
1. `'sem_categoria'` (COALESCE) trata *metadado faltante* (610 produtos) como uma
   vertical real, inflando a diversidade de quem tem cadastro ruim.
2. Diversidade ≠ intensidade: 5 categorias com 1 venda cada contam como 5; um
   HHI/entropia de mix seria mais informativo (fora do escopo de `variaveis.md`).
3. Confundido com porte/tenure (**T2**) e sem recência na Vida (**T4**).

**Defesa da motivação.** É literalmente o pedido ("categorias distintas no
período"); o `COALESCE` evita *perder* sellers que só vendem itens sem categoria
(senão dariam 0 apesar de vender); barata, interpretável e combinável com a 02
para expressar concentração de portfólio.

## 02 — Produtos distintos `*`
**Questionamentos**
1. `product_id` ruidoso (**T3**) superestima a largura real do catálogo.
2. Profundidade ignorada: produto vendido 1× pesa igual a vendido 500×.
3. Confundido com porte/tenure (**T2**).

**Defesa.** `product_id` é a única chave de produto disponível; é o pedido
literal; pareado com a 01 dá a "amplitude do portfólio".

## 03 — Concorrentes mesma categoria `*`
**Questionamentos**
1. Vira proxy de "categoria popular", não de pressão do seller: quem está numa
   categoria grande tem centenas de concorrentes por definição → alta colinearidade
   com a *identidade* da categoria (item 13).
2. Overlap binário e frouxo: compartilhar **1** de 10 categorias já conta como
   concorrente — sem peso por sobreposição (Jaccard / receita compartilhada
   seriam mais fiéis).
3. Vida estagnada (**T4**): concorrente que vendeu na categoria em 2016 e sumiu
   ainda conta. Também não há noção de *share* (A x B mesmo com portes opostos).

**Defesa.** É a contagem pedida ("sellers distintos que oferecem categorias em
comum"); simétrica e determinística; captura quão disputada é a vizinhança do
seller. O auto-join sobre `DISTINCT (seller, categoria)` + `COUNT(DISTINCT
b.seller_id)` garante não duplicar concorrentes que compartilham várias categorias.

## 04 — Concorrentes mesmo produto `*`
**Questionamentos**
1. `product_id` ruidoso (**T3**) corta dos dois lados: concorrência real no mesmo
   item pode estar partida em vários ids.
2. Esparsa e zero-inflada: concorrência direta por SKU idêntico é rara → muitos
   `0`, baixo poder discriminante.
3. Vida estagnada (**T4**) e sem noção de share (igual 03-3).

**Defesa.** Proxy de "guerra de preço no mesmo SKU" (1.225 produtos vendidos por
>1 seller no dataset); complementa a concorrência indireta da 03.

## 05 — Estatísticas de descrição (Vida, sem `*`)
**Questionamentos**
1. As 6 estatísticas são redundantes: média/mediana/p25/p75 fortemente colineares;
   min/max sensíveis a outlier → possível sobre-parametrização.
2. A *ausência* de descrição (610 produtos) é descartada (`IS NOT NULL`) — mas
   "cadastro sem descrição" é provavelmente sinal de churn mais forte que o
   tamanho; um `share_sem_descricao` poderia substituir as 6.
3. Proxy de categoria (eletrônicos têm descrição longa por natureza) e **Vida
   only** (não capta piora recente de cadastro).

**Defesa.** É exatamente o pedido (média, mediana, percentis, min, max); ponderar
por **produto distinto** é o correto (descrição é atributo de cadastro, não de
venda); `spine` mantém os 3.095 sellers com `NULL` onde indefinido. O percentil é
tipo-7 (interpolação linear), idêntico ao `percentile` do Spark — validado contra
`numpy`.

## 06 — Peso médio e mediana `*`
**Questionamentos**
1. Unidade vs produto distinto (**T5**): "peso médio dos produtos" — média sobre
   *unidades enviadas* (escolhido) ou sobre *catálogo*? 1.000 unidades leves + 1
   pesada puxa a média para leve.
2. Média + mediana por janela = 8 colunas para um conceito; há redundância (embora
   úteis juntas em distribuição assimétrica).
3. Padrão "ignora peso NULL" enviesa quando há muitos faltantes (aqui só 2
   produtos, então irrelevante neste dataset).

**Defesa.** Premissa 3.6 — o grão da fato auto-pondera por volume, que é o "perfil
do que o seller realmente despacha"; gramas preservam precisão (o total vai a kg
na 07); mediana tipo-7 = `percentile(w,0.5)` do Spark (validada contra numpy,
inclusive casos `n=0` → NULL).

## 07 — Peso total `*`
**Questionamentos**
1. É quase pura escala/volume — altamente colinear com "nº de itens vendidos";
   mede tamanho, não um construto novo.
2. Total enviesado por NULL: itens sem peso saem da soma → "massa total" vira
   "massa dos itens com peso".
3. Mistura de unidades no projeto: peso em g (item 6) e kg (item 7).

**Defesa.** Variável de **escala** da operação; encolhimento de massa/mês entre
D365 e D28 é sinal clássico de desaceleração; pareia com a cubagem total.

## 08 — Cubagem média `*`
**Questionamentos**
1. Caixa (L×H×W) ≠ volume real e ≠ fator cúbico da transportadora — pode não
   refletir o frete cobrado.
2. Regra de NULL mais dura: *uma* dimensão faltante zera a cubagem do produto
   inteiro (mais severa que o peso).
3. Unidade vs distinto (**T5**).
4. Robustez (não-bug aqui): `INT*INT*INT` no Spark poderia estourar com dados
   sujos; *medido:* cubagem máx por seller = **102M** ≪ 2,1 bi (INT32) e `SUM` do
   Spark promove p/ bigint → **seguro nestes dados**.

**Defesa.** Para frete o que importa é a caixa de envio (paralelepípedo), não o
volume do produto; ponderar por unidade descreve o despacho típico.

## 09 — Cubagem total `*`
**Questionamentos**
1. Escala/volume (igual 07-1) e colinear com peso total.
2. Viés de NULL na soma (igual 08-2).
3. Vida estagnada (**T4**) na versão lifetime.

**Defesa.** Pareada com `peso_total_kg`, descreve a dimensão logística da
operação — variável de escala relevante para o modelo.

## 10 — Fotos média por produto (Vida, sem `*`)
**Questionamentos**
1. Missingness descartada: 610 produtos sem foto (NULL/0) — *ter* foto pode ser
   mais preditivo que a média de quantas.
2. Proxy de categoria/tipo de produto (igual 05-3).
3. Vida only: sem dinâmica de cadastro recente.

**Defesa.** Pedido literal; ponderação por produto distinto (atributo de
cadastro); `spine` preserva todos os sellers.

## 11 — Preço por kg `*`
**Questionamentos**
1. `SUM(price)/SUM(kg)` é média ponderada por massa — dominada por itens
   pesados/baratos; difere do "preço/kg típico" (média das razões). É o que
   `variaveis.md` pede ("receita/massa"), mas o viés deve ser registrado.
2. Restrição a peso não-nulo derruba do numerador a receita de itens sem peso
   (coerência num/den vs completude).
3. Status (**T1**) contamina o numerador (receita de cancelado infla preço/kg).
4. Outliers extremos sem tratamento: *medido* `max = R$ 54.980/kg` — cauda
   pesadíssima, sem winsorização.

**Defesa.** É a definição do enunciado (receita total/massa total); `NULLIF`
protege divisão por zero; `price` é por unidade ⇒ `SUM(price)` é a receita
correta; manter num e den na **mesma base** (peso não-nulo) garante quociente
coerente.

## 12 — Frete por kg `*`
**Questionamentos**
1. Frete tem componente não proporcional ao peso (distância/região/fixo) →
   `frete/kg` mistura logística regional com massa.
2. Confiamos na alocação por item da Olist sem auditá-la.
3. Status (**T1**) e restrição a peso não-nulo (igual 11-2/3).

**Defesa.** O frete já vem **alocado por item** pela própria Olist (não inventamos
rateio); frete/kg alto sinaliza restrição de envio (frágil/remoto) ⇒ menor
competitividade ⇒ predispõe a churn.

## 13 — Top 3 categorias (Vida, sem `*`)
**Questionamentos**
1. Categórica de alta cardinalidade (~70 níveis em `top1`, mais esparsa em
   `top2/3`) — exige *target/embedding encoding*; o nome cru é pouco útil direto.
2. `'sem_categoria'` pode ser o `top1` — *medido:* **93 sellers** — uma
   "categoria" que é, na verdade, ausência de metadado.
3. Status (**T1**): uma venda grande cancelada pode "coroar" uma categoria.
4. Vida sem recência (**T4**): o histórico pode discordar do foco recente.

**Defesa.** Receita (`SUM(price)`) é o critério mais comum de perfil; desempate
determinístico (receita → pedidos distintos → alfabética) com `ROW_NUMBER`
garante 1 categoria por posição; a *identidade* da vertical é sinal categórico
forte (sazonal vs perene).

## 14 — Share top 3 (Vida, sem `*`)
**Questionamentos**
1. `share_top2/3` é `NULL` para **55%** dos sellers (1.689 monocategoria). Pode-se
   argumentar que a fração de uma categoria inexistente é `0%` (definido), não
   "desconhecido" — *recomendação levantada e **não adotada** por decisão do
   cliente; mantém-se `NULL`*.
2. Denominador herda **T1** e `'sem_categoria'` (receita cancelada e bucket de
   ausência entram no total).
3. 3 shares vs 1 índice: um HHI/entropia única seria mais limpo (com `top2/3`
   muito esparsas).

**Defesa.** Mede concentração (fragilidade) com o mesmo ranking da 13;
`share_top1 + share_top2 + share_top3 ≤ 1`; `NULLIF` cobre receita zero. Manter
`NULL` para posições inexistentes preserva a distinção entre "não há k-ésima
categoria" e "k-ésima categoria com share minúsculo" (e árvores lidam com NULL).

---

## Resposta / decisão

Após a revisão, **nada foi alterado**. Em particular, a recomendação mais forte
levantada — trocar `share_top2/3` de `NULL` para `0` no item 14 (afeta 55% da
base) — foi **avaliada e não adotada**: mantém-se `NULL` para posições de
categoria inexistentes. Todas as 14 variáveis seguem como construídas e validadas
originalmente (3.095 sellers, sem duplicidade, monotonia das contagens, cross-check
de médias/percentis/totais/top/share vs `numpy`/manual com 0 divergências).

### Backlog opcional (não implementado)
Registrado apenas como sugestão para evolução futura, fora do escopo de
`variaveis.md`:

1. Features de *missingness* (`share_sem_descricao`, `share_sem_foto`,
   `share_sem_peso`) — endereça críticas 05-2 e 10-1.
2. `taxa_cancelamento` por janela — endereça **T1** sem mexer na decisão de não
   filtrar status.
3. Normalizar concorrência (3, 4) por Jaccard / receita compartilhada (T2,
   03-2).
4. Decaimento temporal nas métricas de Vida (**T4**).
5. Winsorizar/logar `preco_por_kg` e `frete_por_kg` (cauda extrema medida).
6. Tratar `'sem_categoria'` como `NULL` real nos itens 1/3/13, se preferir não
   confundir ausência com vertical.
