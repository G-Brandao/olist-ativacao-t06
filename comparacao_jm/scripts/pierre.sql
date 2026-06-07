-- 1 Tabela base de pedidos com filtro de safra embutido
WITH tb_pedidos AS (
  SELECT *
  FROM workspace.olist.orders
  WHERE order_purchase_timestamp < deploy_date
),

-- 2 Tabela base de itens
tb_itens AS (
  SELECT
    i.seller_id
    , o.order_id
    , o.order_purchase_timestamp
    , i.order_item_id
    , IFNULL(p.product_category_name, 'NA') AS product_category_name
    , i.product_id
    , i.price
    , i.freight_value
  FROM tb_pedidos AS o
  INNER JOIN olist.order_items AS i
    ON i.order_id = o.order_id
  LEFT JOIN olist.products AS p
    ON p.product_id = i.product_id
),

-- 3 Listagem de seller_id e product_category_name. Flag 1 caso tenha tido vendas na janela, caso contrário 0.
tb_seller_category_list AS (
    SELECT
        seller_id
        , product_category_name
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN 1 ELSE 0 END) AS hadCatSale14d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN 1 ELSE 0 END) AS hadCatSale28d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN 1 ELSE 0 END) AS hadCatSale56d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN 1 ELSE 0 END) AS hadCatSale365d
        , 1 AS hadCatSaleVida
    FROM tb_itens
    GROUP BY seller_id, product_category_name
    ORDER BY seller_id, product_category_name
),

-- 4 Listagem de seller_id e product_id. Flag 1 caso tenha tido vendas na janela, caso contrário 0.
tb_seller_product_list AS (
    SELECT
        seller_id
        , product_id
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN 1 ELSE 0 END) AS hadProdSale14d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN 1 ELSE 0 END) AS hadProdSale28d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN 1 ELSE 0 END) AS hadProdSale56d
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN 1 ELSE 0 END) AS hadProdSale365d
        , 1 AS hadProdSaleVida
    FROM tb_itens
    GROUP BY seller_id, product_id
    ORDER BY seller_id, product_id
),

-- 5 Contagem de vendedores distintos por categoria
tb_category_window AS (
  SELECT
    product_category_name
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN SELLER_ID END), 0) AS ctDistinctCatSellers14d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN SELLER_ID END), 0) AS ctDistinctCatSellers28d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN SELLER_ID END), 0) AS ctDistinctCatSellers56d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN SELLER_ID END), 0) AS ctDistinctCatSellers365d
    , IFNULL(COUNT(DISTINCT SELLER_ID), 0) AS ctDistinctCatSellersVida
  FROM tb_itens
  GROUP BY product_category_name
),

-- 6 Contagem de vendedores distintos por produto
tb_product_window AS (
  SELECT
    product_id
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN SELLER_ID END), 0) AS ctDistinctProdSellers14d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN SELLER_ID END), 0) AS ctDistinctProdSellers28d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN SELLER_ID END), 0) AS ctDistinctProdSellers56d
    , IFNULL(COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN SELLER_ID END), 0) AS ctDistinctProdSellers365d
    , IFNULL(COUNT(DISTINCT SELLER_ID), 0) AS ctDistinctProdSellersVida
  FROM tb_itens
  GROUP BY product_id
),

-- 7 Contagem de concorrentes de categorias por seller_id (3 + 5)
tb_category_competitity AS (
    SELECT
        t1.seller_id
        , SUM(ctDistinctCatSellers14d - hadCatSale14d) AS vlContagemCategoriaConcorrentesD14
        , SUM(ctDistinctCatSellers28d - hadCatSale28d) AS vlContagemCategoriaConcorrentesD28
        , SUM(ctDistinctCatSellers56d - hadCatSale56d) AS vlContagemCategoriaConcorrentesD56
        , SUM(ctDistinctCatSellers365d - hadCatSale365d) AS vlContagemCategoriaConcorrentesD365
        , SUM(ctDistinctCatSellersVida - hadCatSaleVida) AS vlContagemCategoriaConcorrentesVida
    FROM tb_seller_category_list AS t1
    LEFT JOIN tb_category_window AS t2
        ON t1.product_category_name = t2.product_category_name
    GROUP BY t1.seller_id
),

