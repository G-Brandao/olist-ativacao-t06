# Críticas Codex — métricas de produtos dos sellers

Data da revisão: 2026-06-02  
Cutoff usado nas validações: `2018-07-01`

## O que foi revisado

Revisei a lógica das features de produtos dos sellers usando:

- `variaveis.md`
- `CONSIDERACOES_IMPORTANTES.md`
- `docs/variaveis_detalhadas.md`
- scripts em `features_sqlite/` e `features_spark/`
- validação local no `olist.db`
- contexto do dataset Olist no Kaggle: <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>

No corte `2018-07-01`, as 12 features SQLite retornaram **2.750 sellers** e **0 duplicidades de `seller_id`**. Isso é um bom sinal: a implementação está consistente no grão esperado.

## Veredito geral

As features foram bem construídas do ponto de vista técnico. A lógica respeita o corte temporal, evita olhar para vendas futuras e mantém uma separação boa entre:

- características do produto, calculadas por `product_id` distinto;
- volume operacional, calculado por unidade vendida.

Eu não encontrei um erro estrutural de join, duplicação ou janela que invalide as métricas.

O principal ponto é outro: várias features são boas como **sinais crus**, mas ainda precisam de tratamento para virarem variáveis fortes em modelo. Algumas misturam porte do seller, tempo de casa, categoria popular, ausência de cadastro e outliers extremos.

## Boas decisões

### 1. Corte temporal bem definido

A regra `order_purchase_timestamp < data_corte` é uma boa decisão. Ela evita vazamento de informação do futuro e deixa claro que o snapshot representa tudo que aconteceu antes do corte.

As janelas D28, D56, D365 e Vida também estão coerentes. Usar intervalos semiabertos, do tipo `[início, corte)`, é correto para esse problema.

Um pequeno ajuste de robustez ainda é recomendado no SQLite: trocar a ponta superior de `< '{data_corte}'` para `< datetime('{data_corte}')`. O resultado deve ser igual, mas a comparação fica mais explícita.

### 2. `order_purchase_timestamp` é melhor que entrega ou aprovação

Usar a data de compra é melhor que usar aprovação ou entrega. Aprovação pode ser nula, e entrega acontece depois, podendo gerar vazamento.

Para prever inativação de sellers, a pergunta principal é: o seller recebeu um pedido? Nesse sentido, `order_purchase_timestamp` é o campo certo.

### 3. Grão por produto distinto nas características de produto

Para descrição, fotos, peso médio, percentis de peso e cubagem média, usar `DISTINCT product_id` por seller é uma boa escolha.

Se um mesmo SKU vende 100 vezes, ele não deveria pesar 100 vezes em uma métrica que descreve o produto em si. Isso evita confundir característica de catálogo com intensidade de venda.

### 4. Totais por unidade vendida

Para peso total, cubagem total, preço/kg e frete/kg, usar unidade vendida também é correto.

Essas métricas não descrevem apenas o catálogo. Elas descrevem a operação real: massa embarcada, volume embarcado, receita e frete.

### 5. Top categorias por quantidade vendida

O ranking por unidades vendidas faz sentido para o texto do `variaveis.md`. Também é bom que `descTopCategoria` e `vlShareTopCategoria` usem a mesma regra de ranking.

## Pontos que merecem revisão

### 1. Pedidos cancelados entram em todas as métricas

A decisão de não filtrar `order_status` é defensável para ativação, porque um pedido realizado mostra que o seller teve movimento.

Mas para métricas como preço/kg, frete/kg, peso total, cubagem total e top categorias, pedidos cancelados ou indisponíveis podem contaminar o sinal.

No corte revisado:

- `canceled` + `unavailable` representam só **0,625% da receita**;
- mas afetam **291 sellers** e **464 itens**.

Impacto global pequeno, mas pode ser relevante justamente para sellers problemáticos.

Recomendação: manter a decisão atual, mas criar features complementares de cancelamento, como `taxaCancelamentoD28`, `taxaCancelamentoD365` ou `qtdPedidosCancelados`.

### 2. `sem_categoria` ajuda, mas também mistura conceitos

Transformar categoria nula em `'sem_categoria'` evita perder sellers no cálculo. Isso é bom.

O problema é que `'sem_categoria'` vira uma categoria artificial. Ela mistura ausência de cadastro com vertical de produto.

No corte revisado:

- **580 produtos distintos** vendidos antes do corte estavam sem categoria;
- **98 sellers** tinham `'sem_categoria'` como top 1 Vida;
- `'sem_categoria'` apareceu **212 vezes** no top 3 Vida.

