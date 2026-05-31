-- =====================================================================
-- Feature 06 (variaveis.md item 6) — Peso médio e mediana dos produtos
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : peso_medio_g_{d28,d56,d365,vida}, peso_mediana_g_{...}
-- Definição: média e mediana de product_weight_g das UNIDADES vendidas na
--            janela (ponderado por venda — sem DISTINCT).
-- Data     : order_purchase_timestamp < :data_corte.
-- Nota     : percentile(x,0.5) é a mediana exata (interpolada, tipo-7) e
--            ignora NULL — por isso a mediana por janela é só
--            percentile(CASE WHEN <janela> THEN w END, 0.5). Janela sem
--            venda -> AVG/percentile retornam NULL.
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
    AVG(       CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END)       AS peso_medio_g_d28,
    percentile(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END, 0.5)  AS peso_mediana_g_d28,
    AVG(       CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END)       AS peso_medio_g_d56,
    percentile(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END, 0.5)  AS peso_mediana_g_d56,
    AVG(       CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END)       AS peso_medio_g_d365,
    percentile(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END, 0.5)  AS peso_mediana_g_d365,
    AVG(w)             AS peso_medio_g_vida,
    percentile(w, 0.5) AS peso_mediana_g_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — há peso NULL? (ignorado no AVG/mediana) -----------------------
-- Esperado: produtos_sem_peso = 2.
SELECT
    COUNT(*)                                                   AS itens_vendidos,
    SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso,
    COUNT(DISTINCT CASE WHEN p.product_weight_g IS NULL
                        THEN oi.product_id END)                AS produtos_sem_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);

-- ----------------------- Prova B — ponderado por UNIDADE (sem DISTINCT): o mesmo SKU entra N vezes -----------------------
-- Oposto de 05/10: peso é atributo da venda, não do cadastro -> conta cada unidade.
SELECT oi.seller_id, oi.product_id,
       p.product_weight_g AS peso_g,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id, p.product_weight_g
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — base não agrupada do AVG/mediana (seller, peso, dt_venda) -----------------------
SELECT oi.seller_id, p.product_weight_g AS peso_g,
       o.order_purchase_timestamp AS dt_venda
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
ORDER BY oi.seller_id, peso_g
LIMIT 50;