-- 8 Contagem de concorrentes de produtos por seller_id (4 + 6)
tb_product_competitity AS (
    SELECT
        t1.seller_id
        , SUM(ctDistinctProdSellers14d - hadProdSale14d) AS vlContagemProdutosConcorrentesD14
        , SUM(ctDistinctProdSellers28d - hadProdSale28d) AS vlContagemProdutosConcorrentesD28
        , SUM(ctDistinctProdSellers56d - hadProdSale56d) AS vlContagemProdutosConcorrentesD56
        , SUM(ctDistinctProdSellers365d - hadProdSale365d) AS vlContagemProdutosConcorrentesD365
        , SUM(ctDistinctProdSellersVida - hadProdSaleVida) AS vlContagemProdutosConcorrentesVida
    FROM tb_seller_product_list AS t1
    LEFT JOIN tb_product_window AS t2
        ON t1.product_id = t2.product_id
    GROUP BY t1.seller_id
),

-- 9 Contagem de quantidade de categorias e produtos distintos nas janelas
tb_seller_cat_prod_count AS (
    SELECT
        seller_id
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_category_name END) AS vlCategoriasDistintasD14
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_category_name END) AS vlCategoriasDistintasD28
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_category_name END) AS vlCategoriasDistintasD56
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_category_name END) AS vlCategoriasDistintasD365
        , COUNT(DISTINCT product_category_name) AS vlCategoriasDistintasVida
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_id END) AS vlProdutosDistintosD14
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_id END) AS vlProdutosDistintosD28
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_id END) AS vlProdutosDistintosD56
        , COUNT(DISTINCT CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_id END) AS vlProdutosDistintosD365
        , COUNT(DISTINCT product_id) AS vlProdutosDistintosVida
    FROM tb_itens
    GROUP BY seller_id
),

-- 10 Listagem de produtos distintos vendidos pelos seller_id
tb_distinct_seller_prod_description AS (
    SELECT DISTINCT
        t1.seller_id
        , t1.product_id
        , IFNULL(t2.product_description_lenght, 0) AS product_description_length
        , IFNULL(t2.product_photos_qty, 0) AS product_photos_qty
    FROM tb_itens AS t1
    LEFT JOIN olist.products AS t2
        ON t1.product_id = t2.product_id
),

-- 11 Cálculo de métricas de descrição e fotos de produtos (10)
tb_atributos_produtos AS (
    SELECT
        seller_id
        , MEAN(product_description_length) AS vlMediaCaracteresDescricao
        , MIN(product_description_length) AS vlMinCaracteresDescricao
        , PERCENTILE(product_description_length, 0.25) AS vlP25CaracteresDescricao
        , MEDIAN(product_description_length) AS vlMedianaCaracteresDescricao
        , PERCENTILE(product_description_length, 0.75) AS vlP75CaracteresDescricao
        , MAX(product_description_length) AS vlMaxCaracteresDescricao
        , MEAN(product_photos_qty) AS vlMediaFotosProduto
    FROM tb_distinct_seller_prod_description
    GROUP BY seller_id
),

-- 12 Listagem de peso em kg e cubagem em cm3 dos pedidos de cada item
tb_seller_prod_dimensions_and_weight AS (
    SELECT
        t1.seller_id
        , order_purchase_timestamp
        , t1.product_id
        , t2.product_weight_g / 1000 AS product_weight_kg
        , (t2.product_length_cm / 1) * (t2.product_height_cm / 1) * (t2.product_width_cm / 1) AS product_cubic_volume_cm3
    FROM tb_itens AS t1
    LEFT JOIN olist.products AS t2
        ON t1.product_id = t2.product_id
),