Recomendação: manter `'sem_categoria'` para não perder linhas, mas criar uma feature separada de qualidade cadastral, como `vlShareProdutosSemCategoria`.

### 3. Muitos sellers não venderam em D28

No corte `2018-07-01`, **1.593 sellers** não venderam nos últimos 28 dias. Isso é **57,93%** da base.

Isso explica muitos zeros e nulos nas features D28. Não é bug; para churn, pode ser um sinal forte.

Mas é importante o modelo saber diferenciar:

- zero porque não houve venda;
- zero porque houve venda, mas a métrica é realmente zero;
- nulo porque a métrica não é definida.

Recomendação: criar flags simples, como `flVendeuD28`, `flVendeuD56` e `qtdItensVendidosD28`. Elas ajudam o modelo a interpretar as demais features.

### 4. Concorrência por categoria pode virar proxy de categoria popular

`vlContagemCategoriaConcorrentes` está bem implementada. O problema é conceitual.

Se uma categoria é muito grande, todo seller nela terá muitos concorrentes. Isso pode medir mais a popularidade da categoria do que a pressão competitiva específica do seller.

No corte revisado:

- média Vida: **406 concorrentes por categoria comum**;
- máximo Vida: **2.352 concorrentes**.

Recomendação: manter a métrica, mas criar versões normalizadas:

- percentual de concorrentes dentro das categorias do seller;
- Jaccard de categorias;
- concorrência ponderada pelo share de categorias do seller.

### 5. Concorrência por produto é muito esparsa

`vlContagemProdutosConcorrentes` é uma métrica interessante, porque tenta medir concorrência direta no mesmo SKU.

Mas ela é muito esparsa:

- em D28, **2.695 sellers** têm valor zero;
- em Vida, **2.127 sellers** têm valor zero.

Isso não invalida a feature, mas reduz a informação numérica da contagem.

Recomendação: além da contagem, criar uma flag binária: `flTemConcorrenteMesmoProduto`. Para muitos modelos, essa flag pode ser mais estável que a contagem bruta.

### 6. `product_id` não é SKU canônico perfeito

As features de produto usam `product_id`, que é a melhor chave disponível no dataset.

Mesmo assim, há uma limitação: o mesmo produto físico pode aparecer com ids diferentes. Isso pode:

- inflar `vlProdutosDistintos`;
- reduzir artificialmente `vlContagemProdutosConcorrentes`;
- espalhar concorrência real em vários ids.

Recomendação: registrar essa limitação no documento final. Corrigir de verdade exigiria uma etapa de deduplicação ou agrupamento de produtos similares, o que está fora do escopo atual.

### 7. Descrição e fotos precisam capturar ausência, não só média

As métricas de descrição e fotos estão corretas ao usar produtos distintos.

Mas hoje a ausência de cadastro aparece de forma indireta. No corte revisado:

- **580 produtos** estavam sem descrição;
- **580 produtos** estavam com `product_photos_qty` nulo;
- **60 sellers** ficaram com média de descrição/fotos nula.

A ausência de descrição ou foto pode ser mais importante que o tamanho médio da descrição.

Recomendação: criar features de missingness:

- `vlShareProdutosSemDescricao`;
- `vlShareProdutosSemFoto`;
- `vlQtdProdutosSemDescricao`;
- `vlQtdProdutosSemFoto`.

### 8. Peso e cubagem são boas, mas carregam escala

Peso total e cubagem total ajudam a medir o tamanho da operação. Isso é útil para churn.

Mas elas também são muito colineares com volume de vendas. Um seller maior naturalmente terá maior peso total, maior cubagem total e mais produtos.

Recomendação: manter as métricas, mas criar razões de recência:

- `vlTotalPesoProdutosD28 / vlTotalPesoProdutosD365`;
- `vlTotalCubagemProdutosD28 / vlTotalCubagemProdutosD365`;
- `vlProdutosDistintosD28 / vlProdutosDistintosVida`.

Essas razões mostram queda ou aceleração, que é mais próximo do comportamento de churn.

### 9. Preço/kg e frete/kg têm outliers extremos

A lógica de `SUM(price) / SUM(kg)` e `SUM(freight_value) / SUM(kg)` está correta para o que foi pedido.

O problema é que produtos muito leves podem gerar valores enormes.

No corte revisado:

- `vlPrecoKgVida` chegou a **R$ 81.355/kg**;
- `vlPrecoKgD28` chegou a **R$ 64.687,50/kg**;
- `vlFreteKgVida` chegou a **R$ 12.105/kg**;
- `vlFreteKgD28` chegou a **R$ 17.382,50/kg**.

Esses valores podem dominar modelos lineares e distorcer algumas análises.

Recomendação: aplicar transformação antes do modelo:

- `log1p(preco/kg)`;
- winsorização;
- ou bucketização por faixas.

### 10. Top categorias precisam de encoding cuidadoso

As top categorias são úteis porque indicam vertical do seller.

Mas são variáveis categóricas com cardinalidade relevante:

- `descTopCategoria1Vida` tem **67 categorias distintas**;
- o dataset antes do corte tem **74 categorias** no total.

Além disso, `top2` e `top3` são muito nulos:

- `vlShareTopCategoria2Vida` é nulo para **1.543 sellers**;
- `vlShareTopCategoria3Vida` é nulo para **2.138 sellers**.

Isso é esperado, porque muitos sellers vendem em uma ou duas categorias. Mas o modelo precisa tratar esses nulos corretamente.

Recomendação:

- usar encoding adequado para categorias;
- manter indicador de ausência de top2/top3;
- testar um índice de concentração, como HHI ou entropia do mix de categorias.

### 11. `docs/revisao_critica.md` parece desatualizado

O arquivo `docs/revisao_critica.md` ainda fala em 14 variáveis, cutoff antigo e top categorias/share como Vida e por receita.

A versão atual do projeto tem 12 scripts por dialeto, cutoff default `2018-07-01`, top categorias por unidades e janelas D28/D56/D365/Vida.

Recomendação: atualizar ou marcar `docs/revisao_critica.md` como documento histórico. Caso contrário, ele pode confundir quem for manter o projeto.

## Crítica por família de métrica

| Família | Avaliação | Principal cuidado |
| --- | --- | --- |
| `vlCategoriasDistintas` | Boa e interpretável | Confunde diversidade com porte; tratar `'sem_categoria'` separado |
| `vlProdutosDistintos` | Boa como largura de catálogo | `product_id` pode não representar produto físico único |
| `vlContagemCategoriaConcorrentes` | Útil, mas bruta | Pode medir popularidade da categoria, não pressão específica |
| `vlContagemProdutosConcorrentes` | Boa ideia | Muito esparsa; criar flag binária |
| `vlCaracteresDescricao` | Tecnicamente correta | Criar sinal explícito de descrição ausente |
| `vlMediaFotosProduto` | Tecnicamente correta | Criar sinal explícito de foto ausente |
| `vlPesoProduto` | Boa separação entre distribuição e total | Totais carregam escala; criar razões de recência |
| `vlCubagemProdutos` | Boa proxy logística | Cubagem da caixa não é volume real; usar log/razões |
| `vlPrecoKg` | Correta pela definição | Outliers extremos; transformar antes do modelo |
| `vlFreteKg` | Correta pela definição | Mistura peso, distância e política de frete |
| `descTopCategoria` | Boa feature categórica | Exige encoding; cuidado com `'sem_categoria'` |
| `vlShareTopCategoria` | Boa medida de concentração | Top2/top3 muito nulos; considerar HHI/entropia |

## Prioridades recomendadas

### Alta prioridade

1. Criar flags de atividade por janela: `flVendeuD28`, `flVendeuD56`, `flVendeuD365`.
2. Criar features de missingness de cadastro: categoria, descrição, fotos e peso ausentes.
3. Tratar outliers de `vlPrecoKg` e `vlFreteKg` antes do modelo.
4. Atualizar ou sinalizar `docs/revisao_critica.md` como documento histórico.

### Média prioridade

1. Criar métricas de recência: D28/Vida, D28/D365, D56/D365.
2. Criar concorrência normalizada, não só contagem absoluta.
3. Criar flag para concorrência direta por produto.
4. Criar HHI ou entropia de categorias.

### Baixa prioridade

1. Ajustar o SQLite para usar `< datetime('{data_corte}')`.
2. Padronizar unidades no nome ou na documentação: peso médio em gramas, peso total em kg.
3. Testar as queries Spark em cluster Databricks real.

## Conclusão

As features atuais são boas para uma primeira versão séria da feature store. Elas estão coerentes com as premissas e foram implementadas com cuidado.

O que falta não é refazer tudo. O próximo ganho deve vir de complementos simples: flags de atividade, missingness, transformações de outlier e razões entre janelas. Isso deixaria as métricas mais claras para o modelo e mais fáceis de explicar para negócio.
