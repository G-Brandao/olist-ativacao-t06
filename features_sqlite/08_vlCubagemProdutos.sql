-- =====================================================================
-- vlCubagemProdutos  (variaveis.md §5) — Cubagem (volume da caixa de envio)
-- Grão de saída: 1 linha por seller_id
-- Dialeto: SQLite (validação local)
-- ---------------------------------------------------------------------
-- Colunas:
--   MÉDIA (ESTÁTICA, sem sufixo — cubagem é atributo do produto):
--     vlMediaCubagemProdutos                           -> em cm³
--   TOTAL (4 janelas D28/D56/D365/Vida — volume embarcado muda no tempo):
--     vlTotalCubagemProdutos{W}                        -> em cm³
-- ---------------------------------------------------------------------
-- DECISÃO DO CLIENTE (atributo de produto não varia no tempo):
--   cubagem = product_length_cm × product_height_cm × product_width_cm, todas
--   vindas de `products` (1 linha por product_id) — IMUTÁVEL. A MÉDIA é
--   ESTÁTICA: calculada UMA vez sobre os PRODUTOS DISTINTOS já vendidos pelo
--   seller (toda a vida < corte), alinhando com descrição/fotos (§3). Antes
--   havia 4 janelas redundantes (mesmo atributo) — eliminadas.
--   O TOTAL é EXCEÇÃO e mantém 4 janelas: é o VOLUME EMBARCADO (soma por
--   UNIDADE vendida), cresce com novas vendas — mesma lógica dos R$/kg (§6).
-- Data     : order_purchase_timestamp < {data_corte}.
-- Nulos    : qualquer dimensão NULL -> cubagem NULL (ignorada na média e no
--            total); seller sem produto com cubagem -> média NULL; janela sem
--            venda -> total NULL.
-- Parâmetro: {data_corte} (ex. 2018-07-01).
-- =====================================================================

-- 1) vendas: uma linha por unidade vendida, com a cubagem do produto.
WITH vendas AS (
    SELECT oi.seller_id, oi.product_id,
           (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cub,
           o.order_purchase_timestamp                                       AS dt_venda
    FROM order_items oi
    JOIN orders   o ON o.order_id   = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < '{data_corte}'
),
-- 2) TOTAL por UNIDADE (volume embarcado), 4 janelas. Cada venda soma uma vez
--    — total cresce no tempo, por isso mantém D28/D56/D365/Vida.
total AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-28 days')  THEN cub END) AS tot_d28,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-56 days')  THEN cub END) AS tot_d56,
        SUM(CASE WHEN dt_venda >= datetime('{data_corte}','-365 days') THEN cub END) AS tot_d365,
        SUM(cub)                                                                      AS tot_vida
    FROM vendas
    GROUP BY seller_id
),
-- 3) PRODUTOS DISTINTOS por seller (toda a vida; cub constante por produto).
--    Base ESTÁTICA da média — sem janelas, pois a cubagem não muda.
produtos AS (
    SELECT DISTINCT seller_id, product_id, cub
    FROM vendas
    WHERE cub IS NOT NULL
),
-- 4) média estática da cubagem sobre os produtos distintos.
media AS (
    SELECT seller_id, AVG(cub) AS med_vida
    FROM produtos
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT
    s.seller_id,
    m.med_vida AS vlMediaCubagemProdutos,
    t.tot_d28  AS vlTotalCubagemProdutosD28,
    t.tot_d56  AS vlTotalCubagemProdutosD56,
    t.tot_d365 AS vlTotalCubagemProdutosD365,
    t.tot_vida AS vlTotalCubagemProdutosVida
FROM spine s
LEFT JOIN media m ON m.seller_id = s.seller_id
LEFT JOIN total t ON t.seller_id = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- A feature é o bloco 1; as provas começam no bloco 2. Rode com:
--   python scripts/run_feature_sqlite.py <este_arquivo> --list
--   python scripts/run_feature_sqlite.py <este_arquivo> --block 2
-- =============================================================================================

-- ----------------------- Prova A — cubagem é ESTÁTICA: D28/D56/D365/Vida dariam o MESMO valor por produto -----------------------
-- A cubagem não muda entre janelas; a janela só mudaria QUAIS SKUs entram.
SELECT oi.product_id,
       COUNT(DISTINCT p.product_length_cm * p.product_height_cm * p.product_width_cm) AS valores_distintos_de_cubagem
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
GROUP BY oi.product_id
HAVING valores_distintos_de_cubagem > 1   -- esperado: 0 linhas
LIMIT 20;

-- ----------------------- Prova B — média usa produto distinto; total usa unidade (grãos diferentes) -----------------------
SELECT oi.seller_id, oi.product_id,
       (p.product_length_cm * p.product_height_cm * p.product_width_cm) AS cubagem_cm3,
       COUNT(*) AS unidades_vendidas
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}'
GROUP BY oi.seller_id, oi.product_id, cubagem_cm3
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — qualquer dimensão NULL zera a cubagem (vira NULL, ignorada) -----------------------
SELECT COUNT(*) AS itens_vendidos,
       SUM(CASE WHEN p.product_length_cm IS NULL
                 OR p.product_height_cm IS NULL
                 OR p.product_width_cm  IS NULL THEN 1 ELSE 0 END) AS itens_dim_incompleta
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < '{data_corte}';
