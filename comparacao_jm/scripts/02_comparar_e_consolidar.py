import pandas as pd, numpy as np

JM = pd.read_excel("FS_Produtos_JoseMauro.xlsx").rename(columns={"vlCategoriasDistintasvida":"vlCategoriasDistintasVida"})
B = pd.read_pickle("out_brandao.pkl"); P = pd.read_pickle("out_pierre.pkl")
W=["D14","D28","D56","D365","Vida"]
mj=JM.set_index("seller_id"); mb=B.set_index("seller_id"); mp=P.set_index("seller_id"); idx=mj.index

# ---- variable mapping: (familia, var, jm, b, bf, p, pf, pierre_dec) pierre_dec=None -> exact ----
rows=[]
def add(fam,var,b,bf,p,pf,pdec): rows.append(dict(familia=fam,var=var,b=b,bf=bf,p=p,pf=pf,pdec=pdec))
for w in W: add("01 Categorias distintas",f"vlCategoriasDistintas{w}",f"vlCategoriasDistintas{w}",1,f"vlCategoriasDistintas{w}",1,0)
for w in W: add("02 Produtos distintos",f"vlProdutosDistintos{w}",f"vlProdutosDistintos{w}",1,f"vlProdutosDistintos{w}",1,0)
for st in ["Media","Mediana","Min","Max"]:
    for w in W:
        pdec=None if st in ("Min","Max") else 3
        add(f"03 Peso produto {st}",f"vl{st}PesoProduto{w}",f"vl{st}PesoProduto{w}",1/1000,f"vl{st}PesoProduto{w}",1,pdec)
for pc in ["25","75"]:
    for w in W: add(f"03 Peso produto P{pc}",f"vl{pc}PesoProduto{w}",f"vl{pc}PesoProduto{w}",1/1000,f"vlP{pc}PesoProduto{w}",1,3)
for w in W: add("03 Peso produto Total",f"vlTotalPesoProdutos{w}",f"vlTotalPesoProdutos{w}",1,f"vlTotalPesoProduto{w}",1,3)
for w in W: add("04 Cubagem Media",f"vlMediaCubagemProdutos{w}",f"vlMediaCubagemProdutos{w}",1,f"vlMediaCubagemProduto{w}",1,1)
for w in W: add("04 Cubagem Total",f"vlTotalCubagemProdutos{w}",f"vlTotalCubagemProdutos{w}",1,f"vlTotalCubagemProduto{w}",1,1)
for w in W: add("05 Preco/kg",f"vlPrecoKg{w}",f"vlPrecoKg{w}",1,f"vlPrecoKg{w}",1,2)
for w in W: add("05 Frete/kg",f"vlFreteKg{w}",f"vlFreteKg{w}",1,f"vlFreteKg{w}",1,2)
for st in ["Media","Mediana","Min","Max"]: add("06 Caracteres descricao",f"vl{st}CaracteresDescricao",f"vl{st}CaracteresDescricao",1,f"vl{st}CaracteresDescricao",1,1)
for pc in ["25","75"]: add("06 Caracteres descricao",f"vl{pc}CaracteresDescricao",f"vl{pc}CaracteresDescricao",1,f"vlP{pc}CaracteresDescricao",1,1)
add("06 Fotos","vlMediaFotosProdutos","vlMediaFotosProduto",1,"vlMediaFotosProduto",1,1)
for st in ["Media","Mediana","Min","Max"]: add("07 Peso portfolio",f"vl{st}PesoPortfolio",f"vl{st}PesoPortfolio",1/1000,None,1,None)
for pc in ["25","75"]: add("07 Peso portfolio",f"vl{pc}PesoPortfolio",f"vl{pc}PesoPortfolio",1/1000,None,1,None)
add("07 Peso portfolio","vlTotalPesoPortfolio","vlTotalPesoPortfolio",1,None,1,None)

def match(a,b,dec):
    a=a.reindex(idx).astype(float); b=b.reindex(idx).astype(float)
    both=a.notna()&b.notna()
    if dec is None: tol=np.maximum(np.abs(a),np.abs(b))*1e-6+1e-9
    else: tol=0.5*10**(-dec)*1.01 + np.maximum(np.abs(a),np.abs(b))*1e-9
    eq=both&(np.abs(a-b)<=tol)
    n=int(both.sum()); ne=int(eq.sum())
    ndiff=n-ne
    md=float(np.abs(a-b)[both].max()) if n else np.nan
    nanmm=int((a.isna()^b.isna()).sum())
    return n,ne,ndiff,round(md,4) if n else None,nanmm

# consolidated wide values (Brandao & Pierre normalized to JM unit)
cons={"seller_id":idx}
res=[]
for r in rows:
    jmv=mj[r["var"]]
    cons[f"{r['var']}__JM"]=jmv.values
    bvn=None; pvn=None
    if r["b"] in mb: bvn=(mb[r["b"]]*r["bf"]); cons[f"{r['var']}__Brandao"]=bvn.reindex(idx).values
    if r["p"] and r["p"] in mp: pvn=(mp[r["p"]]*r["pf"]); cons[f"{r['var']}__Pierre"]=pvn.reindex(idx).values
    rec={"familia":r["familia"],"variavel":r["var"],"unidade":"kg (Brandão nativo g)" if r["bf"]!=1 else ""}
    if bvn is not None:
        n,ne,nd,md,nm=match(jmv,bvn,None)
        rec.update(JM_vs_Brandao_n=n,JM_vs_Brandao_iguais=ne,JM_vs_Brandao_divergem=nd,JM_vs_Brandao_pct=round(100*ne/n,2),JM_vs_Brandao_maxdif=md)
    if pvn is not None:
        n,ne,nd,md,nm=match(jmv,pvn,r["pdec"])
        rec.update(JM_vs_Pierre_n=n,JM_vs_Pierre_iguais=ne,JM_vs_Pierre_divergem=nd,JM_vs_Pierre_pct=round(100*ne/n,2),JM_vs_Pierre_maxdif=md)
    else:
        rec.update(JM_vs_Pierre_pct=None,JM_vs_Pierre_divergem=None); rec["obs_pierre"]="Pierre não calcula portfólio"
    res.append(rec)