-- 13 Cálculo de métricas de peso e cubagem de produtos (12)
tb_peso_e_cubagem_dos_produtos AS (
    SELECT
        seller_id
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END) AS vlMediaPesoProdutoD14
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END) AS vlMediaPesoProdutoD28
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END) AS vlMediaPesoProdutoD56
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END) AS vlMediaPesoProdutoD365
        , MEAN(product_weight_kg) AS vlMediaPesoProdutoVida
        , MIN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END) AS vlMinPesoProdutoD14
        , MIN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END) AS vlMinPesoProdutoD28
        , MIN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END) AS vlMinPesoProdutoD56
        , MIN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END) AS vlMinPesoProdutoD365
        , MIN(product_weight_kg) AS vlMinPesoProdutoVida
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END, 0.25) AS vlP25PesoProdutoD14
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END, 0.25) AS vlP25PesoProdutoD28
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END, 0.25) AS vlP25PesoProdutoD56
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END, 0.25) AS vlP25PesoProdutoD365
        , PERCENTILE(product_weight_kg, 0.25) AS vlP25PesoProdutoVida
        , MEDIAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END) AS vlMedianaPesoProdutoD14
        , MEDIAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END) AS vlMedianaPesoProdutoD28
        , MEDIAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END) AS vlMedianaPesoProdutoD56
        , MEDIAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END) AS vlMedianaPesoProdutoD365
        , MEDIAN(product_weight_kg) AS vlMedianaPesoProdutoVida
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END, 0.75) AS vlP75PesoProdutoD14
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END, 0.75) AS vlP75PesoProdutoD28
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END, 0.75) AS vlP75PesoProdutoD56
        , PERCENTILE(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END, 0.75) AS vlP75PesoProdutoD365
        , PERCENTILE(product_weight_kg, 0.75) AS vlP75PesoProdutoVida
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg END) AS vlMaxPesoProdutoD14
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg END) AS vlMaxPesoProdutoD28
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg END) AS vlMaxPesoProdutoD56
        , MAX(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg END) AS vlMaxPesoProdutoD365
        , MAX(product_weight_kg) AS vlMaxPesoProdutoVida
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_weight_kg ELSE 0 END) AS vlTotalPesoProdutoD14
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_weight_kg ELSE 0 END) AS vlTotalPesoProdutoD28
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_weight_kg ELSE 0 END) AS vlTotalPesoProdutoD56
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_weight_kg ELSE 0 END) AS vlTotalPesoProdutoD365
        , SUM(product_weight_kg) AS vlTotalPesoProdutoVida

        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_cubic_volume_cm3 END) AS vlMediaCubagemProdutoD14
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_cubic_volume_cm3 END) AS vlMediaCubagemProdutoD28
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_cubic_volume_cm3 END) AS vlMediaCubagemProdutoD56
        , MEAN(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_cubic_volume_cm3 END) AS vlMediaCubagemProdutoD365
        , MEAN(product_cubic_volume_cm3) AS vlMediaCubagemProdutoVida
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN product_cubic_volume_cm3 ELSE 0 END) AS vlTotalCubagemProdutoD14
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN product_cubic_volume_cm3 ELSE 0 END) AS vlTotalCubagemProdutoD28
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN product_cubic_volume_cm3 ELSE 0 END) AS vlTotalCubagemProdutoD56
        , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN product_cubic_volume_cm3 ELSE 0 END) AS vlTotalCubagemProdutoD365
        , SUM(product_cubic_volume_cm3) AS vlTotalCubagemProdutoVida
    FROM tb_seller_prod_dimensions_and_weight
    GROUP BY seller_id
),

