-- =====================================================================
-- Feature 09 (variaveis.md item 9) — Cubagem total dos produtos (cm³)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : cubagem_total_cm3_{d28,d56,d365,vida}
-- Definição: volume total enviado (soma das cubagens de cada unidade) na
--            janela. Pareado com peso_total descreve a "escala" do seller.
-- Data     : order_purchase_timestamp < :data_corte.
-- Premissas: cubagem = length_cm*height_cm*width_cm; dimensão NULL ->
--            cubagem NULL -> não contribui; janela sem venda -> NULL.
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub,
        o.order_purchase_timestamp                                       AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    seller_id,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN cub END) AS cubagem_total_cm3_d28,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN cub END) AS cubagem_total_cm3_d56,
    SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN cub END) AS cubagem_total_cm3_d365,
    SUM(cub)                                                                               AS cubagem_total_cm3_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — dimensão NULL não contribui no SUM (mesma checagem do item 08) -----------------------
SELECT
    COUNT(*) AS itens_vendidos,
    SUM(CASE WHEN p.product_length_cm IS NULL
              OR p.product_height_cm IS NULL
              OR p.product_width_cm  IS NULL THEN 1 ELSE 0 END) AS itens_dim_incompleta
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);

-- ----------------------- Prova B — soma das cubagens por seller (ponderada por unidade) -----------------------
-- Pareado com peso_total descreve a 'escala' logística do seller.
SELECT oi.seller_id,
       COUNT(*) AS unidades,
       SUM(p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cubagem_total_cm3
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id
ORDER BY cubagem_total_cm3 DESC
LIMIT 20;
