# CLAUDE.md — contexto persistente do projeto

> Arquivo de contextualização para futuras sessões do Claude Code. Mantém as
> diretrizes do projeto, as **decisões travadas** e uma seção de **planejamento e
> progresso** que **DEVE ser atualizada a cada etapa concluída**.

---

## 1. Persona

Staff Machine Learning Engineer / Data Scientist. Arquitetura de dados para
modelos preditivos, otimização de queries Spark (Databricks) e feature
engineering para marketplaces/e-commerce. Postura: **autônoma e analítica** —
questionar premissas, garantir governança e traduzir regras de negócio em SQL
eficiente e bem documentado. Não só gerar código.

## 2. Contexto de negócio — Ativação de Sellers

- Dataset: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
  (consultar o site é importante; contexto também em
  `brazilian-ecommerce-metadata.json`).
- **Problema:** prever **inativação de sellers** — quem tem alta probabilidade de
  **NÃO vender no mês X+1**.
- **Safra/cutoff:** previsão roda no último dia útil do mês X; features usam todo
  o histórico até X; target = comportamento em X+1.
- **Entregável:** scripts de feature engineering (produtos/sellers) das variáveis
  de `variaveis.md`. **Não** é uma feature store complexa agora.
- **Fonte da verdade das variáveis:** SOMENTE [`variaveis.md`](variaveis.md) —
  reescrito com a **convenção de nomenclatura** `[prefixo][Qualificador][Metrica][Periodo]`
  (`vl`/`desc`; sufixos `D28/D56/D365/Vida`) em 7 seções + extras. A entrega são
  **13 scripts por dialeto** (12 das 7 seções + 1 de missingness; nome do arquivo =
  nome oficial). Métricas de **atributo imutável do produto** (descrição, fotos e a
  **distribuição** de peso/cubagem) são **estáticas** (sem sufixo); as que dependem
  de **venda** (contagens, totais, R$/kg, top/share) têm as **4 janelas** (ver D5).
  [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md) é a documentação
  revisada/crítica.

## 3. Arquitetura técnica (desenvolvimento híbrido)

1. **Validação local — SQLite.** Cada CSV de `dados/` = uma tabela. Banco gerado
   por `scripts/build_sqlite.py` → `olist.db`. Sem CLI `sqlite3`/`duckdb` na
   máquina; usamos **Python 3 stdlib** (`csv` + `sqlite3`). Rodar/validar features
   com `scripts/run_feature_sqlite.py`.
2. **Produção — Spark SQL (Databricks).** Tabelas em `workspace.olist.*` (ex.
   `workspace.olist.order_items`, `workspace.olist.products`). Toda query Spark
   usa esse prefixo.
3. **Estrutura de pastas:**
   - `features_sqlite/` — scripts `.sql` validados no SQLite.
   - `features_spark/` — scripts `.sql` finais em Spark SQL (prefixo
     `workspace.olist.`).
   - **Consolidação:** 1 arquivo por **família de variável** (`NN_<nomeOficial>.sql`,
     ex. `07_vlPesoProduto.sql`); as 4 janelas (`D28/D56/D365/Vida`, quando houver) e
     as colunas irmãs (ex. todas as métricas de peso) ficam no MESMO arquivo. Colunas
     usam o **nome oficial** da convenção: com janela (`vlTotalPesoProdutosD28`,
     `descTopCategoria1Vida`…) ou estáticas sem sufixo (`vlMediaPesoProduto`,
     `vlMediaCubagemProdutos`, métricas de descrição/fotos).
4. **Parametrização de tempo (difere por dialeto):**
   - **SQLite:** token `'{data_corte}'` substituído por `run_feature_sqlite.py`
     (`--cutoff`); datas relativas via `datetime('{data_corte}', '-N days')`.
   - **Spark/Databricks — `.sql` standalone:** widget único no topo de cada query
     (`CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';`) lido pelo **parameter
     marker** `:data_corte` — ex. `timestamp(:data_corte) - INTERVAL N DAYS`. NÃO
     usar a sintaxe legada `${data_corte}` (Databricks emite aviso de depreciação);
     `'{data_corte}'` entre aspas é string literal e NÃO é substituído.
   - **Spark/Databricks — notebook `ativacaoOlistProdutos_databricks.ipynb`:** usa
     **variável de sessão** (não widget) — célula de setup
     `DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';`
     + `SET VARIABLE`; as queries leem `data_corte` direto (o build troca
     `:data_corte`→`data_corte`). Motivo: **widget de texto pode ficar vazio** →
     `timestamp('')` lança `CAST_INVALID_INPUT`. A variável tem sempre o valor do
     DEFAULT. (Decisão do cliente: definir o corte numa célula, não via widget.)
   - Corte **estrito** `order_purchase_timestamp < <corte>` nos dois dialetos.
