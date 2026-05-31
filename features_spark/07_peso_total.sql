-- =====================================================================
-- Feature 07 (variaveis.md item 7) — Peso total dos produtos (kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : peso_total_kg_{d28,d56,d365,vida}
-- Definição: massa total (kg) de TODAS as unidades vendidas na janela.
-- Data     : order_purchase_timestamp < :data_corte.
-- Premissas: SUM ponderado por unidade; g->kg (/1000); peso NULL não
--            contribui; janela sem venda -> NULL.
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        p.product_weight_g          AS w,
        o.order_purchase_timestamp  AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    seller_id,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END) / 1000.0 AS peso_total_kg_d28,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END) / 1000.0 AS peso_total_kg_d56,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END) / 1000.0 AS peso_total_kg_d365,
    SUM(w) / 1000.0                                                                               AS peso_total_kg_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — peso NULL não contribui no SUM -----------------------
-- Esperado: itens_sem_peso > 0 (são 2 produtos sem peso).
SELECT
    COUNT(*)                                                   AS itens_vendidos,
    SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);

-- ----------------------- Prova B — SUM por unidade e conversão g->kg por seller -----------------------
-- Confere o /1000 e que a soma é ponderada por unidade vendida.
SELECT oi.seller_id,
       COUNT(*)                       AS unidades,
       SUM(p.product_weight_g)        AS peso_total_g,
       SUM(p.product_weight_g)/1000.0 AS peso_total_kg
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id
ORDER BY peso_total_kg DESC
LIMIT 20;
