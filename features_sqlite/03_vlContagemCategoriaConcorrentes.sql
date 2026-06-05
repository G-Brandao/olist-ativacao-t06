-- =====================================================================
-- vlContagemCategoriaConcorrentes  (variaveis.md §2) — Concorrência indireta
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlContagemCategoriaConcorrentes{D28,D56,D365,Vida}
-- Definição: para o seller A, nº de OUTROS sellers (B<>A) que venderam em
--            ALGUMA categoria em comum com A na mesma janela (substitutos).
-- Grão     : entidade = SELLER A; COUNT(DISTINCT concorrente) impede contar
--            o mesmo B duas vezes quando ele divide várias categorias com A.
-- Data     : order_purchase_timestamp, corte estrito < {data_corte}.
-- Premissas: sem filtro de order_status; categoria NULL -> 'sem_categoria';
--            janela sem venda -> 0 concorrentes (não está no mercado).
-- Modelagem: em vez de self-join (sc a JOIN sc b), nomeamos os dois papéis:
--            "minhas_cat" (categorias do seller) x "roster" (todos os sellers
--            por categoria). O cruzamento fica explícito e legível.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens vendidos até o corte, com a categoria e a data.
WITH vendas AS (
    SELECT
        oi.seller_id,
        COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
        o.order_purchase_timestamp                         AS dt_venda
    FROM order_items oi
    JOIN orders       o ON o.order_id   = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) pares distintos (seller, categoria, janela): "quem atua em qual categoria".
--    Uma flag por janela evita repetir a base 4 vezes.
atuacao AS (
    SELECT DISTINCT
        seller_id,
        categoria,
        CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN 1 ELSE 0 END AS in_d28,
        CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN 1 ELSE 0 END AS in_d56,
        CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN 1 ELSE 0 END AS in_d365
    FROM vendas
),
-- 3) colapsa para 1 linha por (seller, categoria) carregando a janela mais curta
--    em que o par aparece (MAX das flags).
minhas_cat AS (
    SELECT seller_id, categoria,
           MAX(in_d28) AS in_d28, MAX(in_d56) AS in_d56, MAX(in_d365) AS in_d365
    FROM atuacao
    GROUP BY seller_id, categoria
),
-- 4) cruza A (minhas_cat) com B (mesma tabela como "roster") na MESMA categoria,
--    exigindo que ambos estejam ativos na janela e que B <> A.
concorrentes AS (
    SELECT
        a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS q_d28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS q_d56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS q_d365,
        COUNT(DISTINCT b.seller_id)                                                    AS q_vida
    FROM minhas_cat a
    JOIN minhas_cat b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
-- 5) spine + COALESCE 0: seller sem concorrente em nenhuma janela some do JOIN.
SELECT
    s.seller_id,
    COALESCE(c.q_d28,  0) AS vlContagemCategoriaConcorrentesD28,
    COALESCE(c.q_d56,  0) AS vlContagemCategoriaConcorrentesD56,
    COALESCE(c.q_d365, 0) AS vlContagemCategoriaConcorrentesD365,
    COALESCE(c.q_vida, 0) AS vlContagemCategoriaConcorrentesVida
FROM spine s
LEFT JOIN concorrentes c ON c.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — por que COUNT(DISTINCT concorrente): pares que dividem >1 categoria (Vida) -----------------------
-- Sem DISTINCT, o concorrente B seria contado uma vez por categoria em comum.
WITH minhas_categorias AS (
    SELECT DISTINCT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT a.seller_id AS seller_a, b.seller_id AS concorrente_b,
       COUNT(*) AS categorias_em_comum
FROM minhas_categorias a
JOIN minhas_categorias b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
GROUP BY a.seller_id, b.seller_id
HAVING COUNT(*) > 1
ORDER BY categorias_em_comum DESC
LIMIT 20;

-- ----------------------- Prova B — categorias com um único seller geram 0 concorrentes (-> spine + COALESCE) -----------------------
WITH minhas_categorias AS (
    SELECT DISTINCT oi.seller_id,
           COALESCE(p.product_category_name,'sem_categoria') AS categoria
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT categoria, COUNT(DISTINCT seller_id) AS sellers_na_categoria
FROM minhas_categorias
GROUP BY categoria
HAVING COUNT(DISTINCT seller_id) = 1
ORDER BY categoria
LIMIT 20;
