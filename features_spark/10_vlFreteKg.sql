-- =====================================================================
-- vlFreteKg  (variaveis.md §5) — Frete por kg (R$/kg)
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlFreteKg{D14,D28,D56,D365,Vida}
-- Definição: frete total / massa total = SUM(freight_value)/SUM(kg).
-- GRÃO     : razão de dois totais por UNIDADE (não DISTINCT). Mesma base
--   (peso não-nulo). freight_value já vem ALOCADO por item pela Olist.
--   Denominador 0/NULL -> NULL. Idêntico ao vlPrecoKg, trocando price por frete.
-- Data     : order_purchase_timestamp < data_corte.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (
    SELECT oi.seller_id, oi.freight_value AS frete,
           p.product_weight_g AS w, o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
      AND p.product_weight_g IS NOT NULL
),
componentes AS (
    SELECT seller_id,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN frete END)    AS frete_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)/1000.0  AS kg_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN frete END)    AS frete_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)/1000.0  AS kg_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN frete END)    AS frete_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)/1000.0  AS kg_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN frete END)    AS frete_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)/1000.0  AS kg_d365,
        SUM(frete)                                                                               AS frete_vida,
        SUM(w)/1000.0                                                                            AS kg_vida
    FROM vendas
    GROUP BY seller_id
),
razoes AS (
    SELECT seller_id,
        frete_d14  / NULLIF(kg_d14,  0) AS fk_d14,
        frete_d28  / NULLIF(kg_d28,  0) AS fk_d28,
        frete_d56  / NULLIF(kg_d56,  0) AS fk_d56,
        frete_d365 / NULLIF(kg_d365, 0) AS fk_d365,
        frete_vida / NULLIF(kg_vida, 0) AS fk_vida
    FROM componentes
)
-- razão frete/kg por janela. NULL -> NULL (denominador 0/NULL via NULLIF).
SELECT
    seller_id,
    fk_d14  AS vlFreteKgD14,
    fk_d28  AS vlFreteKgD28,
    fk_d56  AS vlFreteKgD56,
    fk_d365 AS vlFreteKgD365,
    fk_vida AS vlFreteKgVida
FROM razoes;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — freight_value já vem por item (não rateamos) -----------------------
SELECT oi.order_id, oi.seller_id, oi.freight_value, p.product_weight_g
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
ORDER BY oi.freight_value DESC
LIMIT 20;

-- ----------------------- Prova B — componentes da razão + NULLIF (Vida) -----------------------
SELECT oi.seller_id,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.freight_value END)         AS num_frete_rs,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0 AS den_kg,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.freight_value END)
         / NULLIF(SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0, 0) AS frete_kg
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id
ORDER BY frete_kg DESC
LIMIT 20;
