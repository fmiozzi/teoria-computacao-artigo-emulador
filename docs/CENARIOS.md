# Cenários canônicos

A suíte canônica reúne os 12 traços de `Files/Traces/` que exercitam o
monitor composto da v2_3, `M = M_1 ⊗ M_2 ⊗ M_3` (produto sincronizado de
TRÊS componentes, propriedades A1, A2, A3), com o filtro A5 a montante.
Todos trazem `veredito_esperado` (veredito composto) e `status_esperado`
(status terminal do gate) no cabeçalho YAML e são verificados por
`cabal test`. As decisões de modelagem por trás destes cenários estão
registradas em `docs/DECISOES.md`.

O recorte verificado/avaliado é A1, A2, A3 e A5. A numeração SALTA A4
(footnote 4 do artigo); A4 e as demais extensões (A6, A7, A8) são
prospectivas (§6) e ficam fora do recorte (ver última seção).

As propriedades monitoradas são:

- **A1** (safety): `G(rem_i → ab_i)` — retirada só dentro da janela.
- **A2** (liveness temporizada, relógio T_cls):
  `G(leave_ab_i → F[0,Tcls] cls^{≥τ})`.
- **A3** (liveness temporizada, relógio T_dec):
  `G(leave_ab_i → F[0,Tdec] (match_i ∨ div_i))`.
- **A5** (filtro condicional): `conf ≥ τ → M_obs` — descarta
  classificações de baixa confiança antes de compor `M_obs`.

O veredito composto é o ínfimo dos vereditos de `M_1, M_2, M_3` no
reticulado LTL₃ `⊥ < ? < ⊤` (Proposição 2 do artigo).

## Veredito composto ≠ status do gate

O **veredito composto** mede satisfação das propriedades A1/A2/A3. O
**status do gate** é a decisão de processo do efetor (Algoritmo 1, §5.4),
que transita o apontamento de `pendente_verificacao` para UM de quatro
status terminais por causa-raiz:

1. `liberado_integracao` — `match_i` dentro de `T_dec`, sem violação →
   integração nativa MES→ERP.
2. `divergencia_pcp` — `div_i` (`mismatch ∨ fora_ciclo`) OU safety de A1
   (diag `mismatch | fora_ciclo | safety_A1`) → tratativa manual no PCP.
3. `erro_classificacao` — sumidouro de M₂ (diag `timeout_cls`):
   classificação ausente em `T_cls` → time de visão computacional.
4. `erro_decisao` — sumidouro de M₃ (diag `leave_ab_silent`): mes-bridge
   mudo em `T_dec` → TI.

A ordem de prioridade do Algoritmo 1 é
`sinkM1 → sinkM2 → sinkM3 → div → match`. Os dois eixos podem divergir: um
`mismatch` tem veredito composto ⊤ (A1/A2/A3 satisfeitas — a decisão foi
tomada no prazo), mas o gate BLOQUEIA com `divergencia_pcp`, pois `div_i`
é decisão de PROCESSO, não violação de propriedade.

Códigos de saída do CLI: `0` = `liberado_integracao`; `2` = qualquer
BLOQUEAR (`divergencia_pcp` / `erro_classificacao` / `erro_decisao`);
`3` = pendente; `1` = erro de uso/parsing.

## Resumo

| #  | Arquivo                                         | Veredito composto | Status do gate (diag)          |
|----|-------------------------------------------------|:-----------------:|--------------------------------|
| 01 | `trace_01_aceita_simples.txt`                   |        ⊤          | `liberado_integracao`          |
| 02 | `trace_02_aceita_multiplas.txt`                 |        ⊤          | `liberado_integracao`          |
| 03 | `trace_03_viola_a1_inicio.txt`                  |        ⊥          | `divergencia_pcp` (safety_A1)  |
| 04 | `trace_04_viola_a1_apos_leave.txt`              |        ⊥          | `divergencia_pcp` (safety_A1)  |
| 05 | `trace_05_aceita_vazio.txt`                     |        ⊤          | `liberado_integracao`          |
| 06 | `trace_06_aceita_braco1_mix.txt`                |        ⊤          | `liberado_integracao`          |
| 07 | `trace_07_aceita_braco2_uniforme.txt`           |        ⊤          | `liberado_integracao`          |
| 08 | `trace_08_divergencia_molde_vazio.txt`          |        ⊤          | `divergencia_pcp` (mismatch)   |
| 09 | `trace_09_divergencia_op_errada.txt`            |        ⊤          | `divergencia_pcp` (mismatch)   |
| 13 | `trace_13_viola_a2_deriva_cnn.txt`              |        ⊥          | `erro_classificacao` (timeout_cls) |
| 14 | `trace_14_viola_a2_classificacao_atrasada.txt`  |        ⊥          | `erro_classificacao`           |
| 16 | `trace_16_viola_a3_decisao_atrasada.txt`        |        ⊥          | `erro_decisao` (leave_ab_silent) |

