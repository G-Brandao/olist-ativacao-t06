-- =====================================================================
-- Feature 13 (variaveis.md item 13) — Top 3 categorias do vendedor
-- Janela: Vida (sem `*`)           |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : top1_categoria, top2_categoria, top3_categoria
-- Definição: as 3 categorias de maior receita (SUM(price)) até :data_corte.
-- Desempate: receita DESC, pedidos distintos DESC, categoria ASC.
-- Nulos    : categoria NULL -> 'sem_categoria'; <3 categorias -> NULL.
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
        seller_id, categoria,
        ROW_NUMBER() OVER (
            PARTITION BY seller_id
            ORDER BY receita DESC, pedidos DESC, categoria ASC
        ) AS rk
    FROM cat_rev
)
SELECT
    seller_id,
    MAX(CASE WHEN rk = 1 THEN categoria END) AS top1_categoria,
    MAX(CASE WHEN rk = 2 THEN categoria END) AS top2_categoria,
    MAX(CASE WHEN rk = 3 THEN categoria END) AS top3_categoria
FROM ranked
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — ranking COMPLETO de categorias por seller (antes do pivot top1/2/3) -----------------------
-- Mostra o ROW_NUMBER e a regra de desempate em ação.
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
)
SELECT seller_id, categoria, receita, pedidos,
       ROW_NUMBER() OVER (PARTITION BY seller_id
                          ORDER BY receita DESC, pedidos DESC, categoria ASC) AS rk
FROM cat_rev
ORDER BY seller_id, rk
LIMIT 50;

-- ----------------------- Prova B — distribuição do nº de categorias por seller (<3 -> top2/top3 NULL) -----------------------
-- Explica por que muitas posições top2/top3 vêm NULL.
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

-- ----------------------- Prova C — empates de receita no mesmo seller (onde pedidos/alfabética desempatam) -----------------------
-- Justifica o desempate determinístico (receita -> pedidos -> categoria ASC).
WITH cat_rev AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name,'sem_categoria') AS categoria,
        SUM(oi.price) AS receita
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
    GROUP BY oi.seller_id, COALESCE(p.product_category_name,'sem_categoria')
)
SELECT seller_id, receita, COUNT(*) AS categorias_empatadas
FROM cat_rev
GROUP BY seller_id, receita
HAVING COUNT(*) > 1
ORDER BY categorias_empatadas DESC
LIMIT 20;
