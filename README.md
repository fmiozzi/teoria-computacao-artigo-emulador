# Emulador — Monitor LTL/TLTL para Agentes de Visão em Manufatura

Implementação em Haskell de um monitor de verificação em tempo de execução
(*runtime verification*) para as restrições operacionais especificadas no
artigo. O emulador concretiza, em código executável, a figura de arquitetura
de referência (v2): um agente de visão computacional observa uma máquina de
rotomoldagem multi-braço, e cada classificação de produto é submetida a um
monitor de autômatos que decide, em tempo real, se o apontamento de produção
pode prosseguir do MES ao ERP.

O núcleo verificado é o monitor composto `M = M1 ⊗ M2 ⊗ M3 ⊗ M4`, cujos
componentes formalizam as propriedades A1–A4 (Tabela 2 do artigo), com o
filtro estrutural A5 (limiar de confiança da CNN) aplicado a montante. O
veredito do produto é o ínfimo dos vereditos individuais no reticulado de
três valores `⊥ < ? < ⊤` (Bauer, Leucker e Schallhart, 2011), resultado
estabelecido pela Proposição 2. Como `⊥` é absorvente em cada componente,
basta o autômato mais pessimista para determinar o veredito composto.

O monitor consome traços de eventos atômicos com marcação temporal e produz
um veredito de três valores, traduzido por um gate de decisão (Algoritmo 1)
em liberar ou bloquear a integração MES → ERP. As propriedades A6–A8
permanecem como trabalho futuro (artigo §6), com seus autômatos preservados
de forma isolada, fora do monitor composto.

## Mapeamento módulo → bloco da arquitetura (v2)

| Bloco da figura de arquitetura (v2)        | Módulo(s)                                  |
|--------------------------------------------|--------------------------------------------|
| Máquina de rotomoldagem multi-braço        | `Monitor.Types`                            |
| Câmera + agente de visão                   | `Monitor.Parser`                           |
| Pipeline de inferência (CNN) — A5          | `Monitor.Classification` (`filterByTau`)   |
| MES (apontamento, `M_obs`/`M_dec`)         | `Monitor.Multiset`, `Monitor.MesBridge`    |
| Monitor LTL/TLTL (ínfimo, Proposição 2)    | `Monitor.Automata.A1`–`A4`, `Monitor.Composed` |
| Gate MES↔ERP (Algoritmo 1)                 | `Monitor.Gate`                             |
| ERP (renderização do veredito)             | `Output.Plain`, `Output.Detailed`, `Output.Json` |
| Ponto de entrada (CLI)                      | `app/Main.hs`                              |