-- 14 Receita e frete por janela
tb_receita_e_frete_por_janela AS (
  SELECT
    seller_id
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN COALESCE(price, 0) ELSE 0 END) AS vlReceitaTotD14
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN COALESCE(price, 0) ELSE 0 END) AS vlReceitaTotD28
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN COALESCE(price, 0) ELSE 0 END) AS vlReceitaTotD56
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN COALESCE(price, 0) ELSE 0 END) AS vlReceitaTotD365
    , SUM(price) AS vlReceitaTotVida
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14) THEN COALESCE(freight_value, 0) ELSE 0 END) AS vlFreteTotD14
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28) THEN COALESCE(freight_value, 0) ELSE 0 END) AS vlFreteTotD28
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56) THEN COALESCE(freight_value, 0) ELSE 0 END) AS vlFreteTotD56
    , SUM(CASE WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365) THEN COALESCE(freight_value, 0) ELSE 0 END) AS vlFreteTotD365
    , SUM(freight_value) AS vlFreteTotVida
  FROM tb_itens
  GROUP BY seller_id
),
-- 15 tb_indicadores_por_kg (14)
tb_indicadores_por_kg AS (
  SELECT
    t1.seller_id
    , t1.vlReceitaTotD14 / NULLIF(t2.vlTotalPesoProdutoD14, 0) AS vlPrecoKgD14
    , t1.vlReceitaTotD28 / NULLIF(t2.vlTotalPesoProdutoD28, 0) AS vlPrecoKgD28
    , t1.vlReceitaTotD56 / NULLIF(t2.vlTotalPesoProdutoD56, 0) AS vlPrecoKgD56
    , t1.vlReceitaTotD365 / NULLIF(t2.vlTotalPesoProdutoD365, 0) AS vlPrecoKgD365
    , t1.vlReceitaTotVida / NULLIF(t2.vlTotalPesoProdutoVida, 0) AS vlPrecoKgVida
    , t1.vlFreteTotD14 / NULLIF(t2.vlTotalPesoProdutoD14, 0) AS vlFreteKgD14
    , t1.vlFreteTotD28 / NULLIF(t2.vlTotalPesoProdutoD28, 0) AS vlFreteKgD28
    , t1.vlFreteTotD56 / NULLIF(t2.vlTotalPesoProdutoD56, 0) AS vlFreteKgD56
    , t1.vlFreteTotD365 / NULLIF(t2.vlTotalPesoProdutoD365, 0) AS vlFreteKgD365
    , t1.vlFreteTotVida / NULLIF(t2.vlTotalPesoProdutoVida, 0) AS vlFreteKgVida
  FROM tb_receita_e_frete_por_janela AS t1
  LEFT JOIN tb_peso_e_cubagem_dos_produtos AS t2
    ON t1.seller_id = t2.seller_id
),

-- 16 Lista de sellers distintos
tb_sellers AS (
  SELECT DISTINCT
    seller_id
  FROM tb_itens
),

-- 17 Receita por seller e categoria de produto
tb_cat_receita AS (
  SELECT
    seller_id,
    product_category_name,

    SUM(
      CASE 
        WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 14)
        THEN COALESCE(price, 0)
        ELSE 0
      END
    ) AS vlTotalReceitaD14,

    SUM(
      CASE 
        WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 28)
        THEN COALESCE(price, 0)
        ELSE 0
      END
    ) AS vlTotalReceitaD28,

    SUM(
      CASE 
        WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 56)
        THEN COALESCE(price, 0)
        ELSE 0
      END
    ) AS vlTotalReceitaD56,

    SUM(
      CASE 
        WHEN order_purchase_timestamp >= DATE_SUB(deploy_date, 365)
        THEN COALESCE(price, 0)
        ELSE 0
      END
    ) AS vlTotalReceitaD365,

    SUM(COALESCE(price, 0)) AS vlTotalReceitaVida

  FROM tb_itens
  GROUP BY seller_id, product_category_name
),