5. **Provas embutidas (ANÁLISE / PROVAS):** cada feature `.sql` (nos 2 dialetos)
   traz, ABAIXO da query principal, uma seção `-- ===== ANÁLISE / PROVAS =====` com
   sub-queries que comprovam as decisões (NULLs → COALESCE, DISTINCT vs unidade,
   NULLIF, ranking/desempate, SKUs multi-seller). No SQLite são "blocos" rodáveis
   individualmente via `--block N` (ver §7); no Spark cada `SELECT` roda numa célula
   (o widget alimenta o `:data_corte` das provas também).

## 4. Padrões de documentação e qualidade

- `docs/variaveis_detalhadas.md` é a bíblia. Para CADA variável: racional, por que
  data X e não Y, como ajuda a prever inativação, cuidados com nulos, mini-exemplo.
- Nível **Sênior**. Validar localmente antes de traduzir para Spark; fazer
  auto-crítica (ex.: "esse JOIN duplica linhas?").

## 5. Decisões TRAVADAS (não reabrir sem o cliente)

| # | Decisão | Justificativa |
| - | ------- | ------------- |
| D1 | **Data de venda/corte = `order_purchase_timestamp`** (estrito `<`) | nunca nulo; é o evento de venda; `approved_at` tem 160 nulos; `delivered` é futuro/leaky. **Confirmado pelo cliente.** |
| D2 | **Sem filtro de `order_status`** — todo pedido realizado conta | "o que importa é pedido realizado". **Confirmado pelo cliente.** |
| D3 | Grão = 1 linha por `seller_id` em um `{data_corte}` único | enunciado pede corte parametrizável (não painel mensal). |
| D4 | Universo = sellers com ≥1 venda antes do corte | "cadastrados e que já operaram". |
| D5 | Janelas semi-abertas `[corte−N, corte)`. São **estáticas** (só Vida) as métricas de **atributo imutável do produto**: **§3 (descrição + fotos)** e a **distribuição de §4/§5 (peso e cubagem)**. Têm 4 janelas as que dependem de **venda**: contagens (§1,§2), **totais** de peso/cubagem, R$/kg (§6) e top categorias/share (§7) | honra `data_venda < hoje`; atributo de produto não muda no tempo. **Revisado pelo colega** (a v2 dava 4 janelas à distribuição de peso/cubagem; revertido — só os totais têm janela). |
| D6 | Categoria NULL → `'sem_categoria'` | não some do DISTINCT/ranking. |
| D7 | **Estatísticas de distribuição** (média/mediana/percentis/min/max) de **descrição, fotos, peso e cubagem** ponderam por **produto distinto por seller** (`DISTINCT product_id`). Para peso/cubagem é **estática** (toda a vida, sem janela — D5). **Totais** (`vlTotalPeso/Cubagem`) e **razões R$/kg** (§6) somam por **unidade vendida** | característica de produto não deve repetir o SKU; massa/volume/receita embarcados são da venda. **Revisado pelo colega.** |
| D8 | Percentis = **tipo-7 (interpolação linear)** | igual ao `percentile()` do Spark; SQLite reimplementa via window functions. |
| D9 | Top categorias por **quantidade vendida (unidades = linhas de `order_items`)**; share por unidades; desempate: unidades DESC → pedidos distintos DESC → categoria ASC | segue o texto do `variaveis.md` §7. **Atualizado pelo cliente** (antes era `SUM(price)`). |
| D10 | `preco/frete por kg`: num/den restritos a peso não-nulo; den 0/NULL → NULL | quociente coerente. |
| D11 | **Corte default = `2018-07-01`** (janela definida pelo Téo) | 2.750 sellers com ≥1 venda antes do corte. **Confirmado pelo cliente.** |
| D12 | **§3 (descrição + fotos): NULL → 0** (`COALESCE`), não ignorado | quantitativamente "sem cadastro" = 0 caractere / 0 foto; mantém o produto na base e puxa média/mínimo (sinal de catálogo fraco). Não há "0 natural" (mín. real de fotos = 1; descrição vazia = NULL). **Demais numéricas (peso/cubagem/R$/kg) seguem ignorando NULL** (peso 0 seria fisicamente falso). **Decisão do colega.** |

