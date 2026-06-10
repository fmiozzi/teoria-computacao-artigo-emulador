# Arquitetura do Emulador

Este documento descreve como os módulos do emulador realizam os blocos da
figura de arquitetura de referência do artigo (v2_3), do agente de visão ao
ERP. O núcleo executável é o monitor composto `M = M1 ⊗ M2 ⊗ M3` (produto
sincronizado de TRÊS componentes, propriedades A1, A2 e A3), com o filtro
estrutural A5 aplicado a montante. A propriedade A4 (escalonamento ao PCP) é
extensão prospectiva (§6): a escalada é ação determinística do gate, não
obrigação verificada por autômato no produto.

## Mapeamento figura → código

### Máquina de rotomoldagem multi-braço — `Monitor.Types`

Define o vocabulário de eventos atômicos do conjunto AP (§3.2) — `ab_i`,
`rem_{i,j}`, `leave_ab_i`, `match_i`, `div_i`, `cls_{p,i,j}` — e os tipos de
domínio: `Event`, `TimedEvent`, `Verdict`, `MesStatus`, `Diag` e `Config`. A
função `isAP` distingue o alfabeto verificado das proposições das extensões
prospectivas (§6): `esc_pcp_i` (A4), `heartbeat` (A6) e `rej_i` (A7) existem
como construtores de `Event` mas `isAP` retorna `False` para eles — não
pertencem a AP. O reticulado de vereditos é dado por
`data Verdict = Bot | Inconclusive | Top` com a ordem `⊥ < ? < ⊤`. Os
parâmetros do monitor verificado (`T_cls`, `T_dec`, `δ_mb`) e o limiar `τ`
residem em `Config` por `defaultConfig` (cenário-âncora §4: `T_cls = 1500 ms`,
`ε = 200 ms`, `T_dec = 1700 ms`, `δ_mb = 100 ms`, `τ = 0.85`); os parâmetros
das extensões prospectivas (`T_pcp`, `T_h`, `T_rej`, `T_ab_max`) também
residem aqui, mas só são consumidos pelos módulos isolados. `MesStatus` e
`Diag` materializam os quatro status terminais e os diagnósticos de
causa-raiz do gate (§5.4). O catálogo-âncora fechado de 7 SKUs (Figura 12)
está em `anchorCatalog`. Representa a planta observada: a máquina cujos
eventos físicos alimentam toda a cadeia.

### Câmera + agente de visão — `Monitor.Parser`

Lê o arquivo de traço (cabeçalho mais fluxo de eventos com marcação temporal)
e o converte em `[TimedEvent]`. Simula o agente de visão que, em produção,
emite o fluxo de eventos a partir das imagens. O formato é especificado em
[FORMATO_TRACE.md](FORMATO_TRACE.md); este módulo não o duplica.

### Pipeline de inferência (CNN), A5 — `Monitor.Classification`

Implementa o filtro estrutural A5 via `filterByTau`/`isValidCls`: apenas
classificações com confiança `conf ≥ τ` contribuem para `M_obs` e satisfazem
a obrigação de A2. A5 é uma restrição estrutural a montante, não uma fórmula
LTL/TLTL — por isso não há autômato `M5` no produto, e a numeração das
propriedades salta A4 (footnote 4 do artigo). O filtro é consultado tanto
pelo enriquecimento do `Monitor.Gate` (que monta `M_obs` para a comparação
de coerência via `Monitor.MesBridge`) quanto pelo `Monitor.Composed` (ao
acumular `csObs`, informação de exibição).

### MES (`M_obs`/`M_dec`) — `Monitor.Multiset`, `Monitor.MesBridge`

`Monitor.Multiset` modela o apontamento como multiconjuntos e oferece a
comparação `compareMs`. `Monitor.MesBridge` expõe as operações *puras* do
mes-bridge (§3.2, §3.4), consumidas pelo laço online do gate:

- `pronounce :: Multiset -> Multiset -> Pronouncement` — comparação de
  coerência `M_obs =? M_dec` (por multiplicidades de SKU), produzindo
  `PMatch` (igualdade) ou `PMismatch` (diferença). O caso vazio
  `M_obs = M_dec = ∅` resolve em `PMatch`.
