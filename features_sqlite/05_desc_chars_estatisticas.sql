-- =====================================================================
-- Feature 05 (variaveis.md item 5) — Estatísticas de caracteres da descrição
-- Janela: Vida (sem '*')           |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : desc_chars_media, desc_chars_p25, desc_chars_mediana (p50),
--            desc_chars_p75, desc_chars_min, desc_chars_max.
-- Definição: estatísticas de product_description_lenght sobre os PRODUTOS
--            DISTINTOS vendidos pelo seller (cada produto pesa 1 — é
--            propriedade de cadastro, ver premissa 3.6).
-- Data     : order_purchase_timestamp < {data_corte}.
-- ---------------------------------------------------------------------
-- Percentil: SQLite não tem percentile(); calculamos o percentil
--            CONTÍNUO tipo-7 (interpolação linear, idêntico ao
--            percentile() do Spark): idx = (n-1)*p; valor = v[floor(idx)]
--            + frac*(v[floor(idx)+1] - v[floor(idx)]).
-- Nulos    : descrição NULL é ignorada; seller sem produto com descrição
--            -> todas as colunas NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (   -- todas as vendas Vida do seller (define o universo/spine)
    SELECT
        oi.seller_id,
        oi.product_id,
        p.product_description_lenght AS L
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
prod AS (   -- produtos DISTINTOS com descrição (cada produto pesa 1)
    SELECT DISTINCT seller_id, product_id, L
    FROM vendas
    WHERE L IS NOT NULL
),
ranked AS (
    SELECT
        seller_id, L,
        CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY L) AS INTEGER) - 1 AS rn0,
        COUNT(*) OVER (PARTITION BY seller_id) AS n
    FROM prod
),
agg AS (
    SELECT
        seller_id, n,
        AVG(L) AS media, MIN(L) AS mn, MAX(L) AS mx,
        -- p25
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER)     THEN L END) AS p25_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER) + 1 THEN L END) AS p25_hi,
        (n-1)*0.25 - CAST((n-1)*0.25 AS INTEGER)                        AS p25_f,
        -- p50 (mediana)
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER)     THEN L END) AS p50_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER) + 1 THEN L END) AS p50_hi,
        (n-1)*0.50 - CAST((n-1)*0.50 AS INTEGER)                        AS p50_f,
        -- p75
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER)     THEN L END) AS p75_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER) + 1 THEN L END) AS p75_hi,
        (n-1)*0.75 - CAST((n-1)*0.75 AS INTEGER)                        AS p75_f
    FROM ranked
    GROUP BY seller_id, n
),
spine AS (SELECT DISTINCT seller_id FROM vendas)
SELECT
    s.seller_id,
    agg.media                                                              AS desc_chars_media,
    CASE WHEN agg.p25_hi IS NULL THEN agg.p25_lo ELSE agg.p25_lo + agg.p25_f*(agg.p25_hi-agg.p25_lo) END AS desc_chars_p25,
    CASE WHEN agg.p50_hi IS NULL THEN agg.p50_lo ELSE agg.p50_lo + agg.p50_f*(agg.p50_hi-agg.p50_lo) END AS desc_chars_mediana,
    CASE WHEN agg.p75_hi IS NULL THEN agg.p75_lo ELSE agg.p75_lo + agg.p75_f*(agg.p75_hi-agg.p75_lo) END AS desc_chars_p75,
    agg.mn                                                                 AS desc_chars_min,
    agg.mx                                                                 AS desc_chars_max
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — há descrição NULL entre os produtos distintos vendidos? (WHERE L IS NOT NULL) -----------------------
-- Esperado: produtos_sem_descricao > 0.
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_description_lenght AS L
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
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
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id, p.product_description_lenght
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — base ORDENADA do percentil: produtos distintos + L por seller -----------------------
-- É a lista sobre a qual média/p25/mediana/p75 são calculadas.
SELECT DISTINCT oi.seller_id, oi.product_id,
       p.product_description_lenght AS descricao_chars
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
  AND p.product_description_lenght IS NOT NULL
ORDER BY oi.seller_id, descricao_chars
LIMIT 50;
