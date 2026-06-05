-- =====================================================================
-- ativacaoOlistProdutos — TABELÃO de features de produtos (ativação de sellers)
-- Dialeto: Spark SQL (Databricks)        |  Tabelas: workspace.olist.*
-- Grão de saída: 1 linha por seller_id (universo = sellers com >=1 venda < corte)
-- ---------------------------------------------------------------------
-- O QUE É: consolida, numa ÚNICA query, TODAS as features dos 13 scripts
--   01..13 de features_spark/. Rodar esta query devolve a tabela larga com
--   o seller_id + todas as colunas oficiais (variaveis.md §1..§7 + Extras).
--   É a "montagem da feature store" via LEFT JOIN dos blocos por seller_id,
--   mas escrita como um único pipeline de CTEs (sem materializar 13 tabelas).
--
-- FAMÍLIAS (e o script de origem de cada bloco):
--   §1 vlCategoriasDistintas{W}              (01)
--   §1 vlProdutosDistintos{W}                (02)
--   §2 vlContagemCategoriaConcorrentes{W}    (03)  concorrência indireta
--   §2 vlContagemProdutosConcorrentes{W}     (04)  concorrência direta
--   §3 vl{Media,Mediana,25,50,75,Min,Max}CaracteresDescricao  (05) Vida (NULL->0)
--   §3 vlMediaFotosProduto                   (06)  Vida (NULL->0)
--   §4 vl{...}PesoProduto (estático) + vlTotalPesoProdutos{W}  (07)
--   §5 vlMediaCubagemProdutos (estático) + vlTotalCubagemProdutos{W}  (08)
--   §6 vlPrecoKg{W} + vlPrecoKgAjustado{W}   (09)
--   §6 vlFreteKg{W} + vlFreteKgAjustado{W}   (10)
--   §7 descTopCategoria{1,2,3}{W}            (11)
--   §7 vlShareTopCategoria{1,2,3}{W}         (12)
--   Extra vlShareProdutosSem{Categoria,Descricao,Foto,Peso}   (13) Vida
--
-- DECISÕES preservadas dos scripts originais (NÃO reabrir — ver CLAUDE.md §5):
--   • Corte ESTRITO order_purchase_timestamp < :data_corte; sem filtro de status.
--   • Janelas semi-abertas [corte-N, corte). São ESTÁTICAS (Vida) as métricas de
--     atributo imutável do produto: §3 (descrição+fotos) e a distribuição de
--     §4/§5 (peso+cubagem). Totais de peso/cubagem, R$/kg e top/share têm 4 janelas.
--   • Categoria NULL -> 'sem_categoria' (§1/§2/§7). DESCRIÇÃO/FOTOS NULL -> 0
--     (decisão do colega). product_weight_g/dimensões NULL -> ignorados.
--   • Distribuição (peso, cubagem, descrição, fotos) por PRODUTO DISTINTO; peso/
--     cubagem são estáticos (não variam no tempo). Totais e razões R$/kg por UNIDADE.
--   • Top categorias por UNIDADES; desempate unidades DESC -> pedidos DESC ->
--     categoria ASC; posição inexistente -> NULL (guard u_>0).
--
-- IMPORTANTE — JOIN com products difere por família (mantido igual aos scripts):
--   • §1/§2/§7 usam LEFT JOIN products (categoria pode faltar -> 'sem_categoria').
--   • §3/§4/§5/§6/Extra usam INNER JOIN products (precisam do atributo do produto).
--   Para escrever 1 base só, fazemos LEFT JOIN products e usamos a coluna
--   `tem_produto` (= product_id casou em products) para reproduzir o INNER JOIN
--   nas famílias que o exigem.
--
-- Parâmetro: widget único 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH
-- ---------------------------------------------------------------------
-- BASE única: 1 linha por unidade vendida (order_items) antes do corte,
-- já com todos os atributos de produto necessários. LEFT JOIN para não
-- perder itens cujo product_id não esteja em products (raros), e com
-- `tem_produto` para emular o INNER JOIN das famílias §3..§6/Extra.
-- ---------------------------------------------------------------------
base AS (
    SELECT
        oi.seller_id,
        oi.product_id,
        oi.order_id,
        oi.price                                              AS price,
        oi.freight_value                                      AS frete,
        o.order_purchase_timestamp                            AS dt_venda,
        (p.product_id IS NOT NULL)                            AS tem_produto,
        COALESCE(p.product_category_name, 'sem_categoria')    AS categoria,   -- §1/§2/§7
        p.product_category_name                               AS categoria_raw, -- §Extra (NULL importa)
        p.product_description_lenght                          AS desc_len,
        p.product_photos_qty                                  AS fotos,
        p.product_weight_g                                    AS w,
        (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders       o ON o.order_id   = oi.order_id
    LEFT JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),

-- spine = esqueleto da entidade: universo de sellers (>=1 venda < corte);
-- grão de saída = 1 linha por seller. Features penduradas via LEFT JOIN.
spine AS (SELECT DISTINCT seller_id FROM base),

-- =====================================================================
-- §1 — Diversidade de catálogo (01 + 02)
-- =====================================================================
f_diversidade AS (
    SELECT
        seller_id,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN categoria END) AS vlCategoriasDistintasD28,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN categoria END) AS vlCategoriasDistintasD56,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN categoria END) AS vlCategoriasDistintasD365,
        COUNT(DISTINCT categoria)                                                                            AS vlCategoriasDistintasVida,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN product_id END) AS vlProdutosDistintosD28,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN product_id END) AS vlProdutosDistintosD56,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN product_id END) AS vlProdutosDistintosD365,
        COUNT(DISTINCT product_id)                                                                           AS vlProdutosDistintosVida
    FROM base
    GROUP BY seller_id
),

