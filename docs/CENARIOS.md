# Cenários canônicos

A suíte canônica reúne os 13 traços de `Files/Traces/` que exercitam o
monitor composto da v2, `M = M_1 ⊗ M_2 ⊗ M_3 ⊗ M_4` (A1–A4), com o filtro
A5 a montante. Todos trazem `veredito_esperado` no cabeçalho YAML e são
verificados por `cabal test`. As decisões de modelagem por trás destes
cenários estão registradas em `docs/DECISOES.md`.

As propriedades monitoradas são:

- **A1** (safety): `G(rem_i → ab_i)` — retirada só dentro da janela.
- **A2** (liveness temporizada): `G(leave_ab_i → F[0,Tcls] cls^{≥τ})`.
- **A3** (liveness temporizada):
  `G(leave_ab_i → F[0,Tdec] (match_i ∨ div_i))`.
- **A4** (liveness temporizada): `G(div_i → F[0,Tpcp] esc_pcp_i)`.
- **A5** (filtro condicional): `conf ≥ τ → M_obs` — descarta
  classificações de baixa confiança antes de compor `M_obs`.

O veredito composto é o ínfimo das linhas no reticulado LTL₃
`⊥ < ? < ⊤` (Proposição 2 do artigo).

## Resumo

| #  | Arquivo                                         | Veredito | Propriedade(s) |
|----|-------------------------------------------------|:--------:|----------------|
| 01 | `trace_01_aceita_simples.txt`                   |    ⊤     | —              |
| 02 | `trace_02_aceita_multiplas.txt`                 |    ⊤     | —              |
| 03 | `trace_03_viola_a1_inicio.txt`                  |    ⊥     | A1             |
| 04 | `trace_04_viola_a1_apos_leave.txt`              |    ⊥     | A1 (e A3)      |
| 05 | `trace_05_aceita_vazio.txt`                     |    ⊤     | — (vacuosa)    |
| 06 | `trace_06_aceita_braco1_mix.txt`                |    ⊤     | —              |
| 07 | `trace_07_aceita_braco2_uniforme.txt`           |    ⊤     | —              |
| 08 | `trace_08_viola_a4_molde_vazio.txt`             |    ⊥     | A4             |
| 09 | `trace_09_viola_a4_op_errada.txt`               |    ⊥     | A4             |
| 13 | `trace_13_viola_a4_deriva_cnn.txt`              |    ⊥     | A5 → A2 + A4   |
| 14 | `trace_14_viola_a2_classificacao_atrasada.txt`  |    ⊥     | A2             |
| 15 | `trace_15_viola_a4_escalacao_atrasada.txt`      |    ⊥     | A4             |
| 16 | `trace_16_viola_a3_decisao_atrasada.txt`        |    ⊥     | A3             |

Total: 5 aceitas (⊤) e 8 violadas (⊥). Os índices 10/11/12 ficaram livres,
realocados para `extras/` (ver última seção); não houve renumeração dos
demais, para preservar o histórico do repositório.

## 01 — Aceitação canônica (uma peça)

- Arquivo: `trace_01_aceita_simples.txt`
- Veredito esperado: ⊤
- Propriedade(s): nenhuma viola (caminho feliz)

Sequência mínima de aceitação: `ab_i`, `rem_i`, classificação,
`leave_ab_i`, `match_i`. Confirma que o monitor passa no caminho feliz.
O traço não traz cabeçalho com `m_dec` — exercita o caminho legado em que
a contagem decidida não é informada.

## 02 — Aceitação com múltiplas peças

- Arquivo: `trace_02_aceita_multiplas.txt`
- Veredito esperado: ⊤
- Propriedade(s): nenhuma viola (caminho feliz)

Três retiradas e três classificações na mesma janela, cada uma com um SKU
diferente (500L, 1000L, 2000L). Cenário típico de um braço com vários
moldes que produz um lote heterogêneo, com `match_i` ao final.

## 03 — `rem_i` antes de `ab_i`

- Arquivo: `trace_03_viola_a1_inicio.txt`
- Veredito esperado: ⊥
- Propriedade(s): A1

Peça retirada antes de a janela de abastecimento abrir. A1 detecta a
violação já na primeira posição do traço. As demais propriedades não
chegam a ser exercitadas, pois o veredito composto já é levado a ⊥.

## 04 — `rem_i` após `leave_ab_i`

- Arquivo: `trace_04_viola_a1_apos_leave.txt`
- Veredito esperado: ⊥
- Propriedade(s): A1 (e A3 simultaneamente)

Operador tenta retirar peça depois do fim da janela. A1 e A3 disparam
juntas na quarta posição: A1 porque o `rem_i` está fora da janela, e A3
porque o `rem_i` segue um `leave_ab_i` sem que tenha chegado `match_i` ou
`div_i` enquanto o autômato estava aguardando o pronunciamento.

## 05 — Janela vazia (aceitação vacuosa)

- Arquivo: `trace_05_aceita_vazio.txt`
- Veredito esperado: ⊤
- Propriedade(s): nenhuma viola (janela vacuosa)

`ab_i` → `leave_ab_i` → `match_i`, sem nenhuma retirada. A1 é trivialmente
satisfeita (não há `rem_i`). Como `M_obs = M_dec = ∅`, o agente emite
`match_i` automaticamente, satisfazendo A3. Sem peça retirada não há
obrigação de classificar, então A2 aceita vacuosamente (marca `m2SawRem`,
ver D2 em `docs/DECISOES.md`).

## 06 — Braço 1 com mix de OPs

- Arquivo: `trace_06_aceita_braco1_mix.txt`
- Veredito esperado: ⊤
- Propriedade(s): nenhuma viola (caminho feliz)