- `structuralException :: StructuralCtx -> Event -> Maybe Diag` — detector
  plugável de exceções estruturais do ciclo, que emite `fora_ciclo`
  (`leave_ab_i` duplicado; pronunciamento `match`/`div` espúrio, fora de
  ciclo armado).

A montagem da janela e a injeção dos pronunciamentos sintéticos no fluxo é
responsabilidade do `Monitor.Gate` (função `enrich`): ao encerrar a janela de
abastecimento, ele compara o `M_obs` acumulado sobre `[τ_a, τ_b + T_cls]` (já
filtrado por A5) com o `M_dec` declarado no cabeçalho e injeta o
pronunciamento de coerência (`match_i` ou `div_i` por `mismatch`) em
`τ_b + T_cls + δ_mb` (com `δ_mb ≤ T_dec − T_cls`). Sem cabeçalho ou sem
`m_dec`, nenhum pronunciamento de coerência é fabricado (o traço prevalece);
a detecção de exceções estruturais ocorre independentemente.

### Monitor LTL/TLTL (ínfimo, Proposição 2) — `Monitor.Automata.A1`–`A3`, `Monitor.Composed`

Cada propriedade do recorte verificado é um autômato de monitoramento
independente: `A1` (safety `G(rem_{i,j} → ab_i)`), `A2` (liveness temporizada
com relógio `T_cls` ancorado em `leave_ab_i`) e `A3` (liveness temporizada
com `T_dec`, também ancorado em `leave_ab_i`). `Monitor.Composed` é o produto
*puro* `M = M1 ⊗ M2 ⊗ M3`: mantém o estado sincronizado (`ComposedState`) e
calcula o veredito como o ínfimo dos componentes no reticulado `⊥ < ? < ⊤`.
Pela Proposição 2, esse ínfimo é o veredito correto do produto; como `⊥` é
absorvente em cada componente, o autômato mais pessimista determina o
resultado. O módulo expõe um veredito de stream (`verdict`, a cada passo,
domínio `{⊥, ?}`) e um veredito terminal (`finalVerdict`, domínio `{⊥, ⊤}`,
que captura obrigações temporizadas ainda pendentes ao fim do traço), além
dos predicados de sumidouro por componente (`sinkM1`/`sinkM2`/`sinkM3`)
consumidos pelo gate. Cotas do produto: ≤ `2×3×3 = 18` estados; cota binária
`2^|Φ| = 8` com `|Φ| = 3`. Este módulo *não* fabrica `match`/`div` (papel do
mes-bridge) nem promove sumidouros a status (papel do gate): o macro-evento
derivado `div_i` é consumido por M₃ como qualquer outra letra.

### Gate MES↔ERP (Algoritmo 1) — `Monitor.Gate`

É o *motor* do emulador (`run :: Config -> Maybe Multiset -> [TimedEvent] ->
GateResult`) e o *efetor* do ciclo: enriquece o fluxo com os pronunciamentos
do mes-bridge (`enrich`), varre o produto `M1 ⊗ M2 ⊗ M3` evento a evento
(`scan`) e transita o apontamento de `pendente_verificacao` para UM de quatro
status terminais, anexando o diagnóstico de causa-raiz (Algoritmo 1, Figura
9, Tabelas 3–4):

1. `liberado_integracao` — `match_i` dentro de `T_dec`, sem violação →
   integração nativa MES→ERP;
2. `divergencia_pcp` — `div_i` (`mismatch` ∨ `fora_ciclo`) OU violação de
   safety de A1 → tratativa manual no PCP (diag `mismatch`/`fora_ciclo`/
   `safety_A1`);
3. `erro_classificacao` — sumidouro de M₂ (diag `timeout_cls`): classificação
   ausente em `T_cls` → time de visão computacional;
4. `erro_decisao` — sumidouro de M₃ (diag `leave_ab_silent`): mes-bridge mudo
   em `T_dec` → TI.

A ordem de prioridade do roteamento (`decide`) segue exatamente o
Algoritmo 1: `sinkM1 → sinkM2 → sinkM3 → div → match`. Distinção essencial: o
**veredito composto não é o status do gate**. Um `mismatch` tem veredito
composto `⊤` (A1/A2/A3 satisfeitas — a decisão foi tomada em prazo), mas o
gate bloqueia com `divergencia_pcp`, pois `div_i` é decisão de *processo*, não
violação de propriedade.