Total: 12 cenários canônicos curados — 5 com veredito composto ⊤ e
status `liberado_integracao`, 2 com veredito composto ⊤ mas gate
`divergencia_pcp` (08/09, `mismatch`), e 5 com veredito composto ⊥. Os
índices 10/11/12/15 ficaram em `extras/` (ver última seção); não houve
renumeração dos demais, para preservar o histórico do repositório.

> Relação com a contagem do artigo: o artigo cita "15 cenários" e "400
> traços aleatórios" como métricas distintas. O emulador materializa
> estes 12 cenários canônicos curados (recorte verificado A1–A3+A5), mais
> 4 prospectivos em `extras/` (§6), mais o corpus de 400 traços aleatórios
> (PBT da Proposição 2, em `Files/Corpus/`). Os 12 + extras compõem a
> curadoria manual; os números não são idênticos ao "15" citado no texto.

## 01 — Aceitação canônica (uma peça)

- Arquivo: `trace_01_aceita_simples.txt`
- Veredito composto: ⊤
- Status do gate: `liberado_integracao`

Sequência mínima de aceitação: `ab_i`, `rem_i`, classificação,
`leave_ab_i`, `match_i`. Confirma que o monitor passa no caminho feliz e
que o gate libera a integração MES→ERP. O traço não traz cabeçalho com
`m_dec` — exercita o caminho legado em que a contagem decidida não é
informada.

## 02 — Aceitação com múltiplas peças

- Arquivo: `trace_02_aceita_multiplas.txt`
- Veredito composto: ⊤
- Status do gate: `liberado_integracao`

Três retiradas e três classificações na mesma janela (SKUs do
catálogo-âncora) na mesma janela, cada uma com `cls_p_i` aceito. Cenário
típico de um braço com vários moldes que produz um lote heterogêneo, com
`match_i` ao final liberando a integração.

## 03 — `rem_i` antes de `ab_i`

- Arquivo: `trace_03_viola_a1_inicio.txt`
- Veredito composto: ⊥
- Status do gate: `divergencia_pcp` (diag `safety_A1`)

Peça retirada antes de a janela de abastecimento abrir. A1 detecta a
violação de safety já na primeira posição do traço, levando o veredito
composto a ⊥. A violação de safety de A1 é capturada como `fora_ciclo`
com diagnóstico `safety_A1`, e o gate roteia o apontamento a
`divergencia_pcp` (tratativa manual no PCP).

## 04 — `rem_i` após `leave_ab_i`

- Arquivo: `trace_04_viola_a1_apos_leave.txt`
- Veredito composto: ⊥
- Status do gate: `divergencia_pcp` (diag `safety_A1`)

Operador tenta retirar peça depois do fim da janela. A1 dispara na quarta
posição porque o `rem_i` está fora da janela, levando o veredito composto
a ⊥. Como a violação é de safety de A1, o gate roteia a `divergencia_pcp`
com diagnóstico `safety_A1`.

## 05 — Janela vazia (aceitação vacuosa)

- Arquivo: `trace_05_aceita_vazio.txt`
- Veredito composto: ⊤
- Status do gate: `liberado_integracao`

`ab_i` → `leave_ab_i` → `match_i`, sem nenhuma retirada. A1 é trivialmente
satisfeita (não há `rem_i`). Como `M_obs = M_dec = ∅`, o agente emite
`match_i` automaticamente, satisfazendo A3. Sem peça retirada não há
obrigação de classificar, então A2 aceita vacuosamente (marca `m2SawRem`,
ver D2 em `docs/DECISOES.md`). O gate libera a integração.

## 06 — Braço 1 com mix de OPs

- Arquivo: `trace_06_aceita_braco1_mix.txt`
- Veredito composto: ⊤
- Status do gate: `liberado_integracao`

Cenário real de rotomoldagem multi-braço (Situação 1 do artigo). Há quatro
posições físicas: duas `caixa_1000L` (OP A), uma `caixa_500L` (OP B) e um
molde vazio para balanceamento, que não dispara `rem_i` nem `cls_p_i`. O
cabeçalho declara `m_dec: {caixa_1000L: 2, caixa_500L: 1}`, e
`M_obs = M_dec`, resultando em `match_i` e liberação da integração.

## 07 — Braço 2 com OP uniforme

- Arquivo: `trace_07_aceita_braco2_uniforme.txt`
- Veredito composto: ⊤
- Status do gate: `liberado_integracao`

Job uniforme: uma única OP e um único SKU (quatro `caixa_500L`). O
cabeçalho declara `m_dec: {caixa_500L: 4}` e `M_obs = M_dec` leva a
aceitação direta com `match_i` e liberação da integração.

## 08 — Molde vazio esquecido no MES

- Arquivo: `trace_08_divergencia_molde_vazio.txt`
- Veredito composto: ⊤
- Status do gate: `divergencia_pcp` (diag `mismatch`)

