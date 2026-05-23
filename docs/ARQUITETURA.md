# Arquitetura do Emulador

Este documento descreve, em uma página, como os módulos do projeto se
encaixam — do parser ao output — e como o monitor composto $M = M_1
\otimes M_2 \otimes \cdots \otimes M_8$ é construído.

## Visão geral

```
            ┌────────────────────────┐
arquivo ──▶ │  Monitor.Parser        │  parseFile  (Maybe TraceHeader, [TimedEvent])
de traço    └────────────┬───────────┘
                         │
                         ▼
            ┌────────────────────────┐
            │  Monitor.MesBridge     │  injectMesBridge cfg hdr events
            │  (pré-processador)     │   ► insere match_i/div_i no leave_ab_i
            └────────────┬───────────┘     se o traço não pronunciar
                         │
                         ▼  [TimedEvent]
            ┌────────────────────────┐
            │  Monitor.Composed      │  runMonitorTrace cfg events
            │   ┌──────┬──────┬────┐ │   ► foldl step (initial cfg) events
            │   │ M1   │ M2   │ M3 │ │
            │   ├──────┼──────┼────┤ │   verdict s     = ínfimo dos 7 componentes
            │   │ M4   │ M6   │ M7 │ │   finalVerdict  = idem para fim do traço
            │   ├──────┴──────┴────┤ │
            │   │ M8 + csObs/csTau │ │
            │   └──────────────────┘ │
            └────────────┬───────────┘
                         │
                         ▼  (steps, verdict, mFirstViol, rules)
        ┌──────────┬─────┴─────┬───────────┐
        ▼          ▼           ▼           ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐
   │ Plain   │ │ Detailed│ │ Json    │   (selecionados pela flag CLI)
   │ --quiet │ │ default │ │ --json  │
   └─────────┘ └─────────┘ └─────────┘
```

## Tipos centrais

```haskell
-- Monitor.Types
data Event = AbI | RemI | LeaveAbI | MatchI | DivI | EscPcpI
           | ClsPI Text Double | Heartbeat | RejI

data TimedEvent = TimedEvent { teTime :: !Int, teEvent :: !Event }

data Verdict = Bot | Inconclusive | Top
  deriving (Eq, Ord, Show)    -- reticulado: Bot < Inconclusive < Top

data Config = Config
  { cfgTcls      :: Int       -- T_cls em ms     (A2)
  , cfgTpcp      :: Int       -- T_pcp em ms     (A4)
  , cfgTh        :: Int       -- T_h em ms       (A6)
  , cfgTrej      :: Int       -- T_rej em ms     (A7)
  , cfgTabMax    :: Int       -- T_ab_max em ms  (A8)
  , cfgTau       :: Double    -- limiar τ        (A5)
  , cfgValidSKUs :: [Text]
  }
```

## Estado do monitor composto

```haskell
-- Monitor.Composed
data ComposedState = ComposedState
  { csM1   :: !A1.M1   -- safety: G(rem → ab)
  , csM2   :: !A2.M2   -- TLTL  : G(rem → F[T_cls] cls)
  , csM3   :: !A3.M3   -- safety: G(leave → match ∨ div)
  , csM4   :: !A4.M4   -- TLTL  : G(div → F[T_pcp] esc_pcp)
  , csM6   :: !A6.M6   -- TLTL  : G F[T_h] heartbeat
  , csM7   :: !A7.M7   -- safety: G(rej → cls recente)
  , csM8   :: !A8.M8   -- TLTL  : G(ab → F[T_ab_max] leave)
  , csObs  :: !Multiset      -- M_obs acumulado (A5 já filtrou)
  , csTau  :: !Double        -- limiar para acumular em csObs
  }
```

Adicionar uma nova propriedade $A_n$ é mecânico:

1. Criar `Monitor.Automata.An` com `MnState`, `Mn`, `initial`, `step`,
   `verdict`, `finalVerdict`, `summary` (mesma assinatura dos outros).
2. Adicionar campo `csMn` em `ComposedState`.
3. Atualizar `initial`, `step`, `verdict`, `finalVerdict`,
   `violatingRules`, `finalViolatingRules`, `summary`.
4. Acrescentar entrada em `describeRule` (Output.Plain) e
   `perPropertyVerdicts` (Output.Detailed).
5. Adicionar `Monitor.Automata.An` em `lab-monitor.cabal`.

A Proposição 2 do artigo garante que a composição preserva a corretude.

