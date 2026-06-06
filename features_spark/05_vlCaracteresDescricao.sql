-- =====================================================================
-- vlCaracteresDescricao  (variaveis.md §7) — Atributo de cadastro (estático)
-- Janela: Vida (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas  : vlMediaCaracteresDescricao, vlMedianaCaracteresDescricao,
--            vl25CaracteresDescricao, vl75CaracteresDescricao,
--            vlMinCaracteresDescricao, vlMaxCaracteresDescricao.
-- ---------------------------------------------------------------------
-- GRÃO: descrição é atributo do PRODUTO (cadastro). Entidade = PRODUTO ->
--   PRODUTOS DISTINTOS por seller (DISTINCT product_id), p/ o mesmo SKU
--   vendido várias vezes não enviesar. (variaveis.md: o percentil 50 NÃO é
--   coluna própria — equivale à Mediana; por isso não há vl50.)
-- Data     : order_purchase_timestamp < data_corte.
-- NULOS (decisão do cliente): descrição NULL conta como ZERO caractere
--   (COALESCE(L,0)), NÃO é ignorada. O produto sem descrição permanece na
--   base e puxa a média/mínimo para baixo (sinal de catálogo mal cadastrado).
-- Nota     : percentile() do Spark = percentil contínuo tipo-7.
-- Parâmetro: variável de sessão 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, COALESCE(p.product_description_lenght, 0) AS L
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
produtos AS (   -- PRODUTOS DISTINTOS (cada SKU pesa 1); TODOS entram (0 = sem descrição)
    SELECT DISTINCT seller_id, product_id, L
    FROM vendas
),
agg AS (
    SELECT
        seller_id,
        AVG(L)              AS vlMediaCaracteresDescricao,
        percentile(L, 0.50) AS vlMedianaCaracteresDescricao,
        percentile(L, 0.25) AS vl25CaracteresDescricao,
        percentile(L, 0.75) AS vl75CaracteresDescricao,
        MIN(L)              AS vlMinCaracteresDescricao,
        MAX(L)              AS vlMaxCaracteresDescricao
    FROM produtos
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT
    s.seller_id,
    agg.vlMediaCaracteresDescricao,
    agg.vlMedianaCaracteresDescricao,
    agg.vl25CaracteresDescricao,
    agg.vl75CaracteresDescricao,
    agg.vlMinCaracteresDescricao,
    agg.vlMaxCaracteresDescricao
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (a variável de sessão alimenta o data_corte).
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT produto: SKU vendido N vezes NÃO infla a estatística -----------------------
SELECT oi.seller_id, oi.product_id,
       p.product_description_lenght AS descricao_chars,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < data_corte
GROUP BY oi.seller_id, oi.product_id, p.product_description_lenght
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova B — descrição NULL conta como 0 (decisão do cliente): quantos produtos viram 0? -----------------------
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_description_lenght AS L
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
)
SELECT COUNT(*) AS produtos_distintos_vendidos,
       SUM(CASE WHEN L IS NULL THEN 1 ELSE 0 END) AS produtos_que_viram_zero
FROM produtos_distintos;

-- ----------------------- Prova C — efeito do COALESCE na média: ignorar-NULL vs NULL=0 -----------------------
WITH produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_description_lenght AS L
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders o ON o.order_id = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
)
SELECT seller_id,
       AVG(L)              AS media_ignorando_null,
       AVG(COALESCE(L, 0)) AS media_null_zero,
       SUM(CASE WHEN L IS NULL THEN 1 ELSE 0 END) AS produtos_sem_descricao
FROM produtos
GROUP BY seller_id
HAVING produtos_sem_descricao > 0
ORDER BY produtos_sem_descricao DESC
LIMIT 20;