Cenário real de rotomoldagem multi-braço (Situação 1 do artigo). Há quatro
posições físicas: duas caixas 1000L (OP A), uma caixa 2000L (OP B) e um
molde vazio para balanceamento, que não dispara `rem_i` nem `cls_p_i`. O
cabeçalho declara `m_dec: {caixa_1000L: 2, caixa_2000L: 1}`, e
`M_obs = M_dec`, resultando em `match_i`.

## 07 — Braço 2 com OP uniforme

- Arquivo: `trace_07_aceita_braco2_uniforme.txt`
- Veredito esperado: ⊤
- Propriedade(s): nenhuma viola (caminho feliz)

Job uniforme: uma única OP e um único SKU (quatro caixas 2000L). O
cabeçalho declara `m_dec: {caixa_2000L: 4}` e `M_obs = M_dec` leva a
aceitação direta com `match_i`.

## 08 — Molde vazio esquecido no MES

- Arquivo: `trace_08_viola_a4_molde_vazio.txt`
- Veredito esperado: ⊥
- Propriedade(s): A4

Realidade física idêntica ao cenário 06 (duas 1000L, uma 2000L e um molde
vazio), mas o PCP esqueceu de declarar a posição vazia no MES, então
`m_dec: {caixa_1000L: 2, caixa_2000L: 2}` diverge de `M_obs`. O agente não
emite `match_i` nem `div_i` ao fim da janela; o mes-bridge injeta um
`div_i` sintético no instante do `leave_ab_i`, satisfazendo A3 mas armando
A4, que viola por ausência de `esc_pcp_i` dentro de `Tpcp`. Era um falso
negativo da Peça 1 (só A1).

## 09 — OP errada no PLC

- Arquivo: `trace_09_viola_a4_op_errada.txt`
- Veredito esperado: ⊥
- Propriedade(s): A4

O braço 2 produziu quatro caixas 1000L porque os moldes físicos eram para
1000L, mas a OP no MES continua dizendo `caixa_2000L: 4` — divergência
total entre `M_obs` e `M_dec`. O mecanismo é idêntico ao do cenário 08, só
mudando o SKU: o mes-bridge injeta `div_i`, A3 fica satisfeita e A4 viola
por falta da escalação `esc_pcp_i`.

## 13 — Deriva da CNN

- Arquivo: `trace_13_viola_a4_deriva_cnn.txt`
- Veredito esperado: ⊥
- Propriedade(s): A5 → A2 + A4

Câmera suja ou modelo desatualizado: todas as classificações têm
`conf < τ = 0.85`. O filtro A5 descarta cada `cls_p_i`, deixando `M_obs`
vazio. Isso encadeia duas violações: A2 fica pendente desde o primeiro
`rem_i` (nenhuma classificação aceita resolve a pendência) e viola ao fim
do traço; e o mes-bridge, ao comparar `M_obs = ∅` com `M_dec`, injeta
`div_i`, armando A4, que viola por falta de `esc_pcp_i`. Demonstra a
composição capturando uma mesma causa raiz por dois ângulos (D4).

## 14 — Classificação atrasada

- Arquivo: `trace_14_viola_a2_classificacao_atrasada.txt`
- Veredito esperado: ⊥
- Propriedade(s): A2

A peça é retirada e a janela fecha sem classificação válida acumulada. O
MES confirma a contagem com `match_i` dentro de `Tdec` (satisfazendo A3),
mas a classificação da CNN só chega em `t=5000`, 4000 ms após o
`leave_ab_i` em `t=1000`, excedendo o `Tcls=2000` declarado no cabeçalho.
O relógio de A2, ancorado no fecho da janela, expira no sumidouro
`timeout_cls_i` e viola A2 (ver D1).

## 15 — Escalação atrasada

- Arquivo: `trace_15_viola_a4_escalacao_atrasada.txt`
- Veredito esperado: ⊥
- Propriedade(s): A4

O agente detecta corretamente a divergência ao final da janela
(`M_obs = {2000L:1} ≠ M_dec = {2000L:2}`) e emite `div_i` em `t=4500`.
Porém, a escalação ao PCP só chega em `t=305000`, um intervalo de 300500
ms acima do `Tpcp` de 300000 ms (5 min). O próprio `esc_pcp_i` atrasado é
o evento que dispara o sumidouro de A4 — chegou tarde demais.

## 16 — Decisão atrasada

- Arquivo: `trace_16_viola_a3_decisao_atrasada.txt`
- Veredito esperado: ⊥
- Propriedade(s): A3

A peça é retirada e classificada dentro da janela, satisfazendo A2. A
janela fecha em `t=2000`, mas o mes-bridge só emite o pronunciamento
(`match_i`) em `t=5000`, 3000 ms depois, excedendo o `Tdec=2000` declarado
no cabeçalho. O relógio de A3 expira no sumidouro `leave_ab_silent_i` e
viola A3 (ver D3). Este cenário foi criado especificamente para cobrir A3.

## Cenários fora de escopo (extras/)

Os traços em `Files/Traces/extras/` exercitam propriedades classificadas
como trabalho futuro no artigo (§6), que não integram o monitor composto
da v2. Ficam fora da suíte canônica e da bateria de testes, preservados
como referência das extensões (ver `Files/Traces/extras/README.md` e D5).

| #  | Arquivo                                | Propriedade (futura) |
|----|----------------------------------------|----------------------|
| 10 | `trace_10_refugo_peca_defeituosa.txt`  | A7 (`rej_i`)         |
| 11 | `trace_11_janela_longa.txt`            | A8 (`T_ab_max`)      |
| 12 | `trace_12_agente_morto.txt`            | A6 (heartbeat)       |
