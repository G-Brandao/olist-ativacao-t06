-- =====================================================================
-- Feature 11 (variaveis.md item 11) — Preço por kg (R$/kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : preco_por_kg_{d28,d56,d365,vida}
-- Definição: receita total / massa total no período = SUM(price) / SUM(kg).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Premissas: receita = price (NÃO inclui frete — ver item 12); numerador e
--            denominador restritos aos itens com peso não-nulo (mesma base);
--            denominador 0/NULL -> NULL (NULLIF). price é por unidade (grão
--            da fato), então SUM(price) = receita total.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.price                    AS price,
        p.product_weight_g          AS w,
        o.order_purchase_timestamp  AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- Numerador (receita R$) e denominador (massa kg) por janela, em colunas
-- separadas. Só itens com peso não-nulo entram (mesma base no num e no den).
componentes AS (
    SELECT
        seller_id,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-28 days')  THEN price END)        AS receita_d28,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-28 days')  THEN w END) / 1000.0   AS kg_d28,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-56 days')  THEN price END)        AS receita_d56,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-56 days')  THEN w END) / 1000.0   AS kg_d56,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-365 days') THEN price END)        AS receita_d365,
        SUM(CASE WHEN w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-365 days') THEN w END) / 1000.0   AS kg_d365,
        SUM(CASE WHEN w IS NOT NULL THEN price END)                                                              AS receita_vida,
        SUM(CASE WHEN w IS NOT NULL THEN w END) / 1000.0                                                         AS kg_vida
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
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — itens com peso NULL saem do NUMERADOR e do DENOMINADOR (base consistente) -----------------------
-- Sellers onde receita_todos != receita_com_peso são os afetados pela exclusão.
SELECT
    oi.seller_id,
    SUM(oi.price)                                                  AS receita_todos_itens,
    SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END) AS receita_itens_com_peso
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
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
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id
ORDER BY preco_por_kg_rs DESC
LIMIT 20;
