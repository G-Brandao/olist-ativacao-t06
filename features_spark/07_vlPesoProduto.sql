-- =====================================================================
-- vlPesoProduto  (variaveis.md §3) — Peso dos PRODUTOS VENDIDOS
-- Janelas: D14, D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas (todas com as 5 janelas):
--   vl{Media,Mediana,25,75,Min,Max}PesoProduto{W}  -> em GRAMAS
--   vlTotalPesoProdutos{W}                          -> em KG (massa embarcada)
-- ---------------------------------------------------------------------
-- ENTIDADE = VENDA/UNIDADE (decisão do cliente, jun/2026): o peso é ponderado
--   por VOLUME DE VENDA — cada linha de order_items entra com o peso do seu
--   produto, SEM DISTINCT. Contrapartida da §8 (portfólio, SKU distinto, fixo).
--   A janela seleciona as unidades; percentile()/AVG/MIN/MAX/SUM agregam só as
--   da janela (o CASE devolve NULL fora dela, e essas funções ignoram NULL).
-- Data     : order_purchase_timestamp < data_corte (corte estrito).
-- Nota     : percentile() do Spark = percentil contínuo tipo-7 (ignora NULL).
-- Nulos    : peso NULL ignorado (2 produtos sem peso); janela sem venda com
--            peso -> métricas da janela NULL.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (   -- uma linha por unidade vendida (peso pode ser NULL aqui)
    SELECT oi.seller_id,
           p.product_weight_g         AS w,
           o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
-- distribuição (por UNIDADE) + total, em cada janela. O CASE restringe a janela;
-- o peso NULL é naturalmente ignorado por AVG/percentile/MIN/MAX/SUM.
stats AS (
    SELECT seller_id,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS media_d14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.50) AS p50_d14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.25) AS p25_d14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.75) AS p75_d14,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS mn_d14,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS mx_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)/1000.0        AS tot_d14,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS media_d28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.50) AS p50_d28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.25) AS p25_d28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.75) AS p75_d28,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS mn_d28,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS mx_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)/1000.0        AS tot_d28,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS media_d56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.50) AS p50_d56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.25) AS p25_d56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.75) AS p75_d56,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS mn_d56,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS mx_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)/1000.0        AS tot_d56,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS media_d365,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.50) AS p50_d365,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.25) AS p25_d365,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.75) AS p75_d365,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS mn_d365,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS mx_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)/1000.0        AS tot_d365,
        AVG(w)              AS media_vida,
        percentile(w, 0.50) AS p50_vida,
        percentile(w, 0.25) AS p25_vida,
        percentile(w, 0.75) AS p75_vida,
        MIN(w)              AS mn_vida,
        MAX(w)              AS mx_vida,
        SUM(w)/1000.0       AS tot_vida
    FROM vendas
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = 1 linha por seller (grão de saída)
SELECT
    s.seller_id,
    st.media_d14 AS vlMediaPesoProdutoD14, st.media_d28 AS vlMediaPesoProdutoD28, st.media_d56 AS vlMediaPesoProdutoD56, st.media_d365 AS vlMediaPesoProdutoD365, st.media_vida AS vlMediaPesoProdutoVida,
    st.p50_d14 AS vlMedianaPesoProdutoD14, st.p50_d28 AS vlMedianaPesoProdutoD28, st.p50_d56 AS vlMedianaPesoProdutoD56, st.p50_d365 AS vlMedianaPesoProdutoD365, st.p50_vida AS vlMedianaPesoProdutoVida,
    st.p25_d14 AS vl25PesoProdutoD14, st.p25_d28 AS vl25PesoProdutoD28, st.p25_d56 AS vl25PesoProdutoD56, st.p25_d365 AS vl25PesoProdutoD365, st.p25_vida AS vl25PesoProdutoVida,
    st.p75_d14 AS vl75PesoProdutoD14, st.p75_d28 AS vl75PesoProdutoD28, st.p75_d56 AS vl75PesoProdutoD56, st.p75_d365 AS vl75PesoProdutoD365, st.p75_vida AS vl75PesoProdutoVida,
    st.mn_d14 AS vlMinPesoProdutoD14, st.mn_d28 AS vlMinPesoProdutoD28, st.mn_d56 AS vlMinPesoProdutoD56, st.mn_d365 AS vlMinPesoProdutoD365, st.mn_vida AS vlMinPesoProdutoVida,
    st.mx_d14 AS vlMaxPesoProdutoD14, st.mx_d28 AS vlMaxPesoProdutoD28, st.mx_d56 AS vlMaxPesoProdutoD56, st.mx_d365 AS vlMaxPesoProdutoD365, st.mx_vida AS vlMaxPesoProdutoVida,
    st.tot_d14 AS vlTotalPesoProdutosD14, st.tot_d28 AS vlTotalPesoProdutosD28, st.tot_d56 AS vlTotalPesoProdutosD56, st.tot_d365 AS vlTotalPesoProdutosD365, st.tot_vida AS vlTotalPesoProdutosVida
FROM spine s
LEFT JOIN stats st ON st.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — POR UNIDADE (sem DISTINCT): um SKU vendido N vezes entra N vezes -----------------------
-- Contrapartida da §8 (portfólio, SKU distinto): aqui o peso pondera por venda.
SELECT oi.seller_id, oi.product_id, p.product_weight_g AS peso_g,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id, oi.product_id, p.product_weight_g
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — monotonia do TOTAL: D14 <= D28 <= D56 <= D365 <= Vida (0 violações) -----------------------
WITH vendas AS (
    SELECT oi.seller_id, p.product_weight_g AS w, o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte AND p.product_weight_g IS NOT NULL
),
tot AS (
    SELECT seller_id,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END) AS t14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END) AS t28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END) AS t56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END) AS t365,
        SUM(w) AS tvida
    FROM vendas GROUP BY seller_id
)
SELECT COUNT(*) AS violacoes_monotonia_total
FROM tot
WHERE NOT (COALESCE(t14,0) <= COALESCE(t28,0) AND COALESCE(t28,0) <= COALESCE(t56,0)
       AND COALESCE(t56,0) <= COALESCE(t365,0) AND COALESCE(t365,0) <= tvida);

-- ----------------------- Prova C — há peso NULL? (ignorado na distribuição e no total) -----------------------
SELECT COUNT(*) AS itens_vendidos,
       SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso,
       COUNT(DISTINCT CASE WHEN p.product_weight_g IS NULL THEN oi.product_id END) AS produtos_sem_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte;
