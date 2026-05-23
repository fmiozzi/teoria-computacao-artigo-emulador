# Changelog

Todas as fases marcam pontos de release internos durante a construção
incremental do emulador. Datas referem-se ao commit principal de cada fase
no branch `main`.

## [0.7.0] — 2026-05-23 (Fase 10)

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

## [0.5.0] — 2026-05-23 (Fase 8)

Cenários 10–13 + renomeação de trace_08/09.

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

## [0.3.0] — 2026-05-23 (Fase 6)

Mes-bridge — injeção automática de `match_i`/`div_i`.

- `Monitor.MesBridge` é um pré-processador entre `parseFile` e
  `runMonitor`. Política (opção C):
  - Sem header ou sem `m_dec`: traço intacto.
  - Próximo evento após `leave_ab_i` é match/div: deixa o traço prevalecer.
  - Caso contrário: insere match_i (`M_obs = M_dec`) ou div_i (`≠`) no
    mesmo timestamp do leave_ab_i.
- Trace 08 e 09 deixam de violar A3 e passam a violar A4 (mes-bridge
  injeta div_i; A4 espera esc_pcp_i que não chega).

## [0.2.5] — 2026-05-23 (Fase 5)

A4 (TLTL): `G(div_i → F[0,T_pcp] esc_pcp_i)`.

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
monolítico. 5 traços de exemplo. Build com Nix/Cabal. Configuração do
GitHub remoto via `Exec_Git/init.git.sh`/`sync.git.sh`.
