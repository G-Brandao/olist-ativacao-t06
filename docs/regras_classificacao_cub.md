# Regras de classificação do CUB automático

Este documento descreve, por extenso, as regras que o módulo [`cub/`](../cub)
usa para transformar os dados brutos de **CUB (Custo Unitário Básico da
Construção Civil)** divulgados por cada SINDUSCON estadual em um dataset
normalizado por **estado × tipo de obra × nível de padrão (alto / médio / baixo)**.

A implementação canônica destas regras está em
[`cub/classification.py`](../cub/classification.py). **Sempre que uma regra
mudar aqui, o código correspondente deve ser atualizado — e vice-versa.**

---

## 1. O que é o CUB

O CUB/m² é o indicador oficial do custo por metro quadrado da construção civil
no Brasil, calculado mensalmente por cada SINDUSCON com base na norma
**ABNT NBR 12721:2006**. Ele é publicado por **projeto-padrão** (um modelo de
obra representativo) e por **padrão de acabamento** (baixo, normal, alto).

Cada estado publica no site do seu próprio sindicato, em formatos e layouts
diferentes — daí a necessidade de um coletor com um registro de fontes
([`cub/states.py`](../cub/states.py)) e parsers tolerantes
([`cub/parsers.py`](../cub/parsers.py)).

---

## 2. Dimensões normalizadas

Toda linha coletada é reduzida a três dimensões controladas, além do valor:

| Dimensão          | Valores possíveis                                   | Origem |
|-------------------|-----------------------------------------------------|--------|
| `categoria`       | `residencial`, `comercial`, `industrial`, `popular` | finalidade do projeto-padrão |
| `nivel`           | `alto`, `medio`, `baixo`                             | padrão de acabamento |
| `projeto_padrao`  | sigla NBR 12721 (ex.: `R1-A`, `CSL16-N`, `GI`)      | modelo de obra |

O `nivel` `medio` corresponde ao padrão **Normal** da NBR 12721 (é o "meio"
pedido na especificação da tarefa).

---

## 3. Catálogo de projetos-padrão (NBR 12721)

Cada projeto base admite um subconjunto dos padrões de acabamento
**B** (baixo), **N** (normal) e **A** (alto). O sufixo faz parte da sigla.

### Residenciais

| Sigla base | Descrição                                     | Padrões | Categoria |
|------------|-----------------------------------------------|---------|-----------|
| `R1`       | Residência unifamiliar, 1 pavimento           | B, N, A | residencial |
| `PP4`      | Prédio popular, 4 pavimentos                  | B, N    | residencial |
| `R8`       | Residência multifamiliar, 8 pavimentos        | B, N, A | residencial |
| `R16`      | Residência multifamiliar, 16 pavimentos       | N, A    | residencial |

### Comerciais

| Sigla base | Descrição                                     | Padrões | Categoria |
|------------|-----------------------------------------------|---------|-----------|
| `CAL8`     | Comercial andar livre, 8 pavimentos           | N, A    | comercial |
| `CSL8`     | Comercial salas e lojas, 8 pavimentos         | N, A    | comercial |
| `CSL16`    | Comercial salas e lojas, 16 pavimentos        | N, A    | comercial |

### Padrão único (sem sufixo B/N/A)

| Sigla  | Descrição                          | Categoria   |
|--------|------------------------------------|-------------|
| `GI`   | Galpão industrial                  | industrial  |
| `PIS`  | Projeto de interesse social        | popular     |
| `RP1Q` | Residência popular, 1 quarto       | popular     |

> As combinações válidas listadas acima são exaustivas: uma sigla como `R16-B`
> **não existe** na NBR 12721 e, se aparecer em um site, é descartada.

---

## 4. Regras de classificação

### Regra 0 — Normalização da sigla

A sigla bruta do site é convertida para uma **forma compacta** (sem acento, em
maiúsculas, apenas caracteres alfanuméricos) e comparada com o catálogo.
Isso absorve as variações de digitação encontradas na prática:

- `"R-1-A"`, `"R 1 A"`, `"r1a"` → `R1-A`
- `"CSL 16 N"`, `"csl-16-n"`   → `CSL16-N`
- `"RP1Q"`, `"rp 1 q"`         → `RP1Q`

Uma sigla que não corresponda a **nenhuma** combinação válida do catálogo é
descartada (retorna vazio), evitando que texto solto vire registro.

### Regra 1 — Padrão de acabamento → nível (alto / médio / baixo)

O sufixo da sigla determina o nível:

| Sufixo NBR | `nivel` normalizado |
|------------|---------------------|
| `-B` (Baixo)  | `baixo` |
| `-N` (Normal) | `medio` |
| `-A` (Alto)   | `alto`  |

Quando o site publica o projeto base numa coluna e o padrão em **coluna
separada** (ex.: coluna "Projeto" = `R1`, coluna "Padrão" = `Alto`), o texto do
padrão é normalizado por um dicionário de sinônimos antes de virar sufixo:

- `baixo`, `econômico` → `B`
- `normal`, `médio`, `média` → `N`
- `alto`, `elevado` → `A`

### Regra 2 — Projetos de padrão único

`GI`, `PIS` e `RP1Q` não têm sufixo B/N/A. Como a especificação exige que **toda**
obra caia em um dos três níveis, aplica-se uma reclassificação por natureza da
obra:

| Projeto | `nivel` atribuído | Racional |
|---------|-------------------|----------|
| `PIS`   | `baixo`  | Interesse social: menor especificação de acabamento. |
| `RP1Q`  | `baixo`  | Habitação popular: acabamento mínimo. |
| `GI`    | `medio`  | Galpão padronizado, sem acabamento fino residencial; tratado como referência "normal". |

> Esta é uma **regra de negócio**, não uma definição da NBR. Se a área de dados
> preferir manter os projetos de padrão único num nível próprio, basta alterar
> o dicionário `_NIVEL_UNICO` em `cub/classification.py` (e esta tabela).

### Regra 3 — Categoria da obra

A categoria vem diretamente do catálogo (Seção 3): residencial, comercial,
industrial ou popular. Ela **não** depende do padrão de acabamento.

### Regra 4 — Validação do valor

Um número só é aceito como CUB/m² se:

1. tiver casas decimais (o CUB sempre as tem); e
2. estiver no intervalo plausível **R$ 100 a R$ 100.000** por m².

Isso descarta ruído comum nas tabelas: número de pavimentos, área, e variações
percentuais (ex.: `0,42%`).

---

## 5. Manutenção das fontes

Os sites dos SINDUSCONs **mudam de endereço e de layout com frequência**. Por
isso:

- O registro de fontes ([`cub/states.py`](../cub/states.py)) guarda, por UF, a
  URL e a **estratégia de parsing** (`html_table`, `pdf` ou `custom:<UF>`).
- Estados que publicam o CUB apenas em **PDF** precisam de um parser dedicado
  (a estratégia `pdf` está declarada mas ainda não implementada — ver
  `_parse_pdf` em `cub/scraper.py`).
- Rode `python -m cub.cli --check-urls` periodicamente para detectar URLs
  quebradas antes que a coleta falhe silenciosamente.
- As URLs cadastradas refletem os domínios oficiais conhecidos, mas o **caminho
  exato** da página de CUB deve ser revalidado a cada mudança de site.

---

## 6. Fluxo de execução

```
sites SINDUSCON  ──fetch──►  HTML/PDF por UF
        │                         │
        │                    parsers (Regra 0/1/4)
        ▼                         ▼
  cub/states.py            classificar (Regra 1/2/3)
                                  │
                                  ▼
                          CubRecord normalizado
                                  │
                       consolidar + escrever_csv/sql
                                  ▼
              data/cub.csv  /  fs_cub_estados (feature store)
```

Comando padrão:

```bash
python -m cub.cli --out data/cub.csv --sql data/cub_insert.sql
```
