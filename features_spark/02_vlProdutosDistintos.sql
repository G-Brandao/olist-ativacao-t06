-- =====================================================================
-- vlProdutosDistintos  (variaveis.md §1) — Diversidade de catálogo
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlProdutosDistintos{D28,D56,D365,Vida}
-- Definição: nº de product_id (SKU) distintos vendidos por janela.
-- Grão     : entidade = SELLER; COUNT(DISTINCT product_id) dedup o SKU.
-- Data     : order_purchase_timestamp < :data_corte.
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS
                        THEN product_id END) AS vlProdutosDistintosD28,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS
                        THEN product_id END) AS vlProdutosDistintosD56,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS
                        THEN product_id END) AS vlProdutosDistintosD365,
    COUNT(DISTINCT product_id)               AS vlProdutosDistintosVida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (o widget alimenta o :data_corte).
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT importa: SKU vendido em vários pedidos conta 1 -----------------------
SELECT oi.seller_id, oi.product_id, COUNT(*) AS vezes_vendido
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id
HAVING COUNT(*) > 1
ORDER BY vezes_vendido DESC
LIMIT 20;

-- ----------------------- Prova B — monotonia D28 <= D56 <= D365 <= Vida (0 violações) -----------------------
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
por_seller AS (
    SELECT seller_id,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN product_id END) AS d28,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN product_id END) AS d56,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN product_id END) AS d365,
        COUNT(DISTINCT product_id) AS vida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia
FROM por_seller
WHERE NOT (d28 <= d56 AND d56 <= d365 AND d365 <= vida);
