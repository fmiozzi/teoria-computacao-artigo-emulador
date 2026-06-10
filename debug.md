# Guia de Depuração — Emulador LTL/TLTL

Material de consulta para depurar, inspecionar e experimentar com o projeto
`lab-monitor` no GHCi. Voltado a quem não tem prática em Haskell.

> O "código de verdade" do emulador é Haskell — o script `Exec/monitor.sh`
> é só um wrapper. Por isso a depuração real acontece no **GHCi**
> (REPL/depurador do GHC), pelo terminal. VS Code com a extensão Haskell
> Language Server ajuda com hover de tipos e go-to-def, mas não tem
> debugger gráfico estável para Haskell — então tudo o que está aqui é
> linha de comando.

---

## 1. Pré-requisitos

Toolchain disponível (confira com `which`):

- `nix` — para entrar no shell do projeto via `flake.nix`
- `cabal` — gerenciador de build Haskell
- `ghci` — REPL do GHC (vem com o GHC)

Estrutura relevante do projeto:

```
Emulador/
├── app/Main.hs              ← entry point do executável (CLI)
├── app/Corpus.hs            ← gerador do corpus aleatório (`cabal run corpus-gen`)
├── src/
│   ├── Monitor/
│   │   ├── Gate.hs          ← MOTOR: `run`, Algoritmo 1; enriquece o fluxo e roteia o status
│   │   ├── Composed.hs      ← produto puro M₁⊗M₂⊗M₃: `step`, `verdict`, `finalVerdict`, `sinkM*`
│   │   ├── Parser.hs        ← parser de arquivos de traço
│   │   ├── Types.hs         ← `Config`, `defaultConfig`, `Verdict`, `Event`, `MesStatus`, `Diag`
│   │   ├── Header.hs        ← cabeçalho YAML do traço (`veredito_esperado`, `status_esperado`)
│   │   ├── MesBridge.hs     ← operações puras do mes-bridge: `pronounce`, `structuralException`
│   │   ├── Classification.hs← filtro A5 (`isValidCls`)
│   │   ├── Multiset.hs      ← M_obs (multiset de SKUs)
│   │   └── Automata/        ← A1, A2, A3 (verificados) + A4, A6, A7, A8 (prospectivos §6, isolados)
│   └── Output/              ← renderização (Plain, Detailed, Json)
├── Files/Traces/            ← traços do recorte verificado (A1–A3 + A5)
│   └── extras/              ← traços prospectivos (A4/A6/A7/A8, §6 — fora do recorte)
├── Files/Corpus/            ← 400 traços aleatórios + resultados.csv + RELATORIO.md
└── Exec/monitor.sh          ← wrapper que chama `cabal run lab-monitor`
```

> **Atenção (mudança v2 → v2_3).** O motor é `Monitor.Gate.run`. As
> funções antigas `Monitor.Composed.runMonitor` / `runMonitorTrace` e
> `Monitor.MesBridge.injectMesBridge` **não existem mais**.
> `Monitor.Composed` agora é só o produto declarativo dos TRÊS
> componentes A1⊗A2⊗A3; A4 não faz parte do produto.

---

## 2. Abrir o GHCi com o projeto carregado

A partir do diretório do projeto:

```bash
cd /home/fmiozzi/Mestrado/teoria-da-computacao/artigo/Emulador
nix develop --command cabal repl exe:lab-monitor
```

**Detalhe importante:** use `exe:lab-monitor`, não `lab-monitor` puro. O
pacote tem dois componentes homônimos (a biblioteca e o executável). Sem
o prefixo `exe:`, o cabal carrega a biblioteca e o módulo `Main` não fica
disponível.

Sinal de que carregou certo:

```
[1 of 2] Compiling Main             ( app/Main.hs, interpreted )
Ok, one module loaded.
ghci>
```

Para sair:

```haskell
:quit
```

### Sem optimizations (recomendado para depurar)

Se for usar `:break` e quiser maior garantia de que os pontos vão
disparar, force interpretação por bytecode e desliga otimização:

```bash
nix develop --command cabal repl exe:lab-monitor \
  --repl-options=-fbyte-code --repl-options=-O0
```

---

## 3. Duas abordagens de depuração

O GHCi suporta dois estilos. Use o que melhor servir à pergunta:

| Abordagem | Quando usar |
|---|---|
| **A. Breakpoints + `:trace`** | Quer ver o **fluxo** de execução, parar em pontos do código, andar passo a passo. |
| **B. REPL exploratório** | Quer **chamar funções diretamente** e inspecionar resultados — é mais natural em Haskell, e *é* a forma mais útil para entender o emulador "evento por evento". |

A B é, na prática, muito mais produtiva para este projeto. Faça B primeiro.

---

## 4. Abordagem A — Breakpoints e step

### 4.1. Armar breakpoints

Duas sintaxes (note os formatos exatos — espaço vs. ponto):

```haskell
:break Main 42                 -- por linha:   módulo <espaço> número
:break Main.parseArgs          -- por função:  módulo <ponto>  nome
```

Listar / remover:

```haskell
:show breaks
:delete 0          -- remove breakpoint 0
:delete *          -- remove todos
```

### 4.2. Disparar a execução

```haskell
:set args Files/Traces/trace_01_aceita_simples.txt
:trace main
```

- `:set args` define `argv` que `getArgs` vai retornar.
- `:trace main` roda `main` com captura de histórico (permite `:back`).
  Para rodar sem histórico, use só `main`.

### 4.3. Navegar quando parar num breakpoint

| Comando | O que faz |
|---|---|
| `:list` | mostra o trecho de código em que parou |
| `:show bindings` | lista variáveis no escopo atual |
| `:print x` | mostra valor de `x` (avalia 1 nível — preguiçoso) |
| `:force x` | força avaliação completa de `x` |
| `:type x` | tipo de `x` |
| `:step` | avança uma redução (entra em chamadas de função) |
| `:steplocal` | avança sem descer em funções de outros módulos |
| `:stepmodule` | avança sem sair do módulo atual |
| `:continue` (`:c`) | roda até o próximo breakpoint (ou o fim) |
| `:back` | volta um passo no histórico (precisa `:trace`) |
| `:forward` | refaz um `:back` |
| `:history` | mostra pilha de execução do trace |
| `:abandon` | abandona a execução atual |

### 4.4. Armadilhas conhecidas

- **Breakpoint em uma ação IO atômica não pára.** Ex.: `:break Main 36`
  (sobre `getArgs`) é armado, mas pode não disparar. Use uma linha
  dentro de uma função pura (`:break Main.parseArgs`) ou uma linha
  "concreta" como a do `case` ou `let`.

- **Library compilada com `-O1` não para em breakpoints.** Se você
  quiser breakpoints dentro de `Monitor.Composed` ou nos autômatos,
  reabra com `--repl-options=-fbyte-code --repl-options=-O0`
  (veja seção 2).

- **`:break Main main`** dá erro de sintaxe — é coincidência: `main` aí
  é interpretado como número de linha. Use `:break Main.main` (com ponto)
  ou aponte para uma linha do corpo.

- **`*** Exception: ExitSuccess`** ao fim de `:trace main` é normal — é
  o `exitWith ExitSuccess` do programa terminando.

---

## 5. Abordagem B — REPL exploratório (recomendada)

Em vez de stepar pelo código, você **chama as funções do emulador
diretamente** e inspeciona resultados. Para Haskell isso é o equivalente
natural de "depurar".

### 5.1. Carregar módulos e ler um traço

```haskell
:m + Main Monitor.Gate Monitor.Composed Monitor.Parser Monitor.Types Monitor.Header
import qualified Data.Text.IO as TIO

content <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
let Right (hdr, events) = parseFile content
let cfg  = applyParams hdr defaultConfig   -- aplica parametros: {...} do header, se houver
let mDec = hdr >>= thMdec                  -- M_dec declarado (Maybe Multiset)
```

`parseFile` devolve o cabeçalho (`Maybe TraceHeader`) e a lista de
`TimedEvent` **crus** — o enriquecimento do fluxo (injeção de
`match_i`/`div_i`) acontece **dentro** de `Gate.run`, não mais num
pré-processador separado.

Inspeciona o cabeçalho e a lista de eventos:

```haskell
hdr
length events
mapM_ print events
```

### 5.2. Estado inicial do monitor

```haskell
let s0 = initial cfg
s0
```

`s0` é o `ComposedState` antes de processar qualquer evento. Ver a
seção 7.2 para o significado de cada campo.

### 5.3. Processar **um evento por vez**

```haskell
let s1 = step s0 (events !! 0)
s1

let s2 = step s1 (events !! 1)
s2

let s3 = step s2 (events !! 2)
s3
```

