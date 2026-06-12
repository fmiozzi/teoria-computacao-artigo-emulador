# Changelog

Todas as fases marcam pontos de release internos durante a construção
incremental do emulador. Datas referem-se ao commit principal de cada fase
no branch `main`.

> **Nota de leitura.** As entradas até a 0.7.0 descrevem o modelo **v2
> antigo** (M₁⊗M₂⊗M₃⊗M₄, `div_i` com 4 disjuntos, gate binário,
> `runMonitor`/`injectMesBridge`, T_cls = 30 s). Elas ficam preservadas
> como histórico, mas **não refletem o estado atual** do código — a
> entrada [0.8.0] abaixo reescreve a arquitetura para o modelo
> **normativo v2_3** do artigo. Onde uma entrada antiga afirma algo hoje
> falso, há uma marca `⚠ obsoleto desde 0.8.0`.

## [1.0.0] — 2026-06-12 (primeiro release público com DOI)

Primeiro release público e arquivado (Zenodo/DOI). O conteúdo técnico é
idêntico à 0.8.0 (alinhamento ao artigo v2_3): núcleo do monitor, composição
por produto sincronizado e o corpus reproduzível de 400 traços. Esta versão
apenas promove a numeração para 1.0.0 e adiciona os metadados de citação
(CITATION.cff, .zenodo.json).

## [0.8.0] — 2026 (alinhamento ao artigo v2_3)

Reescrita do recorte verificado e do efetor para o modelo **normativo
v2_3** (`Artigo_SBC_Teo_Comp_v2_3.pdf`). Esta entrada consolida as
correções F1–F10; o código compila e testa (GHC 9.4.8 via Nix), **43
testes** verdes.

- **F1 — Composição (`Monitor.Composed`).** O monitor verificado passa a
  ser o produto sincronizado de **TRÊS** componentes, `M = M₁ ⊗ M₂ ⊗ M₃`
  (A1 safety, A2′ e A3′ bounded liveness). **A4 sai do produto**: a
  escalada ao PCP é ação determinística do gate, não obrigação verificada.
  Cota de estados ≤ 2×3×3 = 18; cota binária 2^|Φ| = 8 com |Φ| = 3.
- **F2 — Efetor de QUATRO status (`Monitor.Gate`).** O gate deixa de ser
  binário (Liberar | Bloquear). É um efetor (Algoritmo 1, §5.4, Figura 9,
  Tabelas 3–4) que transita o apontamento de `pendente_verificacao` para
  um de quatro status terminais por causa-raiz: `liberado_integracao`,
  `divergencia_pcp`, `erro_classificacao`, `erro_decisao`. Cada bloqueio
  carrega um diagnóstico (`Diag`: `safety_A1` | `mismatch` | `fora_ciclo`
  | `timeout_cls` | `leave_ab_silent`). Ordem de prioridade: sumidouro de
  M₁ → M₂ → M₃ → `div_i` → `match_i`.
- **F3 — `div_i` com DOIS disjuntos (§3.4).** `div_i := mismatch_i ∨
  fora_ciclo_i`. A forma antiga de quatro disjuntos (`mismatch ∨
  timeout_cls ∨ leave_ab_silent ∨ fora_ciclo`) foi removida. `timeout_cls`
  (sumidouro de M₂) e `leave_ab_silent` (sumidouro de M₃) **não** são
  `div_i` — são roteados a `erro_classificacao`/`erro_decisao` pelo gate.
- **F4 — Veredito ≠ status.** O veredito composto (ínfimo no reticulado
  ⊥ < ? < ⊤, Proposição 2) é independente do status do gate. Um
  `mismatch` tem veredito composto ⊤ (A1/A2/A3 satisfeitas) mas o gate
  bloqueia com `divergencia_pcp`, pois `div_i` é decisão de **processo**.
- **F5 — API do motor.** Ponto de entrada único:
  `Monitor.Gate.run :: Config -> Maybe Multiset -> [TimedEvent] ->
  GateResult`. As funções v2 `Monitor.Composed.runMonitor` /
  `runMonitorTrace` e `Monitor.MesBridge.injectMesBridge` **não existem
  mais**. `Monitor.Composed` expõe só o produto puro
  (`step`/`verdict`/`finalVerdict`/`sinkM1`/`sinkM2`/`sinkM3`);
  `Monitor.MesBridge` expõe `pronounce`/`structuralException` (operações
  puras), e o enriquecimento do fluxo vive em `Monitor.Gate`.