S=pd.DataFrame(res)
# classification
def classify(r):
    fam=r["familia"]
    pb=r.get("JM_vs_Brandao_pct"); 
    if fam.startswith("01"): return "🟡 DIVERGE (definição: categoria ausente não conta p/ JM)"
    if fam.startswith("07"): return "🟢 IGUAL exceto 2 sellers s/ peso (JM: peso ausente=0; Brandão ignora) · Pierre n/d"
    if fam.startswith("05"): return "🟢 IGUAL exceto 2 sellers s/ peso (JM=Pierre; Brandão exclui item s/ peso)"
    if pb==100: return "✅ IDÊNTICO" + (" (unidade: Brandão em g)" if r["unidade"] else "")
    return "🟢 IGUAL (≈)"
S["classificacao"]=S.apply(classify,axis=1)
S["obs_unidade"]=np.where(S["unidade"]!="","Brandão reporta peso em GRAMAS; valores normalizados p/ kg (÷1000)","")

# variables not computed by JM (only Brandao/Pierre)
extra=[]
for fam,var,bcol,pcol,nota in [
  ("EXTRA Concorrência (JM não calcula)","vlContagemCategoriaConcorrentes{W}","sim (DISTINTO)","sim (SOMA exposições)","Brandão conta sellers DISTINTOS; Pierre SOMA por categoria (double-count) — divergem (ver comparacao.md)"),
  ("EXTRA Concorrência (JM não calcula)","vlContagemProdutosConcorrentes{W}","sim (DISTINTO)","sim (SOMA)","idem"),
  ("EXTRA Top categoria (JM não calcula)","descTopCategoria{1,2,3}{W}","sim (por UNIDADES)","sim (por RECEITA)","Critério de ranking difere (unidades vs receita) + rótulo NULL (sem_categoria vs NA)"),
  ("EXTRA Share top categoria (JM não calcula)","vlShareTopCategoria{1,2,3}{W}","sim (share UNIDADES)","sim (share RECEITA)","idem"),
]:
    extra.append(dict(familia=fam,variavel=var,JM_vs_Brandao_pct=None,JM_vs_Pierre_pct=None,classificacao="⚪ JM NÃO CALCULOU",obs_unidade=nota))
S=pd.concat([S,pd.DataFrame(extra)],ignore_index=True)

CONS=pd.DataFrame(cons)

# ---- write excel ----
order=["familia","variavel","classificacao","JM_vs_Brandao_n","JM_vs_Brandao_iguais","JM_vs_Brandao_divergem","JM_vs_Brandao_pct","JM_vs_Brandao_maxdif","JM_vs_Pierre_n","JM_vs_Pierre_iguais","JM_vs_Pierre_divergem","JM_vs_Pierre_pct","JM_vs_Pierre_maxdif","obs_unidade"]
for c in order:
    if c not in S: S[c]=None
S=S[order]

with pd.ExcelWriter("Comparacao_FeatureStore_JM_Brandao_Pierre.xlsx", engine="openpyxl") as xw:
    S.to_excel(xw, sheet_name="resumo_variaveis", index=False)
    CONS.to_excel(xw, sheet_name="consolidado_valores", index=False)
    # long diffs only divergent rows for categorias + edge sellers
    long=[]
    for r in rows:
        jmv=mj[r["var"]].reindex(idx)
        bvn=(mb[r["b"]]*r["bf"]).reindex(idx) if r["b"] in mb else pd.Series(index=idx,dtype=float)
        pvn=(mp[r["p"]]*r["pf"]).reindex(idx) if (r["p"] and r["p"] in mp) else pd.Series(index=idx,dtype=float)
        db=(jmv-bvn).abs(); 
        sel=db> (np.maximum(jmv.abs(),bvn.abs())*1e-6+1e-9)
        for sid in idx[sel.fillna(False)]:
            long.append(dict(seller_id=sid,familia=r["familia"],variavel=r["var"],valor_JM=jmv[sid],valor_Brandao=bvn[sid],valor_Pierre=pvn[sid] if sid in pvn.index else None,dif_JM_Brandao=jmv[sid]-bvn[sid]))
    L=pd.DataFrame(long)
    L.to_excel(xw, sheet_name="divergencias_JM_Brandao_detalhe", index=False)
    print("long divergences rows:",len(L))

S.to_pickle("S.pkl")
print("\n===== RESUMO (JM vs Brandão / Pierre) =====")
pd.set_option("display.width",240,"display.max_columns",30,"display.max_rows",100)
g=S.groupby("familia").agg(vars=("variavel","count"),
   JMvB_pct_min=("JM_vs_Brandao_pct","min"),JMvB_pct_max=("JM_vs_Brandao_pct","max"),
   JMvP_pct_min=("JM_vs_Pierre_pct","min"),JMvP_pct_max=("JM_vs_Pierre_pct","max")).reset_index()
print(g.to_string(index=False))
print("\nExcel salvo. Sheets: resumo_variaveis, consolidado_valores, divergencias_JM_Brandao_detalhe")
print("consolidado shape:",CONS.shape)
