# Cenários cobertos

Os 15 cenários abaixo derivam da análise operacional da rotomoldagem
multi-braço descrita no documento
`Cenarios_Realistas_Rotomoldagem.md` (Miozzi, 2026). Cada cenário vira
ao menos um arquivo de traço em `Files/Traces/`.

Esta tabela é a "carta dos cenários" — combinada com a matriz
[propriedade × cenário](#matriz-propriedade--cenário) abaixo, descreve
exatamente o que cada propriedade do monitor é capaz de capturar.

## Resumo

| #  | Arquivo                                              | Veredito | Regra que dispara |
|----|------------------------------------------------------|---------:|-------------------|
| 01 | `trace_01_aceita_simples.txt`                        | ⊤        | — |
| 02 | `trace_02_aceita_multiplas.txt`                      | ⊤        | — |
| 03 | `trace_03_viola_a1_inicio.txt`                       | ⊥        | A1 |
| 04 | `trace_04_viola_a1_apos_leave.txt`                   | ⊥        | A1 + A3 (rem pós-leave já dispara A3 também) |
| 05 | `trace_05_aceita_vazio.txt`                          | ⊤        | — |
| 06 | `trace_06_aceita_braco1_mix.txt`                     | ⊤        | — |
| 07 | `trace_07_aceita_braco2_uniforme.txt`                | ⊤        | — |
| 08 | `trace_08_viola_a4_molde_vazio.txt`                  | ⊥        | A4 (mes-bridge injeta div_i, esc_pcp_i não chega) |
| 09 | `trace_09_viola_a4_op_errada.txt`                    | ⊥        | A4 (mes-bridge injeta div_i, esc_pcp_i não chega) |
| 10 | `trace_10_refugo_peca_defeituosa.txt`                | ⊥        | A7 (rej_i sem cls recente) |
| 11 | `trace_11_janela_longa.txt`                          | ⊥        | A8 (ab_i sem leave_ab_i em T_ab_max) |
| 12 | `trace_12_agente_morto.txt`                          | ⊥        | A6 (gap entre heartbeats > T_h) |
| 13 | `trace_13_viola_a4_deriva_cnn.txt`                   | ⊥        | A2 + A4 (cls em conf<τ falha A2; mes-bridge injeta div_i; esc_pcp_i não chega) |
| 14 | `trace_14_viola_a2_classificacao_atrasada.txt`       | ⊥        | A2 (gap entre rem_i e cls > T_cls) |
| 15 | `trace_15_viola_a4_escalacao_atrasada.txt`           | ⊥        | A4 (gap entre div_i e esc_pcp_i > T_pcp) |

**Total:** 5 aceitas + 10 violadas. A suite de testes cobre 15 + o
`smoke_formato_estendido.txt`.

## Matriz propriedade × cenário

| Cenário | A1 | A2 | A3 | A4 | A5 | A6 | A7 | A8 | Veredito |
|---------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|---------:|
| 01      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤ |
| 02      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤ |
| 03      | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 04      | **⊥**  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 05      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤ |
| 06      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤ |
| 07      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤ |
| 08      | ⊤  | ⊤  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 09      | ⊤  | ⊤  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 10      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | **⊥**  | ⊤  | ⊥ |
| 11      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | **⊥**  | ⊥ |
| 12      | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊥ |
| 13      | ⊤  | **⊥**  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 14      | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |
| 15      | ⊤  | ⊤  | ⊤  | **⊥**  | ⊤  | ⊤  | ⊤  | ⊤  | ⊥ |

**Veredito composto** = ínfimo da linha (Proposição 2 do artigo).

## Detalhes por cenário

### 01 — Aceitação canônica (1 peça)

Sequência mínima de aceitação. Útil para confirmar que o monitor passa
no caminho feliz. Não tem header com m_dec — caminho legado.

### 02 — Aceitação múltiplas peças

Três retiradas/classificações na mesma janela. Cenário típico de um
braço com vários moldes.

### 03 — `rem_i` antes de `ab_i`

Operador retira peça antes da janela abrir. A1 detecta na posição #1.
Outras propriedades não chegam a ser exercitadas — A1 já levou a
composto a ⊥.

### 04 — `rem_i` após `leave_ab_i`

Operador tenta retirar depois do fim da janela. **A1 e A3 disparam
juntas na posição #4**: A1 porque rem é fora da janela; A3 porque o
rem segue um leave_ab_i sem que tenha chegado match/div.

### 05 — Janela vazia

`ab_i` → `leave_ab_i` → `match_i`. M_obs = M_dec = ∅ ≡ match trivial.
O `match_i` final é necessário para A3 — sem ele, A3 violaria
ao chegar ao fim do traço em Awaiting.

### 06 — Braço 1 com mix OP A + OP B + molde vazio

Cenário real da rotomoldagem (Situação 1). 4 posições físicas: 2× 1000L
(OP A), 1× 2000L (OP B), 1 molde vazio para balanceamento (não dispara
rem_i nem cls_p_i). M_obs = M_dec = {1000L:2, 2000L:1} → match.

### 07 — Braço 2 com OP C uniforme

Job uniforme: uma só OP, um só SKU (4× caixa_2000L). Aceitação direta.

### 08 — Molde vazio esquecido no MES

**Falso negativo da Peça 1 (artigo).** Realidade física idêntica ao
cenário 6, mas o PCP não declarou a posição vazia no MES.
M_dec efetivo = {1000L:2, 2000L:2} ≠ M_obs = {1000L:2, 2000L:1}.

O traço não emite match nem div após leave_ab_i. O mes-bridge interno
do emulador injeta `div_i`. A3 fica satisfeita pelo div injetado, mas
A4 passa a esperar esc_pcp_i em T_pcp — que não chega no traço → A4
viola ao fim.

**Histórico:** Peça 1 (só A1) aceitava (falso negativo); Fase 3 (+A3)
detectava o silêncio; Fase 6 (mes-bridge) realocou a violação para A4.

### 09 — OP errada no PLC

**Falso negativo da Peça 1 (artigo).** Realidade física: 4× caixa_1000L
produzidas (porque os moldes físicos eram para 1000L). A OP no MES
continua dizendo "4× caixa_2000L". Divergência total.

Mecanismo idêntico ao cenário 8 — só muda o SKU. mes-bridge injeta div,
A4 viola por falta de esc_pcp_i.

### 10 — Refugo sem classificação prévia

A peça sai do molde com defeito. O operador retira (`rem_i`) e marca
como refugo (`rej_i`) ANTES de uma classificação. A7 exige cls recente
em T_rej (default 10 s); como não há, viola.

### 11 — Janela longa demais (34 min)

`ab_i` em t=0, `leave_ab_i` em t=2040000 ms (34 min). Todas as outras
propriedades satisfeitas (rem dentro da janela, cls em T_cls, match no
final), mas a janela excede T_ab_max=15 min → A8 viola.

Impacto operacional: o braço bloqueia a estação de abastecimento,
paralisando o ciclo dos demais (forno compartilhado).

### 12 — Agente morto

Trace começa com heartbeat em t=0 (arma A6). Heartbeats em 3000 e 13000
ms — gap de 10 s entre os dois últimos > T_h=5 s → A6 viola.

Cenário real: o vision-agent caiu silenciosamente. O processo físico
continuou; o monitor sem A6 ficaria sem perceber.

### 13 — Deriva da CNN

Todas as cls com `conf < τ` → A5 filtra tudo → M_obs = ∅. Duas
propriedades violam:

- **A2** — rem_i ficam em Pending porque nenhum cls confiável os
  resolve. No fim do traço, A2 está pendente → finalVerdict ⊥.
- **A4** — mes-bridge ao detectar M_obs=∅ ≠ M_dec={2000L:4} injeta
  div_i, mas esc_pcp_i não chega → finalVerdict ⊥.

Composto: ⊥ com regras `[A2, A4]`. A causa raiz operacional ("CNN com
deriva") é métrica observacional fora do escopo LTL (taxa de cls com
conf < τ); aqui o monitor sinaliza o sintoma, não o diagnóstico.

### 14 — Classificação atrasada

Operador retira em t=1500. CNN devolve cls em t=35000 (gap 33500 ms >
T_cls=30000) → A2 viola no evento da classificação.

### 15 — Escalação atrasada

div_i em t=4500 (após leave_ab_i com mes-bridge não interveniente
porque o traço já traz div_i explícito). esc_pcp_i em t=305000 → gap
300500 > T_pcp=300000 → A4 viola no esc_pcp_i atrasado.

## Cobertura observada

| Aut. | Cenários onde viola |
|------|---------------------|
| A1 | 03, 04 |
| A2 | 13, 14 |
| A3 | 04 (junto com A1) |
| A4 | 08, 09, 13, 15 |
| A6 | 12 |
| A7 | 10 |
| A8 | 11 |

Cada propriedade tem pelo menos um cenário onde é a regra principal —
exceto A5, que é estrutural (filtro de confiança). A composição é
exercitada explicitamente pelo cenário 04 (A1+A3) e pelo cenário 13
(A2+A4).

## Cenários historicamente "falsos negativos"

Os cenários **08** e **09** receberam, ao longo das fases, vereditos
diferentes — registro útil para a defesa do mestrado:

| Fase implementada | Cenário 08 / 09 |
|-------------------|-----------------|
| Peça 1 (só A1)    | **⊤ — falso negativo** (rem_i todos dentro da janela) |
| Fase 3 (+A3)      | ⊥ — A3 detecta o silêncio ao fim da janela |
| Fase 6 (mes-bridge) | ⊥ — A4 (div_i injetado; esc_pcp_i ausente) |

Esse arco mostra que o monitor composto **não substitui** A1 — ele
acrescenta capturas adicionais que A1 sozinho não fazia.

## O que está fora

- Tabela 1 da Seção 4.3 do artigo distingue propriedades obrigatórias
  (A1–A4) das condicionais (A5). O emulador reflete essa estrutura.
- Cenários puramente observacionais (deriva da CNN como métrica
  estatística, OEE auditável) não são propriedades LTL e ficam de fora
  do monitor formal — apenas comentados nos respectivos traços.
- Posição do molde no carrossel (cenário 8 do `Cenarios_Realistas`)
  não é capturada porque o monitor opera sobre multiconjuntos, não
  sobre sequências ordenadas (decisão de modelagem deliberada).
