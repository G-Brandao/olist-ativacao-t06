-- =====================================================================
-- Feature 11 (variaveis.md item 11) — Preço por kg (R$/kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : preco_por_kg_{d28,d56,d365,vida}
-- Definição: receita total / massa total = SUM(price) / SUM(kg).
-- Data     : order_purchase_timestamp < :data_corte.
-- Premissas: receita = price (sem frete); num/den restritos a peso
--            não-nulo; denominador 0/NULL -> NULL (NULLIF).
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.price                    AS price,
        p.product_weight_g          AS w,
        o.order_purchase_timestamp  AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
-- Numerador (receita R$) e denominador (massa kg) por janela, em colunas
-- separadas. Só itens com peso não-nulo entram (mesma base no num e no den).
componentes AS (
    SELECT
        seller_id,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN price END)        AS receita_d28,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END) / 1000.0   AS kg_d28,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN price END)        AS receita_d56,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END) / 1000.0   AS kg_d56,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN price END)        AS receita_d365,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END) / 1000.0   AS kg_d365,
        SUM(CASE WHEN w IS NOT NULL THEN price END)                                                                   AS receita_vida,
        SUM(CASE WHEN w IS NOT NULL THEN w END) / 1000.0                                                              AS kg_vida
    FROM vendas
    GROUP BY seller_id
)
-- Razão receita/kg por janela; NULLIF protege contra denominador 0/NULL.
SELECT
    seller_id,
    receita_d28  / NULLIF(kg_d28,  0) AS preco_por_kg_d28,
    receita_d56  / NULLIF(kg_d56,  0) AS preco_por_kg_d56,
    receita_d365 / NULLIF(kg_d365, 0) AS preco_por_kg_d365,
    receita_vida / NULLIF(kg_vida, 0) AS preco_por_kg_vida
FROM componentes;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — itens com peso NULL saem do NUMERADOR e do DENOMINADOR (base consistente) -----------------------
-- Sellers onde receita_todos != receita_com_peso são os afetados pela exclusão.
SELECT
    oi.seller_id,
    SUM(oi.price)                                                  AS receita_todos_itens,
    SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END) AS receita_itens_com_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id
HAVING SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) > 0
ORDER BY receita_todos_itens DESC
LIMIT 20;

-- ----------------------- Prova B — componentes da razão + NULLIF (num R$, den kg, preço/kg) -----------------------
-- Auditar num/den lado a lado; NULLIF protege contra denominador 0.
SELECT
    oi.seller_id,
    SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)                  AS num_receita_rs,
    SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0  AS den_kg,
    SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)
      / NULLIF(SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0, 0) AS preco_por_kg_rs
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id
ORDER BY preco_por_kg_rs DESC
LIMIT 20;
