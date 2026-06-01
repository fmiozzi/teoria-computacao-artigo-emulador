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
├── app/Main.hs              ← entry point do executável
├── src/
│   ├── Monitor/
│   │   ├── Composed.hs      ← orquestra A1..A8, define `step` e `runMonitorTrace`
│   │   ├── Parser.hs        ← parser de arquivos de traço
│   │   ├── Types.hs         ← `Config`, `defaultConfig`, `Verdict`, `Event`
│   │   ├── Header.hs        ← cabeçalho YAML do traço
│   │   ├── MesBridge.hs     ← injeta eventos de bridge MES
│   │   ├── Multiset.hs      ← M_obs (multiset de SKUs)
│   │   └── Automata/        ← A1, A2, A3, A4, A6, A7, A8 (cada um seu `step`)
│   └── Output/              ← renderização (Plain, Detailed, Json)
├── Files/Traces/            ← arquivos de traço para teste
└── Exec/monitor.sh          ← wrapper que chama `cabal run lab-monitor`
```

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
:m + Main Monitor.Composed Monitor.Parser Monitor.Types Monitor.MesBridge
import qualified Data.Text.IO as TIO

content <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
let Right (hdr, events) = parseFile content
let cfg     = defaultConfig
let events' = injectMesBridge cfg hdr events
```

Inspeciona o cabeçalho e a lista de eventos:

```haskell
hdr
length events'
mapM_ print events'
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
let s1 = step s0 (events' !! 0)
s1

let s2 = step s1 (events' !! 1)
s2

let s3 = step s2 (events' !! 2)
s3
```

A cada `step`, compare com o estado anterior para ver **quais
autômatos** mudaram. Isso é literalmente "1 passo do emulador".

### 5.4. Pegar o resultado oficial e ver passo a passo

```haskell
let (steps, v, mFirst, rules) = runMonitorTrace cfg events'

length steps      -- quantos eventos processados
v                 -- veredito final: Top, Bot ou Inconclusive
mFirst            -- índice do primeiro evento que decidiu (se houve)
rules             -- veredito por propriedade (A1..A8)
```

Inspecionar um passo individual:

```haskell
steps !! 0        -- registro completo do passo 0
stepEvent   (steps !! 0)
stepTime    (steps !! 0)
stepState   (steps !! 0)
stepVerdict (steps !! 0)
stepRules   (steps !! 0)
```

Veredito ao longo do tempo:

```haskell
map stepVerdict steps
-- ex: [Top, Top, Top, Top, Top]
```

### 5.5. Zoom em **um autômato isolado**

Cada autômato exporta seu próprio `step`. Dá pra rodar só ele:

```haskell
import qualified Monitor.Automata.A2 as A2
let a2_0 = csM2 s0
let a2_1 = A2.step a2_0 (events' !! 1)
a2_1
```

Vale para A1, A3, A4, A6, A7, A8 também. Útil para entender uma
propriedade específica sem o ruído das outras.

### 5.6. Reiniciar de qualquer ponto

Como tudo é puro (sem efeito colateral nos `step`), basta atribuir um
novo `let`. Pode voltar reaproveitando um `s` anterior:

```haskell
let s2_alt = step s1 (events' !! 1)   -- mesmo evento de novo
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
cenario: "..."             # YAML opcional
veredito_esperado: TOP
---
# comentários iniciam com #
ab_i
rem_i
cls_p_i caixa_1000L 0.93
leave_ab_i
match_i
```

### 6.1. Como o tempo é atribuído ao evento

