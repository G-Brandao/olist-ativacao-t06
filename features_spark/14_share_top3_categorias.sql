-- =====================================================================
-- Feature 14 (variaveis.md item 14) — Share das top 3 categorias
-- Janela: Vida (sem `*`)           |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : share_top1, share_top2, share_top3  (frações em [0,1])
-- Definição: fração da receita total (Vida) em cada uma das 3 categorias de
--            maior receita (mesmo ranking do item 13).
-- Desempate: receita DESC, pedidos distintos DESC, categoria ASC.
-- Nulos    : <k categorias -> share_topk NULL; receita_total 0 -> NULL.
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH cat_rev AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        SUM(oi.price)                AS receita,
        COUNT(DISTINCT oi.order_id)  AS pedidos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders      o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
    GROUP BY oi.seller_id, COALESCE(p.product_category_name, 'sem_categoria')
),
ranked AS (
    SELECT
        seller_id, categoria, receita,
        ROW_NUMBER() OVER (
            PARTITION BY seller_id
            ORDER BY receita DESC, pedidos DESC, categoria ASC
        ) AS rk
    FROM cat_rev
),
tot AS (
    SELECT seller_id, SUM(receita) AS receita_total
    FROM cat_rev
    GROUP BY seller_id
)
SELECT
    r.seller_id,
    MAX(CASE WHEN r.rk = 1 THEN r.receita END) / NULLIF(t.receita_total, 0) AS share_top1,
    MAX(CASE WHEN r.rk = 2 THEN r.receita END) / NULLIF(t.receita_total, 0) AS share_top2,
    MAX(CASE WHEN r.rk = 3 THEN r.receita END) / NULLIF(t.receita_total, 0) AS share_top3
FROM ranked r
JOIN tot t ON t.seller_id = r.seller_id
GROUP BY r.seller_id, t.receita_total;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — componentes do share (receita por categoria, total e fração) p/ rk<=3 -----------------------
-- share_topk = receita(topk)/receita_total; NULLIF protege receita_total 0.
WITH cat_rev AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name,'sem_categoria') AS categoria,
        SUM(oi.price)               AS receita,
        COUNT(DISTINCT oi.order_id) AS pedidos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
    GROUP BY oi.seller_id, COALESCE(p.product_category_name,'sem_categoria')
),
r AS (
    SELECT seller_id, categoria, receita,
           ROW_NUMBER() OVER (PARTITION BY seller_id
                              ORDER BY receita DESC, pedidos DESC, categoria ASC) AS rk,
           SUM(receita) OVER (PARTITION BY seller_id) AS receita_total
    FROM cat_rev
)
SELECT seller_id, rk, categoria, receita, receita_total,
       receita / NULLIF(receita_total, 0) AS share
FROM r
WHERE rk <= 3
ORDER BY seller_id, rk
LIMIT 50;

-- ----------------------- Prova B — distribuição do nº de categorias (explica share_top2/top3 NULL p/ <k categorias) -----------------------
WITH cat_por_seller AS (
    SELECT oi.seller_id,
           COUNT(DISTINCT COALESCE(p.product_category_name,'sem_categoria')) AS n_categorias
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
    GROUP BY oi.seller_id
)
SELECT n_categorias, COUNT(*) AS qtd_sellers
FROM cat_por_seller
GROUP BY n_categorias
ORDER BY n_categorias;