-- =====================================================================
-- §2 — Concorrência INDIRETA: outros sellers na MESMA CATEGORIA (03)
-- pares (seller, categoria) com flag da janela; cruza A x B (B<>A) na categoria.
-- =====================================================================
cat_roster AS (
    SELECT seller_id, categoria,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN 1 ELSE 0 END) AS in_d28,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN 1 ELSE 0 END) AS in_d56,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN 1 ELSE 0 END) AS in_d365
    FROM base
    GROUP BY seller_id, categoria
),
f_conc_categoria AS (
    SELECT
        a.seller_id,
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
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN 1 ELSE 0 END) AS in_d28,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN 1 ELSE 0 END) AS in_d56,
        MAX(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN 1 ELSE 0 END) AS in_d365
    FROM base
    GROUP BY seller_id, product_id
),
f_conc_produto AS (
    SELECT
        a.seller_id,
        COUNT(DISTINCT CASE WHEN a.in_d28  = 1 AND b.in_d28  = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD28,
        COUNT(DISTINCT CASE WHEN a.in_d56  = 1 AND b.in_d56  = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD56,
        COUNT(DISTINCT CASE WHEN a.in_d365 = 1 AND b.in_d365 = 1 THEN b.seller_id END) AS vlContagemProdutosConcorrentesD365,
        COUNT(DISTINCT b.seller_id)                                                    AS vlContagemProdutosConcorrentesVida
    FROM prod_roster a
    JOIN prod_roster b ON b.product_id = a.product_id AND b.seller_id <> a.seller_id
    GROUP BY a.seller_id
),

-- =====================================================================
-- §3 — Caracteres da descrição (05) — Vida, PRODUTO DISTINTO. NULL -> 0
-- (decisão do colega: "sem descrição" conta como 0 caractere; puxa média/min).
-- =====================================================================
prod_descricao AS (
    SELECT DISTINCT seller_id, product_id, COALESCE(desc_len, 0) AS L
    FROM base
    WHERE tem_produto
),
f_descricao AS (
    SELECT
        seller_id,
        AVG(L)              AS vlMediaCaracteresDescricao,
        percentile(L, 0.50) AS vlMedianaCaracteresDescricao,
        percentile(L, 0.25) AS vl25CaracteresDescricao,
        percentile(L, 0.50) AS vl50CaracteresDescricao,
        percentile(L, 0.75) AS vl75CaracteresDescricao,
        MIN(L)              AS vlMinCaracteresDescricao,
        MAX(L)              AS vlMaxCaracteresDescricao
    FROM prod_descricao
    GROUP BY seller_id
),

-- =====================================================================
-- §3 — Média de fotos por produto (06) — Vida, PRODUTO DISTINTO. NULL -> 0
-- (decisão do colega: "sem foto" conta como 0; não há 0 'natural', mín real = 1).
-- =====================================================================
prod_fotos AS (
    SELECT DISTINCT seller_id, product_id, COALESCE(fotos, 0) AS fotos
    FROM base
    WHERE tem_produto
),
f_fotos AS (
    SELECT seller_id, AVG(fotos) AS vlMediaFotosProduto
    FROM prod_fotos
    GROUP BY seller_id
),

-- =====================================================================
-- §4 — Peso do produto (07): distribuição ESTÁTICA por PRODUTO DISTINTO (peso
--      é atributo imutável -> sem janela); total por UNIDADE (massa, g->kg, 4 janelas).
-- =====================================================================
peso_total AS (   -- por UNIDADE (cresce no tempo -> 4 janelas)
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END)/1000.0 AS tot_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END)/1000.0 AS tot_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END)/1000.0 AS tot_d365,
        SUM(w)/1000.0                                                                           AS tot_vida
    FROM base
    WHERE tem_produto
    GROUP BY seller_id
),
peso_prod AS (   -- PRODUTO DISTINTO (toda a vida; w constante por produto)
    SELECT DISTINCT seller_id, product_id, w
    FROM base
    WHERE tem_produto AND w IS NOT NULL
),
f_peso AS (   -- distribuição estática (sem sufixo de janela)
    SELECT seller_id,
        AVG(w)              AS vlMediaPesoProduto,
        percentile(w, 0.50) AS vlMedianaPesoProduto,
        percentile(w, 0.25) AS vl25PesoProduto,
        percentile(w, 0.50) AS vl50PesoProduto,
        percentile(w, 0.75) AS vl75PesoProduto,
        MIN(w)              AS vlMinPesoProduto,
        MAX(w)              AS vlMaxPesoProduto
    FROM peso_prod
    GROUP BY seller_id
),

