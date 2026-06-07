import duckdb, pandas as pd, re

con = duckdb.connect("work.duckdb")
# load CSVs as typed tables
csvmap = {
 "orders":"dados/olist_orders_dataset.csv",
 "order_items":"dados/olist_order_items_dataset.csv",
 "products":"dados/olist_products_dataset.csv",
}
for t,f in csvmap.items():
    con.execute(f"CREATE OR REPLACE TABLE {t} AS SELECT * FROM read_csv_auto('{f}', header=true)")
print("orders cols:", [c[0] for c in con.execute("PRAGMA table_info('products')").fetchall()][:12])

# window lower bounds aligned to JM (anchor 2018-06-30), upper < 2018-07-01
L = {14:"2018-06-16",28:"2018-06-02",56:"2018-05-05",365:"2017-06-30"}
UPPER="2018-07-01"

# ---------- Brandao tabelao ----------
b = open("brandao_tabelao.sql").read()
b = re.sub(r"(?m)^DECLARE OR REPLACE VARIABLE data_corte.*$","",b)
b = b.replace("workspace.olist.","")
for n,lb in L.items():
    b = b.replace(f"datediff(data_corte, dt_venda) <= {n}", f"dt_venda >= TIMESTAMP '{lb}'")
b = b.replace("< data_corte", f"< TIMESTAMP '{UPPER}'")
b = b.replace("percentile(","quantile_cont(")
df_b = con.execute(b).df()
print("BRANDAO:", df_b.shape)

# ---------- Pierre ----------
p = open("pierre.sql").read()
p = p.replace("workspace.olist.","").replace("olist.","")
p = p.replace("order_purchase_timestamp < deploy_date", f"order_purchase_timestamp < TIMESTAMP '{UPPER}'")
for n,lb in L.items():
    p = p.replace(f"DATE_SUB(deploy_date, {n})", f"TIMESTAMP '{lb}'")
p = p.replace("PERCENTILE(","quantile_cont(").replace("MEDIAN(","median(").replace("MEAN(","avg(").replace("IFNULL(","COALESCE(")
df_p = con.execute(p).df()
print("PIERRE:", df_p.shape)

df_b.to_pickle("out_brandao.pkl"); df_p.to_pickle("out_pierre.pkl")

# ---------- sanity vs JM ----------
JM = pd.read_excel("FS_Produtos_JoseMauro.xlsx")
JM = JM.rename(columns={"vlCategoriasDistintasvida":"vlCategoriasDistintasVida"})
for name,df in [("BRANDAO",df_b),("PIERRE",df_p)]:
    m = JM.merge(df, on="seller_id", how="inner", suffixes=("_jm","_x"))
    print(f"\n--- {name}: universe inner={len(m)} (JM={len(JM)}, {name}={len(df)}) ---")
    for col in ["vlCategoriasDistintasD14","vlCategoriasDistintasVida","vlProdutosDistintosD14","vlProdutosDistintosD28","vlProdutosDistintosD56","vlProdutosDistintosD365","vlProdutosDistintosVida"]:
        a=m[col+"_jm"]; b2=m[col+"_x"]
        diff=(a.fillna(-1)!=b2.fillna(-1)).sum()
        print(f"   {col:32s} diffs={diff}")