- **F6 — Parâmetros (`defaultConfig`).** T_cls = 1500 ms; ε = 200 ms;
  T_dec = T_cls + ε = 1700 ms; δ_mb = 100 ms (≤ ε); τ = 0.85. Removidos
  os antigos 30 s / 31 s. T_pcp/T_h/T_rej/T_ab_max ficam em `Config`
  apenas para os módulos prospectivos. Novo campo `cfgTdec`/`cfgDeltaMb`;
  **`cfgValidSKUs` foi removido** do `Config`.
- **F7 — SKUs (`anchorCatalog`).** Catálogo-âncora fechado de 7 SKUs da
  Figura 12: `caixa_500L`, `caixa_1000L`, `tampa_1000L`,
  `molde_caixa_500L_vazio`, `molde_caixa_1000L_vazio`,
  `molde_tampa_500L_vazio`, `molde_tampa_1000L_abastecido`. Removidos
  `caixa_2000L/3000L/5000L` e `molde_vazio` genérico.
- **F8 — AP e proposições (§3.2).** `AP = { ab_i, leave_ab_i, match_i,
  div_i, rem_{i,j}, cls_{p,i,j} }`. `esc_pcp_i`, `heartbeat`, `rej_i`
  **não** pertencem a AP — `Monitor.Types.isAP` reflete isso.
- **F9 — Cabeçalho do traço.** O YAML aceita agora `status_esperado`
  (status terminal do gate, §5.4) além de `veredito_esperado` (veredito
  composto). A suíte `ExampleTraces` checa ambos.
- **F10 — Extensões prospectivas (§6).** A4 (escalação ao PCP), A6
  (heartbeat), A7 (refugo) e A8 (janela máxima) permanecem como
  protótipos isolados (`Monitor.Automata.A4/A6/A7/A8`), **não importados**
  pelo monitor composto nem pelo gate. Os cenários que os exercitam saem
  para `Files/Traces/extras/`.
- **Renomeações de traços.** `trace_08_viola_a4_molde_vazio` →
  `trace_08_divergencia_molde_vazio`;
  `trace_09_viola_a4_op_errada` → `trace_09_divergencia_op_errada`
  (ambos: veredito composto ⊤, status `divergencia_pcp`/`mismatch`);
  `trace_13_viola_a4_deriva_cnn` → `trace_13_viola_a2_deriva_cnn`
  (`erro_classificacao`/`timeout_cls`); novo
  `trace_16_viola_a3_decisao_atrasada` (`erro_decisao`/`leave_ab_silent`).
  Os prospectivos `trace_10/11/12/15` migram para `extras/`.
- **Corpus aleatório (`corpus-gen`).** Novo executável que gera **400
  traços** com PRNG determinístico (semente fixa, reproduzível) em
  `Files/Corpus/`: `traces/corpus_001..400.txt`, `resultados.csv`,
  `RELATORIO.md`. Materializa o PBT da Proposição 2 (confirmada 400/400).
  Distribuição: 208 ⊤ / 192 ⊥; gate 138 `liberado_integracao` / 70
  `divergencia_pcp` / 155 `erro_classificacao` / 37 `erro_decisao`.
- **Testes do efetor (`test/GateProps.hs`).** Nova bateria HUnit que
  exercita os quatro status terminais e os cinco diagnósticos do gate —
  incluindo `fora_ciclo` (detector de exceções estruturais do mes-bridge)
  — e a precedência da decisão (`Gate.decide`). Suíte passa a **43 testes**.
- **Invariante temporal (`Monitor.Gate`).** O δ_mb efetivo é limitado a
  `δ_mb ≤ T_dec − T_cls` (§3.4) em runtime, de forma defensiva, mesmo
  quando o cabeçalho sobrescreve `T_cls`/`T_dec`.
- **Filtro de AP (`Monitor.Gate.run`).** As proposições prospectivas
  (`esc_pcp`/`heartbeat`/`rej`) são descartadas via `isAP` antes do
  produto, garantindo que não avancem relógios do monitor verificado.