A cada `step`, compare com o estado anterior para ver **quais
autômatos** (M₁/M₂/M₃) mudaram. Isso é literalmente "1 passo do produto
sincronizado".

> **Cuidado:** `step` aqui consome a lista de eventos **crua**. Se o
> traço depende de um `match_i`/`div_i` injetado pelo mes-bridge (quando
> há `M_dec` e o traço cala), esse evento sintético **não** está em
> `events` — ele só aparece no fluxo enriquecido que `Gate.run` monta
> internamente. Para inspecionar o fluxo já enriquecido, use os `grSteps`
> da seção 5.4.

### 5.4. Pegar o resultado oficial e ver passo a passo

O motor é `Monitor.Gate.run :: Config -> Maybe Multiset -> [TimedEvent]
-> GateResult`. Ele enriquece o fluxo (mes-bridge), roda o produto
M₁⊗M₂⊗M₃ e roteia o status do gate (Algoritmo 1):

```haskell
let res = run cfg mDec events

grStatus     res   -- status terminal do gate: LiberadoIntegracao | DivergenciaPcp | ErroClassificacao | ErroDecisao
grDiag       res   -- Maybe Diag: causa-raiz do bloqueio (Nothing sse liberado)
grVerdict    res   -- veredito composto terminal (Proposição 2): Top ou Bot
grRules      res   -- componentes formais violados no terminal (ex.: ["A2"])
grFirstViol  res   -- Maybe Int: índice 1-based da primeira violação de stream
grDivAt      res   -- Maybe Int: índice do passo em que div_i se materializou
length (grSteps res)  -- quantos eventos do fluxo ENRIQUECIDO foram processados
```

> **Veredito ≠ status.** `grVerdict` é o veredito composto (ínfimo de
> A1/A2/A3); `grStatus` é a decisão de processo do gate. Um `mismatch`
> tem `grVerdict = Top` (a decisão foi tomada em prazo) mas
> `grStatus = DivergenciaPcp`. São coisas distintas — não os confunda.

Inspecionar um passo individual (os `Step` vêm de `Monitor.Gate`):

```haskell
let steps = grSteps res
steps !! 0        -- registro completo do passo 0
stepEvent   (steps !! 0)
stepTime    (steps !! 0)
stepState   (steps !! 0)
stepVerdict (steps !! 0)   -- veredito de stream neste passo (domínio {⊥, ?})
stepRules   (steps !! 0)
```

Veredito de stream ao longo do tempo:

```haskell
map stepVerdict steps
-- ex: [Inconclusive, Inconclusive, ..., Inconclusive]  (⊤ só surge no terminal)
```

### 5.5. Zoom em **um autômato isolado**

Cada autômato exporta seu próprio `step`. Dá pra rodar só ele:

```haskell
import qualified Monitor.Automata.A2 as A2
let a2_0 = csM2 s0
let a2_1 = A2.step a2_0 (events !! 1)
a2_1
```

Vale para A1 (`csM1`) e A3 (`csM3`) também — são os **três** componentes
do produto verificado. Útil para entender uma propriedade específica sem
o ruído das outras.

> A4/A6/A7/A8 são extensões prospectivas (§6) e **não** estão em
> `ComposedState`. Para experimentar com elas, importe o módulo isolado
> (ex.: `import qualified Monitor.Automata.A4 as A4`) e rode
> `A4.initial cfg` / `A4.step` à parte — elas não participam do veredito
> composto nem do gate.

### 5.6. Reiniciar de qualquer ponto

Como tudo é puro (sem efeito colateral nos `step`), basta atribuir um
novo `let`. Pode voltar reaproveitando um `s` anterior:

```haskell
let s2_alt = step s1 (events !! 1)   -- mesmo evento de novo
```

### 5.7. Recarregar após editar o código

Depois de alterar um `.hs`, dentro do GHCi:

```haskell
:reload      -- ou :r
```

Mantém breakpoints. Mantém os `let` que você definiu? **Não** — os
bindings interativos são perdidos. Refaça os `let` ou tenha um arquivo
de script (`.ghci`) com os imports e comandos prontos.

---

## 6. Formato de arquivo de traço

[Files/Traces/](Files/Traces/) tem exemplos. Estrutura:

```
---
cenario: "..."               # YAML opcional
m_dec: {caixa_1000L: 1}      # multiconjunto declarado (M_dec)
veredito_esperado: TOP                 # veredito composto (Proposição 2)
status_esperado: liberado_integracao   # status do gate (§5.4)
---
# comentários iniciam com #
ab_i
rem_i
cls_p_i caixa_1000L 0.93
leave_ab_i
match_i
```

### 6.1. Como o tempo é atribuído ao evento

Três formas, em ordem de prioridade ([Parser.hs:76-83](src/Monitor/Parser.hs#L76-L83)):

| Forma | Exemplo | Tempo (ms) |
|---|---|---|
| Colchete | `[t=1500] rem_i` | 1500 |
| Inteiro líder | `1500 rem_i` | 1500 |
| Sem tempo | `rem_i` | `i * 1000` |

Onde `i` é o **índice 0-based do evento válido** — não o número de
linha. Linhas em branco e comentários **não** consomem índice
([Parser.hs:62-68](src/Monitor/Parser.hs#L62-L68)).

Exemplo: no `trace_01_aceita_simples.txt`, sem timestamps explícitos:

```
ab_i                        → i=0 → t=0
rem_i                       → i=1 → t=1000
cls_p_i caixa_1000L 0.93    → i=2 → t=2000
leave_ab_i                  → i=3 → t=3000
match_i                     → i=4 → t=4000
```

Para forçar gaps de tempo que violem um prazo (ex.: estourar A2, cujo
`T_cls = 1500` ms por default, ou A3, cujo `T_dec = 1700` ms), use
timestamp explícito:

```
ab_i
rem_i
leave_ab_i
[t=5000] cls_p_i caixa_1000L 0.93   # cls chega 5 s depois — muito além de T_cls
```

---

## 7. Anatomia do estado

### 7.1. `defaultConfig` ([Types.hs:154-165](src/Monitor/Types.hs#L154-L165))

Define os prazos em ms e o τ da CNN, nos valores do cenário-âncora (§4):

```haskell
defaultConfig = Config
  -- monitor verificado (A1–A3 + filtro A5)
  { cfgTcls    = 1500       -- 1,5 s  (A2: latência máx. de classificação)
  , cfgTdec    = 1700       -- T_cls + ε, com ε = 200 ms (A3: prazo de decisão)
  , cfgDeltaMb = 100        -- δ_mb ≤ ε = T_dec − T_cls = 200 ms (latência do mes-bridge)
  , cfgTau     = 0.85       -- limiar de confiança (A5)
    -- extensões prospectivas (§6) — fora do monitor verificado
  , cfgTpcp    = 300000     -- 5 min  (A4, ilustrativo — o artigo não fixa T_pcp)
  , cfgTh      = 5000       -- 5 s    (A6)
  , cfgTrej    = 10000      -- 10 s   (A7)
  , cfgTabMax  = 90000      -- ~ciclo da máquina (A8)
  }
```

> **Mudou de v2 para v2_3:** os prazos não são mais 30 s / 31 s — agora
> T_cls = 1500 ms e T_dec = 1700 ms. O campo `cfgValidSKUs` foi
> **removido**; o catálogo-âncora de 7 SKUs (Figura 12) vive em
> `Monitor.Types.anchorCatalog`, usado pelos traços e pelo `corpus-gen`.
> Os parâmetros `cfgTpcp`/`cfgTh`/`cfgTrej`/`cfgTabMax` só são consumidos
> pelos módulos prospectivos isolados.

### 7.2. `ComposedState` e `initial` ([Composed.hs:49-64](src/Monitor/Composed.hs#L49-L64))

São **três** componentes — o produto verificado é `M = M₁ ⊗ M₂ ⊗ M₃`.
A4/A6/A7/A8 **não** estão aqui (são prospectivos, §6).

```haskell
data ComposedState = ComposedState
  { csM1   :: !A1.M1   -- A1: safety rem → ab
  , csM2   :: !A2.M2   -- A2′: bounded liveness — cls confiável em T_cls
  , csM3   :: !A3.M3   -- A3′: bounded liveness — decisão (match ∨ div) em T_dec
  , csObs  :: !Multiset   -- M_obs da janela corrente (A5); só para exibição
  , csTau  :: !Double     -- τ replicado no nível composto
  }

initial cfg = ComposedState
  { csM1  = A1.initial        -- A1 não usa cfg (safety puro)
  , csM2  = A2.initial cfg
  , csM3  = A3.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }
```

Cada autômato `M_i` carrega no próprio estado os parâmetros relevantes
(ex.: `m2Tcls`, `m3Tdec`). Eles ficam congelados durante a execução —
só o campo `mXState` evolui.

> A5 não tem autômato próprio — é filtro estrutural (`isValidCls` de
> `Monitor.Classification`) aplicado no `step` do `Composed` via `csTau`
> ([Composed.hs:71-83](src/Monitor/Composed.hs#L71-L83)). A comparação
> M_obs vs M_dec é responsabilidade do gate, não do produto.

### 7.3. `Step` e `GateResult` ([Gate.hs:70-93](src/Monitor/Gate.hs#L70-L93))

O `Step` (definido em `Monitor.Gate`) registra um passo sobre o fluxo
**enriquecido**; `GateResult` é a saída completa do Algoritmo 1.

```haskell
data Step = Step
  { stepIdx     :: !Int            -- índice 1-based no fluxo enriquecido
  , stepTime    :: !Int
  , stepEvent   :: !Event
  , stepState   :: !ComposedState
  , stepVerdict :: !Verdict        -- veredito de stream (domínio {⊥, ?})
  , stepRules   :: ![String]
  }

data GateResult = GateResult
  { grSteps      :: ![Step]
  , grVerdict    :: !Verdict          -- veredito composto terminal (∈ {⊥, ⊤})
  , grStatus     :: !MesStatus        -- status terminal do gate (§5.4)
  , grDiag       :: !(Maybe Diag)     -- causa-raiz (Nothing sse liberado)
  , grRules      :: ![String]         -- componentes formais violados (terminal)
  , grFirstViol  :: !(Maybe Int)      -- 1º passo com violação de stream
  , grDivAt      :: !(Maybe Int)      -- passo em que div_i se materializou
  , grFinalState :: !ComposedState
  }

run :: Config -> Maybe Multiset -> [TimedEvent] -> GateResult
```

`run` enriquece o fluxo (mes-bridge), aplica o produto e roteia o status
do gate na ordem de prioridade do Algoritmo 1: sumidouro de M₁ → M₂ → M₃
→ `div_i` → `match_i`.

---

## 8. Receitas prontas

### 8.1. Rodar um traço sem entrar no debugger

Direto do shell (sem GHCi):

```bash
./Exec/monitor.sh Files/Traces/trace_01_aceita_simples.txt
./Exec/monitor.sh --quiet Files/Traces/trace_01_aceita_simples.txt
./Exec/monitor.sh --json  Files/Traces/trace_01_aceita_simples.txt
```

Códigos de saída, derivados do **status do gate** ([Main.hs:11-16](app/Main.hs#L11-L16)):

- `0` — `liberado_integracao` (LIBERAR)
- `2` — qualquer BLOQUEAR (`divergencia_pcp` | `erro_classificacao` | `erro_decisao`)
- `3` — `pendente_verificacao` (apontamento sem decisão terminal)
- `1` — erro de parsing/IO/uso

> O código de saída segue o **status do gate**, não o veredito composto.
> Um traço com veredito ⊤ mas `divergencia_pcp` (ex.: `mismatch`) sai
> com `2`, não `0`.

Para depurar **só o shell** (não entra no Haskell):

```bash
bash -x ./Exec/monitor.sh Files/Traces/trace_01_aceita_simples.txt
```

### 8.2. Comparar dois traços no GHCi

```haskell
content1 <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
content2 <- TIO.readFile "Files/Traces/trace_02_aceita_multiplas.txt"
let Right (h1, ev1) = parseFile content1
let Right (h2, ev2) = parseFile content2
let res1 = run (applyParams h1 defaultConfig) (h1 >>= thMdec) ev1
let res2 = run (applyParams h2 defaultConfig) (h2 >>= thMdec) ev2
(grVerdict res1, grStatus res1, grVerdict res2, grStatus res2)
```

### 8.3. Encontrar onde um traço foi violado

```haskell
let res = run cfg mDec events
grVerdict   res    -- veredito composto terminal
grStatus    res    -- status do gate (a "decisão" final)
grDiag      res    -- causa-raiz do bloqueio
grFirstViol res    -- Just i → o passo i foi o 1º a virar ⊥ no stream
grRules     res    -- qual(is) componente(s) violou(aram)
grSteps res !! 0   -- estado em qualquer passo do fluxo enriquecido
```

### 8.4. Customizar a Config

```haskell
let cfg2 = defaultConfig { cfgTcls = 800, cfgTdec = 1000 }  -- prazos mais agressivos
let res2 = run cfg2 mDec events
(grVerdict res2, grStatus res2)
```

### 8.5. Ver tipos enquanto explora

```haskell
:type run
:type defaultConfig
:info GateResult
:info ComposedState
:info Verdict
:info MesStatus
```

### 8.6. Listar arquivos de traço

```haskell
:!ls Files/Traces/
:!head -20 Files/Traces/trace_03_<nome>.txt
```

(Qualquer comando shell com `:!`.)

---

## 9. Cola rápida — comandos GHCi mais usados

```
:quit                       sair
:reload                     recompilar após editar arquivos
:m + Mod1 Mod2              carrega módulos no escopo
:type expr                  tipo de uma expressão
:info Tipo                  definição/instâncias de um tipo
:set args ...               define argv para `:main`/`:trace main`
:trace main                 roda main com histórico
:break Mod 42               breakpoint por linha
:break Mod.func             breakpoint por função
:show breaks                lista breakpoints
:delete *                   remove todos breakpoints
:list                       código onde parou
:show bindings              variáveis em escopo
:print x                    valor (lazy)
:force x                    valor (estrito)
:step                       avança 1 redução
:steplocal                  avança sem descer em funções de outros módulos
:continue (:c)              até o próximo break / fim
:back / :forward            navega histórico
:! cmd                      executa cmd no shell
```

---

## 10. Solução de problemas

**Erro:** `Could not find module 'Main'`
Carregou a biblioteca em vez do executável. Saia e reabra com
`cabal repl exe:lab-monitor`.

**Erro:** `Syntax: :break ...` ao usar `:break Main parseArgs`.
O GHCi quer **ponto** entre módulo e função: `:break Main.parseArgs`.
A forma com **espaço** é só para `:break Main 42` (linha).

**Erro:** Breakpoint armado mas `:trace main` roda tudo sem parar.
Provável: breakpoint em IO atômico (ex.: `getArgs`) ou módulo compilado
com `-O1`. Solução: aponte para uma função pura (`Main.parseArgs`),
use linha "concreta", ou reabra com `--repl-options=-fbyte-code
--repl-options=-O0`.

**Erro:** `:print x` mostra `x = (_t1::Tipo)`.
É um thunk não avaliado (laziness). Use `:force x` para forçar.

**Erro:** `*** Exception: ExitSuccess`.
Não é erro — é o `exitWith ExitSuccess` ao fim do `main`. Normal.

**Erro:** os `let` desapareceram após `:reload`.
Bindings interativos não sobrevivem ao reload. Refaça-os, ou crie um
arquivo `.ghci` no projeto com os imports/let mais usados (GHCi carrega
automaticamente).

---

## 11. Receita-mestre: do zero até ver um traço passar

Sequência mínima para abrir o REPL, ler um traço, e rodar passo a passo:

```bash
cd /home/fmiozzi/Mestrado/teoria-da-computacao/artigo/Emulador
nix develop --command cabal repl exe:lab-monitor
```

```haskell
:m + Main Monitor.Gate Monitor.Composed Monitor.Parser Monitor.Types Monitor.Header
import qualified Data.Text.IO as TIO

content <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
let Right (hdr, events) = parseFile content
let cfg  = applyParams hdr defaultConfig
let mDec = hdr >>= thMdec

-- (a) passo a passo, à mão, sobre os eventos crus do produto M₁⊗M₂⊗M₃:
let s0 = initial cfg
let s1 = step s0 (events !! 0)
let s2 = step s1 (events !! 1)
let s3 = step s2 (events !! 2)
let s4 = step s3 (events !! 3)
let s5 = step s4 (events !! 4)

-- (b) resultado oficial pelo motor (fluxo enriquecido + gate):
let res = run cfg mDec events
grVerdict res            -- veredito composto terminal
grStatus  res            -- status do gate
grDiag    res            -- causa-raiz, se bloqueou
mapM_ print (map stepVerdict (grSteps res))
```

Imprima cada `sN` para ver os autômatos evoluindo, e compare com o
relatório que `./Exec/monitor.sh` gera para o mesmo arquivo. Note que os
`sN` da parte (a) percorrem os eventos **crus**, enquanto `grSteps res`
da parte (b) percorre o fluxo **enriquecido** pelo mes-bridge — eles
podem ter comprimentos diferentes quando o gate injeta `match_i`/`div_i`.
