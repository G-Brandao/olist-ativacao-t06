-- =====================================================================
-- vlContagemProdutosConcorrentes  (variaveis.md §2) — Concorrência direta
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlContagemProdutosConcorrentes{D28,D56,D365,Vida}
-- Definição: para o seller A, nº de OUTROS sellers (B<>A) que venderam o
--            MESMO product_id que A na mesma janela (concorrência DIRETA —
--            o cliente poderia comprar o SKU idêntico de outro seller).
-- Grão     : entidade = SELLER A; COUNT(DISTINCT concorrente) impede contar
--            o mesmo B duas vezes quando ele divide vários SKUs com A.
-- Data     : order_purchase_timestamp, corte estrito < {data_corte}.
-- Premissas: sem filtro de order_status; 1.225 product_id são vendidos por
--            >1 seller no dataset; janela sem venda -> 0.
-- Modelagem: mesmo padrão da §3, trocando categoria por product_id.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- ---------------------------------------------------------------------
-- LIMITAÇÃO CONHECIDA (interpretação): esta métrica é um PISO de concorrência
--   — alta precisão, baixo recall. `product_id` é o SKU ÚNICO do catálogo Olist
--   (chave de `products`, reusado em várias vendas: 32.951 produtos x 112.650
--   itens, média 3,4 vendas/produto — NÃO é gerado por venda). Só 1.225 produtos
--   (~3,7%) são vendidos por >1 seller (modelo de marketplace/buy box: a mesma
--   página de produto disputada por vários sellers — estruturalmente válido).
--   A variável SÓ enxerga concorrência onde o catálogo JÁ unificou o SKU. Ela é
--   CEGA a produtos FISICAMENTE EQUIVALENTES cadastrados com product_id distintos
--   (ex.: o mesmo isqueiro anunciado 2x). O dataset não tem marca/EAN/GTIN/título
--   para casar equivalentes, então essa concorrência fica invisível. Portanto:
--   um 0 NÃO garante ausência de concorrência. Use em par com a §3 (concorrência
--   por categoria = "teto" largo). Prova C abaixo materializa o piso.
-- =====================================================================

-- 1) vendas: itens vendidos até o corte, com produto e data.
WITH vendas AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        o.order_purchase_timestamp AS dt_venda
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) pares distintos (seller, produto) com flags de janela.
atuacao AS (
    SELECT DISTINCT
        seller_id,
        product_id,
        CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN 1 ELSE 0 END AS in_d28,
        CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN 1 ELSE 0 END AS in_d56,
        CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN 1 ELSE 0 END AS in_d365
    FROM vendas
),
meus_produtos AS (
    SELECT seller_id, product_id,
           MAX(in_d28) AS in_d28, MAX(in_d56) AS in_d56, MAX(in_d365) AS in_d365
    FROM atuacao
    GROUP BY seller_id, product_id
),
-- 3) cruza A com B no MESMO product_id, ambos ativos na janela, B <> A.
concorrentes AS (
    SELECT
        a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS q_d28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS q_d56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS q_d365,
        COUNT(DISTINCT b.seller_id)                                                    AS q_vida
    FROM meus_produtos a
    JOIN meus_produtos b ON b.product_id = a.product_id AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT
    s.seller_id,
    COALESCE(c.q_d28,  0) AS vlContagemProdutosConcorrentesD28,
    COALESCE(c.q_d56,  0) AS vlContagemProdutosConcorrentesD56,
    COALESCE(c.q_d365, 0) AS vlContagemProdutosConcorrentesD365,
    COALESCE(c.q_vida, 0) AS vlContagemProdutosConcorrentesVida
FROM spine s
LEFT JOIN concorrentes c ON c.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — SKUs vendidos por >1 seller (a métrica só faz sentido por causa deles) -----------------------
-- Esperado: ~1.225 product_id disputados.
WITH produtos_disputados AS (
    SELECT oi.product_id, COUNT(DISTINCT oi.seller_id) AS sellers_no_sku
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
    GROUP BY oi.product_id
    HAVING COUNT(DISTINCT oi.seller_id) > 1
)
SELECT COUNT(*) AS skus_disputados, MAX(sellers_no_sku) AS max_sellers_num_sku
FROM produtos_disputados;

-- ----------------------- Prova B — por que COUNT(DISTINCT concorrente): B que divide >1 SKU com A (Vida) -----------------------
WITH meus_produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT a.seller_id AS seller_a, b.seller_id AS concorrente_b,
       COUNT(*) AS skus_em_comum
FROM meus_produtos a
JOIN meus_produtos b ON b.product_id = a.product_id AND b.seller_id <> a.seller_id
GROUP BY a.seller_id, b.seller_id
HAVING COUNT(*) > 1
ORDER BY skus_em_comum DESC
LIMIT 20;

-- ----------------------- Prova C — dois sellers DISTINTOS no MESMO product_id, em VENDAS DISTINTAS -----------------------
-- Comprova a semântica da concorrência: o mesmo SKU do catálogo é vendido por
-- A e por B em PEDIDOS diferentes (não é venda casada no mesmo carrinho).
--   `b.seller_id <> a.seller_id`  -> sellers diferentes (concorrentes).
--   `b.order_id  <> a.order_id`   -> vendas (pedidos) diferentes.
--   `a.seller_id <  b.seller_id`  -> 1 linha por par (evita o espelho B,A).
-- Esperado: ~980 product_id disputados em vendas separadas (cutoff 2018-07-01).
WITH vendas AS (
    SELECT oi.product_id, oi.seller_id, oi.order_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT a.product_id,
       a.seller_id AS seller_a, a.order_id AS pedido_a,
       b.seller_id AS seller_b, b.order_id AS pedido_b
FROM vendas a
JOIN vendas b
  ON b.product_id = a.product_id
 AND b.seller_id <> a.seller_id
 AND b.order_id  <> a.order_id
 AND a.seller_id <  b.seller_id
ORDER BY a.product_id
LIMIT 20;

-- ----------------------- Prova D — contra-prova: concorrência NUNCA é co-ocorrência no mesmo pedido -----------------------
-- Se A e B vendem o mesmo product_id, NUNCA é dentro do mesmo order_id (carrinho).
-- Garante que a Prova C mede concorrência (vendas separadas), não venda casada.
-- Esperado: 0 (cutoff 2018-07-01).
WITH vendas AS (
    SELECT oi.product_id, oi.seller_id, oi.order_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT COUNT(*) AS pares_mesmo_pedido_mesmo_produto_sellers_distintos
FROM vendas a
JOIN vendas b
  ON b.product_id = a.product_id
 AND b.order_id  = a.order_id
 AND b.seller_id <> a.seller_id;