## Pipeline de execução

```haskell
processFile :: Mode -> FilePath -> IO ()
processFile mode fp = do
  txt <- TIO.readFile fp
  case parseFile txt of
    Left  err -> failWith err
    Right (hdr, events) ->
      let cfg     = defaultConfig
          events' = injectMesBridge cfg hdr events     -- ① pré-processa
          (steps, v, mFirst, rules) =
              runMonitorTrace cfg events'              -- ② executa
      in case mode of
           ModeQuiet    -> renderPlain    ...
           ModeDetailed -> renderDetailed ...
           ModeJson     -> renderJson     ...
```

## Verdict de stream vs. terminal

Cada componente expõe **dois** vereditos:

| Função | Quando consultar | Como usa |
|--------|------------------|----------|
| `verdict` | a cada step do stream | Sumidouro absorvente — uma vez ⊥, sempre ⊥. |
| `finalVerdict` | uma única vez ao fim | Captura "obrigações pendentes" (e.g., `M3Awaiting`, `M4Pending`). |

Em geral, para safety pura (A1, A6, A7): `finalVerdict = verdict`. Para
TLTL (A2, A3, A4, A8): `finalVerdict` pode ser ⊥ mesmo que `verdict` seja
⊤ — porque o tempo "parou" no último evento do traço com obrigação ainda
aberta.

A composição é ínfimo dos vereditos individuais:

```haskell
verdict      s = minimum [A1.verdict      (csM1 s), ..., A8.verdict      (csM8 s)]
finalVerdict s = minimum [A1.finalVerdict (csM1 s), ..., A8.finalVerdict (csM8 s)]
```

## Pré-processamento (mes-bridge)

`Monitor.MesBridge` simula o componente externo descrito em §5.4 do
artigo. Ele varre o traço uma vez, mantendo um `M_obs` próprio
(independente do que o monitor faz):

1. `ClsPI sku conf` com `conf ≥ τ` → incrementa `M_obs[sku]`.
2. `LeaveAbI`:
   - se o próximo evento já é `MatchI`/`DivI`: deixa o traço prevalecer;
   - senão: insere `MatchI` se `M_obs = M_dec`, `DivI` caso contrário,
     com o mesmo timestamp do `LeaveAbI`.

Sem header ou sem `m_dec`, o traço passa intacto (caminho legado).

## Decisão sobre testes

A suite Tasty está organizada em três grupos:

| Grupo | Propósito | Tamanho |
|-------|-----------|---------|
| `ExampleTraces` | Cada arquivo em `Files/Traces/` e `Files/Smoke/` vira um caso HUnit. Compara veredito final com `veredito_esperado` do header. | 16 casos |
| `CompositionProps` | QuickCheck: para qualquer sequência de `TimedEvent`s, `verdict s == minimum [verdict componentes]`. Ídem para `finalVerdict`. | 200×2 runs |
| `AbsorbingProps` | QuickCheck: se prefixo levou a ⊥, sufixo mantém ⊥. Corolário "stream ⊥ ⇒ terminal ⊥". | 200×2 runs |

`AbsorbingProps` carrega as instâncias `Arbitrary` definidas em
`CompositionProps` via `import CompositionProps ()`.

## Trade-offs deliberados

- **Parser YAML ad-hoc** (Fase 2). Subset suficiente cabe em ~110 linhas;
  evitamos `libyaml + aeson` e o patch correspondente no `flake.nix`.
  Se precisarmos de listas/nested objects (e.g., `ops:`), migrar para a
  lib `yaml` afeta só `Monitor/Header.hs`.
- **Output JSON ad-hoc** (Fase 7). Mesmo raciocínio. Trocar por `aeson`
  daria schema validation/streaming, ao custo de mais deps.
- **A5 embutido em A2** (Fase 4). Não há autômato $M_5$ separado — A5 é
  filtro estrutural, não temporal.
- **A6 "armed/unarmed"** (Fase 10). Leitura literal de
  $G F_{[0,T_h]} heartbeat$ seria estrita demais para traços históricos
  sem heartbeat. Operacionalmente, A6 só "arma" no primeiro heartbeat.
- **M_obs duplicado** (MesBridge mantém um, ComposedState mantém outro).
  Aceito porque MesBridge é pré-processador (não enxerga o estado de
  runtime); a alternativa (`Composed` chamando `MesBridge.peek`) cruzaria
  a fronteira entre os dois.
