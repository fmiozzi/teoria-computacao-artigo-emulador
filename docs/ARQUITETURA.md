# Arquitetura do Emulador

Este documento descreve como os módulos do emulador realizam os blocos da
figura de arquitetura de referência (v2) do artigo, do agente de visão ao
ERP. O núcleo executável é o monitor composto `M = M1 ⊗ M2 ⊗ M3 ⊗ M4`
(propriedades A1–A4, Tabela 2), com o filtro A5 aplicado a montante.

## Mapeamento figura → código

### Máquina de rotomoldagem multi-braço — `Monitor.Types`

Define o vocabulário de eventos atômicos (`ab_i`, `rem_i`, `leave_ab_i`,
`match_i`, `div_i`, `esc_pcp_i`, `cls_p_i`) e os tipos de domínio: `Event`,
`TimedEvent`, `Verdict` e `Config`. O reticulado de vereditos é dado por
`data Verdict = Bot | Inconclusive | Top` com a ordem `⊥ < ? < ⊤`. Os
parâmetros temporizados (`T_cls`, `T_dec`, `T_pcp`) e o limiar `τ` residem em
`Config`. Representa a planta observada: a máquina cujos eventos físicos
alimentam toda a cadeia.

### Câmera + agente de visão — `Monitor.Parser`

Lê o arquivo de traço (cabeçalho mais fluxo de eventos com marcação temporal)
e o converte em `[TimedEvent]`. Simula o agente de visão que, em produção,
emite o fluxo de eventos a partir das imagens. O formato é especificado em
[FORMATO_TRACE.md](FORMATO_TRACE.md); este módulo não o duplica.

### Pipeline de inferência (CNN), A5 — `Monitor.Classification`

Implementa o filtro estrutural A5 via `filterByTau`/`isValidCls`: apenas
classificações com confiança `conf ≥ τ` contribuem para `M_obs` e satisfazem
a obrigação de A2. A5 é uma restrição estrutural a montante, não uma fórmula
LTL/TLTL — por isso não há autômato `M5` no produto. O filtro é consultado
tanto pelo `MesBridge` (ao montar `M_obs`) quanto pelo `Monitor.Composed`
(ao acumular `csObs`).

### MES (`M_obs`/`M_dec`) — `Monitor.Multiset`, `Monitor.MesBridge`

`Monitor.Multiset` modela o apontamento como multiconjuntos e oferece a
comparação `compareMs`. `Monitor.MesBridge` realiza a ponte descrita em §5.4:
ao chegar em `leave_ab_i` sem que o traço pronuncie `match_i`/`div_i`, ele
compara o `M_obs` acumulado (já filtrado por A5) com o `M_dec` declarado no
cabeçalho e injeta o evento ausente no mesmo instante. Sem cabeçalho ou sem
`m_dec`, o traço passa intacto.

### Monitor LTL/TLTL (ínfimo, Proposição 2) — `Monitor.Automata.A1`–`A4`, `Monitor.Composed`

Cada propriedade é um autômato de monitoramento independente: `A1` (safety
`G(rem_{i,j} → ab_i)`), `A2` (liveness temporizada com relógio `T_cls`
ancorado em `leave_ab_i`), `A3` (liveness temporizada com `T_dec`) e `A4`
(liveness temporizada com `T_pcp`). `Monitor.Composed` mantém o estado
sincronizado (`ComposedState`) e calcula o veredito como o ínfimo dos
componentes no reticulado `⊥ < ? < ⊤`. Pela Proposição 2, esse ínfimo é o
veredito correto do produto; como `⊥` é absorvente em cada componente, o
autômato mais pessimista determina o resultado. O módulo expõe um veredito de
stream (`verdict`, a cada passo) e um veredito terminal (`finalVerdict`, que
captura obrigações temporizadas ainda pendentes ao fim do traço).

### Gate MES↔ERP (Algoritmo 1) — `Monitor.Gate`

Traduz o veredito composto em decisão operacional: `⊤` libera a integração;
`⊥` bloqueia listando as regras `A_k` violadas; `?` é tratado com cautela
como bloqueio sem regras, aguardando mais eventos. Implementa o Algoritmo 1
(decisão online).

### ERP (renderização do veredito) — `Output.Plain`, `Output.Detailed`, `Output.Json`

Renderizam o resultado para consumo a jusante (papel do ERP): bloco curto
(`--quiet`), relatório detalhado evento-a-evento (padrão) e JSON estruturado
(`--json`). A renderização canônica do veredito segue Bauer, Leucker e
Schallhart (2011): `⊤`/`⊥`/`?`.

### Ponto de entrada (CLI) — `app/Main.hs`

Orquestra a cadeia: faz o parsing, aplica os parâmetros do cabeçalho sobre os
defaults, invoca o `MesBridge`, executa o `Monitor.Composed` e seleciona o
renderizador de saída conforme a flag. Mapeia o veredito final aos códigos de
saída `0` (`⊤`), `2` (`⊥`), `3` (`?`) e `1` (erro).

## Encadeamento de eventos derivados (A2/A3 → `div_i` → A4)

O evento derivado é `div_i := mismatch_i ∨ timeout_cls_i ∨
leave_ab_silent_i ∨ fora_ciclo_i`. Os sumidouros de A2 (`timeout_cls_i`,
expiração do relógio `T_cls`) e de A3 (`leave_ab_silent_i`, expiração de
`T_dec`) são, portanto, espécies de divergência. Quando A2 ou A3 viola por
expiração de relógio durante o stream, `Monitor.Composed.step` promove um
`div_i` sintético no mesmo instante, armando A4 (escalação ao PCP). Assim, um
silêncio temporizado de A2/A3 propaga-se para a obrigação de escalação de A4,
em vez de se perder no veredito composto. O cenário `trace_13` exercita esse
encadeamento: o filtro A5 esvazia `M_obs`, A2 fica pendente e o `MesBridge`
injeta `div_i`, resultando nas regras `A2 A4`.

## Propriedades A6–A8 (trabalho futuro)

A6 (heartbeat Armed/Unarmed), A7 (efeito colateral `rej_i`) e A8 (janela
limitada por `T_ab_max`) são extensões de trabalho futuro (artigo §6). Seus
autômatos (`Monitor.Automata.A6`/`A7`/`A8`) permanecem no repositório, mas
isolados: não integram `Monitor.Composed`, a contagem de propriedades nem a
suíte canônica. Os traços correspondentes ficam em `Files/Traces/extras/`.
A5, por sua vez, não é trabalho futuro: é o filtro estrutural já ativo em
`Monitor.Classification`, aplicado a montante do monitor composto.

## Referências cruzadas

- [DECISOES.md](DECISOES.md) — decisões de projeto e suas justificativas
  canônicas (fonte de verdade).
- [CENARIOS.md](CENARIOS.md) — análise dos cenários e matriz propriedade ×
  cenário.