-- 18 Forma longa de tabela seller x product_category_name x janela x receita (17)
tb_cat_janela AS (
  SELECT seller_id, product_category_name, 'D14' AS janela, vlTotalReceitaD14 AS vlReceitaCategoria
  FROM tb_cat_receita

  UNION ALL

  SELECT seller_id, product_category_name, 'D28' AS janela, vlTotalReceitaD28 AS vlReceitaCategoria
  FROM tb_cat_receita

  UNION ALL

  SELECT seller_id, product_category_name, 'D56' AS janela, vlTotalReceitaD56 AS vlReceitaCategoria
  FROM tb_cat_receita

  UNION ALL

  SELECT seller_id, product_category_name, 'D365' AS janela, vlTotalReceitaD365 AS vlReceitaCategoria
  FROM tb_cat_receita

  UNION ALL

  SELECT seller_id, product_category_name, 'Vida' AS janela, vlTotalReceitaVida AS vlReceitaCategoria
  FROM tb_cat_receita
),

-- 19 Tabela base para gerar ranking. Cálculo de receita total por seller_id e janela (18)
tb_rank_base AS (
  SELECT
    seller_id,
    product_category_name,
    janela,
    vlReceitaCategoria,

    SUM(vlReceitaCategoria) OVER (
      PARTITION BY seller_id, janela
    ) AS vlReceitaSellerJanela

  FROM tb_cat_janela
  WHERE vlReceitaCategoria > 0
),

-- 20 Ranking de categoria por seller_id e janela. Cálculo de share
tb_rank AS (
  SELECT
    seller_id,
    product_category_name,
    janela,
    vlReceitaCategoria,
    vlReceitaSellerJanela,

    vlReceitaCategoria / vlReceitaSellerJanela AS shareReceitaCategoria,

    ROW_NUMBER() OVER (
      PARTITION BY seller_id, janela
      ORDER BY vlReceitaCategoria DESC, product_category_name ASC
    ) AS nrRankCategoria

  FROM tb_rank_base
),

-- 21 Tabela com top categorias e share por janela (20)
tb_top_categorias AS (
  SELECT
    s.seller_id,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 1 THEN r.product_category_name END) AS descTopCategoria1D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 1 THEN r.product_category_name END) AS descTopCategoria1D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 1 THEN r.product_category_name END) AS descTopCategoria1D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 1 THEN r.product_category_name END) AS descTopCategoria1D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 1 THEN r.product_category_name END) AS descTopCategoria1Vida,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 2 THEN r.product_category_name END) AS descTopCategoria2D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 2 THEN r.product_category_name END) AS descTopCategoria2D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 2 THEN r.product_category_name END) AS descTopCategoria2D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 2 THEN r.product_category_name END) AS descTopCategoria2D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 2 THEN r.product_category_name END) AS descTopCategoria2Vida,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 3 THEN r.product_category_name END) AS descTopCategoria3D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 3 THEN r.product_category_name END) AS descTopCategoria3D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 3 THEN r.product_category_name END) AS descTopCategoria3D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 3 THEN r.product_category_name END) AS descTopCategoria3D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 3 THEN r.product_category_name END) AS descTopCategoria3Vida,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 1 THEN r.shareReceitaCategoria END) AS shareTopCategoria1D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 1 THEN r.shareReceitaCategoria END) AS shareTopCategoria1D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 1 THEN r.shareReceitaCategoria END) AS shareTopCategoria1D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 1 THEN r.shareReceitaCategoria END) AS shareTopCategoria1D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 1 THEN r.shareReceitaCategoria END) AS shareTopCategoria1Vida,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 2 THEN r.shareReceitaCategoria END) AS shareTopCategoria2D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 2 THEN r.shareReceitaCategoria END) AS shareTopCategoria2D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 2 THEN r.shareReceitaCategoria END) AS shareTopCategoria2D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 2 THEN r.shareReceitaCategoria END) AS shareTopCategoria2D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 2 THEN r.shareReceitaCategoria END) AS shareTopCategoria2Vida,

    MAX(CASE WHEN r.janela = 'D14' AND r.nrRankCategoria = 3 THEN r.shareReceitaCategoria END) AS shareTopCategoria3D14,
    MAX(CASE WHEN r.janela = 'D28' AND r.nrRankCategoria = 3 THEN r.shareReceitaCategoria END) AS shareTopCategoria3D28,
    MAX(CASE WHEN r.janela = 'D56' AND r.nrRankCategoria = 3 THEN r.shareReceitaCategoria END) AS shareTopCategoria3D56,
    MAX(CASE WHEN r.janela = 'D365' AND r.nrRankCategoria = 3 THEN r.shareReceitaCategoria END) AS shareTopCategoria3D365,
    MAX(CASE WHEN r.janela = 'Vida' AND r.nrRankCategoria = 3 THEN r.shareReceitaCategoria END) AS shareTopCategoria3Vida

  FROM tb_sellers AS s
  LEFT JOIN tb_rank AS r
    ON s.seller_id = r.seller_id
    AND r.nrRankCategoria <= 3
  GROUP BY s.seller_id
),

