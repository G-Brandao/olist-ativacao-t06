-- =====================================================================
-- ativacaoOlistProdutos — TABELÃO de features de produtos (ativação de sellers)
-- Dialeto: Spark SQL (Databricks)        |  Tabelas: workspace.olist.*
-- Grão de saída: 1 linha por seller_id (universo = sellers com >=1 venda < corte)
-- ---------------------------------------------------------------------
-- O QUE É: consolida, numa ÚNICA query, TODAS as features dos 13 scripts
--   01..13 de features_spark/ (variaveis.md §1..§8). É a "montagem da feature
--   store" via LEFT JOIN dos blocos por seller_id, num único pipeline de CTEs.
--
-- FAMÍLIAS (e o script de origem de cada bloco):
--   §1 vlCategoriasDistintas{W} / vlProdutosDistintos{W}          (01,02)
--   §2 vlContagemCategoriaConcorrentes{W} (indireta)             (03)
--   §2 vlContagemProdutosConcorrentes{W}  (direta)               (04)
--   §7 vl{Media,Mediana,25,75,Min,Max}CaracteresDescricao        (05) Vida, NULL->0
--   §7 vlMediaFotosProduto                                       (06) Vida, NULL->0
--   §3 vl{Media,Mediana,25,75,Min,Max}PesoProduto{W} + vlTotalPesoProdutos{W}  (07) por UNIDADE
--   §4 vlMediaCubagemProdutos{W} + vlTotalCubagemProdutos{W}     (08) por UNIDADE
--   §5 vlPrecoKg{W} / vlFreteKg{W}                               (09,10)
--   §6 descTopCategoria{1,2,3}{W} / vlShareTopCategoria{1,2,3}{W} (11,12)
--   §8 vl{Media,Mediana,25,75,Min,Max}PesoPortfolio + vlTotalPesoPortfolio  (13) estático, SKU distinto
--   {W} = D14, D28, D56, D365, Vida.
--
-- DECISÕES preservadas dos scripts originais (ver CLAUDE.md §4):
--   • Corte ESTRITO order_purchase_timestamp < data_corte; sem filtro de status.
--   • Janelas semi-abertas [corte-N, corte). §7 (descrição+fotos) e §8 (portfólio)
--     são ESTÁTICAS (sem sufixo). Todo o resto é janelado (D14..Vida).
--   • §3 peso e §4 cubagem: por UNIDADE vendida (ponderado por venda), janelados.
--     §8 portfólio: peso por SKU DISTINTO vinculado, estático (atributo imutável).
--   • Categoria NULL -> 'sem_categoria' (§1/§2/§6). DESCRIÇÃO/FOTOS NULL -> 0
--     (decisão D12). product_weight_g/dimensões NULL -> ignorados.
--   • Top categorias por UNIDADES; desempate unidades DESC -> pedidos DESC ->
--     categoria ASC; posição inexistente -> NULL (guard u_>0).
--   • percentile() = percentil tipo-7 (ignora NULL); a Mediana é o p50 (não há vl50).
--
-- JOIN com products difere por família (igual aos scripts):
--   • §1/§2/§6 usam LEFT JOIN products (categoria pode faltar -> 'sem_categoria').
--   • §7/§3/§4/§5/§8 precisam do atributo do produto -> usam a flag `tem_produto`
--     (= product_id casou em products) para emular o INNER JOIN.
--
-- Parâmetro: variável de sessão único 'data_corte' (DEFAULT '2018-07-01'), lido via data_corte.
-- =====================================================================
DECLARE OR REPLACE VARIABLE data_corte TIMESTAMP DEFAULT TIMESTAMP'2018-07-01';

WITH
-- BASE única: 1 linha por unidade vendida (order_items) antes do corte, já com
-- os atributos de produto. LEFT JOIN + `tem_produto` p/ emular o INNER das §7..§8.
base AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        oi.order_id,
        oi.price                                              AS price,
        oi.freight_value                                      AS frete,
        o.order_purchase_timestamp                            AS dt_venda,
        (p.product_id IS NOT NULL)                            AS tem_produto,
        COALESCE(p.product_category_name, 'sem_categoria')    AS categoria,     -- §1/§2/§6
        p.product_description_lenght                          AS desc_len,
        p.product_photos_qty                                  AS fotos,
        p.product_weight_g                                    AS w,
        (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders       o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < data_corte
),
spine AS (SELECT DISTINCT seller_id FROM base),  -- 1 linha por seller (grão de saída)

