# Decisões de projeto — alinhamento com a v2_3 do artigo

Registro das decisões tomadas na refatoração do emulador para a versão
normativa v2_3 do artigo. O recorte verificado é A1 (safety), A2 e A3
(liveness temporizadas) e A5 (filtro estrutural de confiança τ) — a
numeração salta A4 (footnote 4 do artigo). Cada item indica a referência
canônica e a justificativa.

## D1 — A2 ancorada em `leave_ab_i` (não em `rem_i`)

A2 é **liveness temporizada**: `G(leave_ab_i → F[0,T_cls] ⋁ cls^{≥τ})`.
O relógio é zerado no **encerramento da janela** (`leave_ab_i`), não na
retirada individual.

- **Ref.:** Tabela 2 (A2); `fig-automato-a2-tltl` (caption v2: "a ancoragem
  temporal é o encerramento da janela de abastecimento").
- **Antes:** o código ancorava em `rem_i` (modelo pré-v2).

## D2 — Existência agregada + janela vacuosa

No `leave_ab_i`, A2 é satisfeita se **alguma** `cls^{≥τ}` ocorreu desde a
abertura da janela (`ab_i`) — a legenda da figura define o intervalo como
`[τ_a, τ_b + T_cls]`, que inclui a janela. Caso nenhuma classificação
válida tenha sido vista, inicia-se o relógio (até `T_cls` para uma tardia).

- **Janela vazia (sem `rem_i`)**: vacuosamente aceita (TOP). Sem peça
  retirada, não há obrigação de classificar. Implementado via a marca
  `m2SawRem` em `Monitor.Automata.A2`.
- **Decisão confirmada com o autor.** Preserva `trace_05_aceita_vazio` como
  TOP e reconcilia a figura (que, ao pé da letra, exigiria classificação
  após o `leave_ab_i`) com a legenda (existência agregada).

## D3 — A3 é liveness temporizada (`T_dec`), não safety

A3: `G(leave_ab_i → F[0,T_dec] (match_i ∨ div_i))`, com
`T_dec = T_cls + ε` e `T_dec ≥ T_cls`.

- **Ref.:** Tabela 2 (A3); `fig-automato-a3-tltl` ("A3 reformulada (v2)").
- **Antes:** o código modelava A3 como safety (sem relógio), exigindo
  match/div como evento imediatamente seguinte ao `leave_ab_i`.
- O parâmetro `T_dec` foi adicionado a `Monitor.Types.Config` (`cfgTdec`).

## D4 — Evento derivado `div_i`: exatamente dois disjuntos

`div_i := mismatch_i ∨ fora_ciclo_i` — **dois** disjuntos, e somente dois
(§3.4). A forma de quatro disjuntos da v2 antiga (`mismatch ∨ timeout_cls
∨ leave_ab_silent ∨ fora_ciclo`) está **errada**: a nota † da Tabela 2
define apenas os dois acima.

- `mismatch_i`: emitido pelo mes-bridge em `τ_b + T_cls + δ_mb` quando
  `M_obs[τ_a, τ_b + T_cls] ≠ M_dec` (com `δ_mb ≤ T_dec − T_cls`).
- `fora_ciclo_i`: exceções estruturais do ciclo (ex.: `leave_ab` duplicado,
  pronunciamento espúrio) e a violação de safety de A1 (capturada como
  `fora_ciclo` com diagnóstico `safety_A1`).

Os sumidouros temporais **não** são `div_i` e **não** armam A4. São
eventos sintéticos de diagnóstico roteados pelo gate (ver D10):

- `timeout_cls_i` — sumidouro de M₂ (A2): classificação ausente em `T_cls`
  → status `erro_classificacao`.
- `leave_ab_silent_i` — sumidouro de M₃ (A3): mes-bridge mudo em `T_dec`
  → status `erro_decisao`.

- **Ref.:** definição `div_i := mismatch_i ∨ fora_ciclo_i` (§3.4,
  Tabela 2 nota †); `Monitor.Types.Event` (construtor `DivI`, comentário
  "macro-evento derivado") e `Monitor.Gate.firstDiv`/`decide`.
- **Antes:** a cadeia v2 "A2/A3 → `div_i` sintético → arma A4 → PCP" foi
  **removida** do código. `Monitor.Composed.step` não promove mais `div_i`
  sintético; os sumidouros são detectados via `A2.finalVerdict` /
  `A3.finalVerdict` e roteados a status terminais distintos.
- Demonstrado por `trace_13_viola_a2_deriva_cnn` (A5 esvazia `M_obs` → A2
  pendente → `erro_classificacao`, diag `timeout_cls`).

## D5 — A4/A6/A7/A8 fora do monitor composto (extensões prospectivas)

O monitor composto verificado é `M = M_1 ⊗ M_2 ⊗ M_3` (produto sincronizado
de **três** componentes: A1, A2, A3), com o filtro A5 a montante. **Não há
M₄ no produto.** Qualquer "`M_1 ⊗ M_2 ⊗ M_3 ⊗ M_4`" ou "A1–A4 no monitor
composto" é v2 obsoleto. A4 (escalonamento ao PCP), A6 (heartbeat
Armed/Unarmed), A7 (refugo `rej_i`) e A8 (janela ≤ `T_ab_max`) são
**extensões prospectivas** (artigo §6), situadas **fora** do recorte
avaliado.