### ERP (renderização do veredito) — `Output.Plain`, `Output.Detailed`, `Output.Json`

Renderizam o resultado para consumo a jusante (papel do ERP): bloco curto
(`--quiet`), relatório detalhado evento-a-evento (padrão) e JSON estruturado
(`--json`). A renderização canônica do veredito segue Bauer, Leucker e
Schallhart (2011): `⊤`/`⊥`/`?`; ao lado dele, expõem o status terminal do
gate e o diagnóstico de causa-raiz (§5.4).

### Ponto de entrada (CLI) — `app/Main.hs`

Orquestra a cadeia: faz o parsing, aplica os parâmetros do cabeçalho sobre os
defaults, invoca o motor `Monitor.Gate.run` (que internamente enriquece o
fluxo pelo mes-bridge e varre `M1 ⊗ M2 ⊗ M3`) e seleciona o renderizador de
saída conforme a flag. Mapeia o status terminal do gate aos códigos de saída
(§5.4): `0` (`liberado_integracao`), `2` (qualquer bloqueio —
`divergencia_pcp`/`erro_classificacao`/`erro_decisao`), `3`
(`pendente_verificacao`) e `1` (erro de parsing/IO/uso).

## Evento derivado `div_i` e promoção dos sumidouros (§3.4, §5.4)

O macro-evento derivado é `div_i := mismatch_i ∨ fora_ciclo_i` — EXATAMENTE
dois disjuntos (§3.4). `mismatch_i` é emitido pelo mes-bridge em
`τ_b + T_cls + δ_mb` quando `M_obs[τ_a, τ_b + T_cls] ≠ M_dec`; `fora_ciclo_i`
são exceções estruturais do ciclo (ex.: `leave_ab` duplicado, pronunciamento
espúrio) e também a captura da violação de safety de A1 (diagnóstico
`safety_A1`).

Crucialmente, os sumidouros temporizados **não** são `div_i`. `timeout_cls_i`
(sumidouro de M₂, expiração de `T_cls` sem classificação válida) e
`leave_ab_silent_i` (sumidouro de M₃, expiração de `T_dec` sem
pronunciamento) são eventos sintéticos de *diagnóstico*: o efetor (gate) os
promove a `erro_classificacao` e `erro_decisao`, respectivamente — não à
propriedade A4. A cadeia v2 "A2/A3 → `div_i` sintético → arma A4 → PCP" foi
removida do código; `Monitor.Composed.step` consome `div_i` como letra comum,
sem fabricá-lo. O cenário `trace_13` exercita isso: o filtro A5 esvazia
`M_obs`, A2 fica pendente e expira, e o gate roteia o apontamento a
`erro_classificacao` (diag `timeout_cls`), com veredito composto `⊥` por A2.

## Propriedades prospectivas A4, A6–A8 (§6, fora do recorte)

A4 (escalonamento ao PCP, relógio `T_pcp`), A6 (heartbeat Armed/Unarmed), A7
(efeito colateral `rej_i`) e A8 (janela limitada por `T_ab_max`) são extensões
prospectivas (artigo §6), situadas fora do recorte verificado. Seus autômatos
(`Monitor.Automata.A4`/`A6`/`A7`/`A8`) permanecem no repositório como
protótipos isolados, mas *não* são importados pelo monitor composto: não
integram `Monitor.Composed`, a contagem de propriedades nem a suíte canônica.
Os parâmetros correspondentes em `Config` (`T_pcp`, `T_h`, `T_rej`,
`T_ab_max`) e as proposições fora de AP (`esc_pcp_i`, `heartbeat`, `rej_i`,
filtradas por `isAP`) servem apenas a esses módulos. Note que `T_pcp` não é
fixado pelo artigo — o valor em `defaultConfig` é ilustrativo. Os traços
correspondentes ficam em `Files/Traces/extras/`. A5, por sua vez, não é
prospectiva: é o filtro estrutural já ativo em `Monitor.Classification`,
aplicado a montante do monitor composto.

## Referências cruzadas

- [DECISOES.md](DECISOES.md) — decisões de projeto e suas justificativas
  canônicas (fonte de verdade).
- [CENARIOS.md](CENARIOS.md) — análise dos cenários e matriz propriedade ×
  cenário.