-- =====================================================================
-- §1 — Diversidade de catálogo (01 + 02)
-- =====================================================================
f_diversidade AS (
    SELECT seller_id,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN categoria END) AS vlCategoriasDistintasD14,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN categoria END) AS vlCategoriasDistintasD28,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN categoria END) AS vlCategoriasDistintasD56,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN categoria END) AS vlCategoriasDistintasD365,
        COUNT(DISTINCT categoria)                                                                            AS vlCategoriasDistintasVida,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN product_id END) AS vlProdutosDistintosD14,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN product_id END) AS vlProdutosDistintosD28,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN product_id END) AS vlProdutosDistintosD56,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN product_id END) AS vlProdutosDistintosD365,
        COUNT(DISTINCT product_id)                                                                           AS vlProdutosDistintosVida
    FROM base
    GROUP BY seller_id
),

-- =====================================================================
-- §2 — Concorrência INDIRETA: outros sellers na MESMA CATEGORIA (03)
-- =====================================================================
cat_roster AS (
    SELECT seller_id, categoria,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN 1 ELSE 0 END) AS in_d14,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN 1 ELSE 0 END) AS in_d28,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN 1 ELSE 0 END) AS in_d56,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN 1 ELSE 0 END) AS in_d365
    FROM base GROUP BY seller_id, categoria
),
f_conc_categoria AS (
    SELECT a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d14  = 1 AND b.in_d14  = 1 THEN b.seller_id END) AS vlContagemCategoriaConcorrentesD14,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS vlContagemCategoriaConcorrentesD28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS vlContagemCategoriaConcorrentesD56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS vlContagemCategoriaConcorrentesD365,
        COUNT(DISTINCT b.seller_id)                                                    AS vlContagemCategoriaConcorrentesVida
    FROM cat_roster a
    JOIN cat_roster b ON b.categoria = a.categoria AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),

-- =====================================================================
-- §2 — Concorrência DIRETA: outros sellers no MESMO product_id (04)
-- =====================================================================
prod_roster AS (
    SELECT seller_id, product_id,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN 1 ELSE 0 END) AS in_d14,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN 1 ELSE 0 END) AS in_d28,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN 1 ELSE 0 END) AS in_d56,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN 1 ELSE 0 END) AS in_d365
    FROM base GROUP BY seller_id, product_id
),
f_conc_produto AS (
    SELECT a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d14  = 1 AND b.in_d14  = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD14,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD365,
        COUNT(DISTINCT b.seller_id)                                                    AS vlContagemProdutosConcorrentesVida
    FROM prod_roster a
    JOIN prod_roster b ON b.product_id = a.product_id AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),

-- =====================================================================
-- §7 — Caracteres da descrição (05) — Vida, PRODUTO DISTINTO, NULL -> 0
-- =====================================================================
prod_descricao AS (
    SELECT DISTINCT seller_id, product_id, COALESCE(desc_len, 0) AS L
    FROM base WHERE tem_produto
),
f_descricao AS (
    SELECT seller_id,
        AVG(L)              AS vlMediaCaracteresDescricao,
        percentile(L, 0.50) AS vlMedianaCaracteresDescricao,
        percentile(L, 0.25) AS vl25CaracteresDescricao,
        percentile(L, 0.75) AS vl75CaracteresDescricao,
        MIN(L)              AS vlMinCaracteresDescricao,
        MAX(L)              AS vlMaxCaracteresDescricao
    FROM prod_descricao GROUP BY seller_id
),

-- §7 — Média de fotos por produto (06) — Vida, PRODUTO DISTINTO, NULL -> 0
prod_fotos AS (
    SELECT DISTINCT seller_id, product_id, COALESCE(fotos, 0) AS fotos
    FROM base WHERE tem_produto
),
f_fotos AS (
    SELECT seller_id, AVG(fotos) AS vlMediaFotosProduto
    FROM prod_fotos GROUP BY seller_id
),

