-- =====================================================================
-- Feature 07 (variaveis.md item 7) — Peso total dos produtos (kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : peso_total_kg_{d28,d56,d365,vida}
-- Definição: massa total (kg) de TODAS as unidades vendidas na janela.
-- Data     : order_purchase_timestamp < {data_corte}.
-- Premissas: 1 linha de order_items = 1 unidade -> SUM já é ponderado;
--            convertido g->kg (/1000); pesos NULL não contribuem; janela
--            sem venda -> NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        p.product_weight_g          AS w,
        o.order_purchase_timestamp  AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT
    seller_id,
    SUM(CASE WHEN dt_venda >= datetime('{data_corte}', '-28 days')  THEN w END) / 1000.0 AS peso_total_kg_d28,
    SUM(CASE WHEN dt_venda >= datetime('{data_corte}', '-56 days')  THEN w END) / 1000.0 AS peso_total_kg_d56,
    SUM(CASE WHEN dt_venda >= datetime('{data_corte}', '-365 days') THEN w END) / 1000.0 AS peso_total_kg_d365,
    SUM(w) / 1000.0                                                                       AS peso_total_kg_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — peso NULL não contribui no SUM -----------------------
-- Esperado: itens_sem_peso > 0 (são 2 produtos sem peso).
SELECT
    COUNT(*)                                                   AS itens_vendidos,
    SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';

-- ----------------------- Prova B — SUM por unidade e conversão g->kg por seller -----------------------
-- Confere o /1000 e que a soma é ponderada por unidade vendida.
SELECT oi.seller_id,
       COUNT(*)                       AS unidades,
       SUM(p.product_weight_g)        AS peso_total_g,
       SUM(p.product_weight_g)/1000.0 AS peso_total_kg
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id
ORDER BY peso_total_kg DESC
LIMIT 20;
