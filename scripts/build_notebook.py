"""Gera o notebook `analise_variaveis.ipynb` na raiz do repositório.

Lê cada script de `features_sqlite/*.sql` e monta um notebook onde cada variável
vira uma seção: 1 célula markdown (explicação) + 1 célula de código com o **SQL
inline** (idêntico ao validado), que roda contra `olist.db` e renderiza a tabela.

Sem dependências além da stdlib (escreve o JSON do notebook na mão).
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEAT = ROOT / "features_sqlite"

# Explicação curta por variável (item de variaveis.md, o que mede, janelas).
EXPLICACOES = {
    "01_qtd_categorias_distintas": (
        "## 1. Categorias distintas no período  `*`\n\n"
        "Quantas **categorias diferentes** o seller vendeu em cada janela "
        "(`D28/D56/D365/Vida`). Categoria sem cadastro vira `'sem_categoria'`. "
        "Mede a **diversidade** do portfólio."
    ),
    "02_qtd_produtos_distintos": (
        "## 2. Produtos distintos no período  `*`\n\n"
        "Quantos **`product_id` diferentes** o seller vendeu por janela. "
        "Amplitude do catálogo efetivamente vendido."
    ),
    "03_concorrentes_mesma_categoria": (
        "## 3. Concorrentes na mesma categoria  `*`\n\n"
        "Para cada seller, quantos **outros** sellers venderam em **alguma "
        "categoria em comum**, na mesma janela. Concorrência **indireta**."
    ),
    "04_concorrentes_mesmo_produto": (
        "## 4. Concorrentes no mesmo produto  `*`\n\n"
        "Quantos **outros** sellers venderam o **mesmo `product_id`**, por janela. "
        "Concorrência **direta** (mesmo SKU → guerra de preço)."
    ),
    "05_desc_chars_estatisticas": (
        "## 5. Estatísticas de caracteres da descrição  (Vida)\n\n"
        "Média, p25, mediana, p75, min e max do tamanho da descrição dos "
        "**produtos distintos** vendidos. Proxy de **qualidade do cadastro**."
    ),
    "06_peso_medio_mediana": (
        "## 6. Peso médio e mediana dos produtos  `*`\n\n"
        "Peso (g) **médio** e **mediano** das unidades vendidas, por janela "
        "(ponderado por venda)."
    ),
    "07_peso_total": (
        "## 7. Peso total dos produtos  `*`\n\n"
        "Massa **total (kg)** despachada por janela. Variável de **escala** da "
        "operação."
    ),
    "08_cubagem_media": (
        "## 8. Cubagem média dos produtos  `*`\n\n"
        "Volume **médio** (cm³ = `L×H×W`) das unidades vendidas por janela."
    ),
    "09_cubagem_total": (
        "## 9. Cubagem total dos produtos  `*`\n\n"
        "Volume **total** (cm³) despachado por janela. Pareado com o peso total, "
        "descreve a escala logística."
    ),
    "10_fotos_media_por_produto": (
        "## 10. Quantidade média de fotos por produto  (Vida)\n\n"
        "Média de `product_photos_qty` entre os **produtos distintos** vendidos. "
        "Proxy de qualidade da vitrine."
    ),
    "11_preco_por_kg": (
        "## 11. Preço por kg  `*`\n\n"
        "`SUM(price) / SUM(kg)` por janela (R$/kg). **Valor agregado** praticado."
    ),
    "12_frete_por_kg": (
        "## 12. Custo de frete por kg  `*`\n\n"
        "`SUM(freight_value) / SUM(kg)` por janela (R$/kg). **Custo logístico**."
    ),
    "13_top3_categorias": (
        "## 13. Top 3 categorias do vendedor  (Vida)\n\n"
        "As **3 categorias de maior receita** (`SUM(price)`) do seller. "
        "Posições inexistentes ficam `NULL`."
    ),
    "14_share_top3_categorias": (
        "## 14. Share das top 3 categorias  (Vida)\n\n"
        "**Fração da receita** concentrada nas 3 maiores categorias. Mede "
        "**concentração** (fragilidade)."
    ),
}

INTRO = (
    "# Análise das variáveis — Ativação de Sellers (Olist)\n\n"
    "Notebook de **demonstração**: roda cada variável de `variaveis.md` contra o "
    "banco de validação local **`olist.db`** (SQLite) e mostra a tabela resultante "
    "(`seller_id` × colunas da feature).\n\n"
    "Cada seção tem: a **explicação** (markdown) e o **SQL** (célula de código) — o "
    "mesmo SQL validado em `features_sqlite/`. Os scripts de produção em Spark estão "
    "em `features_spark/` (`workspace.olist.*`).\n\n"
    "**Premissas-chave:** data de venda = `order_purchase_timestamp` (corte estrito "
    "`< {data_corte}`); **sem** filtro de `order_status`; grão = 1 linha por "
    "`seller_id`. Detalhes em [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md).\n\n"
    "👉 Para trocar a data de corte, edite `DATA_CORTE` na célula de setup e rode tudo."
)

SETUP = (
    "# === Setup: conexão, parâmetro de corte e helper ===\n"
    "import os, sys, subprocess, sqlite3\n"
    "import pandas as pd\n\n"
    "DB = 'olist.db'\n"
    "DATA_CORTE = '2018-09-01'   # <<< parâmetro de corte (altere aqui e rode tudo)\n\n"
    "# gera o banco a partir de dados/ caso ainda não exista\n"
    "if not os.path.exists(DB):\n"
    "    subprocess.run([sys.executable, 'scripts/build_sqlite.py'], check=True)\n\n"
    "con = sqlite3.connect(DB)\n\n"
    "def run_sql(sql: str) -> pd.DataFrame:\n"
    "    \"\"\"Substitui {data_corte} pelo parâmetro e retorna o resultado como DataFrame.\"\"\"\n"
    "    return pd.read_sql_query(sql.replace('{data_corte}', DATA_CORTE), con)\n\n"
    "print('Banco:', DB, '| data_corte =', DATA_CORTE)"
)


def md(source, cid):
    return {"cell_type": "markdown", "id": cid, "metadata": {}, "source": source}


def code(source, cid):
    return {"cell_type": "code", "id": cid, "metadata": {},
            "execution_count": None, "outputs": [], "source": source}


def main() -> int:
    cells = [md(INTRO, "intro"), code(SETUP, "setup")]

    for stem in sorted(EXPLICACOES):
        sql = (FEAT / f"{stem}.sql").read_text(encoding="utf-8").rstrip()
        cells.append(md(EXPLICACOES[stem], f"md_{stem}"))
        code_src = (
            f"# Feature {stem}  (fonte: features_sqlite/{stem}.sql)\n"
            f'SQL = """\n{sql}\n"""\n\n'
            "df = run_sql(SQL)\n"
            "print(f'{len(df):,} sellers x {len(df.columns)} colunas')\n"
            "df.head(10)"
        )
        cells.append(code(code_src, f"code_{stem}"))

    cells.append(md(
        "---\n\n### Pronto\n\nCada tabela acima é o resultado da variável para "
        "todos os sellers ativos no corte. Para a tabela larga única, basta um "
        "`LEFT JOIN` dos 14 resultados por `seller_id`.",
        "outro"))

    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }

    out = ROOT / "analise_variaveis.ipynb"
    out.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Notebook gerado: {out}  ({len(cells)} células)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
