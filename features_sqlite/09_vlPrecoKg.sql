-- =====================================================================
-- vlPrecoKg  (variaveis.md §6) — Preço por kg (R$/kg)
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlPrecoKg{D28,D56,D365,Vida} (cru) + vlPrecoKgAjustado{W} (log1p)
-- Definição: receita total / massa total no período = SUM(price)/SUM(kg).
--   `...Ajustado` = ln(1+x) (log1p): produtos leves geram R$/kg enormes
--   (cauda assimétrica, skew ~30+; máx ~R$81 mil/kg); log1p comprime p/ ~0,45
--   de assimetria. Útil p/ modelos lineares/distância; mantemos a coluna crua
--   p/ modelos de árvore. (EXTRA — revisão externa, crítica 9.)
-- ---------------------------------------------------------------------
-- GRÃO: é uma RAZÃO entre dois totais da OPERAÇÃO (receita e massa). Ambos
--   são por UNIDADE vendida (não DISTINCT): cada venda gera receita e
--   embarca massa. Numerador e denominador usam a MESMA base (itens com
--   peso não-nulo), p/ o quociente ser coerente.
-- Premissas: receita = price (NÃO inclui frete — ver vlFreteKg); price é por
--   unidade (grão da fato) -> SUM(price) = receita total; denominador
--   0/NULL -> NULL (NULLIF).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens com peso não-nulo (base comum de num e den), por unidade.
WITH vendas AS (
    SELECT oi.seller_id,
           oi.price                   AS price,
           p.product_weight_g         AS w,
           o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
      AND p.product_weight_g IS NOT NULL
),
-- 2) componentes da razão por janela: receita (R$) e massa (kg) lado a lado.
componentes AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN price END)      AS receita_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN w END)/1000.0    AS kg_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN price END)      AS receita_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN w END)/1000.0    AS kg_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN price END)      AS receita_d365,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN w END)/1000.0    AS kg_d365,
        SUM(price)                                                                           AS receita_vida,
        SUM(w)/1000.0                                                                        AS kg_vida
    FROM vendas
    GROUP BY seller_id
),
-- 3) razão receita/kg por janela; NULLIF protege denominador 0/NULL.
razoes AS (
    SELECT seller_id,
        receita_d28  / NULLIF(kg_d28,  0) AS pk_d28,
        receita_d56  / NULLIF(kg_d56,  0) AS pk_d56,
        receita_d365 / NULLIF(kg_d365, 0) AS pk_d365,
        receita_vida / NULLIF(kg_vida, 0) AS pk_vida
    FROM componentes
)
-- 4) coluna crua + versão Ajustado = ln(1+x) (log1p). NULL -> NULL.
SELECT
    seller_id,
    pk_d28  AS vlPrecoKgD28,
    pk_d56  AS vlPrecoKgD56,
    pk_d365 AS vlPrecoKgD365,
    pk_vida AS vlPrecoKgVida,
    ln(1 + pk_d28)  AS vlPrecoKgAjustadoD28,
    ln(1 + pk_d56)  AS vlPrecoKgAjustadoD56,
    ln(1 + pk_d365) AS vlPrecoKgAjustadoD365,
    ln(1 + pk_vida) AS vlPrecoKgAjustadoVida
FROM razoes;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — itens com peso NULL saem do NUM e do DEN (mesma base) -----------------------
-- Sellers onde receita_todos != receita_com_peso são os afetados pela exclusão.
SELECT oi.seller_id,
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

-- ----------------------- Prova B — componentes da razão + NULLIF (Vida): num R$, den kg, R$/kg -----------------------
SELECT oi.seller_id,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)                 AS num_receita_rs,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0 AS den_kg,
       SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN oi.price END)
         / NULLIF(SUM(CASE WHEN p.product_weight_g IS NOT NULL THEN p.product_weight_g END)/1000.0, 0) AS preco_kg
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id
ORDER BY preco_kg DESC
LIMIT 20;
