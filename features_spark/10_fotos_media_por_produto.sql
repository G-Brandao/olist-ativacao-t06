-- =====================================================================
-- Feature 10 (variaveis.md item 10) — Qtd média de fotos por produto
-- Janela: Vida (sem '*')           |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Coluna   : qtd_fotos_media_por_produto
-- Definição: média de product_photos_qty entre os PRODUTOS DISTINTOS
--            vendidos pelo seller (cada produto pesa 1).
-- Data     : order_purchase_timestamp < :data_corte.
-- Nulos    : fotos NULL ignoradas; seller sem produto com fotos -> NULL
--            (mantido via spine).
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        p.product_photos_qty AS fotos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
prod AS (   -- produtos DISTINTOS do seller
    SELECT DISTINCT seller_id, product_id, fotos
    FROM vendas
),
agg AS (
    SELECT seller_id, AVG(fotos) AS qtd_fotos_media_por_produto
    FROM prod
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)
SELECT
    s.seller_id,
    agg.qtd_fotos_media_por_produto
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — há fotos NULL? (ignoradas no AVG) -----------------------
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_photos_qty AS fotos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    COUNT(*)                                      AS produtos_distintos_vendidos,
    SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS produtos_sem_fotos
FROM produtos_distintos;

-- ----------------------- Prova B — cada produto pesa 1 (DISTINCT): SKU vendido N vezes não infla a média -----------------------
-- fotos é atributo de cadastro -> dedup por produto antes da média.
SELECT oi.seller_id, oi.product_id,
       p.product_photos_qty AS fotos,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id, p.product_photos_qty
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — base do AVG: produtos distintos + fotos por seller -----------------------
SELECT DISTINCT oi.seller_id, oi.product_id, p.product_photos_qty AS fotos
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
ORDER BY oi.seller_id
LIMIT 50;