-- =====================================================================
-- §3 — Peso do produto VENDIDO (07): distribuição + total por UNIDADE, janelados.
-- (w já é NULL quando o produto não casou ou não tem peso -> percentile/AVG/...
--  ignoram NULL, reproduzindo o INNER JOIN + filtro de peso do script 07.)
-- =====================================================================
f_peso AS (
    SELECT seller_id,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS vlMediaPesoProdutoD14,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS vlMediaPesoProdutoD28,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS vlMediaPesoProdutoD56,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS vlMediaPesoProdutoD365,
        AVG(w)                                                                                        AS vlMediaPesoProdutoVida,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.50) AS vlMedianaPesoProdutoD14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.50) AS vlMedianaPesoProdutoD28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.50) AS vlMedianaPesoProdutoD56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.50) AS vlMedianaPesoProdutoD365,
        percentile(w, 0.50)                                                                           AS vlMedianaPesoProdutoVida,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.25) AS vl25PesoProdutoD14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.25) AS vl25PesoProdutoD28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.25) AS vl25PesoProdutoD56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.25) AS vl25PesoProdutoD365,
        percentile(w, 0.25)                                                                           AS vl25PesoProdutoVida,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END, 0.75) AS vl75PesoProdutoD14,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END, 0.75) AS vl75PesoProdutoD28,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END, 0.75) AS vl75PesoProdutoD56,
        percentile(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END, 0.75) AS vl75PesoProdutoD365,
        percentile(w, 0.75)                                                                           AS vl75PesoProdutoVida,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS vlMinPesoProdutoD14,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS vlMinPesoProdutoD28,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS vlMinPesoProdutoD56,
        MIN(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS vlMinPesoProdutoD365,
        MIN(w)                                                                                        AS vlMinPesoProdutoVida,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)              AS vlMaxPesoProdutoD14,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)              AS vlMaxPesoProdutoD28,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)              AS vlMaxPesoProdutoD56,
        MAX(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)              AS vlMaxPesoProdutoD365,
        MAX(w)                                                                                        AS vlMaxPesoProdutoVida,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)/1000.0        AS vlTotalPesoProdutosD14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)/1000.0        AS vlTotalPesoProdutosD28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)/1000.0        AS vlTotalPesoProdutosD56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)/1000.0        AS vlTotalPesoProdutosD365,
        SUM(w)/1000.0                                                                                  AS vlTotalPesoProdutosVida
    FROM base
    GROUP BY seller_id
),

-- =====================================================================
-- §4 — Cubagem (08): média e total por UNIDADE, janelados (cub NULL ignorado).
-- =====================================================================
f_cubagem AS (
    SELECT seller_id,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN cub END) AS vlMediaCubagemProdutosD14,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN cub END) AS vlMediaCubagemProdutosD28,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN cub END) AS vlMediaCubagemProdutosD56,
        AVG(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN cub END) AS vlMediaCubagemProdutosD365,
        AVG(cub)                                                                           AS vlMediaCubagemProdutosVida,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN cub END) AS vlTotalCubagemProdutosD14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN cub END) AS vlTotalCubagemProdutosD28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN cub END) AS vlTotalCubagemProdutosD56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN cub END) AS vlTotalCubagemProdutosD365,
        SUM(cub)                                                                           AS vlTotalCubagemProdutosVida
    FROM base
    GROUP BY seller_id
),

