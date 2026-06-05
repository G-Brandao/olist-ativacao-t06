-- =====================================================================
-- vlContagemCategoriaConcorrentes  (variaveis.md §2) — Concorrência indireta
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlContagemCategoriaConcorrentes{D28,D56,D365,Vida}
-- Definição: para o seller A, nº de OUTROS sellers (B<>A) que venderam em
--            categoria em comum com A na mesma janela (substitutos).
-- Grão     : entidade = SELLER A; COUNT(DISTINCT concorrente) impede contar
--            B duas vezes quando ele divide várias categorias com A.
-- Data     : order_purchase_timestamp < :data_corte.
-- Premissas: sem filtro de status; categoria NULL -> 'sem_categoria';
--            janela sem venda -> 0.
-- Modelagem: dois papéis nomeados (minhas_cat x roster) no lugar de self-join.
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders       o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
-- pares (seller, categoria) com a janela mais curta em que aparecem (MAX flags).
minhas_cat AS (
    SELECT seller_id, categoria,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN 1 ELSE 0 END) AS in_d28,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN 1 ELSE 0 END) AS in_d56,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN 1 ELSE 0 END) AS in_d365
    FROM vendas
    GROUP BY seller_id, categoria
),
-- cruza A com B (mesma tabela como roster) na MESMA categoria, ambos ativos, B<>A.
concorrentes AS (
    SELECT
        a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS q_d28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS q_d56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS q_d365,
        COUNT(DISTINCT b.seller_id)                                                    AS q_vida
    FROM minhas_cat a
    JOIN minhas_cat b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT
    s.seller_id,
    COALESCE(c.q_d28,  0) AS vlContagemCategoriaConcorrentesD28,
    COALESCE(c.q_d56,  0) AS vlContagemCategoriaConcorrentesD56,
    COALESCE(c.q_d365, 0) AS vlContagemCategoriaConcorrentesD365,
    COALESCE(c.q_vida, 0) AS vlContagemCategoriaConcorrentesVida
FROM spine s
LEFT JOIN concorrentes c ON c.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (o widget alimenta o :data_corte).
-- =============================================================================================

-- ----------------------- Prova A — por que COUNT(DISTINCT concorrente): pares que dividem >1 categoria (Vida) -----------------------
WITH minhas_categorias AS (
    SELECT DISTINCT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT a.seller_id AS seller_a, b.seller_id AS concorrente_b,
       COUNT(*) AS categorias_em_comum
FROM minhas_categorias a
JOIN minhas_categorias b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
GROUP BY a.seller_id, b.seller_id
HAVING COUNT(*) > 1
ORDER BY categorias_em_comum DESC
LIMIT 20;

-- ----------------------- Prova B — categorias com um único seller geram 0 concorrentes (-> spine + COALESCE) -----------------------
WITH minhas_categorias AS (
    SELECT DISTINCT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT categoria, COUNT(DISTINCT seller_id) AS sellers_na_categoria
FROM minhas_categorias
GROUP BY categoria
HAVING COUNT(DISTINCT seller_id) = 1
ORDER BY categoria
LIMIT 20;