-- =====================================================================
-- §5 — Cubagem (08): média ESTÁTICA por PRODUTO DISTINTO (atributo imutável ->
--      sem janela); total por UNIDADE (volume, 4 janelas).
-- =====================================================================
cub_total AS (   -- por UNIDADE (cresce no tempo -> 4 janelas)
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN cub END) AS tot_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN cub END) AS tot_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN cub END) AS tot_d365,
        SUM(cub)                                                                           AS tot_vida
    FROM base
    WHERE tem_produto
    GROUP BY seller_id
),
cub_prod AS (   -- PRODUTO DISTINTO (toda a vida; cub constante por produto)
    SELECT DISTINCT seller_id, product_id, cub
    FROM base
    WHERE tem_produto AND cub IS NOT NULL
),
f_cubagem AS (   -- média estática (sem sufixo de janela)
    SELECT seller_id, AVG(cub) AS vlMediaCubagemProdutos
    FROM cub_prod
    GROUP BY seller_id
),

-- =====================================================================
-- §6 — Preço por kg (09) e Frete por kg (10): razão de totais por UNIDADE,
--      base comum = itens com peso não-nulo; denominador 0/NULL -> NULL.
--      Cruas + Ajustado = log1p(x). (price e frete na MESMA base, 1 só CTE.)
-- =====================================================================
rs_kg_comp AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN price END)   AS receita_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN frete END)   AS frete_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END)/1000.0 AS kg_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN price END)   AS receita_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN frete END)   AS frete_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END)/1000.0 AS kg_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN price END)   AS receita_d365,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN frete END)   AS frete_d365,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END)/1000.0 AS kg_d365,
        SUM(price)    AS receita_vida,
        SUM(frete)    AS frete_vida,
        SUM(w)/1000.0 AS kg_vida
    FROM base
    WHERE tem_produto AND w IS NOT NULL
    GROUP BY seller_id
),
rs_kg AS (
    SELECT seller_id,
        receita_d28  / NULLIF(kg_d28,  0) AS pk_d28,  receita_d56  / NULLIF(kg_d56,  0) AS pk_d56,
        receita_d365 / NULLIF(kg_d365, 0) AS pk_d365, receita_vida / NULLIF(kg_vida, 0) AS pk_vida,
        frete_d28    / NULLIF(kg_d28,  0) AS fk_d28,  frete_d56    / NULLIF(kg_d56,  0) AS fk_d56,
        frete_d365   / NULLIF(kg_d365, 0) AS fk_d365, frete_vida   / NULLIF(kg_vida, 0) AS fk_vida
    FROM rs_kg_comp
),
f_rs_kg AS (
    SELECT seller_id,
        pk_d28  AS vlPrecoKgD28,  pk_d56  AS vlPrecoKgD56,  pk_d365 AS vlPrecoKgD365,  pk_vida AS vlPrecoKgVida,
        log1p(pk_d28)  AS vlPrecoKgAjustadoD28,  log1p(pk_d56)  AS vlPrecoKgAjustadoD56,  log1p(pk_d365) AS vlPrecoKgAjustadoD365,  log1p(pk_vida) AS vlPrecoKgAjustadoVida,
        fk_d28  AS vlFreteKgD28,  fk_d56  AS vlFreteKgD56,  fk_d365 AS vlFreteKgD365,  fk_vida AS vlFreteKgVida,
        log1p(fk_d28)  AS vlFreteKgAjustadoD28,  log1p(fk_d56)  AS vlFreteKgAjustadoD56,  log1p(fk_d365) AS vlFreteKgAjustadoD365,  log1p(fk_vida) AS vlFreteKgAjustadoVida
    FROM rs_kg
),

