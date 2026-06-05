-- =====================================================================
-- vlProdutosDistintos  (variaveis.md §1) — Diversidade de catálogo
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlProdutosDistintos{D28,D56,D365,Vida}
-- Definição: nº de product_id (SKU) distintos vendidos pelo seller em cada
--            janela.
-- Grão     : entidade = SELLER; contamos SKUs DISTINTOS, logo o mesmo
--            produto vendido em vários pedidos conta uma vez só.
-- Data     : order_purchase_timestamp, corte estrito < {data_corte}.
-- Premissas: "produto" = product_id; sem filtro de order_status.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: uma linha por item vendido até o corte.
WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
-- 2) Por janela, conta SKUs distintos (CASE restringe a janela; DISTINCT dedup).
SELECT
    seller_id,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-28 days')
                        THEN product_id END) AS vlProdutosDistintosD28,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-56 days')
                        THEN product_id END) AS vlProdutosDistintosD56,
    COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}', '-365 days')
                        THEN product_id END) AS vlProdutosDistintosD365,
    COUNT(DISTINCT product_id)               AS vlProdutosDistintosVida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT importa: SKU vendido em vários pedidos conta 1 -----------------------
-- Mostra SKUs com mais de uma venda (sem DISTINCT, eles inflariam a contagem).
SELECT oi.seller_id, oi.product_id, COUNT(*) AS vezes_vendido
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id
HAVING COUNT(*) > 1
ORDER BY vezes_vendido DESC
LIMIT 20;

-- ----------------------- Prova B — monotonia D28 <= D56 <= D365 <= Vida -----------------------
-- Esperado: 0 violações.
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
por_seller AS (
    SELECT seller_id,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN product_id END) AS d28,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN product_id END) AS d56,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN product_id END) AS d365,
        COUNT(DISTINCT product_id) AS vida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia
FROM por_seller
WHERE NOT (d28 <= d56 AND d56 <= d365 AND d365 <= vida);