- Os módulos `Monitor.Automata.A4/A6/A7/A8` permanecem no repositório como
  protótipos isolados, mas **fora** de `Monitor.Composed` — não são
  importados pelo monitor composto, pelo README canônico nem pela contagem
  de propriedades do recorte. (Mantidos, não removidos — preservam a prova
  de conceito; ver os comentários de cabeçalho em `Monitor.Types`.)
- **Decisão confirmada com o autor.** Os traços que exercitavam essas
  propriedades foram **realocados** para `Files/Traces/extras/` (ver
  `Files/Traces/extras/README.md`): `trace_10` (A7), `trace_11` (A8),
  `trace_12` (A6), `trace_15` (A4). Não foram deletados.

## D6 — Parâmetros por traço sobrepõem os defaults

O campo `parametros: {Tcls, Tdec, Tpcp, tau}` do cabeçalho YAML sobrepõe os
defaults globais de `Config`. Implementado em `Monitor.Header.applyParams`,
usado **tanto** pela CLI (`Main`) quanto pela suíte de testes
(`ExampleTraces`) — garantindo vereditos idênticos entre as duas.

Os defaults do monitor verificado vêm do cenário-âncora do artigo (§4) e
estão em `Monitor.Types.defaultConfig`:

- `T_cls = 1500 ms` (latência máxima de classificação, A2);
- `ε = 200 ms` e `T_dec = T_cls + ε = 1700 ms` (prazo de decisão, A3);
- `δ_mb = 100 ms` (latência de comparação do mes-bridge, com
  `δ_mb ≤ T_dec − T_cls = 200 ms`);
- `τ = 0.85` (limiar de confiança da CNN, A5).

- **Antes:** o campo era ignorado e tudo usava `defaultConfig` com os
  valores v2 antigos (Tcls=30 s, Tdec=31 s), tornando os relógios
  temporizados inertes em traços curtos. Esses valores não são mais usados.
- `Tpcp` (A4) permanece aceito por `applyParams` apenas para os protótipos
  prospectivos: **não** é parâmetro do monitor verificado e **não** é
  fixado pelo artigo (valor ilustrativo). `δ_mb` é parâmetro de `Config`
  (`cfgDeltaMb`), mas não é exposto como chave de `parametros`.

## D7 — Vereditos LTL₃ e códigos de saída

Renderização canônica única (`Monitor.Types.showVerdict`), conforme Bauer,
Leucker e Schallhart (2011), reticulado `⊥ < ? < ⊤`:

- CLI: `⊤ (Top — Aceita)` / `⊥ (Bot — Viola)` / `? (Inconclusive)`.
- YAML/JSON: `TOP` / `BOT` / `INCONCLUSIVE`.
- Removido o sufixo booleano `(T)`/`(F)` (incorreto em LTL₃).

Os códigos de saída do executável, porém, são roteados pelo **status do
gate** (`grStatus`), não pelo veredito composto (ver D10 e
`Monitor.Gate.run`; `exitOn` em `app/Main.hs`):

- `0` = `liberado_integracao`;
- `2` = qualquer bloqueio (`divergencia_pcp` / `erro_classificacao` /
  `erro_decisao`);
- `3` = `pendente_verificacao`;
- `1` = erro de uso/parsing/IO.

O `2` agrega os três status de bloqueio porque a distinção de causa-raiz
fica no diagnóstico textual, não no código de saída. O `3` distingue
pendente de erro (antes ambos eram `1`).

## D8 — Índice de braço `j` implícito

O artigo usa subscrito de braço (`rem_{i,j}`, `cls_{p,i,j}`). O emulador
opera **por braço**: um traço corresponde a um braço `i`, com `j`
implícito. O formato de traço mantém `rem_i` / `cls_p_i`. Expandir o parser
para `j` explícito fica como trabalho futuro.

## D9 — Suíte canônica de cenários

`Files/Traces/` contém **12** traços canônicos do recorte verificado
(A1–A3 + A5), cada um com `veredito_esperado` (veredito composto) e
`status_esperado` (status terminal do gate) no cabeçalho YAML, verificados
por `cabal test`:

