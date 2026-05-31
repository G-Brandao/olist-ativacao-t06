# Considerações importantes

Decisões metodológicas que **não são óbvias no código** e podem gerar
mal-entendidos se não estiverem explícitas. Leia antes de alterar janelas de
tempo, o parâmetro de corte ou a definição de "venda".

---

## 1. Estratégia de corte de data — `datetime('{data_corte}', '-28 days')`

### 1.1 Como foi pensada

Usamos **janela relativa ancorada no corte** (padrão *as-of feature*). Em vez de
datas fixas, tudo é ancorado em `{data_corte}` e subtraímos N dias:

```sql
-- limite inferior (D28)            limite superior (todas as janelas)
dt_venda >= datetime('{data_corte}', '-28 days')   AND   dt_venda < '{data_corte}'
```

Resultando em um intervalo **semiaberto à direita**:

```
D28  = [ datetime(corte, '-28 days') , corte )
D56  = [ datetime(corte, '-56 days') , corte )
D365 = [ datetime(corte, '-365 days'), corte )
Vida = ( -infinito                   , corte )
```

Três decisões deliberadas:

1. **Subtração de dias-calendário** (`datetime(..., '-28 days')`), não aritmética
   manual: o SQLite resolve fronteiras de mês/ano sozinho.
2. **`< corte` estrito** (intervalo semiaberto): honra o `data_venda < hoje()` do
   enunciado e **evita leakage** — a venda do próprio instante do corte nunca
   entra.
3. **28 e 56 são múltiplos exatos de 7** (4 e 8 semanas): janelas em semanas
   inteiras têm **comprimento constante** e neutralizam efeito de dia-da-semana —
   diferente de "1 mês civil" (28–31 dias), que desalinha snapshots.

### 1.2 Comportamento real (confirmado no `olist.db`, corte `2018-09-01`)

| Verificação | Resultado |
|-------------|-----------|
| `datetime('2018-09-01','-28 days')` | `2018-08-04 00:00:00` |
| `datetime('2018-09-01')` | `2018-09-01 00:00:00` |
| Janela D28 real | **5.585 pedidos**, de `2018-08-04 00:06:27` a `2018-08-31 16:13:44` |
| `< '2018-09-01'` vs `< datetime('2018-09-01')` | **idêntico** (99.421 pedidos) |
| `'2018-08-31 23:59:59' < '2018-09-01'` | **INCLUI** |
| `'2018-09-01 00:00:00' < '2018-09-01'` | **EXCLUI** |
| `'2018-09-01 00:00:01' < '2018-09-01'` | **EXCLUI** |

### 1.3 É a melhor metodologia?

É **sólida, à prova de leakage e aderente ao `variaveis.md`**. Dois pontos de
atenção honestos:

**(a) Janela rolante de N dias ≠ mês civil.** O negócio roda a previsão no último
dia útil do mês X. `D28` é uma janela rolante de 28×24h, que **não coincide** com
"o último mês civil". Mitigamos no nível do corte: usando `{data_corte}` = **1º
dia do mês X+1** (ex.: `2018-09-01`), a janela **Vida** captura exatamente "todo o
histórico até o fim do mês X". D28/D56 seguem rolantes — escolha de
comparabilidade, não erro.

**(b) Assimetria *date* × *timestamp* nas duas pontas.**
- Limite **inferior**: `datetime(corte,'-28 days')` → string explícita com hora
  (`'2018-08-04 00:00:00'`).
- Limite **superior**: token cru `< '{data_corte}'` → `< '2018-09-01'` (sem hora).

No SQLite ambas são **comparações lexicográficas de string** — funcionam *porque*
o formato é ISO `YYYY-MM-DD HH:MM:SS`, zero-padded (ordem alfabética = ordem
cronológica). No Spark já usamos `timestamp(:data_corte)` (comparação temporal
de verdade). Os dois dialetos dão o mesmo número, mas a ponta superior do SQLite
depende implicitamente do formato ISO.

### 1.4 Sim — há armadilhas de "definição de dia"

| # | Ambiguidade | Como ficou aqui |
|---|-------------|-----------------|
| 1 | Fronteiras inclusiva/exclusiva | `[inferior **inclusivo**, superior **exclusivo**)` |
| 2 | O **dia do corte** entra? | **Não** (estrito `<`). Snapshot = "fim do dia anterior ao corte" |
| 3 | "28 dias" conta a partir de quê? | Da **meia-noite** da data do corte → **28 dias civis** completos (Ago 4 00:00 → Ago 31 23:59) |
| 4 | Comparar **timestamp** com **date** | SQLite: lexicográfica (ok por ser ISO); Spark: temporal. Mesmo resultado |
| 5 | Fuso / horário de verão | `datetime(...,'-28 days')` é "relógio de parede" (28×24h civis); Brasil tinha horário de verão em 2018. Irrelevante em janela de dias, mas existe |
| 6 | O que você passa como `{data_corte}` | **Data** (`2018-09-01`) → âncora à meia-noite; **timestamp** (`2018-09-01 12:00:00`) → janela rolante exata a partir daquele instante |

O risco prático de mal-entendido está nos itens **2 e 3**: alguém pode esperar que
"D28" inclua o dia do snapshot, ou conte 28 dias a partir do timestamp exato da
execução. A convenção aqui é clara e consistente: **corte à meia-noite, dia do
corte fora, 28 dias civis completos terminando na véspera**.

### 1.5 Recomendação (NÃO aplicada — decisão em aberto)

Para blindar contra os itens 4 e 6 e remover a assimetria, a mudança mínima —
**sem alterar nenhum resultado** (validado: 99.421 = 99.421) — é tornar a ponta
superior explícita no SQLite:

```sql
WHERE o.order_purchase_timestamp < datetime('{data_corte}')   -- em vez de < '{data_corte}'
```

Força o corte a `'2018-09-01 00:00:00'` sempre, deixando as duas pontas no mesmo
formato, independente de truque lexicográfico. É puramente legibilidade/robustez.
**Status: não aplicado** (numericamente idêntico; o Spark já é explícito).

---

## Referências cruzadas

- Premissas globais e janelas: [`docs/variaveis_detalhadas.md`](docs/variaveis_detalhadas.md) §3.4.
- Decisões travadas (data de venda, sem filtro de status): [`CLAUDE.md`](CLAUDE.md) §5.
- Revisão crítica das variáveis: [`docs/revisao_critica.md`](docs/revisao_critica.md).