tb_product_feature_store AS (
  SELECT
    t1.seller_id

    -- Diversidade de catálogo
    , t2.vlCategoriasDistintasD14
    , t2.vlCategoriasDistintasD28
    , t2.vlCategoriasDistintasD56
    , t2.vlCategoriasDistintasD365
    , t2.vlCategoriasDistintasVida
    , t2.vlProdutosDistintosD14
    , t2.vlProdutosDistintosD28
    , t2.vlProdutosDistintosD56
    , t2.vlProdutosDistintosD365
    , t2.vlProdutosDistintosVida

    -- Concorrência entre sellers
    , t3.vlContagemCategoriaConcorrentesD14
    , t3.vlContagemCategoriaConcorrentesD28
    , t3.vlContagemCategoriaConcorrentesD56
    , t3.vlContagemCategoriaConcorrentesD365
    , t3.vlContagemCategoriaConcorrentesVida
    , t4.vlContagemProdutosConcorrentesD14
    , t4.vlContagemProdutosConcorrentesD28
    , t4.vlContagemProdutosConcorrentesD56
    , t4.vlContagemProdutosConcorrentesD365
    , t4.vlContagemProdutosConcorrentesVida

    -- Atributos de produto
    , ROUND(t5.vlMediaCaracteresDescricao, 1) AS vlMediaCaracteresDescricao
    , ROUND(t5.vlMedianaCaracteresDescricao, 1) AS vlMedianaCaracteresDescricao
    , ROUND(t5.vlP25CaracteresDescricao, 1) AS vlP25CaracteresDescricao
    , ROUND(t5.vlP75CaracteresDescricao, 1) AS vlP75CaracteresDescricao
    , ROUND(t5.vlMinCaracteresDescricao, 1) AS vlMinCaracteresDescricao
    , ROUND(t5.vlMaxCaracteresDescricao, 1) AS vlMaxCaracteresDescricao
    , ROUND(t5.vlMediaFotosProduto, 1) AS vlMediaFotosProduto

    -- Peso dos produtos
    , ROUND(t6.vlMediaPesoProdutoD14, 3) AS vlMediaPesoProdutoD14
    , ROUND(t6.vlMediaPesoProdutoD28, 3) AS vlMediaPesoProdutoD28
    , ROUND(t6.vlMediaPesoProdutoD56, 3) AS vlMediaPesoProdutoD56
    , ROUND(t6.vlMediaPesoProdutoD365, 3) AS vlMediaPesoProdutoD365
    , ROUND(t6.vlMediaPesoProdutoVida, 3) AS vlMediaPesoProdutoVida
    , ROUND(t6.vlMedianaPesoProdutoD14, 3) AS vlMedianaPesoProdutoD14
    , ROUND(t6.vlMedianaPesoProdutoD28, 3) AS vlMedianaPesoProdutoD28
    , ROUND(t6.vlMedianaPesoProdutoD56, 3) AS vlMedianaPesoProdutoD56
    , ROUND(t6.vlMedianaPesoProdutoD365, 3) AS vlMedianaPesoProdutoD365
    , ROUND(t6.vlMedianaPesoProdutoVida, 3) AS vlMedianaPesoProdutoVida
    , ROUND(t6.vlP25PesoProdutoD14, 3) AS vlP25PesoProdutoD14
    , ROUND(t6.vlP25PesoProdutoD28, 3) AS vlP25PesoProdutoD28
    , ROUND(t6.vlP25PesoProdutoD56, 3) AS vlP25PesoProdutoD56
    , ROUND(t6.vlP25PesoProdutoD365, 3) AS vlP25PesoProdutoD365
    , ROUND(t6.vlP25PesoProdutoVida, 3) AS vlP25PesoProdutoVida
    , ROUND(t6.vlP75PesoProdutoD14, 3) AS vlP75PesoProdutoD14
    , ROUND(t6.vlP75PesoProdutoD28, 3) AS vlP75PesoProdutoD28
    , ROUND(t6.vlP75PesoProdutoD56, 3) AS vlP75PesoProdutoD56
    , ROUND(t6.vlP75PesoProdutoD365, 3) AS vlP75PesoProdutoD365
    , ROUND(t6.vlP75PesoProdutoVida, 3) AS vlP75PesoProdutoVida
    , t6.vlMinPesoProdutoD14
    , t6.vlMinPesoProdutoD28
    , t6.vlMinPesoProdutoD56
    , t6.vlMinPesoProdutoD365
    , t6.vlMinPesoProdutoVida
    , t6.vlMaxPesoProdutoD14
    , t6.vlMaxPesoProdutoD28
    , t6.vlMaxPesoProdutoD56
    , t6.vlMaxPesoProdutoD365
    , t6.vlMaxPesoProdutoVida
    , ROUND(t6.vlTotalPesoProdutoD14, 3) AS vlTotalPesoProdutoD14
    , ROUND(t6.vlTotalPesoProdutoD28, 3) AS vlTotalPesoProdutoD28
    , ROUND(t6.vlTotalPesoProdutoD56, 3) AS vlTotalPesoProdutoD56
    , ROUND(t6.vlTotalPesoProdutoD365, 3) AS vlTotalPesoProdutoD365
    , ROUND(t6.vlTotalPesoProdutoVida, 3) AS vlTotalPesoProdutoVida

    -- Cubagem dos produtos
    , ROUND(t6.vlMediaCubagemProdutoD14, 1) AS vlMediaCubagemProdutoD14
    , ROUND(t6.vlMediaCubagemProdutoD28, 1) AS vlMediaCubagemProdutoD28
    , ROUND(t6.vlMediaCubagemProdutoD56, 1) AS vlMediaCubagemProdutoD56
    , ROUND(t6.vlMediaCubagemProdutoD365, 1) AS vlMediaCubagemProdutoD365
    , ROUND(t6.vlMediaCubagemProdutoVida, 1) AS vlMediaCubagemProdutoVida
    , ROUND(t6.vlTotalCubagemProdutoD14, 1) AS vlTotalCubagemProdutoD14
    , ROUND(t6.vlTotalCubagemProdutoD28, 1) AS vlTotalCubagemProdutoD28
    , ROUND(t6.vlTotalCubagemProdutoD56, 1) AS vlTotalCubagemProdutoD56
    , ROUND(t6.vlTotalCubagemProdutoD365, 1) AS vlTotalCubagemProdutoD365
    , ROUND(t6.vlTotalCubagemProdutoVida, 1) AS vlTotalCubagemProdutoVida

    -- Indicadores por kg
    , ROUND(t7.vlPrecoKgD14, 2) AS vlPrecoKgD14
    , ROUND(t7.vlPrecoKgD28, 2) AS vlPrecoKgD28
    , ROUND(t7.vlPrecoKgD56, 2) AS vlPrecoKgD56
    , ROUND(t7.vlPrecoKgD365, 2) AS vlPrecoKgD365
    , ROUND(t7.vlPrecoKgVida, 2) AS vlPrecoKgVida
    , ROUND(t7.vlFreteKgD14, 2) AS vlFreteKgD14
    , ROUND(t7.vlFreteKgD28, 2) AS vlFreteKgD28
    , ROUND(t7.vlFreteKgD56, 2) AS vlFreteKgD56
    , ROUND(t7.vlFreteKgD365, 2) AS vlFreteKgD365
    , ROUND(t7.vlFreteKgVida, 2) AS vlFreteKgVida

    -- Top 3 categorias do seller
    , t8.descTopCategoria1D14
    , t8.descTopCategoria1D28
    , t8.descTopCategoria1D56
    , t8.descTopCategoria1D365
    , t8.descTopCategoria1Vida
    , t8.descTopCategoria2D14
    , t8.descTopCategoria2D28
    , t8.descTopCategoria2D56
    , t8.descTopCategoria2D365
    , t8.descTopCategoria2Vida
    , t8.descTopCategoria3D14
    , t8.descTopCategoria3D28
    , t8.descTopCategoria3D56
    , t8.descTopCategoria3D365
    , t8.descTopCategoria3Vida
    , ROUND(t8.shareTopCategoria1D14, 3) AS shareTopCategoria1D14
    , ROUND(t8.shareTopCategoria1D28, 3) AS shareTopCategoria1D28
    , ROUND(t8.shareTopCategoria1D56, 3) AS shareTopCategoria1D56
    , ROUND(t8.shareTopCategoria1D365, 3) AS shareTopCategoria1D365
    , ROUND(t8.shareTopCategoria1Vida, 3) AS shareTopCategoria1Vida
    , ROUND(t8.shareTopCategoria2D14, 3) AS shareTopCategoria2D14
    , ROUND(t8.shareTopCategoria2D28, 3) AS shareTopCategoria2D28
    , ROUND(t8.shareTopCategoria2D56, 3) AS shareTopCategoria2D56
    , ROUND(t8.shareTopCategoria2D365, 3) AS shareTopCategoria2D365
    , ROUND(t8.shareTopCategoria2Vida, 3) AS shareTopCategoria2Vida
    , ROUND(t8.shareTopCategoria3D14, 3) AS shareTopCategoria3D14
    , ROUND(t8.shareTopCategoria3D28, 3) AS shareTopCategoria3D28
    , ROUND(t8.shareTopCategoria3D56, 3) AS shareTopCategoria3D56
    , ROUND(t8.shareTopCategoria3D365, 3) AS shareTopCategoria3D365
    , ROUND(t8.shareTopCategoria3Vida, 3) AS shareTopCategoria3Vida
  FROM tb_sellers AS t1
  LEFT JOIN tb_seller_cat_prod_count AS t2
    ON t1.seller_id = t2.seller_id
  LEFT JOIN tb_category_competitity AS t3
    ON t1.seller_id = t3.seller_id
  LEFT JOIN tb_product_competitity AS t4
    ON t1.seller_id = t4.seller_id
  LEFT JOIN tb_atributos_produtos AS t5
    ON t1.seller_id = t5.seller_id
  LEFT JOIN tb_peso_e_cubagem_dos_produtos AS t6
    ON t1.seller_id = t6.seller_id
  LEFT JOIN tb_indicadores_por_kg AS t7
    ON t1.seller_id = t7.seller_id
  LEFT JOIN tb_top_categorias AS t8
    ON t1.seller_id = t8.seller_id
)

SELECT *
FROM tb_product_feature_store;