-- =====================================================================
-- vlPesoProduto  (variaveis.md §4) — Peso dos produtos
-- Grão de saída: 1 linha por seller_id
-- Dialeto: Spark SQL (Databricks)  |  Tabelas: workspace.olist.*
-- ---------------------------------------------------------------------
-- Colunas:
--   DISTRIBUIÇÃO (ESTÁTICA, sem sufixo — peso é atributo do produto):
--     vl{Media,Mediana,25,50,75,Min,Max}PesoProduto   -> em GRAMAS
--   TOTAL (4 janelas D28/D56/D365/Vida — massa embarcada muda no tempo):
--     vlTotalPesoProdutos{W}                           -> em KG
-- ---------------------------------------------------------------------
-- DECISÃO DO CLIENTE (atributo de produto não varia no tempo):
--   Peso vem de `products` (1 linha por product_id), é IMUTÁVEL — não muda
--   entre D28/D56/D365/Vida. A DISTRIBUIÇÃO (media/mediana/percentis/min/max)
--   é ESTÁTICA: calculada UMA vez sobre os PRODUTOS DISTINTOS já vendidos pelo
--   seller (toda a vida < corte), alinhando com descrição/fotos (§3).
--   O TOTAL é EXCEÇÃO e mantém 4 janelas: é a MASSA EMBARCADA (soma por UNIDADE
--   vendida), cresce com novas vendas — mesma lógica dos R$/kg (§6).
-- Data     : order_purchase_timestamp < :data_corte.
-- Nota     : percentile() = percentil tipo-7 (ignora NULL). vlMediana == vl50.
-- Nulos    : peso NULL ignorado (2 produtos sem peso).
-- Parâmetro: widget 'data_corte' (DEFAULT '2018-07-01'), lido via :data_corte.
-- =====================================================================
CREATE WIDGET TEXT data_corte DEFAULT '2018-07-01';

WITH vendas AS (   -- uma linha por unidade vendida
    SELECT oi.seller_id, oi.product_id,
           p.product_weight_g         AS w,
           o.order_purchase_timestamp AS dt_venda
    FROM workspace.olist.order_items oi
    JOIN workspace.olist.orders   o ON o.order_id   = oi.order_id
    JOIN workspace.olist.products p ON p.product_id = oi.product_id
    WHERE o.order_purchase_timestamp < timestamp(:data_corte)
),
-- TOTAL por UNIDADE (massa embarcada, g->kg), 4 janelas (cresce no tempo).
total AS (
    SELECT seller_id,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 28 DAYS  THEN w END)/1000.0 AS tot_d28,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 56 DAYS  THEN w END)/1000.0 AS tot_d56,
        SUM(CASE WHEN dt_venda >= timestamp(:data_corte) - INTERVAL 365 DAYS THEN w END)/1000.0 AS tot_d365,
        SUM(w)/1000.0                                                                            AS tot_vida
    FROM vendas
    GROUP BY seller_id
),
-- PRODUTOS DISTINTOS por seller (toda a vida; peso constante por produto).
-- Base ESTÁTICA da distribuição — sem janelas, pois o peso não muda no tempo.
produtos AS (
    SELECT DISTINCT seller_id, product_id, w
    FROM vendas
    WHERE w IS NOT NULL
),
-- distribuição estática sobre os produtos distintos.
stats AS (
    SELECT seller_id,
        AVG(w)              AS media,
        percentile(w, 0.50) AS p50,
        percentile(w, 0.25) AS p25,
        percentile(w, 0.75) AS p75,
        MIN(w)              AS mn,
        MAX(w)              AS mx
    FROM produtos
    GROUP BY seller_id
),
spine AS (SELECT DISTINCT seller_id FROM vendas)  -- spine = esqueleto da entidade: 1 linha por seller (grao de saida)
SELECT
    s.seller_id,
    st.media AS vlMediaPesoProduto,
    st.p50   AS vlMedianaPesoProduto,
    st.p25   AS vl25PesoProduto,
    st.p50   AS vl50PesoProduto,
    st.p75   AS vl75PesoProduto,
    st.mn    AS vlMinPesoProduto,
    st.mx    AS vlMaxPesoProduto,
    t.tot_d28  AS vlTotalPesoProdutosD28,
    t.tot_d56  AS vlTotalPesoProdutosD56,
    t.tot_d365 AS vlTotalPesoProdutosD365,
    t.tot_vida AS vlTotalPesoProdutosVida
FROM spine s
LEFT JOIN stats st ON st.seller_id = s.seller_id
LEFT JOIN total t  ON t.seller_id  = s.seller_id;

-- ====================== ANÁLISE / PROVAS DA DECISÃO (rodar manualmente) ======================
-- Rode cada SELECT numa célula isolada (o widget alimenta o :data_corte).
-- =============================================================================================

-- ----------------------- Prova A — peso é ESTÁTICO: D28/D56/D365/Vida dariam o MESMO valor por produto -----------------------
-- O peso não muda entre janelas; a janela só mudaria QUAIS SKUs entram.
SELECT oi.product_id,
       COUNT(DISTINCT p.product_weight_g) AS valores_distintos_de_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.products p ON p.product_id = oi.product_id
GROUP BY oi.product_id
HAVING valores_distintos_de_peso > 1   -- esperado: 0 linhas
LIMIT 20;

-- ----------------------- Prova B — DISTRIBUIÇÃO usa produto distinto; TOTAL usa unidade (grãos diferentes) -----------------------
SELECT oi.seller_id, oi.product_id, p.product_weight_g AS peso_g,
       COUNT(*) AS unidades_vendidas
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte)
GROUP BY oi.seller_id, oi.product_id, p.product_weight_g
HAVING COUNT(*) > 1
ORDER BY unidades_vendidas DESC
LIMIT 20;

-- ----------------------- Prova C — há peso NULL? (ignorado na distribuição e no total) -----------------------
SELECT COUNT(*) AS itens_vendidos,
       SUM(CASE WHEN p.product_weight_g IS NULL THEN 1 ELSE 0 END) AS itens_sem_peso,
       COUNT(DISTINCT CASE WHEN p.product_weight_g IS NULL THEN oi.product_id END) AS produtos_sem_peso
FROM workspace.olist.order_items oi
JOIN workspace.olist.orders o ON o.order_id = oi.order_id
JOIN workspace.olist.products p ON p.product_id = oi.product_id
WHERE o.order_purchase_timestamp < timestamp(:data_corte);
