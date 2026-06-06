-- =====================================================================
-- vlCategoriasDistintas  (variaveis.md §1) — Diversidade de catálogo
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlCategoriasDistintas{D14,D28,D56,D365,Vida}
-- Definição: nº de categorias distintas dos produtos vendidos por janela.
-- Grão     : entidade = SELLER; COUNT(DISTINCT categoria) -> repetir
--            produto/pedido não infla.
-- Data     : order_purchase_timestamp < data_corte (corte estrito).
-- Premissas: sem filtro de order_status; categoria NULL -> 'sem_categoria'.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (variável de sessão no topo do notebook):
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders       o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
)
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14
                        THEN categoria END) AS vlCategoriasDistintasD14,
    COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28
                        THEN categoria END) AS vlCategoriasDistintasD28,
    COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56
                        THEN categoria END) AS vlCategoriasDistintasD56,
    COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365
                        THEN categoria END) AS vlCategoriasDistintasD365,
    COUNT(DISTINCT categoria)               AS vlCategoriasDistintasVida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O variável de sessão 'data_corte' do topo
-- também alimenta o data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — existe categoria NULL? (justifica o COALESCE) -----------------------
SELECT
    COUNT(*)                                                        AS itens_vendidos,
    SUM(CASE WHEN p.product_category_name IS NULL THEN 1 ELSE 0 END) AS itens_sem_categoria,
    COUNT(DISTINCT CASE WHEN p.product_category_name IS NULL
                        THEN oi.product_id END)                     AS produtos_sem_categoria
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte;

-- ----------------------- Prova B — monotonia D14 <= D28 <= D56 <= D365 <= Vida (0 violações) -----------------------
WITH vendas AS (
    SELECT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria,
           o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
por_seller AS (
    SELECT seller_id,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN categoria END) AS d14,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN categoria END) AS d28,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN categoria END) AS d56,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN categoria END) AS d365,
        COUNT(DISTINCT categoria) AS vida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia
FROM por_seller
WHERE NOT (d14 <= d28 AND d28 <= d56 AND d56 <= d365 AND d365 <= vida);