Detalhamento do mapeamento em [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## Propriedades A1–A5 (Tabela 2)

| ID | Tipo                 | Fórmula                                                | Parâm.  |
|----|----------------------|--------------------------------------------------------|---------|
| A1 | safety               | `G(rem_{i,j} → ab_i)`                                   | —       |
| A2 | liveness temporizada | `G(leave_ab_i → F_{[0,T_cls]} ⋁_{j,p} cls_{p,i,j}^{≥τ})` | `T_cls` |
| A3 | liveness temporizada | `G(leave_ab_i → F_{[0,T_dec]} (match_i ∨ div_i))`      | `T_dec` |
| A4 | liveness temporizada | `G(div_i → F_{[0,T_pcp]} esc_pcp_i)`                   | `T_pcp` |
| A5 | restrição estrutural | filtro `conf ≥ τ` sobre `cls` antes de `M_obs`         | `τ`     |

`T_dec = T_cls + ε`, com `T_dec ≥ T_cls`. O evento derivado é definido como
`div_i := mismatch_i ∨ timeout_cls_i ∨ leave_ab_silent_i ∨ fora_ciclo_i`
(Tabela 2, nota †).

## Monitor composto (ínfimo de M1..M4)

```
                     filtro A5 (conf ≥ τ)
                            │
            traço ─────────►│ Monitor.Classification
                            ▼
              ┌─────────────────────────────────┐
              │           Monitor.Composed        │
              │                                   │
              │   ┌────┐  ┌────┐  ┌────┐  ┌────┐  │
              │   │ M1 │  │ M2 │  │ M3 │  │ M4 │  │
              │   │ A1 │  │ A2 │  │ A3 │  │ A4 │  │
              │   └─┬──┘  └─┬──┘  └─┬──┘  └─┬──┘  │
              │     │       │       │       │     │
              │     └───────┴───┬───┴───────┘     │
              │                 ▼                 │
              │      veredito = ínfimo (⊥<?<⊤)    │
              │           (Proposição 2)          │
              └─────────────────┬─────────────────┘
                                ▼
                        Monitor.Gate (Alg. 1)
                                │
                   ┌────────────┴────────────┐
                   ▼                          ▼
              ⊤: liberar                 ⊥/?: bloquear
              MES → ERP                  MES → ERP
```

## Build e execução

Toolchain: GHC 9.4.8 e Cabal 3.10, provisionados de forma reproduzível pelo
Nix (flakes). Não há dependências de sistema fora do Nix.

```bash
# Compilar
nix develop --command cabal build

# Suíte de testes (verifica os 13 traços canônicos + composição + absorção)
nix develop --command cabal test

# Rodar todos os traços canônicos em modo curto
./Exec/batch.sh Files/Traces

# Rodar um traço específico
./Exec/monitor.sh Files/Traces/trace_08_viola_a4_molde_vazio.txt
./Exec/monitor.sh --quiet Files/Traces/trace_08_viola_a4_molde_vazio.txt
./Exec/monitor.sh --json  Files/Traces/trace_08_viola_a4_molde_vazio.txt
```

> Nota (Nix flakes): o Nix só enxerga arquivos rastreados pelo Git. Em um
> repositório novo, rode `git add -N Emulador/` (intent-to-add) antes de
> `nix develop`.

### Modos da CLI

A interface é `lab-monitor [--quiet|--json] <arquivo_de_traço>`.

| Modo      | Saída |
|-----------|-------|
| (padrão)  | Relatório detalhado: parâmetros, eventos, vereditos por propriedade e gate. |
| `--quiet` | Bloco curto com o veredito e as regras violadas (usado por `batch.sh`). |
| `--json`  | JSON estruturado: cabeçalho, configuração, passos, veredito e regras. |

### Códigos de saída

| Código | Veredito                  |
|--------|---------------------------|
| 0      | `⊤` (aceita)              |
| 2      | `⊥` (viola)               |
| 3      | `?` (inconclusivo)        |
| 1      | erro de parsing/IO/uso    |

## Cenários canônicos

A suíte canônica reúne 13 traços em `Files/Traces/` (5 aceitam, 8 violam),
todos com `veredito_esperado` no cabeçalho e verificados por `cabal test`.

| Traço | Cenário                          | Veredito | Decide  |
|-------|----------------------------------|----------|---------|
| 01    | aceita simples                   | `⊤`      | —       |
| 02    | aceita múltiplas                 | `⊤`      | —       |
| 05    | aceita vazio (janela vacuosa)    | `⊤`      | —       |
| 06    | aceita braço 1 (mix)             | `⊤`      | —       |
| 07    | aceita braço 2 (uniforme)        | `⊤`      | —       |
| 03    | viola A1 (retirada no início)    | `⊥`      | A1      |
| 04    | viola A1 (retirada após leave)   | `⊥`      | A1      |
| 14    | classificação tardia             | `⊥`      | A2      |
| 16    | decisão tardia                   | `⊥`      | A3      |
| 08    | molde vazio (esc. ausente)       | `⊥`      | A4      |
| 09    | OP errada (esc. ausente)         | `⊥`      | A4      |
| 15    | escalação tardia                 | `⊥`      | A4      |
| 13    | deriva da CNN (A5 → A2 + A4)     | `⊥`      | A2, A4  |

Os cenários que exercitam as propriedades A6–A8 (trabalho futuro) ficam em
`Files/Traces/extras/`: `trace_10` (A7), `trace_11` (A8), `trace_12` (A6).
Análise detalhada em [docs/CENARIOS.md](docs/CENARIOS.md); decisões de
projeto em [docs/DECISOES.md](docs/DECISOES.md); formato de traço em
[docs/FORMATO_TRACE.md](docs/FORMATO_TRACE.md).

## Como citar

```bibtex
@mastersthesis{miozzi2026monitor,
  author  = {Batista, Fl{\'a}vio Miozzi},
  title   = {Verifica{\c c}{\~a}o de Restri{\c c}{\~o}es Operacionais em
             Agentes de Vis{\~a}o Computacional via Aut{\^o}matos de
             Monitoramento},
  school  = {Programa de P{\'o}s-Gradua{\c c}{\~a}o em Computa{\c c}{\~a}o
             Aplicada (PPComp), Instituto Federal do Esp{\'i}rito Santo (Ifes)},
  year    = {2026},
  note    = {Venue a definir}
}
```

## Licença

Consulte o arquivo [LICENSE](LICENSE). A licença definitiva está a definir
conforme o conteúdo de `LICENSE`.