-- =====================================================================
-- §7 — Top 3 categorias (11) + Share das top 3 (12).
-- Por unidades; desempate unidades DESC -> pedidos DESC -> categoria ASC.
-- (cat_base e rk compartilhados pelas duas famílias.)
-- =====================================================================
top_cat_base AS (
    SELECT seller_id, categoria,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN 1 ELSE 0 END)        AS u_d28,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN order_id END) AS p_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN 1 ELSE 0 END)        AS u_d56,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN order_id END) AS p_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN 1 ELSE 0 END)        AS u_d365,
        COUNT(DISTINCT CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN order_id END) AS p_d365,
        COUNT(*)                                                                                       AS u_vida,
        COUNT(DISTINCT order_id)                                                                       AS p_vida
    FROM base
    GROUP BY seller_id, categoria
),
top_cat_rk AS (
    SELECT seller_id, categoria, u_d28, u_d56, u_d365, u_vida,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d28  DESC, p_d28  DESC, categoria ASC) AS rk_d28,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d56  DESC, p_d56  DESC, categoria ASC) AS rk_d56,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_d365 DESC, p_d365 DESC, categoria ASC) AS rk_d365,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY u_vida DESC, p_vida DESC, categoria ASC) AS rk_vida
    FROM top_cat_base
),
f_top_cat AS (
    SELECT
        seller_id,
        -- descTopCategoria{1,2,3} (11)
        MAX(CASE WHEN rk_d28 =1 AND u_d28 >0 THEN categoria END) AS descTopCategoria1D28,
        MAX(CASE WHEN rk_d56 =1 AND u_d56 >0 THEN categoria END) AS descTopCategoria1D56,
        MAX(CASE WHEN rk_d365=1 AND u_d365>0 THEN categoria END) AS descTopCategoria1D365,
        MAX(CASE WHEN rk_vida=1 AND u_vida>0 THEN categoria END) AS descTopCategoria1Vida,
        MAX(CASE WHEN rk_d28 =2 AND u_d28 >0 THEN categoria END) AS descTopCategoria2D28,
        MAX(CASE WHEN rk_d56 =2 AND u_d56 >0 THEN categoria END) AS descTopCategoria2D56,
        MAX(CASE WHEN rk_d365=2 AND u_d365>0 THEN categoria END) AS descTopCategoria2D365,
        MAX(CASE WHEN rk_vida=2 AND u_vida>0 THEN categoria END) AS descTopCategoria2Vida,
        MAX(CASE WHEN rk_d28 =3 AND u_d28 >0 THEN categoria END) AS descTopCategoria3D28,
        MAX(CASE WHEN rk_d56 =3 AND u_d56 >0 THEN categoria END) AS descTopCategoria3D56,
        MAX(CASE WHEN rk_d365=3 AND u_d365>0 THEN categoria END) AS descTopCategoria3D365,
        MAX(CASE WHEN rk_vida=3 AND u_vida>0 THEN categoria END) AS descTopCategoria3Vida,
        -- vlShareTopCategoria{1,2,3} (12) — *1.0 força divisão real (consistente
        -- com 12_vlShareTopCategoria.sql; inofensivo no Spark, correto no SQLite)
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
    FROM top_cat_rk
    GROUP BY seller_id
),