| Veredito | Status do gate | Traços | Propriedade / causa |
|---|---|---|---|
| ⊤ | `liberado_integracao` | 01, 02, 06, 07 | caminho feliz |
| ⊤ | `liberado_integracao` | 05 | janela vazia (vacuosa) |
| ⊥ | `divergencia_pcp` (`safety_A1`) | 03, 04 | A1 (rem fora da janela) |
| ⊥ | `erro_classificacao` (`timeout_cls`) | 13, 14 | A2 (classificação ausente/tardia) |
| ⊥ | `erro_decisao` (`leave_ab_silent`) | 16 | A3 (decisão tardia) |
| ⊤ | `divergencia_pcp` (`mismatch`) | 08, 09 | div_i (M_obs ≠ M_dec) |

Note a distinção essencial (ver D11): `trace_08`/`trace_09` têm veredito
composto **⊤** (A1/A2/A3 satisfeitas — a decisão foi tomada em prazo), mas
o gate **bloqueia** com `divergencia_pcp` por `mismatch`. `trace_13`
(deriva da CNN, A5 esvazia `M_obs`) viola A2 e é roteado a
`erro_classificacao`, não mais a "A2 + A4".

Histórico de renomeações v2 → v2_3: `trace_08`/`trace_09` foram
`viola_a4_*` e passaram a `divergencia_*`; `trace_13` foi
`viola_a4_deriva_cnn` e passou a `viola_a2_deriva_cnn`. `trace_14` foi
**redesenhado** para a nova A2 (a versão antiga violava por ancoragem em
`rem_i`); `trace_16` cobre A3. Os índices 10/11/12/15 foram **realocados** a
`extras/` (extensões prospectivas, ver D5); não houve renumeração dos
demais (preserva histórico git).

### Contagem honesta de cenários (F8)

O artigo cita "15 cenários" e "400 traços aleatórios" como métricas
distintas. O emulador materializa, de fato:

- **12** cenários canônicos curados (recorte verificado A1–A3 + A5), em
  `Files/Traces/`;
- **4** cenários prospectivos (§6: A4/A6/A7/A8), em `Files/Traces/extras/`;
- o **corpus de 400 traços aleatórios** (PBT da Proposição 2), em
  `Files/Corpus/`, gerado por `cabal run corpus-gen` com PRNG determinístico
  (semente fixa, reproduzível). A Proposição 2 foi confirmada em 400/400.
  Distribuição: 208 ⊤ / 192 ⊥; gate 138 `liberado_integracao` /
  70 `divergencia_pcp` / 155 `erro_classificacao` / 37 `erro_decisao`.

A soma 12 + 4 = 16 traços curados aproxima o "15" do artigo sem coincidir
exatamente; os dois conjuntos foram mantidos sincronizados na intenção, não
na contagem literal. Esta documentação declara os números reais.

## D10 — Gate é um efetor de quatro status, não binário

O gate **não** é mais binário (`Liberar | Bloquear [regras]`). É um efetor
que transita o apontamento de `pendente_verificacao` para **um de quatro**
status terminais, por causa-raiz, anexando um diagnóstico auditável
(§5.4, Algoritmo 1, Figura 9, Tabelas 3–4). Implementado em
`Monitor.Gate.decide` / `run`; os status e diagnósticos vivem em
`Monitor.Types` (`MesStatus`, `Diag`).

| Status | Disparo | Diagnóstico | Escala para |
|---|---|---|---|
| `liberado_integracao` | `match_i` dentro de `T_dec`, sem violação | — | integração nativa MES→ERP |
| `divergencia_pcp` | `div_i` (`mismatch ∨ fora_ciclo`) ou safety de A1 | `mismatch` / `fora_ciclo` / `safety_A1` | PCP (tratativa manual) |
| `erro_classificacao` | sumidouro de M₂ (A2) | `timeout_cls` | time de visão computacional |
| `erro_decisao` | sumidouro de M₃ (A3) | `leave_ab_silent` | TI |

A ordem de prioridade do roteamento segue exatamente o Algoritmo 1:
`sinkM1 → sinkM2 → sinkM3 → div → match` (ver as guardas de
`Monitor.Gate.decide`). Os sumidouros são detectados por
`A1/A2/A3.finalVerdict`, cobrindo tanto a expiração de relógio durante o
stream quanto a obrigação pendente ao fim do traço.

## D11 — Veredito composto ≠ status do gate

Distinção essencial: o **veredito composto** (Proposição 2: ínfimo dos
vereditos de M₁, M₂, M₃ no reticulado `⊥ < ? < ⊤`) é uma propriedade
**formal**; o **status do gate** é uma decisão **de processo**. Os dois não
coincidem em geral.

- Um `mismatch_i` tem veredito composto **⊤** (A1, A2 e A3 satisfeitas — a
  decisão foi tomada em prazo), mas o gate **bloqueia** com
  `divergencia_pcp`, pois `div_i` é decisão de processo, não violação de
  propriedade. Ver `trace_08`/`trace_09` (D9).
- Por isso `GateResult` carrega ambos: `grVerdict` (composto, terminal) e
  `grStatus` (gate). O cabeçalho de traço também separa `veredito_esperado`
  de `status_esperado` (ver `docs/FORMATO_TRACE.md`).
