-- =====================================================================
-- vlCaracteresDescricao  (variaveis.md §3) — Atributo de cadastro (estático)
-- Janela: Vida (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlMediaCaracteresDescricao, vlMedianaCaracteresDescricao,
--            vl25CaracteresDescricao, vl50CaracteresDescricao,
--            vl75CaracteresDescricao, vlMinCaracteresDescricao,
--            vlMaxCaracteresDescricao.
-- Definição: estatísticas de product_description_lenght.
-- ---------------------------------------------------------------------
-- GRÃO (importante): descrição é atributo do PRODUTO (cadastro), não da
--   venda. A entidade aqui é o PRODUTO. Por isso tomamos os PRODUTOS
--   DISTINTOS vendidos por cada seller (DISTINCT product_id) — assim o
--   mesmo SKU vendido em vários pedidos NÃO entra repetido e não enviesa a
--   média/percentis. (vlMediana == vl50: a mediana é o percentil 50.)
-- Data     : order_purchase_timestamp < {data_corte}.
-- Percentil: SQLite não tem percentile(); usamos o percentil CONTÍNUO
--   tipo-7 (interpolação linear, idêntico ao percentile() do Spark):
--   idx = (n-1)*p; valor = v[floor(idx)] + frac*(v[floor(idx)+1]-v[floor(idx)]).
-- NULOS (decisão do cliente): descrição NULL é tratada como ZERO caractere,
--   NÃO ignorada. Quantitativamente é equivalente — o produto SEM descrição
--   continua na base e PUXA a média/mínimo para baixo (sinaliza catálogo mal
--   cadastrado, que ajuda a prever inativação). COALESCE(L,0). Não há valor 0
--   "natural" na base (descrição vazia aparece como NULL), então o 0 é nosso.
--   Seller sem NENHUM produto (impossível aqui, todos têm ≥1 venda) -> NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens vendidos até o corte (define o universo de sellers).
--    COALESCE(L,0): descrição ausente conta como 0 caractere (não é descartada).
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id, COALESCE(p.product_description_lenght, 0) AS L
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) produtos: PRODUTOS DISTINTOS por seller (cada SKU pesa 1). TODOS entram,
--    inclusive os de descrição 0 (antes ausente) — daí não há filtro de NULL.
produtos AS (
    SELECT DISTINCT seller_id, product_id, L
    FROM vendas
),
-- 3) ranqueia L dentro de cada seller para o percentil tipo-7.
ranked AS (
    SELECT seller_id, L,
           CAST(ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY L) AS INTEGER) - 1 AS rn0,
           COUNT(*) OVER (PARTITION BY seller_id)                                     AS n
    FROM produtos
),
-- 4) componentes do percentil (limite inferior, superior e fração) por seller.
agg AS (
    SELECT
        seller_id, n,
        AVG(L) AS media, MIN(L) AS mn, MAX(L) AS mx,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER)     THEN L END) AS p25_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.25 AS INTEGER) + 1 THEN L END) AS p25_hi,
        (n-1)*0.25 - CAST((n-1)*0.25 AS INTEGER)                        AS p25_f,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER)     THEN L END) AS p50_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.50 AS INTEGER) + 1 THEN L END) AS p50_hi,
        (n-1)*0.50 - CAST((n-1)*0.50 AS INTEGER)                        AS p50_f,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER)     THEN L END) AS p75_lo,
        MAX(CASE WHEN rn0 = CAST((n-1)*0.75 AS INTEGER) + 1 THEN L END) AS p75_hi,
        (n-1)*0.75 - CAST((n-1)*0.75 AS INTEGER)                        AS p75_f
    FROM ranked
    GROUP BY seller_id, n
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
-- 5) interpola cada percentil; vlMediana e vl50 são o mesmo valor (p50).
SELECT
    s.seller_id,
    agg.media                                                                                              AS vlMediaCaracteresDescricao,
    CASE WHEN agg.p50_hi IS NULL THEN agg.p50_lo ELSE agg.p50_lo + agg.p50_f*(agg.p50_hi-agg.p50_lo) END AS vlMedianaCaracteresDescricao,
    CASE WHEN agg.p25_hi IS NULL THEN agg.p25_lo ELSE agg.p25_lo + agg.p25_f*(agg.p25_hi-agg.p25_lo) END AS vl25CaracteresDescricao,
    CASE WHEN agg.p50_hi IS NULL THEN agg.p50_lo ELSE agg.p50_lo + agg.p50_f*(agg.p50_hi-agg.p50_lo) END AS vl50CaracteresDescricao,
    CASE WHEN agg.p75_hi IS NULL THEN agg.p75_lo ELSE agg.p75_lo + agg.p75_f*(agg.p75_hi-agg.p75_lo) END AS vl75CaracteresDescricao,
    agg.mn                                                                                                 AS vlMinCaracteresDescricao,
    agg.mx                                                                                                 AS vlMaxCaracteresDescricao
FROM spine s
LEFT JOIN agg ON agg.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — DISTINCT produto: o mesmo SKU vendido N vezes NÃO infla a estatística -----------------------
-- Lista SKUs vendidos em vários pedidos; sem o DISTINCT, a descrição deles
-- entraria N vezes na média/percentis (viés pela entidade errada — venda, não produto).
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

-- ----------------------- Prova B — descrição NULL conta como 0 (decisão do cliente): quantos produtos viram 0? -----------------------
-- Esperado: ~580 produtos distintos (<corte) sem descrição entram com L=0,
-- afetando média e mínimo (o mínimo de muitos sellers cai para 0).
WITH produtos_distintos AS (
    SELECT DISTINCT oi.product_id, p.product_description_lenght AS L
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT COUNT(*) AS produtos_distintos_vendidos,
       SUM(CASE WHEN L IS NULL THEN 1 ELSE 0 END) AS produtos_que_viram_zero
FROM produtos_distintos;

-- ----------------------- Prova C — efeito do COALESCE na média: comparação ignorar-NULL vs NULL=0 -----------------------
-- Mostra, por seller, a média descartando NULL (antiga) vs tratando NULL como 0
-- (atual). Diferem exatamente nos sellers que vendem algum produto sem descrição.
WITH produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_description_lenght AS L
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
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