Realidade física idêntica ao cenário 06 (duas 1000L, uma 500L e um molde
vazio), mas o PCP esqueceu de declarar a posição vazia no MES, então
`m_dec` diverge de `M_obs`. O mes-bridge compara `M_obs[τ_a, τ_b+T_cls]`
com `M_dec`, detecta a diferença e emite `div_i` por `mismatch` dentro de
`T_dec`. Como a decisão foi tomada no prazo, A1/A2/A3 ficam satisfeitas e
o **veredito composto é ⊤**; mas `div_i` é decisão de processo, então o
gate BLOQUEIA com `divergencia_pcp` (diag `mismatch`) para tratativa
manual no PCP. Ilustra a distinção essencial veredito ≠ status do gate.

## 09 — OP errada no PLC

- Arquivo: `trace_09_divergencia_op_errada.txt`
- Veredito composto: ⊤
- Status do gate: `divergencia_pcp` (diag `mismatch`)

O braço 2 produziu quatro `caixa_1000L` porque os moldes físicos eram para
1000L, mas a OP no MES continua dizendo `caixa_500L: 4` — divergência total
entre `M_obs` e `M_dec`. O mecanismo é idêntico ao do cenário 08: o
mes-bridge emite `div_i` por `mismatch` no prazo, o veredito composto
permanece ⊤ e o gate bloqueia com `divergencia_pcp` (diag `mismatch`).

## 13 — Deriva da CNN

- Arquivo: `trace_13_viola_a2_deriva_cnn.txt`
- Veredito composto: ⊥
- Status do gate: `erro_classificacao` (diag `timeout_cls`)

Câmera suja ou modelo desatualizado: todas as classificações têm
`conf < τ = 0.85`. O filtro A5 descarta cada `cls_p_i`, deixando `M_obs`
vazio. Sem nenhuma classificação aceita até `T_cls`, A2 atinge seu
sumidouro `timeout_cls` e viola, levando o veredito composto a ⊥. O gate
roteia o apontamento a `erro_classificacao` (diag `timeout_cls`),
encaminhando ao time de visão computacional. Demonstra a composição
capturando a causa raiz "CNN ineficaz" pelo ângulo de A2 (D4).

## 14 — Classificação atrasada

- Arquivo: `trace_14_viola_a2_classificacao_atrasada.txt`
- Veredito composto: ⊥
- Status do gate: `erro_classificacao` (diag `timeout_cls`)

A peça é retirada e a janela fecha sem classificação válida acumulada. O
MES confirma a contagem com `match_i` dentro de `T_dec` (satisfazendo A3),
mas a classificação da CNN só chega em `t=5000`, 4000 ms após o
`leave_ab_i` em `t=1000`, excedendo o `T_cls` declarado no cabeçalho. O
relógio de A2, ancorado no fecho da janela, expira no sumidouro
`timeout_cls` e viola A2 (ver D1). O gate roteia a `erro_classificacao`.

## 16 — Decisão atrasada

- Arquivo: `trace_16_viola_a3_decisao_atrasada.txt`
- Veredito composto: ⊥
- Status do gate: `erro_decisao` (diag `leave_ab_silent`)

A peça é retirada e classificada dentro da janela, satisfazendo A2. A
janela fecha em `t=2000`, mas o mes-bridge só emite o pronunciamento
(`match_i`) em `t=5000`, 3000 ms depois, excedendo o `T_dec` declarado no
cabeçalho. O relógio de A3 expira no sumidouro `leave_ab_silent` e viola
A3 (ver D3), levando o veredito composto a ⊥. O gate roteia o apontamento
a `erro_decisao` (mes-bridge mudo no prazo → TI). Este cenário foi criado
especificamente para cobrir A3.

## Cenários fora de escopo (extras/)

Os traços em `Files/Traces/extras/` exercitam propriedades classificadas
como extensões prospectivas no artigo (§6), que NÃO integram o monitor
composto `M_1 ⊗ M_2 ⊗ M_3` da v2_3. Os módulos correspondentes
(`Monitor.Automata.A4/A6/A7/A8`) permanecem no código, isolados e não
importados pelo monitor composto. Ficam fora da suíte canônica e da
bateria de testes, preservados como referência das extensões (ver
`Files/Traces/extras/README.md` e D5).

| #  | Arquivo                                      | Extensão prospectiva (§6)        |
|----|----------------------------------------------|----------------------------------|
| 10 | `trace_10_refugo_peca_defeituosa.txt`        | A7 (`rej_i`, refugo)             |
| 11 | `trace_11_janela_longa.txt`                  | A8 (`T_ab_max`, duração máxima)  |
| 12 | `trace_12_agente_morto.txt`                  | A6 (heartbeat)                   |
| 15 | `trace_15_viola_a4_escalacao_atrasada.txt`   | A4 (escalonamento ao PCP)        |