## 6. Fatos do dataset (verificados no olist.db, **cutoff 2018-07-01**)

- `order_purchase_timestamp`: 2016-09-04 → 2018-10-17 (dataset inteiro).
- **2.750 sellers** com ≥1 venda antes de 2018-07-01 (todas as 13 features
  retornam 2.750 linhas, sem duplicidade).
- 98.309 itens vendidos antes do corte.
- 87 pedidos (< corte) com `order_approved_at` NULL.
- Produtos distintos vendidos: **580** sem categoria/descrição/foto (os mesmos
  produtos — cadastro vazio em bloco; com D12 viram 0 em desc/fotos, afetando 190
  sellers na média e 250 no mínimo); **2** sem peso. **Peso e cubagem são únicos
  por `product_id`** (0 produtos com >1 valor) → atributo estático (D5/D7).
- **980** `product_id` vendidos por >1 seller antes do corte (§2 concorrência
  direta é relevante).
- Erros de grafia mantidos: `product_name_lenght`, `product_description_lenght`.
- (Referência: no cutoff antigo 2018-09-01 eram 3.095 sellers / 1.225 SKUs
  multi-seller / 610 sem categoria.)

## 7. Comandos úteis

```powershell
python scripts/build_sqlite.py                                   # gera olist.db
python scripts/run_feature_sqlite.py features_sqlite/07_vlPesoProduto.sql        # default --cutoff 2018-07-01
# provas embutidas (a feature é o bloco 1; as provas começam no bloco 2):
python scripts/run_feature_sqlite.py features_sqlite/01_vlCategoriasDistintas.sql --list
python scripts/run_feature_sqlite.py features_sqlite/01_vlCategoriasDistintas.sql --block 2
```

---

## 8. Planejamento e próximas etapas (ATUALIZAR A CADA ETAPA)

### Concluído
- [x] Setup SQLite autônomo (`scripts/build_sqlite.py`, `run_feature_sqlite.py`);
      `olist.db` com 9 tabelas e contagens conferidas.
- [x] **Features 01–14** em `features_sqlite/` e `features_spark/` (1 arquivo por
      variável, 4 janelas embutidas quando `*`).
- [x] Validação local de todos os 14 scripts SQLite: 3.095 sellers, sem
      duplicidade, monotonia das contagens, cross-check de
      médias/percentis/totais/top/share vs `numpy`/manual (0 divergências).
- [x] `docs/variaveis_detalhadas.md` reescrito (premissas vigentes + itens 1–14 +
      dicionário consolidado).
- [x] `README.md` realinhado (SQLite+Spark; removida narrativa DuckDB).
- [x] `CLAUDE.md` (este arquivo).
- [x] **Revisão crítica das 14 variáveis** registrada em
      [`docs/revisao_critica.md`](docs/revisao_critica.md) (≥3 questionamentos por
      variável + defesa da motivação). **Decisão do cliente: NENHUMA alteração
      adotada** — as 14 variáveis permanecem como originalmente construídas e
      validadas (inclusive item 14 `share_topk` = `NULL` para <k categorias). As
      recomendações ficam apenas documentadas como backlog opcional.
- [x] **Spark parametrizado por widget** — os 14 `features_spark/` trocaram o token
      `'{data_corte}'` por `CREATE WIDGET TEXT data_corte DEFAULT '2018-09-01'` +
      `:data_corte` (parameter marker). Some o erro de cast e o aviso de `$`.
