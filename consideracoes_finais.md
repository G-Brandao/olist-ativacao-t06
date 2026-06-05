# Considerações finais — limitações conhecidas e cuidados de modelagem

> Pontos levantados na revisão externa (`criticas_codex.md`) que **não viram
> mudança de código** nesta entrega, mas precisam ficar **registrados** para quem
> for treinar o modelo. São limitações das tabelas-fonte e decisões que pertencem
> à etapa de modelagem (encoding/transformação), não à engenharia das features.
> As features estão longe da perfeição — o objetivo aqui é tornar as fragilidades
> **explícitas** para que não virem viés silencioso.
>
> Validações no `olist.db`, corte `2018-07-01` (2.750 sellers).

---

## 1. `product_id` não é um SKU canônico perfeito (crítica 6)

Todas as features de produto (`vlProdutosDistintos`, concorrência por produto,
estatísticas de peso/cubagem/descrição/fotos) usam `product_id` como chave de
produto — é a **melhor chave disponível** no dataset Olist.

**O que `product_id` É (verificado no `olist.db`).** É a **chave única do catálogo**
`products` (1 linha por `product_id`; 32.951 produtos ↔ 32.951 linhas), e é
**estável/reusado** entre vendas — **não** é gerado por anúncio nem por venda.
Prova: 112.650 itens em `order_items` para 32.951 `product_id` distintos (**média
3,4 vendas por produto**; o mais vendido aparece em 527 itens). Logo, ao agrupar
por `product_id` já estamos olhando o **produto único** — não há `product_unique_id`
(esse padrão "id muda a cada operação" existe em `customers`, com
`customer_id`/`customer_unique_id`, **não** em produtos).

**O que `product_id` NÃO captura (a limitação real).** Não há chave de produto
canônica (GTIN/EAN/modelo/marca) nem o **título** (só comprimentos truncados em
`product_name_lenght`). Então o **mesmo produto físico** cadastrado com
`product_id` diferentes (ex.: o mesmo isqueiro anunciado 2x) **não** é reconhecido
como o mesmo item. A sobreposição de SKU entre sellers existe e é
**estruturalmente válida** — é o modelo de marketplace/buy box (a mesma página de
produto disputada por vários sellers) — mas é **rara**: só **980/28.794 (3,4%)**
dos produtos vendidos antes do corte têm >1 seller.

**Efeitos no sinal (direção do viés):**
- **Infla `vlProdutosDistintos`** — dois cadastros do mesmo item contam como 2 SKUs
  (catálogo parece mais largo do que é).
- **Subestima `vlContagemProdutosConcorrentes`** — se dois sellers vendem o mesmo
  item físico sob `product_id` diferentes, eles **não** são detectados como
  concorrentes diretos. Isso já se reflete na esparsidade da métrica (a maioria
  dos sellers tem 0 concorrentes diretos).
- **Espalha a concorrência real** entre vários ids, enfraquecendo a contagem.

**Magnitude no corte.** 28.794 `product_id` distintos vendidos antes do corte;
apenas **980** são vendidos por >1 seller. A baixa sobreposição é em parte real,
em parte **artefato** desta fragmentação de cadastro.

**Como interpretar `vlContagemProdutosConcorrentes`.** É um **PISO** de
concorrência — **alta precisão, baixo recall**. Quando dá >0, é concorrência
direta e inequívoca (mesmo SKU do catálogo, outro seller). Quando dá **0, NÃO
garante ausência de concorrência** — pode haver concorrente vendendo o item
equivalente sob outro `product_id`, invisível ao dado. Por isso ela deve ser lida
**em par com `vlContagemCategoriaConcorrentes`** (§3): a de categoria é o "teto"
largo (alto recall), a de produto é o "piso" estrito. A esparsidade da métrica de
produto é em parte real, em parte artefato dessa fragmentação de cadastro.

**Comprovação embutida nos scripts.** As provas A–D do
`04_vlContagemProdutosConcorrentes.sql` (ambos dialetos) materializam tudo isso:
- **A** — 980 SKUs disputados (máx. 8 sellers no mesmo SKU).
- **B** — por que `COUNT(DISTINCT)` no concorrente (B que divide >1 SKU com A).
- **C** — dois sellers **distintos** vendendo o **mesmo** `product_id` em **pedidos
  distintos** (concorrência ≠ mesma venda). 980 SKUs nessa condição.
- **D** — **contra-prova = 0**: nunca há dois sellers no mesmo `product_id` dentro
  do **mesmo** `order_id`. Confirma que a métrica mede concorrência (vendas
  separadas), nunca venda casada no carrinho.

**Decisão.** **Não corrigir agora.** Deduplicar de verdade exigiria *entity
resolution* (agrupar produtos similares por texto/atributos), o que é um projeto à
parte e fora do escopo. Mantemos `product_id` e registramos a limitação. Se no
futuro o tema for crítico, o caminho é uma etapa de *fuzzy matching* de produtos
antes das features de catálogo/concorrência.

---

## 2. Encoding das top categorias (`descTopCategoria`) (crítica 10)

As colunas `descTopCategoria{1,2,3}{W}` são **categóricas textuais de cardinalidade
relevante** e exigem encoding cuidadoso na modelagem — isto é **responsabilidade do
pipeline de treino**, não das features (que entregam o nome cru de propósito, para
não fixar uma escolha de encoding prematura).

**O que os dados mostram (corte, Vida):**
- `descTopCategoria1Vida` tem **67 categorias distintas** (de **74** vendidas no
  total) → alta cardinalidade para one-hot direto.
- **`'sem_categoria'`** aparece como **top1** de **98 sellers** → é um nível
  legítimo (e ao mesmo tempo um sinal de cadastro ausente — ver
  `vlShareProdutosSemCategoria`).
- `top2`/`top3` são **muito nulos** (esperado: muitos sellers vendem em 1–2
  categorias): `vlShareTopCategoria2Vida` é NULL para **1.543** sellers e
  `vlShareTopCategoria3Vida` para **2.138** (de 2.750).

**Recomendações de encoding (na modelagem):**
- **Não usar one-hot cru** das 67+ categorias × 3 posições × 4 janelas (explosão de
  dimensionalidade + colunas esparsíssimas). Preferir:
  - **target/mean encoding** (com regularização e *fit* só no treino, p/ evitar
    leakage), ou **frequency encoding**; ou
  - **agrupar categorias raras** num bucket `'outras'` (manter só as N mais
    frequentes como níveis próprios).
- **Tratar o NULL de `top2`/`top3` como nível explícito** (`'ausente'`), não como
  dado faltante a imputar — o NULL aqui **significa** "o seller não tem 2ª/3ª
  categoria", que é informação (concentração).
- Manter **`'sem_categoria'`** como nível próprio (não confundir com NULL de
  posição inexistente): um é "vendeu produto sem cadastro de categoria", o outro é
  "não existe k-ésima categoria".

> Escopo: a crítica 10 também sugeria índices de concentração (HHI/entropia) do mix
> de categorias. **Fora do escopo desta entrega** (decisão do cliente) — registrado
> apenas o cuidado de **encoding**. `vlShareTopCategoria1` já é uma proxy simples de
> concentração se for preciso um sinal numérico imediato.

---

## Referências

- Revisão externa completa: [`criticas_codex.md`](criticas_codex.md).
- Variáveis extras adotadas desta revisão (missingness e `Ajustado`):
  [`variaveis.md`](variaveis.md) (seção "Variáveis Extras") e
  [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md).
- Premissas e decisões travadas: [`CLAUDE.md`](CLAUDE.md) §5.
