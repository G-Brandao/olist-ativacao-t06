-- =====================================================================
-- vlFreteKg  (variaveis.md §6) — Frete por kg (R$/kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlFreteKg{D28,D56,D365,Vida} (cru) + vlFreteKgAjustado{W} (log1p)
-- Definição: frete total / massa total no período = SUM(freight_value)/SUM(kg).
--   `...Ajustado` = ln(1+x) (log1p): mesma cauda assimétrica do preço/kg
--   (skew ~30+; máx ~R$17 mil/kg). Mantemos a coluna crua. (EXTRA — crítica 9.)
-- ---------------------------------------------------------------------
-- GRÃO: razão entre dois totais por UNIDADE vendida (não DISTINCT). Mesma
--   base (itens com peso não-nulo) no num e no den. freight_value já vem
--   ALOCADO por item pela Olist — não fazemos rateio. Denominador 0/NULL ->
--   NULL (NULLIF). Idêntico ao vlPrecoKg, trocando price por freight_value.
-- Data     : order_purchase_timestamp < {data_corte}.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens com peso não-nulo (base comum), por unidade.
WITH vendas AS (
    SELECT oi.seller_id,
           oi.freight_value           AS frete,
           p.product_weight_g         AS w,
           o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
      AND p.product_weight_g IS NOT NULL
),
-- 2) componentes da razão por janela: frete (R$) e massa (kg).
componentes AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN frete END)      AS frete_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN w END)/1000.0    AS kg_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN frete END)      AS frete_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN w END)/1000.0    AS kg_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN frete END)      AS frete_d365,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN w END)/1000.0    AS kg_d365,
        SUM(frete)                                                                           AS frete_vida,
        SUM(w)/1000.0                                                                        AS kg_vida
    FROM vendas
    GROUP BY seller_id
),
-- 3) razão frete/kg por janela; NULLIF protege denominador 0/NULL.
razoes AS (
    SELECT seller_id,
        frete_d28  / NULLIF(kg_d28,  0) AS fk_d28,
        frete_d56  / NULLIF(kg_d56,  0) AS fk_d56,
        frete_d365 / NULLIF(kg_d365, 0) AS fk_d365,
        frete_vida / NULLIF(kg_vida, 0) AS fk_vida
    FROM componentes
)
-- 4) coluna crua + versão Ajustado = ln(1+x) (log1p). NULL -> NULL.
SELECT
    seller_id,
    fk_d28  AS vlFreteKgD28,
    fk_d56  AS vlFreteKgD56,
    fk_d365 AS vlFreteKgD365,
    fk_vida AS vlFreteKgVida,
    ln(1 + fk_d28)  AS vlFreteKgAjustadoD28,
    ln(1 + fk_d56)  AS vlFreteKgAjustadoD56,
    ln(1 + fk_d365) AS vlFreteKgAjustadoD365,
    ln(1 + fk_vida) AS vlFreteKgAjustadoVida
FROM razoes;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — freight_value já vem por item (não rateamos) -----------------------
-- Mostra frete e peso por item: a soma é direta, sem distribuir frete de pedido.
SELECT oi.order_id, oi.seller_id, oi.freight_value, p.product_weight_g
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
ORDER BY oi.freight_value DESC
LIMIT 20;

-- ----------------------- Prova B — componentes da razão + NULLIF (Vida): num R$, den kg, R$/kg -----------------------
SELECT oi.seller_id,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.freight_value END)         AS num_frete_rs,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0 AS den_kg,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.freight_value END)
         / NULLIF(SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0, 0) AS frete_kg
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id
ORDER BY frete_kg DESC
LIMIT 20;