-- =====================================================================
-- §5 — Preço por kg (09) e Frete por kg (10): razão de totais por UNIDADE,
--      base = itens com peso não-nulo; denominador 0/NULL -> NULL.
-- =====================================================================
rs_kg_comp AS (
    SELECT seller_id,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN price END)   AS receita_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN frete END)   AS frete_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN w END)/1000.0 AS kg_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN price END)   AS receita_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN frete END)   AS frete_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN w END)/1000.0 AS kg_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN price END)   AS receita_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN frete END)   AS frete_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN w END)/1000.0 AS kg_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN price END)   AS receita_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN frete END)   AS frete_d365,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN w END)/1000.0 AS kg_d365,
        SUM(price)    AS receita_vida,
        SUM(frete)    AS frete_vida,
        SUM(w)/1000.0 AS kg_vida
    FROM base
    WHERE tem_produto AND w IS NOT NULL
    GROUP BY seller_id
),
f_rs_kg AS (
    SELECT seller_id,
        receita_d14  / NULLIF(kg_d14,  0) AS vlPrecoKgD14,
        receita_d28  / NULLIF(kg_d28,  0) AS vlPrecoKgD28,
        receita_d56  / NULLIF(kg_d56,  0) AS vlPrecoKgD56,
        receita_d365 / NULLIF(kg_d365, 0) AS vlPrecoKgD365,
        receita_vida / NULLIF(kg_vida, 0) AS vlPrecoKgVida,
        frete_d14    / NULLIF(kg_d14,  0) AS vlFreteKgD14,
        frete_d28    / NULLIF(kg_d28,  0) AS vlFreteKgD28,
        frete_d56    / NULLIF(kg_d56,  0) AS vlFreteKgD56,
        frete_d365   / NULLIF(kg_d365, 0) AS vlFreteKgD365,
        frete_vida   / NULLIF(kg_vida, 0) AS vlFreteKgVida
    FROM rs_kg_comp
),

