-- =====================================================================
-- vlMediaFotosProduto  (variaveis.md §7) — Atributo de cadastro (estático)
-- Janela: Vida (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Coluna   : vlMediaFotosProduto
-- Definição: média de product_photos_qty por produto do seller.
-- GRÃO     : nº de fotos é atributo do PRODUTO. Entidade = PRODUTO ->
--   PRODUTOS DISTINTOS por seller (DISTINCT product_id); SKU repetido pesa 1.
-- Data     : order_purchase_timestamp < data_corte.
-- NULOS (decisão do cliente): fotos NULL conta como ZERO (COALESCE(fotos,0)),
--   NÃO é ignorada. Não há foto=0 "natural" (mínimo real = 1); produto sem
--   foto permanece na base e puxa a média/mínimo para baixo (catálogo fraco).
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, COALESCE(p.product_photos_qty, 0) AS fotos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
produtos AS (   -- PRODUTOS DISTINTOS por seller (cada SKU pesa 1); TODOS entram (0 = sem foto)
    SELECT DISTINCT seller_id, product_id, fotos
    FROM vendas
),
agg AS (
    SELECT seller_id, AVG(fotos) AS vlMediaFotosProduto
    FROM produtos
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT s.seller_id, agg.vlMediaFotosProduto
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT produto: SKU vendido N vezes pesa 1 na média -----------------------
SELECT oi.seller_id, oi.product_id,
       p.product_photos_qty AS fotos,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id, oi.product_id, p.product_photos_qty
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — fotos NULL conta como 0 (decisão do cliente): não há 0 "natural"; quantos viram 0? -----------------------
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_photos_qty AS fotos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
)
SELECT COUNT(*) AS produtos_distintos_vendidos,
       SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS produtos_que_viram_zero,
       MIN(fotos) AS min_fotos_real
FROM produtos_distintos;

-- ----------------------- Prova C — efeito do COALESCE na média: ignorar-NULL vs NULL=0 -----------------------
WITH produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_photos_qty AS fotos
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
)
SELECT seller_id,
       AVG(fotos)              AS media_ignorando_null,
       AVG(COALESCE(fotos, 0)) AS media_null_zero,
       SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS produtos_sem_foto
FROM produtos
GROUP BY seller_id
HAVING produtos_sem_foto > 0
ORDER BY produtos_sem_foto DESC
LIMIT 20;
