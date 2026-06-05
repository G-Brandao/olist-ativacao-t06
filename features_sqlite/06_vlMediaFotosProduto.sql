-- =====================================================================
-- vlMediaFotosProduto  (variaveis.md §3) — Atributo de cadastro (estático)
-- Janela: Vida (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Coluna   : vlMediaFotosProduto
-- Definição: média de product_photos_qty por produto do seller.
-- ---------------------------------------------------------------------
-- GRÃO (importante): nº de fotos é atributo do PRODUTO (cadastro). A
--   entidade é o PRODUTO, então tomamos os PRODUTOS DISTINTOS vendidos por
--   cada seller (DISTINCT product_id) — o mesmo SKU vendido várias vezes
--   pesa 1 e não enviesa a média.
-- Data     : order_purchase_timestamp < {data_corte}.
-- NULOS (decisão do cliente): fotos NULL conta como ZERO foto
--   (COALESCE(fotos,0)), NÃO é ignorada. No dataset não existe foto=0
--   "natural" (mínimo real = 1); os ~580 produtos sem foto aparecem como
--   NULL, e tratá-los como 0 mantém o produto na base e PUXA a média/mínimo
--   para baixo — "não cadastrou foto" é informação (catálogo fraco, pior
--   conversão), que ajuda a prever inativação.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens vendidos até o corte (universo de sellers).
--    COALESCE(fotos,0): produto sem foto conta como 0 (não é descartado).
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, COALESCE(p.product_photos_qty, 0) AS fotos
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) produtos: PRODUTOS DISTINTOS por seller (cada SKU pesa 1). TODOS entram.
produtos AS (
    SELECT DISTINCT seller_id, product_id, fotos
    FROM vendas
),
-- 3) média de fotos por produto distinto (0 incluído).
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
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT produto: SKU vendido N vezes pesa 1 na média -----------------------
SELECT oi.seller_id, oi.product_id,
       p.product_photos_qty AS fotos,
       COUNT(*) AS unidades_vendidas
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id, p.product_photos_qty
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — fotos NULL conta como 0 (decisão do cliente): não há 0 "natural"; quantos viram 0? -----------------------
-- min_fotos_real é o menor valor NÃO-nulo (esperado 1): confirma que o 0 só
-- existe porque criamos (NULL->0). produtos_que_viram_zero ~580 (<corte).
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_photos_qty AS fotos
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT COUNT(*) AS produtos_distintos_vendidos,
       SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS produtos_que_viram_zero,
       MIN(fotos) AS min_fotos_real
FROM produtos_distintos;

-- ----------------------- Prova C — efeito do COALESCE na média: ignorar-NULL vs NULL=0 -----------------------
WITH produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_photos_qty AS fotos
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
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