- [x] **Provas embutidas por feature** — seção `ANÁLISE / PROVAS` anexada aos 28
      `.sql` (spark+sqlite), 2–3 sub-queries por feature. `run_feature_sqlite.py`
      ganhou `--list`/`--block` (splitter consciente de `;` em comentários; default
      = bloco 1 = feature, saída inalterada). Provas SQLite rodadas no `olist.db`
      reconfirmam os fatos do §6 (1.225 SKUs multi-seller; 2 sem peso; 610 sem
      categoria/descrição).
- [x] **Refactor de legibilidade (03/04/11/12, ambos dialetos)** — removidos os
      self-joins de 03/04 (`sc a JOIN sc b`) em favor de CTEs nomeadas
      (`minhas_categorias`/`meus_produtos` × `roster_*`); 11/12 quebram o
      `SUM(...)/NULLIF(SUM(...))` aninhado numa CTE `componentes` (num/den por
      janela). Provas reescritas no mesmo padrão (04 Prova A: subquery → CTE
      `produtos_disputados`). **Saída idêntica** validada por hash do resultado
      completo no `olist.db` (cutoff 2018-09-01): 03/04/11/12 inalterados.
- [x] **Subqueries das PROVAS eliminadas** — `FROM (SELECT…) t` das provas de
      05/10/13/14 (ambos dialetos) viraram CTEs (`produtos_distintos`,
      `cat_por_seller`). Hash dos blocos inalterado. Agora **nenhum self-join nem
      subquery** resta em código nos 28 `.sql` (só comentários citam o padrão antigo).
- [x] **Refactor v2 — renomeação + nova convenção + corte 2018-07-01** (sessão
      atual). Os 14 arquivos viraram **12 por dialeto** com o nome oficial da
      variável (`NN_vl…/desc…`.sql); colunas no padrão `[prefixo][Metrica][Periodo]`.
      Queries reescritas com CTEs limpas e "montagem gradual" (peso usa formato
      longo `prod_janela` p/ escrever a interpolação tipo-7 1×; top categorias usa
      agregação condicional + `ROW_NUMBER` por janela). **Mudanças de regra (cliente):**
      (a) corte default `2018-07-01`; (b) **D7** — distribuição de **peso e cubagem**
      também por **produto distinto por janela** (totais/razões seguem por unidade);
      (c) **D9** — top categorias/share por **unidades vendidas**; (d) **§7 com 4
      janelas**. **Validação no `olist.db` (cutoff 2018-07-01):** 12 features = 2.750
      sellers, 0 duplicidade, monotonia OK; percentis de descrição/peso e médias de
      cubagem batem com `numpy` sobre produtos distintos; top/share conferidos vs
      Python (120 sellers × 4 janelas × 3 posições, 0 divergências). **Spark ≡ SQLite**
      por tradução de dialeto + comparação (percentil tipo-7 = `percentile()`).
      Corrigido bug no share (posição inexistente devia ser `NULL`, não `0` → guard
      `u_>0`). Docs (`variaveis_detalhadas.md`, `README.md`, este arquivo) realinhados.

- [x] **Variáveis extras da revisão externa** (`criticas_codex.md`). Adotados só os
      pontos pedidos pelo cliente: **(7) missingness de cadastro** — novo
      `13_vlShareProdutosSemCadastro` (ambos dialetos) com
      `vlShareProdutosSem{Categoria,Descricao,Foto,Peso}` (DISTINCT produto, Vida);
      análise mostrou que cat≡desc≡foto são **colineares** (mesmos 580 produtos) e
      `SemPeso` é ~constante (2 produtos) — documentado. **(9) outliers** —
      `vlPrecoKgAjustado{W}`/`vlFreteKgAjustado{W}` = `log1p` adicionados em `09`/`10`
      (cruas mantidas); skew bruto ~30–45 → ~0,45. **(6) `product_id`** e **(10)
      encoding** registrados em novo `consideracoes_finais.md` (sem mudança de
      código). Validado: 13 SQLite = 2.750 sellers, `ln(1+x)`≡`numpy.log1p`,
      colinearidade/cobertura confirmadas nas provas. `variaveis.md` ganhou seção
      "Variáveis Extras"; docs e notebook realinhados. Demais pontos da revisão
      (cancelamento, flags de atividade, concorrência normalizada, HHI) **não**
      adotados.

