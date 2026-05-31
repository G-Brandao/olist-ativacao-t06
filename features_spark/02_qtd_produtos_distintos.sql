-- =====================================================================
-- Feature 02 (variaveis.md item 2) — Quantidade de produtos distintos
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Definição : nº de product_id distintos VENDIDOS pelo seller na janela.
-- Data venda: order_purchase_timestamp (corte estrito < :data_corte).
-- Premissas : sem filtro de order_status; "produto" = SKU (product_id).
-- Parâmetro : widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders      o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS
                        THEN product_id END) AS qtd_produtos_distintos_d28,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS
                        THEN product_id END) AS qtd_produtos_distintos_d56,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS
                        THEN product_id END) AS qtd_produtos_distintos_d365,
    COUNT(DISTINCT product_id)               AS qtd_produtos_distintos_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — product_id é sempre presente? (por isso não há COALESCE/LEFT JOIN aqui) -----------------------
-- Esperado: itens_sem_product_id = 0.
SELECT
    COUNT(*)                                               AS itens_vendidos,
    SUM(CASE WHEN oi.product_id IS NULL THEN 1 ELSE 0 END) AS itens_sem_product_id
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);

-- ----------------------- Prova B — mesmo SKU vendido várias vezes (o DISTINCT colapsa unidades em produtos) -----------------------
-- Cada linha são N vendas do mesmo product_id que viram 1 no COUNT(DISTINCT).
SELECT oi.seller_id, oi.product_id, COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;