- **Higiene do artefato (DOI).** Removidos `Hello_World/` (tutorial não
  relacionado, versionado com binário) e `Exec_Git/` (scripts de
  sincronização pessoal); o CI passa a verificar que o corpus versionado
  não diverge do gerador (`git diff --exit-code Files/Corpus`).

## [0.7.0] — 2026-05-23 (Fase 10) ⚠ obsoleto desde 0.8.0

Extensões A6, A7, A8 + promoção dos cenários 10/11/12.

- **A6 (TLTL)** — heartbeat: `G F[0,T_h] heartbeat_i`. Modelado com
  semântica "Unarmed/Armed" — só "arma" no primeiro heartbeat para tolerar
  traços históricos sem heartbeat.
- **A7 (safety)** — refugo: `G(rej_i → cls recente em T_rej)`. Quando o
  refugo é válido, decrementa o SKU correspondente de `M_obs`.
- **A8 (TLTL)** — janela limitada: `G(ab_i → F[0,T_ab_max] leave_ab_i)`.
- Novo evento `rej_i`. `cfgTrej` na Config (default 10 s).
- Parser passa a ignorar comentários inline (`# texto` no fim da linha).
- `Multiset.removeCls` (não-negativo).
- Testes `CompositionProps` atualizados para incluir A6/A7/A8 no ínfimo
  (bug latente exposto pelas extensões — minimum sobre lista incompleta).

## [0.6.0] — 2026-05-23 (Fase 9)

Suite de testes automatizados.

- Reestruturação: `src/` vira library, `app/Main.hs` é o executável,
  `test/` ganha a suite.
- `ExampleTraces` — 1 caso por traço em `Files/Traces/`/`Files/Smoke/`,
  comparando o veredito com `veredito_esperado` do header.
- `CompositionProps` — Proposição 2 via QuickCheck (200 runs cada para
  stream + terminal).
- `AbsorbingProps` — absorção do `Violated` no stream + corolário
  "stream ⊥ ⇒ terminal ⊥".
- Traces 01–05 ganham `veredito_esperado` no header.
- Deps: `tasty`, `tasty-hunit`, `tasty-quickcheck`, `QuickCheck`,
  `directory`, `filepath`.

**Pegadinha registrada:** a formulação ingênua "finalVerdict ⊥ é
absorvente" é falsa — Pending → Idle pode "consertar" o terminal.

## [0.5.0] — 2026-05-23 (Fase 8) ⚠ parcialmente obsoleto desde 0.8.0

Cenários 10–13 + renomeação de trace_08/09. (A cadeia "div_i sintético →
arma A4 → PCP" descrita abaixo foi **removida** na 0.8.0: `trace_08/09`
hoje têm veredito composto ⊤ e status de gate `divergencia_pcp`;
`trace_13` foi renomeado para `trace_13_viola_a2_deriva_cnn`.)

- `trace_08`/`trace_09`: removido sufixo `viola_a3` (obsoleto desde Fase 6 —
  agora violam A4 via mes-bridge); comentários internos atualizados.
- `trace_13_viola_a4_deriva_cnn`: todas as cls com `conf < τ` → A5
  descarta tudo; M_obs=∅; mes-bridge injeta div_i; A4 espera esc_pcp_i
  que não chega. Resultado: composição A2 + A4.
- Traços `trace_10`/`trace_11`/`trace_12` colocados em
  `Files/Traces/_pending/` (especificações de cenários para A6/A7/A8,
  promovidos na Fase 10).

## [0.4.0] — 2026-05-23 (Fase 7)

Output detalhado tipo "emulador" + flags `--quiet` e `--json`.

- `Output.Detailed` — cabeçalho, identificação do traço, parâmetros,
  M_dec, processamento evento-a-evento com estado dos autômatos,
  vereditos por propriedade, decisão do gate.
- `Output.Json` — JSON estruturado ad-hoc (sem aeson).
- Composed ganha `csObs`/`csTau` (M_obs no estado), `Step`, e
  `runMonitorTrace` que devolve a sequência de steps.
- Cada autômato expõe `summary :: M_ -> String`.
- CLI parsea `--quiet`/`--json`/`--help`.
- `Exec/monitor.sh` repassa flags; `Exec/batch.sh` usa `--quiet`.

