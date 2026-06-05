-- =====================================================================
-- vlShareProdutosSemCadastro  (EXTRA — revisão externa, crítica 7)
-- Janela: Vida (sem sufixo)        |   Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas  : vlShareProdutosSemCategoria, vlShareProdutosSemDescricao,
--            vlShareProdutosSemFoto, vlShareProdutosSemPeso  (frações [0,1])
-- Definição: fração dos PRODUTOS DISTINTOS do seller com atributo de
--   cadastro AUSENTE (NULL). É uma feature de **missingness** — captura
--   ausência de cadastro, que a média (AVG) NÃO vê (AVG descarta NULL; em
--   `product_photos_qty` não existe valor 0, só NULL → a ausência some da
--   média de fotos/descrição). Sinal de qualidade/engajamento do seller.
-- ---------------------------------------------------------------------
-- GRÃO: atributo do PRODUTO -> PRODUTOS DISTINTOS por seller (DISTINCT
--   product_id); denominador = nº de produtos distintos do seller.
-- Data     : order_purchase_timestamp < {data_corte}.
-- ⚠ Achados no Olist (corte 2018-07-01): os 580 produtos sem categoria são
--   EXATAMENTE os mesmos sem descrição e sem foto -> as 3 colunas de
--   cadastro são colineares (idênticas) NESTE dataset; mantidas separadas
--   porque a equivalência pode quebrar num refresh. `SemPeso` é quase
--   constante (só 2 produtos sem peso) -> candidata a descarte no modelo.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) produtos: PRODUTOS DISTINTOS vendidos pelo seller (cada SKU 1x), com os
--    atributos de cadastro.
WITH produtos AS (
    SELECT DISTINCT
        oi.seller_id,
        oi.product_id,
        p.product_category_name    AS categoria,
        p.product_description_lenght AS descricao,
        p.product_photos_qty       AS fotos,
        p.product_weight_g         AS peso
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
-- 2) share de ausência por atributo = média do indicador (NULL -> 1) sobre os
--    produtos distintos. Denominador (COUNT) > 0 sempre (seller tem ≥1 venda).
SELECT
    seller_id,
    AVG(CASE WHEN categoria IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemCategoria,
    AVG(CASE WHEN descricao IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemDescricao,
    AVG(CASE WHEN fotos     IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemFoto,
    AVG(CASE WHEN peso      IS NULL THEN 1.0 ELSE 0 END) AS vlShareProdutosSemPeso
FROM produtos
GROUP BY seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — missingness é INVISÍVEL à média (fotos NULL, não 0) -----------------------
-- product_photos_qty nunca é 0 (mín=1); produtos sem cadastro têm NULL, que o
-- AVG de vlMediaFotosProduto descarta. Logo a média não enxerga a ausência.
WITH produtos AS (
    SELECT DISTINCT oi.product_id, p.product_photos_qty AS fotos
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT MIN(fotos) AS min_fotos_nao_nulo,
       SUM(CASE WHEN fotos = 0 THEN 1 ELSE 0 END)    AS produtos_fotos_zero,
       SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS produtos_fotos_null
FROM produtos;

-- ----------------------- Prova B — categoria/descrição/foto AUSENTES são os MESMOS produtos (colinearidade) -----------------------
-- Esperado: os três NULL coincidem (cadastro vazio em bloco) -> 3 shares idênticos.
WITH produtos AS (
    SELECT DISTINCT oi.product_id,
           p.product_category_name AS cat, p.product_description_lenght AS descr, p.product_photos_qty AS fotos
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
)
SELECT
    SUM(CASE WHEN cat IS NULL THEN 1 ELSE 0 END)   AS sem_categoria,
    SUM(CASE WHEN descr IS NULL THEN 1 ELSE 0 END) AS sem_descricao,
    SUM(CASE WHEN fotos IS NULL THEN 1 ELSE 0 END) AS sem_fotos,
    SUM(CASE WHEN cat IS NULL AND descr IS NULL AND fotos IS NULL THEN 1 ELSE 0 END) AS sem_os_tres,
    SUM(CASE WHEN cat IS NULL AND descr IS NOT NULL THEN 1 ELSE 0 END)               AS divergencia_cat_desc
FROM produtos;

-- ----------------------- Prova C — distribuição do share (quantos sellers têm catálogo todo sem cadastro) -----------------------
-- Esperado: ~250 sellers com share>0 e ~60 com share==1 (catálogo inteiro sem cadastro).
WITH produtos AS (
    SELECT DISTINCT oi.seller_id, oi.product_id, p.product_category_name AS cat
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
por_seller AS (
    SELECT seller_id, AVG(CASE WHEN cat IS NULL THEN 1.0 ELSE 0 END) AS share
    FROM produtos GROUP BY seller_id
)
SELECT
    SUM(CASE WHEN share > 0      THEN 1 ELSE 0 END) AS sellers_com_algum_sem_cadastro,
    SUM(CASE WHEN share >= 0.999 THEN 1 ELSE 0 END) AS sellers_catalogo_todo_sem_cadastro,
    COUNT(*)                                        AS total_sellers
FROM por_seller;
