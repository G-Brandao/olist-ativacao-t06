-- =====================================================================
-- Feature 05 (variaveis.md item 5) — Estatísticas de caracteres da descrição
-- Janela: Vida (sem '*')           |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : desc_chars_media, desc_chars_p25, desc_chars_mediana (p50),
--            desc_chars_p75, desc_chars_min, desc_chars_max.
-- Definição: estatísticas de product_description_lenght sobre os PRODUTOS
--            DISTINTOS vendidos pelo seller (cada produto pesa 1).
-- Data     : order_purchase_timestamp < :data_corte.
-- Nota     : percentile() do Spark = percentil contínuo tipo-7 (mesma
--            lógica do cálculo manual feito no script SQLite). Sellers sem
--            produto com descrição -> stats NULL (mantidos via spine).
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
-- >>> Único ponto p/ trocar a data de corte (widget aparece no topo do notebook):
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        p.product_description_lenght AS L
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
prod AS (   -- produtos DISTINTOS com descrição
    SELECT DISTINCT seller_id, product_id, L
    FROM vendas
    WHERE L IS NOT NULL
),
agg AS (
    SELECT
        seller_id,
        AVG(L)             AS desc_chars_media,
        percentile(L, 0.25) AS desc_chars_p25,
        percentile(L, 0.50) AS desc_chars_mediana,
        percentile(L, 0.75) AS desc_chars_p75,
        MIN(L)             AS desc_chars_min,
        MAX(L)             AS desc_chars_max
    FROM prod
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)
SELECT
    s.seller_id,
    agg.desc_chars_media,
    agg.desc_chars_p25,
    agg.desc_chars_mediana,
    agg.desc_chars_p75,
    agg.desc_chars_min,
    agg.desc_chars_max
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT abaixo numa célula isolada. O widget 'data_corte' do topo
-- do notebook também alimenta o :data_corte destas queries de apoio.
-- =============================================================================================

-- ----------------------- Prova A — há descrição NULL entre os produtos distintos vendidos? (WHERE L IS NOT NULL) -----------------------
-- Esperado: produtos_sem_descricao > 0.
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_description_lenght AS L
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
)
SELECT
    COUNT(*)                                   AS produtos_distintos_vendidos,
    SUM(CASE WHEN L IS NULL THEN 1 ELSE 0 END) AS produtos_sem_descricao
FROM produtos_distintos;

-- ----------------------- Prova B — cada produto pesa 1 (DISTINCT): SKU vendido N vezes não infla a estatística -----------------------
-- Contraste com 06/07 (lá é ponderado por unidade). Aqui descrição é cadastro.
SELECT oi.seller_id, oi.product_id,
       p.product_description_lenght AS descricao_chars,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id, p.product_description_lenght
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — base ORDENADA do percentil: produtos distintos + L por seller -----------------------
-- É a lista sobre a qual média/p25/mediana/p75 são calculadas.
SELECT DISTINCT oi.seller_id, oi.product_id,
       p.product_description_lenght AS descricao_chars
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
  AND p.product_description_lenght IS NOT NULL
ORDER BY oi.seller_id, descricao_chars
LIMIT 50;
