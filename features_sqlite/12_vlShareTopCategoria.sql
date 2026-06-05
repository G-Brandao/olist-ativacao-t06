-- =====================================================================
-- vlShareTopCategoria{1,2,3}  (variaveis.md §7) — Share das top 3 categorias
-- Janelas: D28, D56, D365, Vida   |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlShareTopCategoria{1,2,3}{D28,D56,D365,Vida}  (12 colunas)
-- Definição: fração das UNIDADES vendidas concentrada em cada uma das 3
--            categorias mais vendidas (mesmo ranking de descTopCategoria).
-- ---------------------------------------------------------------------
-- CRITÉRIO: share = unidades(topk, janela) / unidades_totais(janela). Mesmo
--   ranking/desempate do §7 (unidades DESC -> pedidos DESC -> categoria ASC).
--   soma dos 3 shares <= 1. *1.0 força divisão real; total 0 -> NULL (NULLIF).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Nulos    : seller com <k categorias na janela -> share_k NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: itens vendidos até o corte (categoria, pedido, data).
WITH vendas AS (
    SELECT oi.seller_id,
           COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
           oi.order_id,
           o.order_purchase_timestamp                         AS dt_venda
    FROM order_items oi
    JOIN orders       o ON o.order_id   = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) por (seller, categoria): unidades e pedidos distintos por janela.
cat_base AS (
    SELECT seller_id, categoria,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN 1 ELSE 0 END)        AS u_d28,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN order_id END) AS p_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN 1 ELSE 0 END)        AS u_d56,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN order_id END) AS p_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN 1 ELSE 0 END)        AS u_d365,
        COUNT(DISTINCT CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN order_id END) AS p_d365,
        COUNT(*)                                                                                 AS u_vida,
        COUNT(DISTINCT order_id)                                                                 AS p_vida
    FROM vendas
    GROUP BY seller_id, categoria
),
-- 3) ranking por janela (idêntico ao descTopCategoria).
rk AS (
    SELECT seller_id, categoria, u_d28, u_d56, u_d365, u_vida,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d28  DESC, p_d28  DESC, categoria ASC) AS rk_d28,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d56  DESC, p_d56  DESC, categoria ASC) AS rk_d56,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d365 DESC, p_d365 DESC, categoria ASC) AS rk_d365,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_vida DESC, p_vida DESC, categoria ASC) AS rk_vida
    FROM cat_base
)
-- 4) share = unidades da posição k / total de unidades da janela (SUM por seller).
--    Guard "u_>0": se a posição k não existe na janela (seller com <k
--    categorias vendidas), o numerador vira NULL -> share NULL (não 0).
SELECT
    seller_id,
    MAX(CASE WHEN rk_d28 =1 AND u_d28 >0 THEN u_d28  END) * 1.0 / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria1D28,
    MAX(CASE WHEN rk_d56 =1 AND u_d56 >0 THEN u_d56  END) * 1.0 / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria1D56,
    MAX(CASE WHEN rk_d365=1 AND u_d365>0 THEN u_d365 END) * 1.0 / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria1D365,
    MAX(CASE WHEN rk_vida=1 AND u_vida>0 THEN u_vida END) * 1.0 / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria1Vida,
    MAX(CASE WHEN rk_d28 =2 AND u_d28 >0 THEN u_d28  END) * 1.0 / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria2D28,
    MAX(CASE WHEN rk_d56 =2 AND u_d56 >0 THEN u_d56  END) * 1.0 / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria2D56,
    MAX(CASE WHEN rk_d365=2 AND u_d365>0 THEN u_d365 END) * 1.0 / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria2D365,
    MAX(CASE WHEN rk_vida=2 AND u_vida>0 THEN u_vida END) * 1.0 / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria2Vida,
    MAX(CASE WHEN rk_d28 =3 AND u_d28 >0 THEN u_d28  END) * 1.0 / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria3D28,
    MAX(CASE WHEN rk_d56 =3 AND u_d56 >0 THEN u_d56  END) * 1.0 / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria3D56,
    MAX(CASE WHEN rk_d365=3 AND u_d365>0 THEN u_d365 END) * 1.0 / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria3D365,
    MAX(CASE WHEN rk_vida=3 AND u_vida>0 THEN u_vida END) * 1.0 / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria3Vida
FROM rk
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — componentes do share (Vida): unidades por posição, total e fração -----------------------
WITH vendas AS (
    SELECT oi.seller_id, COALESCE(p.product_category_name,'sem_categoria') AS categoria, oi.order_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
r AS (
    SELECT seller_id, categoria, COUNT(*) AS unidades,
           ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY COUNT(*) DESC, COUNT(DISTINCT order_id) DESC, categoria ASC) AS rk,
           SUM(COUNT(*)) OVER (PARTITION BY seller_id) AS unidades_totais
    FROM vendas GROUP BY seller_id, categoria
)
SELECT seller_id, rk, categoria, unidades, unidades_totais,
       unidades * 1.0 / NULLIF(unidades_totais, 0) AS share
FROM r
WHERE rk <= 3
ORDER BY seller_id, rk
LIMIT 50;

-- ----------------------- Prova B — soma dos 3 shares <= 1 (Vida): nenhuma violação esperada -----------------------
WITH vendas AS (
    SELECT oi.seller_id, COALESCE(p.product_category_name,'sem_categoria') AS categoria, oi.order_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    LEFT JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
r AS (
    SELECT seller_id, categoria, COUNT(*) AS unidades,
           ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY COUNT(*) DESC, COUNT(DISTINCT order_id) DESC, categoria ASC) AS rk,
           SUM(COUNT(*)) OVER (PARTITION BY seller_id) AS unidades_totais
    FROM vendas GROUP BY seller_id, categoria
)
SELECT COUNT(*) AS violacoes_soma_maior_que_1
FROM (
    SELECT seller_id, SUM(unidades) * 1.0 / NULLIF(MAX(unidades_totais), 0) AS soma_top3
    FROM r WHERE rk <= 3 GROUP BY seller_id
)
WHERE soma_top3 > 1.0000001;
