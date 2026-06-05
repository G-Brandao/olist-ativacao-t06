# Feature Store — Variáveis de Produtos

## Convenção de Nomenclatura

**Estrutura:** `[prefixo][Qualificador][Metrica][Periodo]`

### Prefixos

| Prefixo | Tipo de dado |
|---------|--------------|
| `vl` | Valor numérico |
| `desc` | Valor textual / descritivo |

### Qualificadores Estatísticos *(inseridos entre o prefixo e a métrica)*

| Qualificador | Significado |
|--------------|-------------|
| `Media` | Média aritmética |
| `Mediana` | Mediana |
| `25`, `50`, `75` | Percentis (ex.: `vl25Metrica`) |
| `Min` | Mínimo |
| `Max` | Máximo |
| `Total` | Soma acumulada |
| `Share` | Participação percentual |

### Sufixos de Período *(variáveis marcadas com `*` possuem as quatro versões)*

| Sufixo | Janela de tempo |
|--------|-----------------|
| `D28` | Últimos 28 dias |
| `D56` | Últimos 56 dias |
| `D365` | Últimos 365 dias |
| `Vida` | Desde o primeiro registro (lifetime) |

> **Regra de corte:** `data_venda < hoje()`
>
> **O que NÃO tem sufixo (estático):** §3 (descrição, fotos) e a **distribuição**
> de §4/§5 (peso, cubagem) — são **atributos imutáveis do produto** (`products`,
> 1 linha por `product_id`), idênticos em qualquer janela; calcular D28/D56/D365
> seria redundante (só mudaria *quais* SKUs entram, nunca o valor). Já os
> **totais** de peso/cubagem (massa/volume embarcado) e os indicadores por kg
> (§6) **mantêm as 4 janelas**, pois somam/dependem de **vendas**, que crescem
> no tempo.

---

## Lista de Variáveis

### 1. Diversidade de Catálogo

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlCategoriasDistintas[D28\|D56\|D365\|Vida]` | Quantidade de categorias distintas no período |
| [ ] | `vlProdutosDistintos[D28\|D56\|D365\|Vida]` | Quantidade de produtos distintos no período |

### 2. Concorrência entre Sellers

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlContagemCategoriaConcorrentes[D28\|D56\|D365\|Vida]` | Sellers distintos que oferecem categorias em comum no período |
| [ ] | `vlContagemProdutosConcorrentes[D28\|D56\|D365\|Vida]` | Sellers distintos que oferecem os mesmos produtos no período |

### 3. Atributos de Produto *(estáticos — sem sufixo de período)*

> **NULL = 0** (descrição e fotos): atributo ausente é tratado como **zero**
> (`COALESCE(.,0)`), não descartado. Quantitativamente é o mesmo — o produto
> sem cadastro **permanece na base** e **puxa a média/mínimo para baixo**,
> sinalizando catálogo fraco (útil para prever inativação). No dataset não há
> "0 natural" (descrição vazia e foto ausente aparecem como NULL).

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlMediaCaracteresDescricao` | Média de caracteres na descrição do produto (NULL→0) |
| [ ] | `vlMedianaCaracteresDescricao` | Mediana de caracteres na descrição do produto (NULL→0) |
| [ ] | `vl25CaracteresDescricao` | Percentil 25 de caracteres na descrição (NULL→0) |
| [ ] | `vl50CaracteresDescricao` | Percentil 50 de caracteres na descrição (NULL→0) |
| [ ] | `vl75CaracteresDescricao` | Percentil 75 de caracteres na descrição (NULL→0) |
| [ ] | `vlMinCaracteresDescricao` | Mínimo de caracteres na descrição (NULL→0) |
| [ ] | `vlMaxCaracteresDescricao` | Máximo de caracteres na descrição (NULL→0) |
| [ ] | `vlMediaFotosProduto` | Quantidade média de fotos por produto (NULL→0) |

### 4. Peso dos Produtos

> **Distribuição estática + total por janela.** Peso é atributo **imutável** do
> produto (`products`, 1 linha por `product_id`) — não muda no tempo. Logo a
> **distribuição** (média/mediana/percentis/mín/máx) é **estática** (sem sufixo),
> calculada sobre os **produtos distintos** já vendidos pelo seller. Só o
> **total** (`vlTotalPesoProdutos`) mantém as 4 janelas, pois é **massa embarcada**
> (soma por unidade vendida) e **cresce com novas vendas** — mesma lógica de §6.

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlMediaPesoProduto` | Peso médio dos produtos distintos do seller (estático) |
| [ ] | `vlMedianaPesoProduto` | Peso mediano dos produtos distintos (estático) |
| [ ] | `vl25PesoProduto` | Percentil 25 do peso dos produtos distintos (estático) |
| [ ] | `vl50PesoProduto` | Percentil 50 do peso dos produtos distintos (estático) |
| [ ] | `vl75PesoProduto` | Percentil 75 do peso dos produtos distintos (estático) |
| [ ] | `vlMinPesoProduto` | Peso mínimo dos produtos distintos (estático) |
| [ ] | `vlMaxPesoProduto` | Peso máximo dos produtos distintos (estático) |
| [ ] | `vlTotalPesoProdutos[D28\|D56\|D365\|Vida]` | Peso total (massa embarcada) dos produtos vendidos no período |

