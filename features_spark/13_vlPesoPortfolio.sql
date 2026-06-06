-- =====================================================================
-- vlPesoPortfolio  (variaveis.md §8) — Peso do PORTFÓLIO do seller
-- Janela: estática (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas (estáticas — snapshot do catálogo, sem janela):
--   vl{Media,Mediana,25,75,Min,Max}PesoPortfolio  -> em GRAMAS
--   vlTotalPesoPortfolio                           -> em KG
-- ---------------------------------------------------------------------
-- ENTIDADE = SKU DO CATÁLOGO (produto distinto), COM DISTINCT, FIXO. Mede o
--   PERFIL FÍSICO do catálogo VINCULADO ao seller: cada product_id entra 1×
--   (peso unitário), sem ponderar por venda e sem janela. Contrapartida estática
--   da §3 (peso vendido, por unidade, janelado) — NÃO confundir.
-- LIMITAÇÃO DE DADOS: `products` não tem seller_id. Proxy de "vinculado": SKU
--   que o seller JÁ VENDEU ≥1 vez antes do corte (via order_items). O corte
--   define QUAIS SKUs são do seller, mas NÃO há janela (peso é imutável por SKU).
-- Data     : order_purchase_timestamp < data_corte (define o universo de SKUs).
-- Nota     : percentile() do Spark = percentil contínuo tipo-7 (ignora NULL).
-- Nulos    : peso NULL ignorado (2 produtos sem peso); vlTotalPesoPortfolio em KG.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH portfolio AS (   -- SKUs DISTINTOS vendidos pelo seller (cada product_id 1x)
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_weight_g AS w
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
produtos AS (   -- só SKUs com peso entram na distribuição
    SELECT seller_id, product_id, w FROM portfolio WHERE w IS NOT NULL
),
stats AS (
    SELECT seller_id,
        AVG(w)              AS media,
        percentile(w, 0.50) AS p50,
        percentile(w, 0.25) AS p25,
        percentile(w, 0.75) AS p75,
        MIN(w)              AS mn,
        MAX(w)              AS mx,
        SUM(w)/1000.0       AS total_kg
    FROM produtos
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM portfolio)  -- spine = 1 linha por seller (grão de saída)
SELECT
    s.seller_id,
    st.media    AS vlMediaPesoPortfolio,
    st.p50      AS vlMedianaPesoPortfolio,
    st.p25      AS vl25PesoPortfolio,
    st.p75      AS vl75PesoPortfolio,
    st.mn       AS vlMinPesoPortfolio,
    st.mx       AS vlMaxPesoPortfolio,
    st.total_kg AS vlTotalPesoPortfolio
FROM spine s
LEFT JOIN stats st ON st.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — COM DISTINCT (≠ §3): um SKU vendido N vezes entra 1x -----------------------
SELECT oi.seller_id,
       COUNT(*)                      AS unidades_vendidas,
       COUNT(DISTINCT oi.product_id) AS skus_distintos_no_portfolio
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id
HAVING COUNT(*) > COUNT(DISTINCT oi.product_id)
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — peso é ESTÁTICO por product_id (justifica "sem janela") -----------------------
-- Esperado: 0 linhas (nenhum product_id com >1 valor de peso).
SELECT oi.product_id, COUNT(DISTINCT p.product_weight_g) AS pesos_distintos
FROM workspace.olist.order_items oi
JOIN workspace.olist.products p ON p.product_id = oi.product_id
GROUP BY oi.product_id
HAVING COUNT(DISTINCT p.product_weight_g) > 1
LIMIT 20;

-- ----------------------- Prova C — §8 (SKU distinto) difere de §3 Vida (por unidade) p/ o mesmo seller -----------------------
WITH portfolio AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_weight_g AS w
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte AND p.product_weight_g IS NOT NULL
),
unidades AS (
    SELECT oi.seller_id, p.product_weight_g AS w
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte AND p.product_weight_g IS NOT NULL
),
mp AS (SELECT seller_id, AVG(w) AS media_portfolio FROM portfolio GROUP BY seller_id),
mu AS (SELECT seller_id, AVG(w) AS media_vendido    FROM unidades  GROUP BY seller_id)
SELECT mp.seller_id, mp.media_portfolio, mu.media_vendido
FROM mp JOIN mu ON mu.seller_id = mp.seller_id
WHERE ABS(mp.media_portfolio - mu.media_vendido) > 1
ORDER BY mp.seller_id
LIMIT 20;
