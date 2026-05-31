-- =====================================================================
-- Feature 08 (variaveis.md item 8) — Cubagem média dos produtos (cm³)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : cubagem_media_cm3_{d28,d56,d365,vida}
-- Definição: volume médio (L×H×W da caixa de envio) das UNIDADES vendidas
--            na janela (ponderado por venda).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Premissas: cubagem = length_cm*height_cm*width_cm; qualquer dimensão
--            NULL -> cubagem NULL -> ignorada no AVG; janela sem venda -> NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub,
        o.order_purchase_timestamp                                       AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT
    seller_id,
    AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-28 days')  THEN cub END) AS cubagem_media_cm3_d28,
    AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-56 days')  THEN cub END) AS cubagem_media_cm3_d56,
    AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-365 days') THEN cub END) AS cubagem_media_cm3_d365,
    AVG(cub)                                                                       AS cubagem_media_cm3_vida
FROM vendas
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — qualquer dimensão NULL zera a cubagem (vira NULL, ignorada no AVG) -----------------------
SELECT
    COUNT(*) AS itens_vendidos,
    SUM(CASE WHEN p.product_length_cm IS NULL
              OR p.product_height_cm IS NULL
              OR p.product_width_cm  IS NULL THEN 1 ELSE 0 END) AS itens_dim_incompleta
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';

-- ----------------------- Prova B — cubagem por produto (L x H x W) — base do AVG -----------------------
-- Mostra a conta e que dimensão NULL produz cubagem NULL.
SELECT DISTINCT oi.product_id,
       p.product_length_cm, p.product_height_cm, p.product_width_cm,
       (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cubagem_cm3
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
ORDER BY cubagem_cm3 DESC
LIMIT 20;