## [0.3.0] — 2026-05-23 (Fase 6) ⚠ obsoleto desde 0.8.0

Mes-bridge — injeção automática de `match_i`/`div_i`. (Na 0.8.0 o
enriquecimento do fluxo migrou para `Monitor.Gate`; `injectMesBridge` e
`runMonitor` deixaram de existir, e a injeção de `div_i` não mais "arma
A4".)

- `Monitor.MesBridge` é um pré-processador entre `parseFile` e
  `runMonitor`. Política (opção C):
  - Sem header ou sem `m_dec`: traço intacto.
  - Próximo evento após `leave_ab_i` é match/div: deixa o traço prevalecer.
  - Caso contrário: insere match_i (`M_obs = M_dec`) ou div_i (`≠`) no
    mesmo timestamp do leave_ab_i.
- Trace 08 e 09 deixam de violar A3 e passam a violar A4 (mes-bridge
  injeta div_i; A4 espera esc_pcp_i que não chega).

## [0.2.5] — 2026-05-23 (Fase 5) ⚠ obsoleto desde 0.8.0

A4 (TLTL): `G(div_i → F[0,T_pcp] esc_pcp_i)`. (A4 saiu do produto na
0.8.0 — virou extensão prospectiva §6, fora do monitor verificado.)

- M4 estruturalmente idêntico a A2 (Idle | Pending | Violated), sem
  filtro de confiança.
- Novo `trace_15_viola_a4_escalacao_atrasada`.

## [0.2.0] — 2026-05-23 (Fase 4)

A2 (TLTL) + A5 embutido.

- M2 com 3 estados: `Idle | Pending(clock_ms) | Violated`.
- `T_cls` e `τ` embutidos no estado de M2.
- A5 fica embedded em A2 — cls com `conf < τ` não resolve a pendência.
- `Composed.step` agora recebe `TimedEvent`. A1/A3 continuam recebendo
  só `Event` por baixo.
- Novo `trace_14_viola_a2_classificacao_atrasada`.

## [0.1.5] — 2026-05-23 (Fase 3)

A3 (safety) + cenários 06–09.

- M3 com 3 estados: `Ok | Awaiting | Violated`.
- Cada autômato passa a expor `verdict` (stream) e `finalVerdict`
  (terminal). Awaiting só vira ⊥ no `finalVerdict`.
- `runMonitor` devolve também `[String]` (regras violadas).
- Traços novos: `trace_06`, `trace_07`, `trace_08`, `trace_09`.
- `trace_05` ajustado: janela vazia precisa de match_i explícito (M_obs =
  M_dec = ∅ ≡ match trivial).

## [0.1.2] — 2026-05-23 (Fase 2)

Formato de traço estendido (cabeçalho YAML + timestamps).

- Cabeçalho entre `---/---` com `cenario`, `maquina`, `braco`,
  `m_dec` (flow style), `veredito_esperado`.
- Timestamps por evento: `[t=NNN]`, `NNN ` líder, ou ausente (`idx*1000`).
- Novo `TimedEvent`. `Composed.runMonitor` passa a recebê-los; A1 ignora
  `teTime`, A2/A4 consomem.
- `parseVerdict` aceita `TOP/BOT/ACEITA/VIOLA/⊤/⊥`.
- Parser ad-hoc do YAML (subset) para evitar `libyaml`/`aeson` neste estágio.

## [0.1.1] — 2026-05-23 (Fase 1)

Quebra do `Main.hs` monolítico em módulos coesos.

- `Monitor/Types` (Event, Verdict, Config), `Monitor/Parser`,
  `Monitor/Multiset`, `Monitor/Automata/A1`, `Monitor/Composed`,
  `Output/Plain`.
- `Main.hs` reduzido a 45 linhas (só CLI).
- Nova dep: `containers`.
- Vereditos preservados nos 5 traços iniciais.

## [0.1.0] — 2026-05-22 (Peça 1)

Versão inicial — A1 (`G(rem_i → ab_i)`) implementada em `Main.hs`
monolítico. 5 traços de exemplo. Build com Nix/Cabal. (Os scripts de
sincronização com o GitHub usados nesta fase foram removidos do artefato
na 0.8.0.)
