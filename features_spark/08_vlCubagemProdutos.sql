-- =====================================================================
-- vlCubagemProdutos  (variaveis.md §4) — Cubagem (volume da caixa de envio)
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas (todas com as 5 janelas):
--   vlMediaCubagemProdutos{W}   -> cm³ (média por UNIDADE vendida na janela)
--   vlTotalCubagemProdutos{W}   -> cm³ (volume embarcado = soma por unidade)
-- ---------------------------------------------------------------------
-- ENTIDADE = VENDA/UNIDADE (decisão do cliente, jun/2026): igual à §3 (peso),
--   a cubagem é ponderada por VOLUME DE VENDA — cada order_items entra com a
--   cubagem do seu produto, SEM DISTINCT. Média e total janelados (dependem de
--   venda, crescem no tempo).
-- Cubagem  : product_length_cm × product_height_cm × product_width_cm; qualquer
--   dimensão NULL -> cubagem NULL (ignorada por AVG/SUM).
-- Data     : order_purchase_timestamp < data_corte.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (   -- uma linha por unidade vendida, com a cubagem do produto
    SELECT oi.seller_id,
           (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub,
           o.order_purchase_timestamp                                       AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
agg AS (
    SELECT seller_id,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN cub END) AS med_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN cub END) AS tot_d14,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN cub END) AS med_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN cub END) AS tot_d28,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN cub END) AS med_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN cub END) AS tot_d56,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN cub END) AS med_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN cub END) AS tot_d365,
        AVG(cub) AS med_vida,
        SUM(cub) AS tot_vida
    FROM vendas
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = 1 linha por seller (grão de saída)
SELECT
    s.seller_id,
    a.med_d14  AS vlMediaCubagemProdutosD14,
    a.med_d28  AS vlMediaCubagemProdutosD28,
    a.med_d56  AS vlMediaCubagemProdutosD56,
    a.med_d365 AS vlMediaCubagemProdutosD365,
    a.med_vida AS vlMediaCubagemProdutosVida,
    a.tot_d14  AS vlTotalCubagemProdutosD14,
    a.tot_d28  AS vlTotalCubagemProdutosD28,
    a.tot_d56  AS vlTotalCubagemProdutosD56,
    a.tot_d365 AS vlTotalCubagemProdutosD365,
    a.tot_vida AS vlTotalCubagemProdutosVida
FROM spine s
LEFT JOIN agg a ON a.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — POR UNIDADE: um SKU vendido N vezes entra N vezes na média/total -----------------------
SELECT oi.seller_id, oi.product_id,
       (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cubagem_cm3,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id, oi.product_id, (p.product_length_cm * p.product_height_cm * p.product_width_cm)
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — monotonia do TOTAL: D14 <= D28 <= D56 <= D365 <= Vida (0 violações) -----------------------
WITH vendas AS (
    SELECT oi.seller_id,
           (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub,
           o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
tot AS (
    SELECT seller_id,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN cub END) AS t14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN cub END) AS t28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN cub END) AS t56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN cub END) AS t365,
        SUM(cub) AS tvida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia_total
FROM tot
WHERE NOT (COALESCE(t14,0) <= COALESCE(t28,0) AND COALESCE(t28,0) <= COALESCE(t56,0)
       AND COALESCE(t56,0) <= COALESCE(t365,0) AND COALESCE(t365,0) <= tvida);

-- ----------------------- Prova C — qualquer dimensão NULL zera a cubagem (vira NULL, ignorada) -----------------------
SELECT COUNT(*) AS itens_vendidos,
       SUM(CASE WHEN p.product_length_cm IS NULL
                 OR p.product_height_cm IS NULL
                 OR p.product_width_cm  IS NULL THEN 1 ELSE 0 END) AS itens_dim_incompleta
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte;