-- =====================================================================
-- §6 — Top 3 categorias (11) + Share das top 3 (12). Por unidades; desempate
--      unidades DESC -> pedidos DESC -> categoria ASC. (cat_base/rk compartilhados.)
-- =====================================================================
top_cat_base AS (
    SELECT seller_id, categoria,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN 1 ELSE 0 END)        AS u_d14,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 14  THEN order_id END) AS p_d14,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN 1 ELSE 0 END)        AS u_d28,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 28  THEN order_id END) AS p_d28,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN 1 ELSE 0 END)        AS u_d56,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 56  THEN order_id END) AS p_d56,
        SUM(CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN 1 ELSE 0 END)        AS u_d365,
        COUNT(DISTINCT CASE WHEN datediff(data_corte, dt_venda) <= 365 THEN order_id END) AS p_d365,
        COUNT(*)                                                                                       AS u_vida,
        COUNT(DISTINCT order_id)                                                                       AS p_vida
    FROM base
    GROUP BY seller_id, categoria
),
top_cat_rk AS (
    SELECT seller_id, categoria, u_d14, u_d28, u_d56, u_d365, u_vida,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d14  DESC, p_d14  DESC, categoria ASC) AS rk_d14,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d28  DESC, p_d28  DESC, categoria ASC) AS rk_d28,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d56  DESC, p_d56  DESC, categoria ASC) AS rk_d56,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d365 DESC, p_d365 DESC, categoria ASC) AS rk_d365,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_vida DESC, p_vida DESC, categoria ASC) AS rk_vida
    FROM top_cat_base
),
f_top_cat AS (
    SELECT seller_id,
        -- descTopCategoria{1,2,3}{W} (11)
        MAX(CASE WHEN rk_d14 =1 AND u_d14 >0 THEN categoria END) AS descTopCategoria1D14,
        MAX(CASE WHEN rk_d28 =1 AND u_d28 >0 THEN categoria END) AS descTopCategoria1D28,
        MAX(CASE WHEN rk_d56 =1 AND u_d56 >0 THEN categoria END) AS descTopCategoria1D56,
        MAX(CASE WHEN rk_d365=1 AND u_d365>0 THEN categoria END) AS descTopCategoria1D365,
        MAX(CASE WHEN rk_vida=1 AND u_vida>0 THEN categoria END) AS descTopCategoria1Vida,
        MAX(CASE WHEN rk_d14 =2 AND u_d14 >0 THEN categoria END) AS descTopCategoria2D14,
        MAX(CASE WHEN rk_d28 =2 AND u_d28 >0 THEN categoria END) AS descTopCategoria2D28,
        MAX(CASE WHEN rk_d56 =2 AND u_d56 >0 THEN categoria END) AS descTopCategoria2D56,
        MAX(CASE WHEN rk_d365=2 AND u_d365>0 THEN categoria END) AS descTopCategoria2D365,
        MAX(CASE WHEN rk_vida=2 AND u_vida>0 THEN categoria END) AS descTopCategoria2Vida,
        MAX(CASE WHEN rk_d14 =3 AND u_d14 >0 THEN categoria END) AS descTopCategoria3D14,
        MAX(CASE WHEN rk_d28 =3 AND u_d28 >0 THEN categoria END) AS descTopCategoria3D28,
        MAX(CASE WHEN rk_d56 =3 AND u_d56 >0 THEN categoria END) AS descTopCategoria3D56,
        MAX(CASE WHEN rk_d365=3 AND u_d365>0 THEN categoria END) AS descTopCategoria3D365,
        MAX(CASE WHEN rk_vida=3 AND u_vida>0 THEN categoria END) AS descTopCategoria3Vida,
        -- vlShareTopCategoria{1,2,3}{W} (12) — / em Spark já promove INT->DOUBLE
        MAX(CASE WHEN rk_d14 =1 AND u_d14 >0 THEN u_d14  END) / NULLIF(SUM(u_d14),  0) AS vlShareTopCategoria1D14,
        MAX(CASE WHEN rk_d28 =1 AND u_d28 >0 THEN u_d28  END) / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria1D28,
        MAX(CASE WHEN rk_d56 =1 AND u_d56 >0 THEN u_d56  END) / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria1D56,
        MAX(CASE WHEN rk_d365=1 AND u_d365>0 THEN u_d365 END) / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria1D365,
        MAX(CASE WHEN rk_vida=1 AND u_vida>0 THEN u_vida END) / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria1Vida,
        MAX(CASE WHEN rk_d14 =2 AND u_d14 >0 THEN u_d14  END) / NULLIF(SUM(u_d14),  0) AS vlShareTopCategoria2D14,
        MAX(CASE WHEN rk_d28 =2 AND u_d28 >0 THEN u_d28  END) / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria2D28,
        MAX(CASE WHEN rk_d56 =2 AND u_d56 >0 THEN u_d56  END) / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria2D56,
        MAX(CASE WHEN rk_d365=2 AND u_d365>0 THEN u_d365 END) / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria2D365,
        MAX(CASE WHEN rk_vida=2 AND u_vida>0 THEN u_vida END) / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria2Vida,
        MAX(CASE WHEN rk_d14 =3 AND u_d14 >0 THEN u_d14  END) / NULLIF(SUM(u_d14),  0) AS vlShareTopCategoria3D14,
        MAX(CASE WHEN rk_d28 =3 AND u_d28 >0 THEN u_d28  END) / NULLIF(SUM(u_d28),  0) AS vlShareTopCategoria3D28,
        MAX(CASE WHEN rk_d56 =3 AND u_d56 >0 THEN u_d56  END) / NULLIF(SUM(u_d56),  0) AS vlShareTopCategoria3D56,
        MAX(CASE WHEN rk_d365=3 AND u_d365>0 THEN u_d365 END) / NULLIF(SUM(u_d365), 0) AS vlShareTopCategoria3D365,
        MAX(CASE WHEN rk_vida=3 AND u_vida>0 THEN u_vida END) / NULLIF(SUM(u_vida), 0) AS vlShareTopCategoria3Vida
    FROM top_cat_rk
    GROUP BY seller_id
),

-- =====================================================================
-- §8 — Peso do PORTFÓLIO (13): SKU DISTINTO vinculado, estático (sem janela).
-- =====================================================================
portfolio AS (
    SELECT DISTINCT seller_id, product_id, w
    FROM base WHERE tem_produto AND w IS NOT NULL
),
f_portfolio AS (
    SELECT seller_id,
        AVG(w)              AS vlMediaPesoPortfolio,
        percentile(w, 0.50) AS vlMedianaPesoPortfolio,
        percentile(w, 0.25) AS vl25PesoPortfolio,
        percentile(w, 0.75) AS vl75PesoPortfolio,
        MIN(w)              AS vlMinPesoPortfolio,
        MAX(w)              AS vlMaxPesoPortfolio,
        SUM(w)/1000.0       AS vlTotalPesoPortfolio
    FROM portfolio GROUP BY seller_id
)

