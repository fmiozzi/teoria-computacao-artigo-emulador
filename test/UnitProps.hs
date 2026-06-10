{-# LANGUAGE OverloadedStrings #-}

-- | Testes unitários (HUnit) das peças de baixo nível do monitor
-- verificado (A1–A3 + A5): filtro A5 ('Monitor.Classification'),
-- multiconjuntos ('Monitor.Multiset') e os relógios dos autômatos
-- temporizados A2 e A3 (casos de borda x = T vs x > T). A4 é extensão
-- prospectiva (§6) e não integra a suíte do recorte verificado.
module UnitProps (tests) where

import qualified Data.Map.Strict        as Map
import           Test.Tasty             (TestTree, testGroup)
import           Test.Tasty.HUnit       (testCase, (@?=), assertBool)

import           Monitor.Classification (filterByTau, isValidCls)
import qualified Monitor.Multiset       as MS
import qualified Monitor.Automata.A2    as A2
import qualified Monitor.Automata.A3    as A3
import           Monitor.Types

-- | Config com prazos curtos para exercitar os relógios.
cfg :: Config
cfg = defaultConfig { cfgTcls = 2000, cfgTdec = 2000, cfgTau = 0.85 }

runA2 :: [TimedEvent] -> A2.M2
runA2 = foldl A2.step (A2.initial cfg)

runA3 :: [TimedEvent] -> A3.M3
runA3 = foldl A3.step (A3.initial cfg)

te :: Int -> Event -> TimedEvent
te = TimedEvent

tests :: TestTree
tests = testGroup "UnitProps"
  [ testGroup "Classification (A5)"
    [ testCase "isValidCls aceita conf >= tau" $
        isValidCls 0.85 (ClsPI "caixa_1000L" 0.90) @?= True
    , testCase "isValidCls rejeita conf < tau" $
        isValidCls 0.85 (ClsPI "caixa_1000L" 0.50) @?= False
    , testCase "isValidCls falso para não-classificação" $
        isValidCls 0.85 AbI @?= False
    , testCase "filterByTau descarta cls fracas e mantém o resto" $
        filterByTau 0.85
          [AbI, ClsPI "a" 0.90, ClsPI "b" 0.50, RemI, ClsPI "c" 0.85]
          @?= [AbI, ClsPI "a" 0.90, RemI, ClsPI "c" 0.85]
    ]
  , testGroup "Multiset"
    [ testCase "addCls acumula e compara igual" $
        MS.compareMs (MS.addCls "a" (MS.addCls "a" MS.empty)) (Map.fromList [("a", 2)])
          @?= Right ()
    , testCase "compareMs detecta divergência" $
        assertBool "esperado Left" (isLeft (MS.compareMs MS.empty (Map.fromList [("a", 1)])))
    , testCase "removeCls decrementa" $
        MS.compareMs (MS.removeCls "a" (MS.addCls "a" (MS.addCls "a" MS.empty)))
                     (Map.fromList [("a", 1)])
          @?= Right ()
    ]
  , testGroup "A2 (relógio T_cls; ancorada em leave_ab_i)"
    [ testCase "janela vazia é vacuosamente aceita" $
        A2.finalVerdict (runA2 [te 0 AbI, te 1000 LeaveAbI]) @?= Top
    , testCase "cls válida durante a janela satisfaz" $
        A2.finalVerdict (runA2 [te 0 AbI, te 500 RemI, te 600 (ClsPI "a" 0.9), te 1000 LeaveAbI])
          @?= Top
    , testCase "rem sem cls válida e cls tardia > T_cls viola" $
        A2.verdict (runA2 [te 0 AbI, te 500 RemI, te 1000 LeaveAbI, te 3001 (ClsPI "a" 0.9)])
          @?= Bot
    , testCase "cls com conf < tau não satisfaz (pendente no fim)" $
        A2.finalVerdict (runA2 [te 0 AbI, te 500 RemI, te 600 (ClsPI "a" 0.5), te 1000 LeaveAbI])
          @?= Bot
    ]
  , testGroup "A3 (relógio T_dec)"
    [ testCase "match dentro de T_dec satisfaz" $
        A3.finalVerdict (runA3 [te 0 AbI, te 1000 LeaveAbI, te 2000 MatchI]) @?= Top
    , testCase "match após T_dec viola (x > T_dec)" $
        A3.verdict (runA3 [te 0 AbI, te 1000 LeaveAbI, te 3001 MatchI]) @?= Bot
    , testCase "leave sem decisão até o fim viola" $
        A3.finalVerdict (runA3 [te 0 AbI, te 1000 LeaveAbI]) @?= Bot
    ]
  ]

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False
