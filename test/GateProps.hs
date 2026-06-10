{-# LANGUAGE OverloadedStrings #-}

-- | Testes do efetor (gate, Algoritmo 1, §5.4): a função pura
-- 'Gate.decide' (ordem de prioridade sinkM1 → sinkM2 → sinkM3 → div →
-- match) e o motor 'Gate.run' ponta a ponta, cobrindo os QUATRO status
-- terminais e os CINCO diagnósticos de causa-raiz — incluindo
-- @fora_ciclo@, materializado pelo detector de exceções estruturais do
-- mes-bridge.
module GateProps (tests) where

import qualified Data.Map.Strict        as Map
import           Test.Tasty             (TestTree, testGroup)
import           Test.Tasty.HUnit       (testCase, (@?=))

import qualified Monitor.Composed       as C
import           Monitor.Gate           (GateResult (..), decide, run)
import           Monitor.Multiset       (Multiset, SKU)
import           Monitor.Types

cfg :: Config
cfg = defaultConfig   -- T_cls = 1500, T_dec = 1700, δ_mb = 100, τ = 0.85

te :: Int -> Event -> TimedEvent
te = TimedEvent

-- | Roda o gate e devolve (status, diagnóstico) terminal.
gate :: Maybe Multiset -> [TimedEvent] -> (MesStatus, Maybe Diag)
gate mDec evs = let r = run cfg mDec evs in (grStatus r, grDiag r)

verdictOf :: Maybe Multiset -> [TimedEvent] -> Verdict
verdictOf mDec evs = grVerdict (run cfg mDec evs)

-- estado composto alcançado por uma sequência de eventos
stateOf :: [TimedEvent] -> C.ComposedState
stateOf = foldl C.step (C.initial cfg)

tests :: TestTree
tests = testGroup "GateProps (efetor / Algoritmo 1)"
  [ testGroup "Gate.run — 4 status terminais e diagnósticos"
    [ testCase "liberado_integracao: match em prazo, sem violação" $
        gate Nothing [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI, te 1000 MatchI]
          @?= (LiberadoIntegracao, Nothing)

    , testCase "divergencia_pcp / safety_A1: rem fora da janela (A1)" $
        gate Nothing [te 0 RemI]
          @?= (DivergenciaPcp, Just SafetyA1)

    , testCase "erro_classificacao / timeout_cls: cls válida só após T_cls (A2)" $
        gate Nothing [te 0 AbI, te 500 RemI, te 1000 LeaveAbI, te 3000 (ClsPI "caixa_1000L" 0.95)]
          @?= (ErroClassificacao, Just TimeoutCls)

    , testCase "erro_decisao / leave_ab_silent: pronunciamento após T_dec (A3)" $
        gate Nothing [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI, te 3000 MatchI]
          @?= (ErroDecisao, Just LeaveAbSilent)

    , testCase "divergencia_pcp / mismatch: M_obs ≠ M_dec, agente mudo" $
        gate (Just (mset [("caixa_1000L", 2)]))
             [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI]
          @?= (DivergenciaPcp, Just Mismatch)

    , testCase "divergencia_pcp / fora_ciclo: pronunciamento espúrio fora do ciclo" $
        gate Nothing [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 800 DivI, te 1000 LeaveAbI, te 1000 MatchI]
          @?= (DivergenciaPcp, Just ForaCiclo)
    ]

  , testGroup "Gate.run — veredito composto ≠ status do gate"
    [ testCase "mismatch tem veredito composto ⊤ (A1–A3 satisfeitas)" $
        verdictOf (Just (mset [("caixa_1000L", 2)]))
                  [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI]
          @?= Top
    , testCase "violação de A1 tem veredito composto ⊥" $
        verdictOf Nothing [te 0 RemI] @?= Bot
    ]

  , testGroup "Gate.decide — precedência do Algoritmo 1 (sinkM1 > div)"
    [ testCase "A1 violada vence div materializado (safety_A1)" $
        -- estado com A1 no sumidouro; ainda que div tenha materializado,
        -- a prioridade do Algoritmo 1 roteia a divergencia_pcp/safety_A1.
        decide (stateOf [te 0 RemI]) True (Just Mismatch)
          @?= (DivergenciaPcp, Just SafetyA1)

    , testCase "estado limpo + div materializado → divergencia_pcp/diag" $
        decide (stateOf [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI, te 1000 MatchI])
               True (Just ForaCiclo)
          @?= (DivergenciaPcp, Just ForaCiclo)

    , testCase "estado limpo, sem div → liberado_integracao" $
        decide (stateOf [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI, te 1000 MatchI])
               False Nothing
          @?= (LiberadoIntegracao, Nothing)

    , testCase "div sem diagnóstico explícito assume mismatch" $
        decide (stateOf [te 0 AbI, te 500 RemI, te 700 (ClsPI "caixa_1000L" 0.95), te 1000 LeaveAbI, te 1000 MatchI])
               True Nothing
          @?= (DivergenciaPcp, Just Mismatch)
    ]
  ]

-- | Constrói um multiconjunto a partir de pares (SKU, multiplicidade).
mset :: [(SKU, Int)] -> Multiset
mset = Map.fromList . filter ((> 0) . snd)
