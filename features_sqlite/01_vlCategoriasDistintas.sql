-- =====================================================================
-- vlCategoriasDistintas  (variaveis.md §1) — Diversidade de catálogo
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlCategoriasDistintas{D28,D56,D365,Vida}
-- Definição: nº de categorias (product_category_name) distintas dos
--            produtos VENDIDOS pelo seller em cada janela.
-- Grão     : a entidade é o SELLER; contamos categorias DISTINTAS, então
--            repetir o produto/pedido não infla o resultado.
-- Data     : order_purchase_timestamp, corte estrito < {data_corte}.
-- Premissas: sem filtro de order_status; categoria NULL -> 'sem_categoria'
--            (senão o COUNT(DISTINCT) a descartaria).
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: uma linha por item vendido até o corte (a base de tudo).
WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM order_items oi
    JOIN orders       o ON o.order_id   = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'        -- Vida (corte estrito)
)
-- 2) Por janela, conta categorias distintas. O CASE restringe a janela e o
--    DISTINCT garante que cada categoria conte uma única vez.
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-28 days')
                        THEN categoria END) AS vlCategoriasDistintasD28,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-56 days')
                        THEN categoria END) AS vlCategoriasDistintasD56,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-365 days')
                        THEN categoria END) AS vlCategoriasDistintasD365,
    COUNT(DISTINCT categoria)               AS vlCategoriasDistintasVida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — existe categoria NULL? (justifica o COALESCE) -----------------------
-- Esperado: produtos_sem_categoria > 0 (há ~610 produtos sem categoria no dataset).
SELECT
    COUNT(*)                                                        AS itens_vendidos,
    SUM(CASE WHEN p.product_category_name IS NULL THEN 1 ELSE 0 END) AS itens_sem_categoria,
    COUNT(DISTINCT CASE WHEN p.product_category_name IS NULL
                        THEN oi.product_id END)                     AS produtos_sem_categoria
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
LEFT JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';

-- ----------------------- Prova B — monotonia D28 <= D56 <= D365 <= Vida -----------------------
-- Como D28 ⊂ D56 ⊂ D365 ⊂ Vida, a contagem só pode crescer. Esperado: 0 violações.
WITH vendas AS (
    SELECT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria,
           o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
por_seller AS (
    SELECT seller_id,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN categoria END) AS d28,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN categoria END) AS d56,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN categoria END) AS d365,
        COUNT(DISTINCT categoria) AS vida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia
FROM por_seller
WHERE NOT (d28 <= d56 AND d56 <= d365 AND d365 <= vida);
