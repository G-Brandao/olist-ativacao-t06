-- =====================================================================
-- Feature 04 (variaveis.md item 4) — Sellers concorrentes no mesmo produto
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Definição : para o seller A, nº de OUTROS sellers (B<>A) que venderam
--             ao menos um dos MESMOS product_id que A, na mesma janela.
--             (concorrência DIRETA — mesmo SKU = guerra de preço).
-- Data venda: order_purchase_timestamp (corte estrito < {data_corte}).
-- Premissas : sem filtro de order_status; product_id sempre presente.
-- Modelagem : em vez de um self-join (sp a JOIN sp b), separamos os dois papéis
--             em CTEs nomeadas: "meus_produtos" (SKUs que o seller vende) e o
--             "roster" (todos os sellers por product_id). COUNT(DISTINCT
--             concorrente) evita dupla contagem de quem divide >1 SKU.
-- Parâmetro : {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- (1) Meus produtos: pares distintos (seller, product_id) ativos por janela.
meus_prod_d28  AS (SELECT DISTINCT seller_id, product_id FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-28 days')),
meus_prod_d56  AS (SELECT DISTINCT seller_id, product_id FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-56 days')),
meus_prod_d365 AS (SELECT DISTINCT seller_id, product_id FROM vendas WHERE dt_venda >= datetime('{data_corte}', '-365 days')),
meus_prod_vida AS (SELECT DISTINCT seller_id, product_id FROM vendas),
-- (2) Roster por produto: os mesmos pares vistos como "concorrente no SKU".
roster_d28  AS (SELECT product_id, seller_id AS concorrente FROM meus_prod_d28),
roster_d56  AS (SELECT product_id, seller_id AS concorrente FROM meus_prod_d56),
roster_d365 AS (SELECT product_id, seller_id AS concorrente FROM meus_prod_d365),
roster_vida AS (SELECT product_id, seller_id AS concorrente FROM meus_prod_vida),
-- (3) Concorrentes distintos: cruza os SKUs do seller com o roster do produto
--     e exclui o próprio seller.
conc_d28  AS (SELECT mp.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM meus_prod_d28  mp JOIN roster_d28  r ON r.product_id = mp.product_id AND r.concorrente <> mp.seller_id GROUP BY mp.seller_id),
conc_d56  AS (SELECT mp.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM meus_prod_d56  mp JOIN roster_d56  r ON r.product_id = mp.product_id AND r.concorrente <> mp.seller_id GROUP BY mp.seller_id),
conc_d365 AS (SELECT mp.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM meus_prod_d365 mp JOIN roster_d365 r ON r.product_id = mp.product_id AND r.concorrente <> mp.seller_id GROUP BY mp.seller_id),
conc_vida AS (SELECT mp.seller_id, COUNT(DISTINCT r.concorrente) AS q FROM meus_prod_vida mp JOIN roster_vida r ON r.product_id = mp.product_id AND r.concorrente <> mp.seller_id GROUP BY mp.seller_id),
spine AS (SELECT DISTINCT seller_id FROM vendas)
SELECT
    s.seller_id,
    COALESCE(conc_d28.q,  0) AS qtd_concorrentes_mesmo_produto_d28,
    COALESCE(conc_d56.q,  0) AS qtd_concorrentes_mesmo_produto_d56,
    COALESCE(conc_d365.q, 0) AS qtd_concorrentes_mesmo_produto_d365,
    COALESCE(conc_vida.q, 0) AS qtd_concorrentes_mesmo_produto_vida
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

-- ----------------------- Prova A — premissa central: quantos product_id são vendidos por >1 seller? -----------------------
-- Esperado: ~1225 no cutoff 2018-07-01. Se fosse 0, a feature seria sempre 0.
WITH produtos_disputados AS (
    SELECT oi.product_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
    GROUP BY oi.product_id
    HAVING COUNT(DISTINCT oi.seller_id) > 1
)
SELECT COUNT(*) AS produtos_disputados_por_varios_sellers
FROM produtos_disputados;

-- ----------------------- Prova B — quais SKUs são mais disputados (ranking de sellers por produto) -----------------------
SELECT oi.product_id, COUNT(DISTINCT oi.seller_id) AS qtd_sellers
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.product_id
HAVING COUNT(DISTINCT oi.seller_id) > 1
ORDER BY qtd_sellers DESC
LIMIT 20;

-- ----------------------- Prova C — pares de sellers concorrentes no MESMO product_id (não agrupado) -----------------------
-- Matéria-prima do COUNT(DISTINCT concorrente) da feature, com os dois papéis
-- nomeados (meus_produtos x roster) no lugar de um self-join a/b.
WITH meus_produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
roster_por_produto AS (
    SELECT product_id, seller_id AS concorrente FROM meus_produtos
)
SELECT mp.product_id, mp.seller_id AS seller_a, r.concorrente AS concorrente_b
FROM meus_produtos mp
JOIN roster_por_produto r ON r.product_id = mp.product_id AND r.concorrente <> mp.seller_id
ORDER BY mp.product_id
LIMIT 50;
