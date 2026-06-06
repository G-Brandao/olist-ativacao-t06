-- =====================================================================
-- vlPrecoKg  (variaveis.md §5) — Preço por kg (R$/kg)
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlPrecoKg{D14,D28,D56,D365,Vida}
-- Definição: receita total / massa total = SUM(price)/SUM(kg) por janela.
-- GRÃO     : razão de dois totais por UNIDADE (não DISTINCT). Mesma base
--   (itens com peso não-nulo) no num e no den; denominador 0/NULL -> NULL.
--   Receita = price (NÃO inclui frete — ver vlFreteKg).
-- Data     : order_purchase_timestamp < data_corte.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (   -- itens com peso não-nulo (base comum de num e den)
    SELECT oi.seller_id, oi.price AS price,
           p.product_weight_g AS w, o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
      AND p.product_weight_g IS NOT NULL
),
componentes AS (
    SELECT seller_id,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN price END)    AS receita_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)/1000.0  AS kg_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN price END)    AS receita_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)/1000.0  AS kg_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN price END)    AS receita_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)/1000.0  AS kg_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN price END)    AS receita_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)/1000.0  AS kg_d365,
        SUM(price)                                                                               AS receita_vida,
        SUM(w)/1000.0                                                                            AS kg_vida
    FROM vendas
    GROUP BY seller_id
),
razoes AS (
    SELECT seller_id,
        receita_d14  / NULLIF(kg_d14,  0) AS pk_d14,
        receita_d28  / NULLIF(kg_d28,  0) AS pk_d28,
        receita_d56  / NULLIF(kg_d56,  0) AS pk_d56,
        receita_d365 / NULLIF(kg_d365, 0) AS pk_d365,
        receita_vida / NULLIF(kg_vida, 0) AS pk_vida
    FROM componentes
)
-- razão receita/kg por janela. NULL -> NULL (denominador 0/NULL via NULLIF).
SELECT
    seller_id,
    pk_d14  AS vlPrecoKgD14,
    pk_d28  AS vlPrecoKgD28,
    pk_d56  AS vlPrecoKgD56,
    pk_d365 AS vlPrecoKgD365,
    pk_vida AS vlPrecoKgVida
FROM razoes;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — itens com peso NULL saem do NUM e do DEN (mesma base) -----------------------
SELECT oi.seller_id,
       SUM(oi.price)                                                  AS receita_todos_itens,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END) AS receita_itens_com_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id
HAVING SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) > 0
ORDER BY receita_todos_itens DESC
LIMIT 20;

-- ----------------------- Prova B — componentes da razão + NULLIF (Vida) -----------------------
SELECT oi.seller_id,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)                 AS num_receita_rs,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0 AS den_kg,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)
         / NULLIF(SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0, 0) AS preco_kg
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id
ORDER BY preco_kg DESC
LIMIT 20;
