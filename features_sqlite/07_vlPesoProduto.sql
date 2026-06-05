-- =====================================================================
-- vlPesoProduto  (variaveis.md §4) — Peso dos produtos
-- Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas:
--   DISTRIBUIÇÃO (ESTÁTICA, sem sufixo — peso é atributo do produto):
--     vl{Media,Mediana,25,50,75,Min,Max}PesoProduto   -> em GRAMAS
--   TOTAL (4 janelas D28/D56/D365/Vida — massa embarcada muda no tempo):
--     vlTotalPesoProdutos{W}                           -> em KG
-- ---------------------------------------------------------------------
-- DECISÃO DO CLIENTE (atributo de produto não varia no tempo):
--   Peso vem da tabela `products` (1 linha por product_id), é IMUTÁVEL — não
--   muda entre D28/D56/D365/Vida. Logo a DISTRIBUIÇÃO (media/mediana/percentis/
--   min/max) é ESTÁTICA: calculada UMA vez sobre os PRODUTOS DISTINTOS que o
--   seller já vendeu (toda a vida < corte). Antes havia 4 janelas redundantes
--   (mesmo atributo, só mudava quais SKUs entravam) — eliminadas, alinhando
--   com descrição/fotos (§3). (vlMediana == vl50: a mediana é o percentil 50.)
--
--   O TOTAL (vlTotalPesoProdutos) é EXCEÇÃO e MANTÉM as 4 janelas: é a MASSA
--   EMBARCADA, soma por UNIDADE vendida (cada linha de order_items), e portanto
--   CRESCE com novas vendas. Mesma lógica que justifica janelas nos R$/kg (§6).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Percentil: SQLite não tem percentile(); percentil contínuo tipo-7
--   (interpolação linear), idêntico ao percentile() do Spark.
-- Nulos    : peso NULL ignorado (2 produtos sem peso); seller sem produto com
--            peso -> distribuição NULL; janela sem venda -> total NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: uma linha por unidade vendida até o corte.
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id,
           p.product_weight_g         AS w,
           o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) TOTAL por UNIDADE (massa embarcada, g->kg), com as 4 janelas. Cada venda
--    soma uma vez — total cresce no tempo, por isso mantém D28/D56/D365/Vida.
total AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN w END)/1000.0 AS tot_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN w END)/1000.0 AS tot_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN w END)/1000.0 AS tot_d365,
        SUM(w)/1000.0                                                                      AS tot_vida
    FROM vendas
    GROUP BY seller_id
),
-- 3) PRODUTOS DISTINTOS por seller (toda a vida; peso constante por produto).
--    Base ESTÁTICA da distribuição — sem janelas, pois o peso não muda.
produtos AS (
    SELECT DISTINCT seller_id, product_id, w
    FROM vendas
    WHERE w IS NOT NULL
),
-- 4) ranqueia o peso dentro de cada seller para o percentil tipo-7.
ranked AS (
    SELECT seller_id, w,
           CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY w) AS INTEGER) - 1 AS rn0,
           COUNT(*) OVER (PARTITION BY seller_id)                                     AS n
    FROM produtos
),
-- 5) componentes do percentil (limite inferior, superior e fração) por seller.
agg AS (
    SELECT
        seller_id, n,
        AVG(w) AS media, MIN(w) AS mn, MAX(w) AS mx,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER)     THEN w END) AS p25_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER) + 1 THEN w END) AS p25_hi,
        (n-1)*0.25 - CAST((n-1)*0.25 AS INTEGER)                        AS p25_f,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER)     THEN w END) AS p50_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER) + 1 THEN w END) AS p50_hi,
        (n-1)*0.50 - CAST((n-1)*0.50 AS INTEGER)                        AS p50_f,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER)     THEN w END) AS p75_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER) + 1 THEN w END) AS p75_hi,
        (n-1)*0.75 - CAST((n-1)*0.75 AS INTEGER)                        AS p75_f
    FROM ranked
    GROUP BY seller_id, n
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
-- 6) interpola os percentis (distribuição estática) e anexa os totais (4 janelas).
SELECT
    s.seller_id,
    agg.media                                                                                          AS vlMediaPesoProduto,
    CASE WHEN agg.p50_hi IS NULL THEN agg.p50_lo ELSE agg.p50_lo + agg.p50_f*(agg.p50_hi-agg.p50_lo) END AS vlMedianaPesoProduto,
    CASE WHEN agg.p25_hi IS NULL THEN agg.p25_lo ELSE agg.p25_lo + agg.p25_f*(agg.p25_hi-agg.p25_lo) END AS vl25PesoProduto,
    CASE WHEN agg.p50_hi IS NULL THEN agg.p50_lo ELSE agg.p50_lo + agg.p50_f*(agg.p50_hi-agg.p50_lo) END AS vl50PesoProduto,
    CASE WHEN agg.p75_hi IS NULL THEN agg.p75_lo ELSE agg.p75_lo + agg.p75_f*(agg.p75_hi-agg.p75_lo) END AS vl75PesoProduto,
    agg.mn                                                                                              AS vlMinPesoProduto,
    agg.mx                                                                                              AS vlMaxPesoProduto,
    t.tot_d28  AS vlTotalPesoProdutosD28,
    t.tot_d56  AS vlTotalPesoProdutosD56,
    t.tot_d365 AS vlTotalPesoProdutosD365,
    t.tot_vida AS vlTotalPesoProdutosVida
FROM spine s
LEFT JOIN agg   ON agg.seller_id = s.seller_id
LEFT JOIN total t ON t.seller_id  = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — peso é ESTÁTICO: D28/D56/D365/Vida dariam o MESMO valor por produto -----------------------
-- O peso é o mesmo em qualquer janela; a janela só mudaria QUAIS SKUs entram,
-- não o valor de cada um. Por isso a distribuição não precisa de sufixo de período.
SELECT oi.product_id,
       COUNT(DISTINCT p.product_weight_g) AS valores_distintos_de_peso
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
GROUP BY oi.product_id
HAVING valores_distintos_de_peso > 1   -- esperado: 0 linhas (peso nunca muda por produto)
LIMIT 20;

-- ----------------------- Prova B — DISTRIBUIÇÃO usa produto distinto; TOTAL usa unidade (grãos diferentes) -----------------------
-- Para um SKU vendido N vezes: na distribuição entra 1x; no total entra N vezes.
SELECT oi.seller_id, oi.product_id, p.product_weight_g AS peso_g,
       COUNT(*) AS unidades_vendidas
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id, p.product_weight_g
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — há peso NULL? (ignorado na distribuição e no total) -----------------------
-- Esperado: produtos_sem_peso = 2.
SELECT COUNT(*) AS itens_vendidos,
       SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso,
       COUNT(DISTINCT CASE WHEN p.product_weight_g IS NULL THEN oi.product_id END) AS produtos_sem_peso
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';
