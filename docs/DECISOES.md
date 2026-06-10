# Decisões de projeto — alinhamento com a v2 do artigo

Registro das decisões tomadas na refatoração do emulador para a versão v2
do artigo (Tabela 2, A1–A5). Cada item indica a referência canônica e a
justificativa.

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

## D4 — Eventos derivados: `div_i` sintético arma A4

Os sumidouros de A2 (`timeout_cls_i`) e A3 (`leave_ab_silent_i`) são
disjuntos de `div_i`. Quando A2 ou A3 viola por expiração de relógio
durante o stream, `Monitor.Composed.step` promove um `div_i` sintético no
mesmo instante, armando A4 (escalação ao PCP).

- **Ref.:** definição de `div_i := mismatch_i ∨ timeout_cls_i ∨
  leave_ab_silent_i ∨ fora_ciclo_i` (Tabela 2, nota †).
- Demonstrado por `trace_13_viola_a4_deriva_cnn` (A5 esvazia `M_obs` → A2
  pendente + `div_i` do mes-bridge → A4): regras reportadas `A2 A4`.

## D5 — A6/A7/A8 fora do monitor composto (extensões futuras)

O monitor composto entregue é `M = M_1 ⊗ M_2 ⊗ M_3 ⊗ M_4` (A1–A4) com o
filtro A5 a montante. A6 (heartbeat Armed/Unarmed), A7 (efeito colateral
`rej_i`) e A8 (janela ≤ `T_ab_max`) são **trabalho futuro** (artigo §6).

- Os módulos `Monitor.Automata.A6/A7/A8` permanecem no repositório, mas
  **fora** de `Monitor.Composed`, do README canônico e da contagem de
  propriedades. (Mantidos, não removidos — preservam a prova de conceito.)
- **Decisão confirmada com o autor.** Os traços que exercitavam essas
  propriedades foram **realocados** para `Files/Traces/extras/` (ver
  `Files/Traces/extras/README.md`): `trace_10` (A7), `trace_11` (A8),
  `trace_12` (A6). Não foram deletados.

## D6 — Parâmetros por traço sobrepõem os defaults

O campo `parametros: {Tcls, Tdec, Tpcp, tau}` do cabeçalho YAML sobrepõe os
defaults globais de `Config`. Implementado em `Monitor.Header.applyParams`,
usado **tanto** pela CLI (`Main`) quanto pela suíte de testes
(`ExampleTraces`) — garantindo vereditos idênticos entre as duas.

- **Antes:** o campo era ignorado e tudo usava `defaultConfig` (Tcls=30 s,
  Tpcp=5 min), tornando os relógios temporizados inertes em traços curtos.

## D7 — Vereditos LTL₃ e códigos de saída

Renderização canônica única (`Monitor.Types.showVerdict`), conforme Bauer,
Leucker e Schallhart (2011), reticulado `⊥ < ? < ⊤`:

- CLI: `⊤ (Top — Aceita)` / `⊥ (Bot — Viola)` / `? (Inconclusive)`.
- YAML/JSON: `TOP` / `BOT` / `INCONCLUSIVE`.
- Removido o sufixo booleano `(T)`/`(F)` (incorreto em LTL₃).

Códigos de saída do executável: `0` = ⊤, `2` = ⊥, `3` = ? (inconclusivo),
`1` = erro de parsing/IO. O `3` distingue inconclusivo de erro (antes
ambos eram `1`).

## D8 — Índice de braço `j` implícito

O artigo usa subscrito de braço (`rem_{i,j}`, `cls_{p,i,j}`). O emulador
opera **por braço**: um traço corresponde a um braço `i`, com `j`
implícito. O formato de traço mantém `rem_i` / `cls_p_i`. Expandir o parser
para `j` explícito fica como trabalho futuro.

## D9 — Suíte canônica de cenários

`Files/Traces/` contém 13 traços canônicos (A1–A5), todos com
`veredito_esperado` no cabeçalho YAML, verificados por `cabal test`:

| Veredito | Traços | Propriedade |
|---|---|---|
| ⊤ | 01, 02, 06, 07 | caminho feliz |
| ⊤ | 05 | janela vazia (vacuosa) |
| ⊥ | 03, 04 | A1 |
| ⊥ | 14 | A2 (classificação tardia) |
| ⊥ | 16 | A3 (decisão tardia) |
| ⊥ | 08, 09, 15 | A4 (escalação ausente/tardia) |
| ⊥ | 13 | A5 → A2+A4 (deriva da CNN) |

`trace_14` foi **redesenhado** para a nova A2 (a versão pré-v2 violava por
ancoragem em `rem_i`). `trace_16` foi **criado** para cobrir A3. Índices
10/11/12 ficaram livres (realocados a `extras/`); não houve renumeração dos
demais (preserva histórico git).
