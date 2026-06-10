# Cenários fora do recorte verificado (extensões prospectivas §6)

Os traços neste diretório exercitam propriedades classificadas como
**extensões prospectivas** no artigo (§6) e que **não** integram o monitor
composto verificado $M = M_1 \otimes M_2 \otimes M_3$ (propriedades A1, A2,
A3). A numeração salta A4 (footnote 4): A4 — como A6, A7 e A8 — está fora do
recorte avaliado e é mantida apenas como protótipo isolado.

Estes traços ficam fora da suíte canônica (`Files/Traces/`), da bateria de
testes automatizados e do `batch.sh`, mas são preservados como referência
das extensões. Os autômatos correspondentes existem isolados em
`src/Monitor/Automata/` e **não** são importados por `Monitor.Composed`.

| Arquivo | Propriedade (prospectiva, §6) | Cenário |
|---|---|---|
| `trace_10_refugo_peca_defeituosa.txt`       | A7 (refugo: `rej_i`)              | Refugo marcado sem classificação prévia |
| `trace_11_janela_longa.txt`                 | A8 (janela ≤ `T_ab_max`)          | Janela de abastecimento longa demais |
| `trace_12_agente_morto.txt`                 | A6 (heartbeat `T_h`)              | Agente de visão sem sinal de vida |
| `trace_15_viola_a4_escalacao_atrasada.txt`  | A4 (escalonamento ao PCP, `T_pcp`)| `div_i` sem `esc_pcp_i` dentro de `T_pcp` |

Os autômatos correspondentes existem em `src/Monitor/Automata/A4.hs`,
`A6.hs`, `A7.hs` e `A8.hs`, todos marcados como extensão prospectiva e
isolados do produto verificado. Ver `docs/DECISOES.md` (D5) e `docs/CENARIOS.md`.

> **Nota.** Avaliados sob o recorte verificado (A1–A3 + A5), estes traços
> recebem o status do gate correspondente às três propriedades efetivamente
> monitoradas (p.ex. `trace_15` resulta em `divergencia_pcp`, pois o `div_i`
> é pronunciado em prazo); a violação da propriedade prospectiva (A4, A6,
> A7, A8) só é observável no autômato isolado da respectiva extensão, fora
> de `M = M_1 \otimes M_2 \otimes M_3`.
