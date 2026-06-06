-- =====================================================================
-- descTopCategoria{1,2,3}  (variaveis.md §6) — Top 3 categorias do seller
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : descTopCategoria{1,2,3}{D14,D28,D56,D365,Vida}  (15 colunas)
-- Definição: nome da 1ª/2ª/3ª categoria MAIS VENDIDA do seller na janela.
-- CRITÉRIO  : ranking por QUANTIDADE VENDIDA = nº de itens (linhas) na
--   categoria. Desempate: unidades DESC -> pedidos distintos DESC ->
--   categoria ASC. ROW_NUMBER (não RANK) garante 1 categoria por posição.
-- Data     : order_purchase_timestamp < data_corte.
-- Nulos    : categoria NULL -> 'sem_categoria'; posição inexistente -> NULL.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (
    SELECT oi.seller_id,
           COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
           oi.order_id,
           o.order_purchase_timestamp                         AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders       o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
cat_base AS (   -- por (seller, categoria): unidades e pedidos distintos por janela
    SELECT seller_id, categoria,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN 1 ELSE 0 END)        AS u_d14,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN order_id END) AS p_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN 1 ELSE 0 END)        AS u_d28,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN order_id END) AS p_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN 1 ELSE 0 END)        AS u_d56,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN order_id END) AS p_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN 1 ELSE 0 END)        AS u_d365,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN order_id END) AS p_d365,
        COUNT(*)                                                                                       AS u_vida,
        COUNT(DISTINCT order_id)                                                                       AS p_vida
    FROM vendas
    GROUP BY seller_id, categoria
),
rk AS (
    SELECT seller_id, categoria, u_d14, u_d28, u_d56, u_d365, u_vida,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d14  DESC, p_d14  DESC, categoria ASC) AS rk_d14,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d28  DESC, p_d28  DESC, categoria ASC) AS rk_d28,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d56  DESC, p_d56  DESC, categoria ASC) AS rk_d56,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d365 DESC, p_d365 DESC, categoria ASC) AS rk_d365,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_vida DESC, p_vida DESC, categoria ASC) AS rk_vida
    FROM cat_base
)
SELECT
    seller_id,
    MAX(CASE WHEN rk_d14 =1 AND u_d14 >0 THEN categoria END) AS descTopCategoria1D14,
    MAX(CASE WHEN rk_d28 =1 AND u_d28 >0 THEN categoria END) AS descTopCategoria1D28,
    MAX(CASE WHEN rk_d56 =1 AND u_d56 >0 THEN categoria END) AS descTopCategoria1D56,
    MAX(CASE WHEN rk_d365=1 AND u_d365>0 THEN categoria END) AS descTopCategoria1D365,
    MAX(CASE WHEN rk_vida=1 AND u_vida>0 THEN categoria END) AS descTopCategoria1Vida,
    MAX(CASE WHEN rk_d14 =2 AND u_d14 >0 THEN categoria END) AS descTopCategoria2D14,
    MAX(CASE WHEN rk_d28 =2 AND u_d28 >0 THEN categoria END) AS descTopCategoria2D28,
    MAX(CASE WHEN rk_d56 =2 AND u_d56 >0 THEN categoria END) AS descTopCategoria2D56,
    MAX(CASE WHEN rk_d365=2 AND u_d365>0 THEN categoria END) AS descTopCategoria2D365,
    MAX(CASE WHEN rk_vida=2 AND u_vida>0 THEN categoria END) AS descTopCategoria2Vida,
    MAX(CASE WHEN rk_d14 =3 AND u_d14 >0 THEN categoria END) AS descTopCategoria3D14,
    MAX(CASE WHEN rk_d28 =3 AND u_d28 >0 THEN categoria END) AS descTopCategoria3D28,
    MAX(CASE WHEN rk_d56 =3 AND u_d56 >0 THEN categoria END) AS descTopCategoria3D56,
    MAX(CASE WHEN rk_d365=3 AND u_d365>0 THEN categoria END) AS descTopCategoria3D365,
    MAX(CASE WHEN rk_vida=3 AND u_vida>0 THEN categoria END) AS descTopCategoria3Vida
FROM rk
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — ranking COMPLETO por unidades (Vida), com desempate -----------------------
WITH vendas AS (
    SELECT oi.seller_id, COALESCE(p.product_category_name,'sem_categoria') AS categoria, oi.order_id
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
cat AS (
    SELECT seller_id, categoria, COUNT(*) AS unidades, COUNT(DISTINCT order_id) AS pedidos
    FROM vendas GROUP BY seller_id, categoria
)
SELECT seller_id, categoria, unidades, pedidos,
       ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY unidades DESC, pedidos DESC, categoria ASC) AS rk
FROM cat
ORDER BY seller_id, rk
LIMIT 50;

-- ----------------------- Prova B — distribuição do nº de categorias por seller (<3 -> top2/top3 NULL) -----------------------
WITH cat_por_seller AS (
    SELECT oi.seller_id,
           COUNT(DISTINCT COALESCE(p.product_category_name,'sem_categoria')) AS n_categorias
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
    GROUP BY oi.seller_id
)
SELECT n_categorias, COUNT(*) AS qtd_sellers
FROM cat_por_seller
GROUP BY n_categorias
ORDER BY n_categorias;