Três formas, em ordem de prioridade ([Parser.hs:73-79](src/Monitor/Parser.hs#L73-L79)):

| Forma | Exemplo | Tempo (ms) |
|---|---|---|
| Colchete | `[t=1500] rem_i` | 1500 |
| Inteiro líder | `1500 rem_i` | 1500 |
| Sem tempo | `rem_i` | `i * 1000` |

Onde `i` é o **índice 0-based do evento válido** — não o número de
linha. Linhas em branco e comentários **não** consomem índice
([Parser.hs:60-65](src/Monitor/Parser.hs#L60-L65)).

Exemplo: no `trace_01_aceita_simples.txt`, sem timestamps explícitos:

```
ab_i                        → i=0 → t=0
rem_i                       → i=1 → t=1000
cls_p_i caixa_1000L 0.93    → i=2 → t=2000
leave_ab_i                  → i=3 → t=3000
match_i                     → i=4 → t=4000
```

Para forçar gaps de tempo grandes (ex.: violar A2 cujo `T_cls = 30000`),
use timestamp explícito:

```
ab_i
[t=40000] rem_i
```

---

## 7. Anatomia do estado

### 7.1. `defaultConfig` ([Types.hs:90-102](src/Monitor/Types.hs#L90-L102))

Define os timeouts em ms e o τ da CNN:

```haskell
defaultConfig = Config
  { cfgTcls      = 30000      -- 30 s  (A2: latência de classificação)
  , cfgTpcp      = 300000     -- 5 min (A4: prazo de escalação ao PCP)
  , cfgTh        = 5000       -- 5 s   (A6: período máx. de heartbeat)
  , cfgTrej      = 10000      -- 10 s  (A7: janela rej_i → cls_p_i)
  , cfgTabMax    = 900000     -- 15 min (A8: janela máxima)
  , cfgTau       = 0.85       -- limiar de confiança (A5)
  , cfgValidSKUs = [ "caixa_500L", "caixa_1000L", ... ]
  }
```

### 7.2. `ComposedState` e `initial` ([Composed.hs:41-64](src/Monitor/Composed.hs#L41-L64))

```haskell
data ComposedState = ComposedState
  { csM1   :: !M1     -- A1: safety rem → ab
  , csM2   :: !M2     -- A2: TLTL cls em T_cls
  , csM3   :: !M3     -- A3: safety leave → match ∨ div
  , csM4   :: !M4     -- A4: TLTL esc em T_pcp
  , csM6   :: !M6     -- A6: TLTL heartbeat em T_h
  , csM7   :: !M7     -- A7: safety rej → cls recente
  , csM8   :: !M8     -- A8: TLTL janela ≤ T_ab_max
  , csObs  :: !Multiset   -- M_obs: SKUs classificados observados
  , csTau  :: !Double     -- τ replicado no nível composto
  }

initial cfg = ComposedState
  { csM1 = A1.initial          -- A1 e A3 não usam cfg (safety puro)
  , csM2 = A2.initial cfg
  , csM3 = A3.initial
  , csM4 = A4.initial cfg
  , csM6 = A6.initial cfg
  , csM7 = A7.initial cfg
  , csM8 = A8.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }
```

Cada autômato `M_i` carrega no próprio estado os parâmetros relevantes
(ex.: `m2Tcls`, `m4Tpcp`). Eles ficam congelados durante a execução —
só o campo `mXState` evolui.

> A5 não tem autômato próprio — é filtro estrutural aplicado direto no
> `step` do `Composed` via `csTau` ([Composed.hs:72-77](src/Monitor/Composed.hs#L72-L77)).

### 7.3. `Step` e `runMonitorTrace` ([Composed.hs:136-167](src/Monitor/Composed.hs#L136-L167))

```haskell
data Step = Step
  { stepIdx     :: !Int
  , stepTime    :: !Int
  , stepEvent   :: !Event
  , stepState   :: !ComposedState
  , stepVerdict :: !Verdict
  , stepRules   :: ![String]
  }

runMonitorTrace
  :: Config
  -> [TimedEvent]
  -> ([Step], Verdict, Maybe (Int, Event), [String])
```

Retorna a lista detalhada de passos, o veredito final, o primeiro
evento que decidiu (se houve), e a lista de regras por propriedade.

---

## 8. Receitas prontas

### 8.1. Rodar um traço sem entrar no debugger

Direto do shell (sem GHCi):

```bash
./Exec/monitor.sh Files/Traces/trace_01_aceita_simples.txt
./Exec/monitor.sh --quiet Files/Traces/trace_01_aceita_simples.txt
./Exec/monitor.sh --json  Files/Traces/trace_01_aceita_simples.txt
```

Códigos de saída ([Main.hs:11-15](app/Main.hs#L11-L15)):

- `0` — traço aceito (⊤)
- `1` — erro de parsing/uso ou veredito inconclusivo
- `2` — traço violado (⊥)

Para depurar **só o shell** (não entra no Haskell):

```bash
bash -x ./Exec/monitor.sh Files/Traces/trace_01_aceita_simples.txt
```

### 8.2. Comparar dois traços no GHCi

```haskell
content1 <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
content2 <- TIO.readFile "Files/Traces/trace_02_<nome>.txt"
let Right (_, ev1) = parseFile content1
let Right (_, ev2) = parseFile content2
let cfg = defaultConfig
let (_, v1, _, _) = runMonitorTrace cfg (injectMesBridge cfg Nothing ev1)
let (_, v2, _, _) = runMonitorTrace cfg (injectMesBridge cfg Nothing ev2)
(v1, v2)
```

### 8.3. Encontrar onde um traço foi violado

```haskell
let (steps, v, mFirst, rules) = runMonitorTrace cfg events'
v
mFirst              -- Just (i, evt) → o evento i foi o gatilho do ⊥
rules               -- veja qual propriedade falhou
steps !! (fst <$> mFirst <*> pure 0)   -- estado naquele ponto
```

### 8.4. Customizar a Config

```haskell
let cfg2 = defaultConfig { cfgTcls = 5000 }   -- T_cls mais agressivo (5 s)
let (_, v2, _, _) = runMonitorTrace cfg2 events'
v2
```

### 8.5. Ver tipos enquanto explora

```haskell
:type runMonitorTrace
:type defaultConfig
:info ComposedState
:info Verdict
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
:m + Main Monitor.Composed Monitor.Parser Monitor.Types Monitor.MesBridge
import qualified Data.Text.IO as TIO

content <- TIO.readFile "Files/Traces/trace_01_aceita_simples.txt"
let Right (hdr, events) = parseFile content
let cfg     = defaultConfig
let events' = injectMesBridge cfg hdr events

let s0 = initial cfg
let s1 = step s0 (events' !! 0)
let s2 = step s1 (events' !! 1)
let s3 = step s2 (events' !! 2)
let s4 = step s3 (events' !! 3)
let s5 = step s4 (events' !! 4)

let (steps, v, mFirst, rules) = runMonitorTrace cfg events'
v
mFirst
rules
mapM_ print (map stepVerdict steps)
```

Imprima cada `sN` para ver os autômatos evoluindo, e compare com o
relatório que `./Exec/monitor.sh` gera para o mesmo arquivo.