-- =====================================================================
-- TABELÃO FINAL — spine LEFT JOIN de todas as famílias por seller_id.
-- COALESCE só onde o script original devolve 0 p/ ausência (§2 concorrência);
-- demais ausências permanecem NULL (sem produto/peso/categoria na janela).
-- =====================================================================
SELECT
    s.seller_id,

    -- §1 Diversidade de catálogo
    d.vlCategoriasDistintasD14, d.vlCategoriasDistintasD28, d.vlCategoriasDistintasD56, d.vlCategoriasDistintasD365, d.vlCategoriasDistintasVida,
    d.vlProdutosDistintosD14,   d.vlProdutosDistintosD28,   d.vlProdutosDistintosD56,   d.vlProdutosDistintosD365,   d.vlProdutosDistintosVida,

    -- §2 Concorrência indireta (mesma categoria) — ausência -> 0
    COALESCE(cc.vlContagemCategoriaConcorrentesD14,  0) AS vlContagemCategoriaConcorrentesD14,
    COALESCE(cc.vlContagemCategoriaConcorrentesD28,  0) AS vlContagemCategoriaConcorrentesD28,
    COALESCE(cc.vlContagemCategoriaConcorrentesD56,  0) AS vlContagemCategoriaConcorrentesD56,
    COALESCE(cc.vlContagemCategoriaConcorrentesD365, 0) AS vlContagemCategoriaConcorrentesD365,
    COALESCE(cc.vlContagemCategoriaConcorrentesVida, 0) AS vlContagemCategoriaConcorrentesVida,

    -- §2 Concorrência direta (mesmo product_id) — ausência -> 0
    COALESCE(cp.vlContagemProdutosConcorrentesD14,  0) AS vlContagemProdutosConcorrentesD14,
    COALESCE(cp.vlContagemProdutosConcorrentesD28,  0) AS vlContagemProdutosConcorrentesD28,
    COALESCE(cp.vlContagemProdutosConcorrentesD56,  0) AS vlContagemProdutosConcorrentesD56,
    COALESCE(cp.vlContagemProdutosConcorrentesD365, 0) AS vlContagemProdutosConcorrentesD365,
    COALESCE(cp.vlContagemProdutosConcorrentesVida, 0) AS vlContagemProdutosConcorrentesVida,

    -- §7 Caracteres da descrição (Vida) + média de fotos (Vida)
    dc.vlMediaCaracteresDescricao, dc.vlMedianaCaracteresDescricao, dc.vl25CaracteresDescricao,
    dc.vl75CaracteresDescricao, dc.vlMinCaracteresDescricao, dc.vlMaxCaracteresDescricao,
    ft.vlMediaFotosProduto,

    -- §3 Peso do produto vendido (distribuição + total por UNIDADE, 5 janelas)
    pe.vlMediaPesoProdutoD14, pe.vlMediaPesoProdutoD28, pe.vlMediaPesoProdutoD56, pe.vlMediaPesoProdutoD365, pe.vlMediaPesoProdutoVida,
    pe.vlMedianaPesoProdutoD14, pe.vlMedianaPesoProdutoD28, pe.vlMedianaPesoProdutoD56, pe.vlMedianaPesoProdutoD365, pe.vlMedianaPesoProdutoVida,
    pe.vl25PesoProdutoD14, pe.vl25PesoProdutoD28, pe.vl25PesoProdutoD56, pe.vl25PesoProdutoD365, pe.vl25PesoProdutoVida,
    pe.vl75PesoProdutoD14, pe.vl75PesoProdutoD28, pe.vl75PesoProdutoD56, pe.vl75PesoProdutoD365, pe.vl75PesoProdutoVida,
    pe.vlMinPesoProdutoD14, pe.vlMinPesoProdutoD28, pe.vlMinPesoProdutoD56, pe.vlMinPesoProdutoD365, pe.vlMinPesoProdutoVida,
    pe.vlMaxPesoProdutoD14, pe.vlMaxPesoProdutoD28, pe.vlMaxPesoProdutoD56, pe.vlMaxPesoProdutoD365, pe.vlMaxPesoProdutoVida,
    pe.vlTotalPesoProdutosD14, pe.vlTotalPesoProdutosD28, pe.vlTotalPesoProdutosD56, pe.vlTotalPesoProdutosD365, pe.vlTotalPesoProdutosVida,

    -- §4 Cubagem (média + total por UNIDADE, 5 janelas)
    cb.vlMediaCubagemProdutosD14, cb.vlMediaCubagemProdutosD28, cb.vlMediaCubagemProdutosD56, cb.vlMediaCubagemProdutosD365, cb.vlMediaCubagemProdutosVida,
    cb.vlTotalCubagemProdutosD14, cb.vlTotalCubagemProdutosD28, cb.vlTotalCubagemProdutosD56, cb.vlTotalCubagemProdutosD365, cb.vlTotalCubagemProdutosVida,

    -- §5 Preço/kg e Frete/kg
    rk.vlPrecoKgD14, rk.vlPrecoKgD28, rk.vlPrecoKgD56, rk.vlPrecoKgD365, rk.vlPrecoKgVida,
    rk.vlFreteKgD14, rk.vlFreteKgD28, rk.vlFreteKgD56, rk.vlFreteKgD365, rk.vlFreteKgVida,

    -- §6 Top 3 categorias (nome)
    tc.descTopCategoria1D14, tc.descTopCategoria1D28, tc.descTopCategoria1D56, tc.descTopCategoria1D365, tc.descTopCategoria1Vida,
    tc.descTopCategoria2D14, tc.descTopCategoria2D28, tc.descTopCategoria2D56, tc.descTopCategoria2D365, tc.descTopCategoria2Vida,
    tc.descTopCategoria3D14, tc.descTopCategoria3D28, tc.descTopCategoria3D56, tc.descTopCategoria3D365, tc.descTopCategoria3Vida,

    -- §6 Share das top 3 categorias
    tc.vlShareTopCategoria1D14, tc.vlShareTopCategoria1D28, tc.vlShareTopCategoria1D56, tc.vlShareTopCategoria1D365, tc.vlShareTopCategoria1Vida,
    tc.vlShareTopCategoria2D14, tc.vlShareTopCategoria2D28, tc.vlShareTopCategoria2D56, tc.vlShareTopCategoria2D365, tc.vlShareTopCategoria2Vida,
    tc.vlShareTopCategoria3D14, tc.vlShareTopCategoria3D28, tc.vlShareTopCategoria3D56, tc.vlShareTopCategoria3D365, tc.vlShareTopCategoria3Vida,

    -- §8 Peso do portfólio (estático, SKU distinto)
    pf.vlMediaPesoPortfolio, pf.vlMedianaPesoPortfolio, pf.vl25PesoPortfolio, pf.vl75PesoPortfolio,
    pf.vlMinPesoPortfolio, pf.vlMaxPesoPortfolio, pf.vlTotalPesoPortfolio

FROM spine s
LEFT JOIN f_diversidade    d  ON d.seller_id  = s.seller_id
LEFT JOIN f_conc_categoria cc ON cc.seller_id = s.seller_id
LEFT JOIN f_conc_produto   cp ON cp.seller_id = s.seller_id
LEFT JOIN f_descricao      dc ON dc.seller_id = s.seller_id
LEFT JOIN f_fotos          ft ON ft.seller_id = s.seller_id
LEFT JOIN f_peso           pe ON pe.seller_id = s.seller_id
LEFT JOIN f_cubagem        cb ON cb.seller_id = s.seller_id
LEFT JOIN f_rs_kg          rk ON rk.seller_id = s.seller_id
LEFT JOIN f_top_cat        tc ON tc.seller_id = s.seller_id
LEFT JOIN f_portfolio      pf ON pf.seller_id = s.seller_id;
