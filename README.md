# Emulador LTL/TLTL — Monitor de Apontamento de Produção

Implementação em Haskell de um monitor de *runtime verification* para 8
propriedades LTL/TLTL especificadas no artigo

> Miozzi, F. M. B. (2026). *Verificação de Restrições Operacionais em Agentes
> de Visão Computacional via Autômatos de Monitoramento: Especificação em LTL
> e TLTL para Apontamento de Produção em Manufatura.*

O monitor consome traços de eventos atômicos (gerados, em produção, por um
agente de visão computacional sobre uma máquina de rotomoldagem multi-braço)
e decide, em tempo real, se o apontamento de produção deve ser **liberado**
ou **bloqueado** na integração MES → ERP.

---

## Sumário

- [Status](#status)
- [Quick start](#quick-start)
- [Estrutura de pastas](#estrutura-de-pastas)
- [Propriedades implementadas](#propriedades-implementadas)
- [Cenários cobertos](#cenários-cobertos)
- [Modos de saída do CLI](#modos-de-saída-do-cli)
- [Formato do arquivo de traço](#formato-do-arquivo-de-traço)
- [Configuração de parâmetros](#configuração-de-parâmetros)
- [Como rodar os testes](#como-rodar-os-testes)
- [Roadmap](#roadmap)
- [Como contribuir](#como-contribuir)
- [Citação](#citação)
- [Licença](#licença)

---

## Status

| Indicador | Valor |
|-----------|-------|
| Versão | `0.7.0` |
| Propriedades implementadas | A1, A2, A3, A4, A5 (core do artigo) + A6, A7, A8 (extensões) |
| Cenários cobertos | 15 (todos do `Cenarios_Realistas_Rotomoldagem.md`) |
| Suite de testes | 20/20 passando — 16 traces + 2 properties Prop. 2 + 2 absorção |
| Build | `cabal build` limpo com `-Wall -Wincomplete-patterns -Wincomplete-uni-patterns` |

Roteiro detalhado em [docs/CENARIOS.md](docs/CENARIOS.md) e
[CHANGELOG.md](CHANGELOG.md).

---

## Quick start

**Pré-requisitos** — somente o Nix com flakes habilitado. Toda a toolchain
(GHC 9.4.8, Cabal 3.10, HLS, bibliotecas Haskell) é provisionada
automaticamente.

```bash
# 1) Entra no ambiente reproduzível (Nix devShell)
nix develop

# 2) Compila
cabal build

# 3) Roda todos os traços (formato curto)
./Exec/batch.sh

# 4) Roda um traço com output detalhado tipo "emulador"
./Exec/monitor.sh Files/Traces/trace_08_viola_a4_molde_vazio.txt

# 5) JSON estruturado
./Exec/monitor.sh --json Files/Traces/trace_08_viola_a4_molde_vazio.txt
```

> **Atenção (Nix flakes):** o Nix só enxerga arquivos rastreados pelo Git.
> Se acabou de clonar, isso já está resolvido. Se está adicionando
> `Emulador/` a um repositório novo, antes de rodar `nix develop`:
>
> ```bash
> git add -N Emulador/   # intent-to-add (não stage o conteúdo)
> ```

**Códigos de saída** do executável `lab-monitor`:

| Código | Significado |
|--------|-------------|
| 0 | Traço aceito (⊤) |
| 1 | Erro de parsing/uso, ou veredito inconclusivo |
| 2 | Traço violado (⊥) |

---

## Estrutura de pastas

```
Emulador/
├── app/
│   └── Main.hs                       # CLI (argumentos, dispatch de modo)
├── src/
│   ├── Monitor/
│   │   ├── Types.hs                  # Event, Verdict, TimedEvent, Config
│   │   ├── Parser.hs                 # Cabeçalho YAML + timestamps
│   │   ├── Header.hs                 # Parser ad-hoc do header
│   │   ├── Multiset.hs               # M_obs, M_dec, compareMs
│   │   ├── MesBridge.hs              # Injeção de match/div pós leave_ab_i
│   │   ├── Automata/
│   │   │   ├── A1.hs                 # safety: G(rem→ab)
│   │   │   ├── A2.hs                 # TLTL : G(rem→F[T_cls] cls)
│   │   │   ├── A3.hs                 # safety: G(leave→match∨div)
│   │   │   ├── A4.hs                 # TLTL : G(div→F[T_pcp] esc_pcp)
│   │   │   ├── A6.hs                 # TLTL : G F[T_h] heartbeat
│   │   │   ├── A7.hs                 # safety: G(rej→cls recente)
│   │   │   └── A8.hs                 # TLTL : G(ab→F[T_ab_max] leave)
│   │   └── Composed.hs               # Produto sincronizado (Prop. 2)
│   └── Output/
│       ├── Plain.hs                  # Formato curto (--quiet)
│       ├── Detailed.hs               # Formato detalhado (default)
│       └── Json.hs                   # JSON estruturado (--json)
├── test/
│   ├── Spec.hs                       # Entry point Tasty
│   ├── ExampleTraces.hs              # 1 caso por traço em Files/
│   ├── CompositionProps.hs           # Proposição 2 via QuickCheck
│   └── AbsorbingProps.hs             # Sumidouro Violated é absorvente
├── Files/
│   ├── Traces/                       # 15 cenários (trace_01 a trace_15)
│   └── Smoke/                        # Testes do parser (cabeçalho + timestamps)
├── Exec/
│   ├── monitor.sh                    # Roda um traço (com flags)
│   └── batch.sh                      # Roda todos os traços de Files/Traces/
├── Exec_Git/
│   ├── init.git.sh                   # Inicializa o repo Git remoto
│   └── sync.git.sh                   # Sincroniza commits com o remoto
├── docs/
│   ├── ARQUITETURA.md                # Diagrama do monitor composto
│   ├── CENARIOS.md                   # Tabela detalhada dos 15 cenários
│   └── REFERENCIAS.md                # Bibliografia
├── CHANGELOG.md
├── README.md
├── LICENSE
├── flake.nix                         # Ambiente Nix
└── lab-monitor.cabal                 # library + executable + test-suite
```

---

## Propriedades implementadas

| ID | Tipo | Fórmula | Default | Captura |
|----|------|---------|---------|---------|
| **A1** | safety LTL | $G(rem_i \to ab_i)$ | — | Retirada fora da janela de abastecimento |
| **A2** | TLTL | $G(rem_i \to F_{[0,T_{cls}]} \bigvee_p cls_{p,i})$ | $T_{cls}=30\text{s}$ | Classificação atrasada ou ausente |
| **A3** | safety LTL | $G(leave\_ab_i \to match_i \vee div_i)$ | — | Fim da janela sem pronunciamento |
| **A4** | TLTL | $G(div_i \to F_{[0,T_{pcp}]} esc\_pcp_i)$ | $T_{pcp}=5\text{min}$ | Escalação ao PCP atrasada |
| **A5** | filtro | $cls_{p,i}$ contribui para $M_{obs}$ se $\text{conf} \geq \tau$ | $\tau=0{,}85$ | Filtro de confiança da CNN |
| **A6** | TLTL ext. | $G F_{[0,T_h]} heartbeat_i$ | $T_h=5\text{s}$ | Agente "morto" ou "cego" |
| **A7** | safety ext. | $G(rej_i \to \exists\,recent\,cls_{p,i})$ | $T_{rej}=10\text{s}$ | Refugo sem classificação prévia |
| **A8** | TLTL ext. | $G(ab_i \to F_{[0,T_{ab\_max}]} leave\_ab_i)$ | $T_{ab\_max}=15\text{min}$ | Janela aberta tempo demais |

**Composição** (Proposição 2 do artigo): o veredito do monitor composto
$M = M_1 \otimes M_2 \otimes \cdots \otimes M_8$ é o **ínfimo** dos
vereditos individuais no reticulado $\bot < \text{?} < \top$. Implementação em
[`src/Monitor/Composed.hs`](src/Monitor/Composed.hs).

**A5 embutido em A2.** Não há autômato $M_5$ separado: o limiar $\tau$
filtra as classificações que resolvem A2 e que contribuem para $M_{obs}$.
É decisão de modelagem deliberada — A5 não é uma propriedade temporal.

**Mes-bridge** (§5.4 do artigo, [`src/Monitor/MesBridge.hs`](src/Monitor/MesBridge.hs)):
ao chegar em `leave_ab_i`, se o traço não pronunciar `match_i`/`div_i`, o
emulador compara `M_obs` (acumulado) com `M_dec` (do cabeçalho YAML) e
injeta automaticamente o evento ausente — simulando o componente externo
que existe em produção.

Tabela cenário×propriedade em [docs/CENARIOS.md](docs/CENARIOS.md).

---

## Cenários cobertos

Os 15 cenários derivam da análise operacional de rotomoldagem multi-braço.
Cada um vira ao menos um arquivo em `Files/Traces/`.

| # | Cenário | Veredito | Propriedade que captura |
|---|---------|---------:|-------------------------|
| 01 | Aceitação canônica (1 peça) | ⊤ | — |
| 02 | Aceitação múltiplas peças | ⊤ | — |
| 03 | rem_i antes de ab_i | ⊥ | A1 |
| 04 | rem_i após leave_ab_i | ⊥ | A1 (+ A3) |
| 05 | Janela vazia | ⊤ | — |
| 06 | Braço 1 mix OP A+B+vazio | ⊤ | — |
| 07 | Braço 2 OP C uniforme | ⊤ | — |
| 08 | Molde vazio esquecido no MES | ⊥ | A4 (após mes-bridge) |
| 09 | OP errada no PLC | ⊥ | A4 (após mes-bridge) |
| 10 | Refugo sem cls prévia | ⊥ | A7 |
| 11 | Janela longa demais (34 min) | ⊥ | A8 |
| 12 | Agente morto (gap > T_h) | ⊥ | A6 |
| 13 | Deriva da CNN (todas conf<τ) | ⊥ | A2 + A4 |
| 14 | Classificação atrasada (gap > T_cls) | ⊥ | A2 |
| 15 | Escalação atrasada (gap > T_pcp) | ⊥ | A4 |

Análise por cenário em [docs/CENARIOS.md](docs/CENARIOS.md).

---

## Modos de saída do CLI

```bash
lab-monitor [--quiet|--json] <arquivo_de_traço>
```

| Modo | Quando usar |
|------|-------------|
| (padrão) | Formato detalhado tipo "emulador" — parâmetros, processamento evento-a-evento, vereditos por propriedade, decisão do gate. Auditável. |
| `--quiet` | Bloco curto (~5 linhas) com veredito e regras violadas. Usado pelo `batch.sh`. |
| `--json` | JSON estruturado: header, config, todos os steps com estado, veredito final, índice da primeira violação, regras violadas. |

### Exemplo — formato detalhado (default)

```
===================================================================
EMULADOR LTL/TLTL — Monitor de Apontamento de Produção
Versão 0.7.0 — A1, A2, A3, A4, A5 + extensões A6, A7, A8
===================================================================

Arquivo : Files/Traces/trace_08_viola_a4_molde_vazio.txt
Cenário : Molde vazio esquecido no MES (Situação 2 do artigo)
Máquina : ROTO-01
Braço   : 1

Parâmetros do monitor:
  T_cls    = 30000 ms     (A2)
  T_pcp    = 300000 ms    (A4)
  T_h      = 5000 ms      (A6)
  T_rej    = 10000 ms     (A7)
  T_ab_max = 900000 ms    (A8)
  τ        = 0.85         (A5)

M_dec declarado no MES: {caixa_1000L:2, caixa_2000L:2}

-------------------------------------------------------------------
Processamento evento-a-evento:
[t=0       ms]  ab_i              | M1:ok(ab) M2:idle ...  V=⊤
[t=1500    ms]  rem_i             | M2:pending(x=1500) ... V=⊤
...
[t=8000    ms]  div_i             | M3:ok M4:pending(x=8000) V=⊤

-------------------------------------------------------------------
Vereditos por propriedade:
  A1 (safety: rem → ab)              : ⊤  ✓
  A2 (TLTL: cls em T_cls)            : ⊤  ✓
  A3 (safety: leave → match ∨ div)   : ⊤  ✓
  A4 (TLTL: esc em T_pcp)            : ⊥  ✗ ← violação
  ...

VEREDITO COMPOSTO (Proposição 2: ínfimo): VIOLA  (F)

-------------------------------------------------------------------
Decisão do gate (§5.4 do artigo):
  Decisão  : BLOQUEAR integração MES → ERP
  Motivo   : propriedade A4 violada
  Local    : detectado no fim do traço

===================================================================
Resultado: VIOLA  (F)
Código de saída: 2
===================================================================
```

---

## Formato do arquivo de traço

Texto simples, **um evento por linha**. Comentários (`#`) e linhas vazias são
ignorados. Cabeçalho YAML opcional entre `---` no topo. Timestamps opcionais
por evento.

```yaml
---
cenario: "Molde vazio esquecido no MES"
maquina: ROTO-01
braco: 1
m_dec: {caixa_1000L: 2, caixa_2000L: 2}
veredito_esperado: BOT
---
# Comentários livres
[t=    0] ab_i
[t= 1500] rem_i
[t= 2000] cls_p_i caixa_1000L 0.93
[t= 8000] leave_ab_i
```

### Sintaxes de timestamp aceitas

| Forma | Exemplo |
|-------|---------|
| Bracketed | `[t=1500] rem_i` |
| Inteiro inicial | `1500 rem_i` |
| Ausente (idx × 1000 ms) | `rem_i` |

### Eventos suportados

| Sintaxe | Significado |
|---------|-------------|
| `ab_i` | Braço entrou na janela de abastecimento |
| `rem_i` | Peça retirada |
| `leave_ab_i` | Fim da janela |
| `match_i` | $M_{obs} = M_{dec}$ |
| `div_i` | $M_{obs} \neq M_{dec}$ |
| `esc_pcp_i` | Escalação ao PCP |
| `heartbeat` | Sinal de vida do agente (A6) |
| `rej_i` | Peça marcada como refugo (A7) |
| `cls_p_i <sku> <conf>` | Classificação (ex.: `cls_p_i caixa_1000L 0.93`) |

### Campos do cabeçalho YAML

| Campo | Tipo | Uso |
|-------|------|-----|
| `cenario` | string | Exibido no output detalhado |
| `maquina` | string | Idem |
| `braco` | int | Idem |
| `m_dec` | mapa `{sku: int, ...}` flow style | Comparação multiset → injeção match/div |
| `veredito_esperado` | `TOP\|BOT\|INCONCLUSIVE` (case-insensitive) | Usado pela suite de testes |

Chaves não reconhecidas são silenciosamente ignoradas — extensibilidade
sem quebra.

---

## Configuração de parâmetros

Defaults em `Monitor.Types.defaultConfig`:

```haskell
defaultConfig = Config
  { cfgTcls   = 30000      -- 30 s     (A2)
  , cfgTpcp   = 300000     -- 5 min    (A4)
  , cfgTh     = 5000       -- 5 s      (A6)
  , cfgTrej   = 10000      -- 10 s     (A7)
  , cfgTabMax = 900000     -- 15 min   (A8)
  , cfgTau    = 0.85       -- limiar de A5
  , cfgValidSKUs = ["caixa_500L", "caixa_1000L", "caixa_2000L",
                   "caixa_3000L", "caixa_5000L", "molde_vazio"]
  }
```

> **Override via CLI ainda não implementado** (flags `--t-cls`, `--tau` etc.).
> Está no roadmap — atualmente, alterações exigem edição de
> `src/Monitor/Types.hs`.

---

## Como rodar os testes

```bash
nix develop --command cabal test --test-show-details=streaming
```

Saída esperada (resumida):

```
ExampleTraces       16 OK   (15 em Files/Traces + 1 em Files/Smoke)
CompositionProps     2 OK   (200 runs cada — Proposição 2)
AbsorbingProps       2 OK   (200 runs cada — sumidouro)
All 20 tests passed
```

Detalhes da suite em [test/](test/).

---

## Roadmap

Implementado nas Fases 1–11 (commits `1ec36d6..481238f`):

- [x] Modularização e tipos
- [x] Cabeçalho YAML + timestamps
- [x] A1 / A2 / A3 / A4 + composição (Prop. 2)
- [x] Mes-bridge (injeção automática match/div)
- [x] Output detalhado, `--quiet`, `--json`
- [x] A6 (heartbeat), A7 (refugo), A8 (janela limitada)
- [x] Suite Tasty (HUnit + QuickCheck)
- [x] Documentação

Próximos passos (não cobertos):

- [ ] Flags CLI para sobrescrever parâmetros (`--t-cls`, `--tau` etc.)
- [ ] Input via stream (stdin/socket) para integração ao agente real
- [ ] Multi-braço: `Map ArmId MonitorState` para instâncias independentes
- [ ] Métrica observacional de "deriva da CNN" (taxa de cls com conf < τ)
- [ ] CI no GitHub Actions

---

## Como contribuir

1. Crie um branch a partir de `main`.
2. Implemente a mudança mantendo `cabal build` limpo (`-Wall`) e
   `cabal test` verde.
3. Para novos cenários, adicione um traço em `Files/Traces/` com
   cabeçalho YAML completo (especialmente `veredito_esperado`) — a suite
   de testes pega automaticamente.
4. Para novas propriedades, siga o padrão dos módulos `Monitor/Automata/A*.hs`
   (mesmo formato de `step`/`verdict`/`finalVerdict`/`summary`). Adicione
   ao produto em `Monitor.Composed`.
5. Abra um PR descrevendo o cenário operacional motivador.

---

## Citação

```bibtex
@mastersthesis{miozzi2026monitor,
  author  = {Miozzi, Fl{\'a}vio M. Batista},
  title   = {Verifica{\c c}{\~a}o de Restri{\c c}{\~o}es Operacionais em
             Agentes de Vis{\~a}o Computacional via Aut{\^o}matos de
             Monitoramento: Especifica{\c c}{\~a}o em LTL e TLTL para
             Apontamento de Produ{\c c}{\~a}o em Manufatura},
  school  = {Universidade [...]},
  year    = {2026},
  note    = {C{\'o}digo-fonte do emulador:
             \url{https://github.com/fmiozzi/teoria-computacao-artigo-emulador}}
}
```

Bibliografia complementar em [docs/REFERENCIAS.md](docs/REFERENCIAS.md).

---

## Licença

MIT — veja [LICENSE](LICENSE). Software acadêmico de demonstração; uso e
modificação livres, sem garantias.