-- =====================================================================
-- Extra — Missingness de cadastro (13) — Vida, PRODUTO DISTINTO.
-- categoria_raw (NULL importa aqui, ao contrário do COALESCE de §1/§2/§7).
-- =====================================================================
prod_cadastro AS (
    SELECT DISTINCT seller_id, product_id, categoria_raw, desc_len, fotos, w
    FROM base
    WHERE tem_produto
),
f_missing AS (
    SELECT
        seller_id,
        AVG(CASE WHEN categoria_raw IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemCategoria,
        AVG(CASE WHEN desc_len      IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemDescricao,
        AVG(CASE WHEN fotos         IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemFoto,
        AVG(CASE WHEN w             IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemPeso
    FROM prod_cadastro
    GROUP BY seller_id
)

-- =====================================================================
-- TABELÃO FINAL — spine LEFT JOIN de todas as famílias por seller_id.
-- COALESCE só onde o script original devolve 0 p/ ausência (§2 concorrência);
-- demais ausências permanecem NULL (sem produto/peso/categoria na janela).
-- =====================================================================
SELECT
    s.seller_id,

    -- §1 Diversidade de catálogo
    d.vlCategoriasDistintasD28, d.vlCategoriasDistintasD56, d.vlCategoriasDistintasD365, d.vlCategoriasDistintasVida,
    d.vlProdutosDistintosD28,   d.vlProdutosDistintosD56,   d.vlProdutosDistintosD365,   d.vlProdutosDistintosVida,

    -- §2 Concorrência indireta (mesma categoria) — ausência -> 0
    COALESCE(cc.vlContagemCategoriaConcorrentesD28,  0) AS vlContagemCategoriaConcorrentesD28,
    COALESCE(cc.vlContagemCategoriaConcorrentesD56,  0) AS vlContagemCategoriaConcorrentesD56,
    COALESCE(cc.vlContagemCategoriaConcorrentesD365, 0) AS vlContagemCategoriaConcorrentesD365,
    COALESCE(cc.vlContagemCategoriaConcorrentesVida, 0) AS vlContagemCategoriaConcorrentesVida,

    -- §2 Concorrência direta (mesmo product_id) — ausência -> 0
    COALESCE(cp.vlContagemProdutosConcorrentesD28,  0) AS vlContagemProdutosConcorrentesD28,
    COALESCE(cp.vlContagemProdutosConcorrentesD56,  0) AS vlContagemProdutosConcorrentesD56,
    COALESCE(cp.vlContagemProdutosConcorrentesD365, 0) AS vlContagemProdutosConcorrentesD365,
    COALESCE(cp.vlContagemProdutosConcorrentesVida, 0) AS vlContagemProdutosConcorrentesVida,

    -- §3 Caracteres da descrição (Vida)
    dc.vlMediaCaracteresDescricao, dc.vlMedianaCaracteresDescricao,
    dc.vl25CaracteresDescricao, dc.vl50CaracteresDescricao, dc.vl75CaracteresDescricao,
    dc.vlMinCaracteresDescricao, dc.vlMaxCaracteresDescricao,

    -- §3 Média de fotos por produto (Vida)
    ft.vlMediaFotosProduto,

    -- §4 Peso do produto (distribuição ESTÁTICA por produto distinto + total por unidade, 4 janelas)
    pe.vlMediaPesoProduto, pe.vlMedianaPesoProduto, pe.vl25PesoProduto, pe.vl50PesoProduto,
    pe.vl75PesoProduto, pe.vlMinPesoProduto, pe.vlMaxPesoProduto,
    pt.tot_d28 AS vlTotalPesoProdutosD28, pt.tot_d56 AS vlTotalPesoProdutosD56, pt.tot_d365 AS vlTotalPesoProdutosD365, pt.tot_vida AS vlTotalPesoProdutosVida,

    -- §5 Cubagem (média ESTÁTICA por produto distinto + total por unidade, 4 janelas)
    cb.vlMediaCubagemProdutos,
    ct.tot_d28 AS vlTotalCubagemProdutosD28, ct.tot_d56 AS vlTotalCubagemProdutosD56, ct.tot_d365 AS vlTotalCubagemProdutosD365, ct.tot_vida AS vlTotalCubagemProdutosVida,

    -- §6 Preço por kg (cru + Ajustado log1p)
    rk.vlPrecoKgD28, rk.vlPrecoKgD56, rk.vlPrecoKgD365, rk.vlPrecoKgVida,
    rk.vlPrecoKgAjustadoD28, rk.vlPrecoKgAjustadoD56, rk.vlPrecoKgAjustadoD365, rk.vlPrecoKgAjustadoVida,

    -- §6 Frete por kg (cru + Ajustado log1p)
    rk.vlFreteKgD28, rk.vlFreteKgD56, rk.vlFreteKgD365, rk.vlFreteKgVida,
    rk.vlFreteKgAjustadoD28, rk.vlFreteKgAjustadoD56, rk.vlFreteKgAjustadoD365, rk.vlFreteKgAjustadoVida,

    -- §7 Top 3 categorias (nome)
    tc.descTopCategoria1D28, tc.descTopCategoria1D56, tc.descTopCategoria1D365, tc.descTopCategoria1Vida,
    tc.descTopCategoria2D28, tc.descTopCategoria2D56, tc.descTopCategoria2D365, tc.descTopCategoria2Vida,
    tc.descTopCategoria3D28, tc.descTopCategoria3D56, tc.descTopCategoria3D365, tc.descTopCategoria3Vida,

    -- §7 Share das top 3 categorias
    tc.vlShareTopCategoria1D28, tc.vlShareTopCategoria1D56, tc.vlShareTopCategoria1D365, tc.vlShareTopCategoria1Vida,
    tc.vlShareTopCategoria2D28, tc.vlShareTopCategoria2D56, tc.vlShareTopCategoria2D365, tc.vlShareTopCategoria2Vida,
    tc.vlShareTopCategoria3D28, tc.vlShareTopCategoria3D56, tc.vlShareTopCategoria3D365, tc.vlShareTopCategoria3Vida,

    -- Extra — Missingness de cadastro (Vida)
    mi.vlShareProdutosSemCategoria, mi.vlShareProdutosSemDescricao, mi.vlShareProdutosSemFoto, mi.vlShareProdutosSemPeso

FROM spine s
LEFT JOIN f_diversidade    d  ON d.seller_id  = s.seller_id
LEFT JOIN f_conc_categoria cc ON cc.seller_id = s.seller_id
LEFT JOIN f_conc_produto   cp ON cp.seller_id = s.seller_id
LEFT JOIN f_descricao      dc ON dc.seller_id = s.seller_id
LEFT JOIN f_fotos          ft ON ft.seller_id = s.seller_id
LEFT JOIN f_peso           pe ON pe.seller_id = s.seller_id
LEFT JOIN peso_total       pt ON pt.seller_id = s.seller_id
LEFT JOIN f_cubagem        cb ON cb.seller_id = s.seller_id
LEFT JOIN cub_total        ct ON ct.seller_id = s.seller_id
LEFT JOIN f_rs_kg          rk ON rk.seller_id = s.seller_id
LEFT JOIN f_top_cat        tc ON tc.seller_id = s.seller_id
LEFT JOIN f_missing        mi ON mi.seller_id = s.seller_id;
