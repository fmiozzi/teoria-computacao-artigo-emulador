# Cenários fora do escopo do monitor composto da v2

Os traços neste diretório exercitam propriedades classificadas como
**trabalho futuro** no artigo (§6) e que **não** integram o monitor
composto $M = M_1 \otimes M_2 \otimes M_3 \otimes M_4$ (A1–A4) entregue na
v2. Eles ficam fora da suíte canônica (`Files/Traces/`) e da bateria de
testes/`batch.sh`, mas são preservados como referência das extensões.

| Arquivo | Propriedade (futura) | Cenário |
|---|---|---|
| `trace_10_refugo_peca_defeituosa.txt` | A7 (efeito colateral: `rej_i`) | Refugo marcado sem classificação prévia |
| `trace_11_janela_longa.txt`           | A8 (janela ≤ `T_ab_max`)       | Janela de abastecimento longa demais |
| `trace_12_agente_morto.txt`           | A6 (heartbeat `T_h`)           | Agente de visão sem sinal de vida |

Os autômatos correspondentes existem em `src/Monitor/Automata/A6.hs`,
`A7.hs` e `A8.hs`, igualmente marcados como extensão futura. Ver
`docs/DECISOES.md`.
