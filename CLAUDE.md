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
- **Fonte da verdade das variáveis:** SOMENTE [`variaveis.md`](variaveis.md) (14
  itens). [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md) é a
  documentação revisada/crítica (substituiu um rascunho DuckDB que nunca existiu
  como código).

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
   - **Consolidação:** 1 arquivo por variável; variantes que mudam só a janela de
     tempo (`_d28/_d56/_d365/_vida`) ficam no MESMO arquivo, modulares.
4. **Parametrização de tempo (difere por dialeto):**
   - **SQLite:** token `'{data_corte}'` substituído por `run_feature_sqlite.py`
     (`--cutoff`); datas relativas via `datetime('{data_corte}', '-N days')`.
   - **Spark/Databricks:** widget único no topo de cada query
     (`CREATE WIDGET TEXT data_corte DEFAULT '2018-09-01';`) lido pelo **parameter
     marker** `:data_corte` — ex. `timestamp(:data_corte) - INTERVAL N DAYS`. NÃO
     usar a sintaxe legada `${data_corte}` (Databricks emite aviso de depreciação);
     `'{data_corte}'` entre aspas é string literal e NÃO é substituído.
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
| D5 | Janelas semi-abertas `[corte−N, corte)`; itens com `*` → 4 janelas; sem `*` (5,10,13,14) → só Vida | honra `data_venda < hoje`. |
| D6 | Categoria NULL → `'sem_categoria'` | não some do DISTINCT/ranking. |
| D7 | Itens 5 e 10 ponderam por **produto distinto**; demais por **unidade vendida** | descrição/fotos são cadastro; peso/preço são da venda. |
| D8 | Percentis = **tipo-7 (interpolação linear)** | igual ao `percentile()` do Spark; SQLite reimplementa via window functions. |
| D9 | Top categorias por **`SUM(price)`**; desempate: receita DESC → pedidos distintos DESC → categoria ASC | determinístico. |
| D10 | `preco/frete por kg`: num/den restritos a peso não-nulo; den 0/NULL → NULL | quociente coerente. |

## 6. Fatos do dataset (verificados no olist.db, cutoff 2018-09-01)

- `order_purchase_timestamp`: 2016-09-04 → 2018-10-17.
- 3.095 sellers; **todos** com ≥1 venda antes de 2018-09-01.
- 160 pedidos com `order_approved_at` NULL.
- products: 610 sem categoria/descrição; 2 sem peso.
- 1.225 `product_id` vendidos por >1 seller (item 4 é relevante).
- Erros de grafia mantidos: `product_name_lenght`, `product_description_lenght`.

## 7. Comandos úteis

```powershell
python scripts/build_sqlite.py                                   # gera olist.db
python scripts/run_feature_sqlite.py features_sqlite/06_peso_medio_mediana.sql --cutoff 2018-09-01
# provas embutidas (a feature é o bloco 1; as provas começam no bloco 2):
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --list
python scripts/run_feature_sqlite.py features_sqlite/01_qtd_categorias_distintas.sql --block 2
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

### Próximas etapas sugeridas (fora do escopo atual)
- [ ] Validar os scripts `features_spark/` num cluster Databricks real (widget
      `data_corte` + `:data_corte`, `percentile`, `INTERVAL`, `timestamp()`),
      comparando com os números do SQLite.
- [ ] Definir e calcular o **alvo** de churn (vendeu ou não em X+1).
- [ ] (Opcional) Montagem da feature store larga via `LEFT JOIN` dos 14 scripts
      por `seller_id`.
- [ ] Malha de cutoffs mensais para gerar massa de treino.
- [ ] Treinar classificador e avaliar.

### Convenções para manutenção
- Ao criar/alterar uma feature: validar no SQLite **antes** de traduzir; manter
  os dois dialetos sincronizados (só prefixo + funções + parametrização devem
  diferir); atualizar `docs/variaveis_detalhadas.md` e esta seção.
- Toda feature nova deve trazer a seção `ANÁLISE / PROVAS` (provas das decisões)
  nos dois dialetos, validada no SQLite via `--block`.
