-- =====================================================================
-- Feature 01 (variaveis.md item 1) — Quantidade de categorias distintas
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Definição : nº de categorias distintas (product_category_name) de
--             produtos VENDIDOS pelo seller em cada janela.
-- Data venda: order_purchase_timestamp (corte estrito < :data_corte).
-- Premissas : sem filtro de order_status; categoria NULL -> 'sem_categoria'.
-- Parâmetro : widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders      o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS
                        THEN categoria END) AS qtd_categorias_distintas_d28,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS
                        THEN categoria END) AS qtd_categorias_distintas_d56,
    COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS
                        THEN categoria END) AS qtd_categorias_distintas_d365,
    COUNT(DISTINCT categoria)               AS qtd_categorias_distintas_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — existe categoria NULL? (justifica o COALESCE) -----------------------
-- Esperado: produtos_sem_categoria > 0 (no dataset há ~610 produtos sem categoria).
SELECT
    COUNT(*)                                                        AS itens_vendidos,
    SUM(CASE WHEN p.product_category_name IS NULL THEN 1 ELSE 0 END) AS itens_sem_categoria,
    COUNT(DISTINCT CASE WHEN p.product_category_name IS NULL
                        THEN oi.product_id END)                     AS produtos_sem_categoria
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);

-- ----------------------- Prova B — estrutura ANTES do COUNT DISTINCT (linhas não agrupadas) -----------------------
-- Veja o bucket 'sem_categoria' aparecendo no lugar de NULL.
SELECT
    oi.seller_id,
    COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
    o.order_purchase_timestamp                          AS dt_venda
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
ORDER BY oi.seller_id, categoria
LIMIT 50;

-- ----------------------- Prova C — impacto do COALESCE (sellers que ganham o bucket 'sem_categoria') -----------------------
-- COUNT(DISTINCT) ignora NULL: sem COALESCE, quem só vende sem categoria contaria 0.
SELECT
    oi.seller_id,
    COUNT(DISTINCT p.product_category_name)                           AS categorias_sem_coalesce,
    COUNT(DISTINCT COALESCE(p.product_category_name,'sem_categoria')) AS categorias_com_coalesce
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT p.product_category_name)
     < COUNT(DISTINCT COALESCE(p.product_category_name,'sem_categoria'))
ORDER BY categorias_com_coalesce DESC
LIMIT 20;