### 5. Cubagem dos Produtos

> **Média estática + total por janela** (mesma lógica de §4). Cubagem
> (`length × height × width`) é atributo **imutável** do produto. A **média** é
> **estática** (produtos distintos); só o **total** (`vlTotalCubagemProdutos`),
> que é **volume embarcado** (soma por unidade), mantém as 4 janelas.

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlMediaCubagemProdutos` | Cubagem média dos produtos distintos do seller (estático) |
| [ ] | `vlTotalCubagemProdutos[D28\|D56\|D365\|Vida]` | Cubagem total (volume embarcado) dos produtos vendidos no período |

### 6. Indicadores por Kg

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlPrecoKg[D28\|D56\|D365\|Vida]` | Receita total / massa total dos produtos no período (R$/kg) |
| [ ] | `vlFreteKg[D28\|D56\|D365\|Vida]` | Frete total / massa total dos produtos no período (R$/kg) |

### 7. Top 3 Categorias do Seller

> Três colunas separadas, uma por posição do ranking, determinado por quantidade vendida. Período aplicado a todas.

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `descTopCategoria1[D28\|D56\|D365\|Vida]` | Nome da 1ª categoria mais vendida do seller no período |
| [ ] | `descTopCategoria2[D28\|D56\|D365\|Vida]` | Nome da 2ª categoria mais vendida do seller no período |
| [ ] | `descTopCategoria3[D28\|D56\|D365\|Vida]` | Nome da 3ª categoria mais vendida do seller no período |
| [ ] | `vlShareTopCategoria1[D28\|D56\|D365\|Vida]` | Share (%) da 1ª categoria no período |
| [ ] | `vlShareTopCategoria2[D28\|D56\|D365\|Vida]` | Share (%) da 2ª categoria no período |
| [ ] | `vlShareTopCategoria3[D28\|D56\|D365\|Vida]` | Share (%) da 3ª categoria no período |

---

## Variáveis Extras *(complementares — revisão externa)*

> Variáveis **adicionais** às 7 seções acima, adotadas a partir da revisão
> [`criticas_codex.md`](criticas_codex.md). Não substituem nenhuma variável
> original; complementam o conjunto. Detalhes e ressalvas em
> [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md).

### E1. Missingness de cadastro *(estáticas — sem sufixo de período)*

> Capturam **ausência de cadastro** (atributo NULL), que a média não enxerga
> (`AVG` descarta NULL; não há valor 0 explícito em fotos). Calculadas sobre os
> **produtos distintos** do seller. ⚠ No dataset Olist os três primeiros
> coincidem (mesmos produtos sem cadastro) e `vlShareProdutosSemPeso` é quase
> constante (só 2 produtos sem peso) — ver doc detalhada.

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlShareProdutosSemCategoria` | Fração dos produtos distintos do seller sem categoria cadastrada |
| [ ] | `vlShareProdutosSemDescricao` | Fração dos produtos distintos sem descrição |
| [ ] | `vlShareProdutosSemFoto` | Fração dos produtos distintos sem foto |
| [ ] | `vlShareProdutosSemPeso` | Fração dos produtos distintos sem peso |

### E2. Indicadores por kg ajustados (log) `*`

> Versão `log1p` (`ln(1+x)`) de §6, para conter a cauda assimétrica de R$/kg
> (produtos leves geram valores enormes; skew bruto ~30–45 → ~0,45). **Mantêm-se
> as colunas cruas** de §6; estas são adicionais (sufixo `Ajustado`).

| Status | Variável | Descrição |
|--------|----------|-----------|
| [ ] | `vlPrecoKgAjustado[D28\|D56\|D365\|Vida]` | `log1p` do preço por kg no período |
| [ ] | `vlFreteKgAjustado[D28\|D56\|D365\|Vida]` | `log1p` do frete por kg no período |
