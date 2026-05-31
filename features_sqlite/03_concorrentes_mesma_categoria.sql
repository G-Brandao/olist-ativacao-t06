-- =====================================================================
-- Feature 03 (variaveis.md item 3) — Sellers concorrentes em mesma categoria
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Definição : para o seller A, nº de OUTROS sellers (B<>A) que venderam
--             em ALGUMA categoria em que A vendeu, na mesma janela.
--             (concorrência indireta — produtos substitutos).
-- Data venda: order_purchase_timestamp (corte estrito < {data_corte}).
-- Premissas : sem filtro de order_status; categoria NULL -> 'sem_categoria';
--             medida simétrica; sem venda na janela -> 0 concorrentes.
-- Modelagem : em vez de um self-join (sc a JOIN sc b), separamos os dois papéis
--             em CTEs nomeadas: "minhas_categorias" (onde o seller atua) e o
--             "roster" (todos os sellers por categoria). O cruzamento fica
--             explícito e legível; COUNT(DISTINCT concorrente) impede dupla
--             contagem quando A e B compartilham várias categorias.
-- Parâmetro : {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM order_items oi
    JOIN orders      o ON o.order_id   = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- (1) Minhas categorias: pares distintos (seller, categoria) ativos por janela.
minhas_cat_d28  AS (SELECT DISTINCT seller_id, categoria FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-28 days')),
minhas_cat_d56  AS (SELECT DISTINCT seller_id, categoria FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-56 days')),
minhas_cat_d365 AS (SELECT DISTINCT seller_id, categoria FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-365 days')),
minhas_cat_vida AS (SELECT DISTINCT seller_id, categoria FROM vendas),
-- (2) Roster por categoria: os mesmos pares vistos como "concorrente na categoria".
roster_d28  AS (SELECT categoria, seller_id AS concorrente FROM minhas_cat_d28),
roster_d56  AS (SELECT categoria, seller_id AS concorrente FROM minhas_cat_d56),
roster_d365 AS (SELECT categoria, seller_id AS concorrente FROM minhas_cat_d365),
roster_vida AS (SELECT categoria, seller_id AS concorrente FROM minhas_cat_vida),
-- (3) Concorrentes distintos: cruza as categorias do seller com o roster da
--     categoria e exclui o próprio seller.
conc_d28  AS (SELECT mc.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM minhas_cat_d28  mc JOIN roster_d28  r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id GROUP BY mc.seller_id),
conc_d56  AS (SELECT mc.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM minhas_cat_d56  mc JOIN roster_d56  r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id GROUP BY mc.seller_id),
conc_d365 AS (SELECT mc.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM minhas_cat_d365 mc JOIN roster_d365 r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id GROUP BY mc.seller_id),
conc_vida AS (SELECT mc.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM minhas_cat_vida mc JOIN roster_vida r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id GROUP BY mc.seller_id),
spine AS (SELECT DISTINCT seller_id FROM vendas)
SELECT
    s.seller_id,
    COALESCE(conc_d28.q,  0) AS qtd_concorrentes_mesma_categoria_d28,
    COALESCE(conc_d56.q,  0) AS qtd_concorrentes_mesma_categoria_d56,
    COALESCE(conc_d365.q, 0) AS qtd_concorrentes_mesma_categoria_d365,
    COALESCE(conc_vida.q, 0) AS qtd_concorrentes_mesma_categoria_vida
FROM spine s
LEFT JOIN conc_d28  ON conc_d28.seller_id  = s.seller_id
LEFT JOIN conc_d56  ON conc_d56.seller_id  = s.seller_id
LEFT JOIN conc_d365 ON conc_d365.seller_id = s.seller_id
LEFT JOIN conc_vida ON conc_vida.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — estrutura do roster join: pares (minhas_categorias, concorrente) na mesma categoria -----------------------
-- É a matéria-prima do COUNT(DISTINCT concorrente) por seller. Note os dois
-- papéis nomeados (minhas_categorias x roster) no lugar de um self-join a/b.
WITH minhas_categorias AS (
    SELECT DISTINCT
        oi.seller_id,
        COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
roster_por_categoria AS (
    SELECT categoria, seller_id AS concorrente FROM minhas_categorias
)
SELECT mc.seller_id AS seller_a, mc.categoria, r.concorrente AS concorrente_b
FROM minhas_categorias mc
JOIN roster_por_categoria r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id
ORDER BY mc.seller_id, mc.categoria
LIMIT 50;

-- ----------------------- Prova B — por que COUNT(DISTINCT concorrente): pares que compartilham >1 categoria -----------------------
-- Sem DISTINCT, o concorrente seria contado uma vez por categoria em comum (dupla contagem).
WITH minhas_categorias AS (
    SELECT DISTINCT
        oi.seller_id,
        COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
roster_por_categoria AS (
    SELECT categoria, seller_id AS concorrente FROM minhas_categorias
)
SELECT mc.seller_id AS seller_a, r.concorrente AS concorrente_b,
       COUNT(*) AS categorias_em_comum
FROM minhas_categorias mc
JOIN roster_por_categoria r ON r.categoria = mc.categoria AND r.concorrente <> mc.seller_id
GROUP BY mc.seller_id, r.concorrente
HAVING COUNT(*) > 1
ORDER BY categorias_em_comum DESC
LIMIT 20;

-- ----------------------- Prova C — categorias com um único seller (geram 0 concorrentes -> COALESCE 0 / spine) -----------------------
-- Confirma por que precisamos do spine + COALESCE(...,0) para não perder esses sellers.
WITH minhas_categorias AS (
    SELECT DISTINCT
        oi.seller_id,
        COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT categoria, COUNT(DISTINCT seller_id) AS sellers_na_categoria
FROM minhas_categorias
GROUP BY categoria
HAVING COUNT(DISTINCT seller_id) = 1
ORDER BY categoria
LIMIT 20;
