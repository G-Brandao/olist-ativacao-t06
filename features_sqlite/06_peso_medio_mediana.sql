-- =====================================================================
-- Feature 06 (variaveis.md item 6) — Peso médio e mediana dos produtos
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : peso_medio_g_{d28,d56,d365,vida}, peso_mediana_g_{...}
-- Definição: média e mediana de product_weight_g das UNIDADES vendidas na
--            janela (ponderado por venda — sem DISTINCT, premissa 3.6).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Mediana  : SQLite não tem MEDIAN; usamos percentil contínuo tipo-7
--            (igual ao percentile(w,0.5) do Spark), ranqueado DENTRO de
--            cada janela. Pesos NULL ignorados; janela sem venda -> NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================
WITH vendas AS (
    SELECT
        oi.seller_id,
        p.product_weight_g          AS w,
        o.order_purchase_timestamp  AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
avgs AS (   -- médias por janela (emite todos os sellers)
    SELECT
        seller_id,
        AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-28 days')  THEN w END) AS peso_medio_g_d28,
        AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-56 days')  THEN w END) AS peso_medio_g_d56,
        AVG(CASE WHEN dt_venda >= datetime('{data_corte}', '-365 days') THEN w END) AS peso_medio_g_d365,
        AVG(w)                                                                       AS peso_medio_g_vida
    FROM vendas
    GROUP BY seller_id
),
-- ----- ranqueamento por janela (para a mediana) -----
r_d28  AS (SELECT seller_id, w, CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY w) AS INTEGER)-1 AS rn0, COUNT(*) OVER (PARTITION BY seller_id) AS n FROM vendas WHERE w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-28 days')),
r_d56  AS (SELECT seller_id, w, CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY w) AS INTEGER)-1 AS rn0, COUNT(*) OVER (PARTITION BY seller_id) AS n FROM vendas WHERE w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-56 days')),
r_d365 AS (SELECT seller_id, w, CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY w) AS INTEGER)-1 AS rn0, COUNT(*) OVER (PARTITION BY seller_id) AS n FROM vendas WHERE w IS NOT NULL AND dt_venda >= datetime('{data_corte}', '-365 days')),
r_vida AS (SELECT seller_id, w, CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY w) AS INTEGER)-1 AS rn0, COUNT(*) OVER (PARTITION BY seller_id) AS n FROM vendas WHERE w IS NOT NULL),
-- mediana interpolada (tipo-7) por janela
m_d28  AS (SELECT seller_id, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER) THEN w END) AS lo, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER)+1 THEN w END) AS hi, (n-1)*0.5-CAST((n-1)*0.5 AS INTEGER) AS f FROM r_d28  GROUP BY seller_id, n),
m_d56  AS (SELECT seller_id, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER) THEN w END) AS lo, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER)+1 THEN w END) AS hi, (n-1)*0.5-CAST((n-1)*0.5 AS INTEGER) AS f FROM r_d56  GROUP BY seller_id, n),
m_d365 AS (SELECT seller_id, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER) THEN w END) AS lo, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER)+1 THEN w END) AS hi, (n-1)*0.5-CAST((n-1)*0.5 AS INTEGER) AS f FROM r_d365 GROUP BY seller_id, n),
m_vida AS (SELECT seller_id, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER) THEN w END) AS lo, MAX(CASE WHEN rn0=CAST((n-1)*0.5 AS INTEGER)+1 THEN w END) AS hi, (n-1)*0.5-CAST((n-1)*0.5 AS INTEGER) AS f FROM r_vida GROUP BY seller_id, n)
SELECT
    a.seller_id,
    a.peso_medio_g_d28,
    CASE WHEN m_d28.hi  IS NULL THEN m_d28.lo  ELSE m_d28.lo  + m_d28.f *(m_d28.hi -m_d28.lo)  END AS peso_mediana_g_d28,
    a.peso_medio_g_d56,
    CASE WHEN m_d56.hi  IS NULL THEN m_d56.lo  ELSE m_d56.lo  + m_d56.f *(m_d56.hi -m_d56.lo)  END AS peso_mediana_g_d56,
    a.peso_medio_g_d365,
    CASE WHEN m_d365.hi IS NULL THEN m_d365.lo ELSE m_d365.lo + m_d365.f*(m_d365.hi-m_d365.lo) END AS peso_mediana_g_d365,
    a.peso_medio_g_vida,
    CASE WHEN m_vida.hi IS NULL THEN m_vida.lo ELSE m_vida.lo + m_vida.f*(m_vida.hi-m_vida.lo) END AS peso_mediana_g_vida
FROM avgs a
LEFT JOIN m_d28  ON m_d28.seller_id  = a.seller_id
LEFT JOIN m_d56  ON m_d56.seller_id  = a.seller_id
LEFT JOIN m_d365 ON m_d365.seller_id = a.seller_id
LEFT JOIN m_vida ON m_vida.seller_id = a.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature principal é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — há peso NULL? (ignorado no AVG/mediana) -----------------------
-- Esperado: produtos_sem_peso = 2.
SELECT
    COUNT(*)                                                   AS itens_vendidos,
    SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso,
    COUNT(DISTINCT CASE WHEN p.product_weight_g IS NULL
                        THEN oi.product_id END)                AS produtos_sem_peso
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';

-- ----------------------- Prova B — ponderado por UNIDADE (sem DISTINCT): o mesmo SKU entra N vezes -----------------------
-- Oposto de 05/10: peso é atributo da venda, não do cadastro -> conta cada unidade.
SELECT oi.seller_id, oi.product_id,
       p.product_weight_g AS peso_g,
       COUNT(*) AS unidades_vendidas
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id, p.product_weight_g
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — base não agrupada do AVG/mediana (seller, peso, dt_venda) -----------------------
SELECT oi.seller_id, p.product_weight_g AS peso_g,
       o.order_purchase_timestamp AS dt_venda
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
ORDER BY oi.seller_id, peso_g
LIMIT 50;