- [x] **Revisão do colega — peso/cubagem estáticos + descrição/fotos NULL→0**
      (sessão atual). Três considerações avaliadas e adotadas (decisão do cliente):
      **(1)** §3 descrição e fotos tratam **NULL como 0** (`COALESCE`, antes
      ignoravam) — "sem cadastro" entra como zero e puxa média/mínimo (D12). Impacto
      no `olist.db` (cutoff 2018-07-01): 580 produtos distintos viram 0 → **190
      sellers** mudam a média, **250** passam a ter mínimo 0. **(2)** Peso (§4) e
      cubagem (§5) são **atributos imutáveis** do produto (`products` = 1 linha/
      `product_id`) → a **distribuição** voltou a ser **estática** (sem D28/D56/
      D365), revertendo a v2 (D5/D7). Os **totais** (`vlTotalPeso/Cubagem`, massa/
      volume embarcado) **mantêm as 4 janelas** porque dependem de venda. **(3)**
      R$/kg (§6) **mantidos com 4 janelas** (receita/frete mudam no tempo) — nenhuma
      alteração. Reescritos 05/06/07/08 nos 2 dialetos (peso/cubagem simplificados:
      sem `prod_janela`/flags `in_dXX`; distribuição = mesmo padrão de 05). Saída:
      07 de 33→**12 col.**, 08 de 9→**6 col.**; total do projeto **108→84 colunas**
      de feature. **Validação (cutoff 2018-07-01):** 05/06/07/08 = 2.750 sellers, 0
      duplicidade; cross-check vs `numpy` (300 sellers × 6 estatísticas, **0
      divergências**) com zeros incluídos em desc/fotos e base estática em peso/
      cubagem; **prova A de 07/08 retorna 0 linhas** (nenhum `product_id` tem >1
      valor de peso/cubagem — confirma a imutabilidade). `variaveis.md`,
      `docs/variaveis_detalhadas.md` (premissas 3.4/3.6/3.7, §4.3/4.4/4.5,
      dicionário, contagem) e este arquivo (D5/D7/D12, §2, §6) realinhados.

- [x] **Notebook Databricks: corte por variável de sessão + validação do tabelão**
      (sessão atual). Erro em produção: `CAST_INVALID_INPUT` ao rodar o consolidado —
      o **widget `data_corte` estava vazio** e `timestamp('')` quebra. Solução (pedido
      do cliente): trocar o widget por **variável de sessão** numa célula de setup
      (`DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01'`
      + `SET VARIABLE`); o `build_databricks_notebook.py` agora gera essa célula e
      troca `:data_corte`→`data_corte` em todas as queries (os 13 `.sql` standalone
      seguem com widget). **Validação inédita do consolidado:** traduzi o tabelão do
      notebook para SQLite e comparei com o `LEFT JOIN` dos 13 scripts —
      **0 divergências em 40.800 checagens** (600 sellers × 68 colunas: contagens,
      médias incl. peso/cubagem estáticos, min/max, totais, share, top, missingness;
      percentis/`log1p` validados nos scripts individuais). Nisso achei e corrigi um
      bug latente: o share do consolidado não tinha o `* 1.0` do `12_…` (no Spark
      `INT/INT`=DOUBLE, mas no SQLite dava divisão inteira → 0) — alinhado.

### Próximas etapas sugeridas (fora do escopo atual)
- [ ] Validar os scripts `features_spark/` num cluster Databricks real (widget
      `data_corte` + `:data_corte`, `percentile`, `INTERVAL`, `timestamp()`),
      comparando com os números do SQLite.
- [ ] Definir e calcular o **alvo** de churn (vendeu ou não em X+1).
- [ ] (Opcional) Montagem da feature store larga via `LEFT JOIN` dos 13 scripts
      por `seller_id`.
- [ ] Malha de cutoffs mensais para gerar massa de treino.
- [ ] Treinar classificador e avaliar.

### Convenções para manutenção
- Ao criar/alterar uma feature: validar no SQLite **antes** de traduzir; manter
  os dois dialetos sincronizados (só prefixo + funções + parametrização devem
  diferir); atualizar `docs/variaveis_detalhadas.md` e esta seção.
- Toda feature nova deve trazer a seção `ANÁLISE / PROVAS` (provas das decisões)
  nos dois dialetos, validada no SQLite via `--block`.
