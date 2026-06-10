{-# LANGUAGE OverloadedStrings #-}

-- | Proposição 2 do artigo via QuickCheck.
--
-- Para qualquer estado do monitor composto alcançável por uma sequência
-- de 'TimedEvent's, o veredito composto é o ínfimo dos vereditos
-- individuais dos componentes — e o mesmo vale para 'finalVerdict'.
module CompositionProps (tests) where

import           Test.Tasty               (TestTree, testGroup)
import           Test.Tasty.QuickCheck    (testProperty, withMaxSuccess)
import           Test.QuickCheck          ( Arbitrary (..)
                                          , choose, elements, oneof
                                          )
import qualified Data.Text                as T

import qualified Monitor.Automata.A1      as A1
import qualified Monitor.Automata.A2      as A2
import qualified Monitor.Automata.A3      as A3
import qualified Monitor.Automata.A4      as A4
import qualified Monitor.Composed         as C
import           Monitor.Types

instance Arbitrary Event where
  arbitrary = oneof
    [ pure AbI, pure RemI, pure LeaveAbI
    , pure MatchI, pure DivI, pure EscPcpI, pure Heartbeat
    , ClsPI <$> elements sampleSKUs <*> choose (0.0, 1.0)
    ]

instance Arbitrary TimedEvent where
  -- Timestamps monotônicos não-decrescentes (gerados por 'genTrace').
  arbitrary = TimedEvent <$> choose (0, 1000000) <*> arbitrary

sampleSKUs :: [T.Text]
sampleSKUs = ["caixa_500L", "caixa_1000L", "caixa_2000L", "molde_vazio"]

tests :: TestTree
tests = testGroup "CompositionProps (Proposição 2)"
  [ testProperty "verdict = ínfimo dos componentes (stream)"
      (withMaxSuccess 200 prop_stream)
  , testProperty "finalVerdict = ínfimo dos componentes (terminal)"
      (withMaxSuccess 200 prop_terminal)
  ]

prop_stream :: [TimedEvent] -> Bool
prop_stream tes =
  let s   = run tes
      ind = minimum
              [ A1.verdict (C.csM1 s), A2.verdict (C.csM2 s)
              , A3.verdict (C.csM3 s), A4.verdict (C.csM4 s)
              ]
  in C.verdict s == ind

prop_terminal :: [TimedEvent] -> Bool
prop_terminal tes =
  let s   = run tes
      ind = minimum
              [ A1.finalVerdict (C.csM1 s), A2.finalVerdict (C.csM2 s)
              , A3.finalVerdict (C.csM3 s), A4.finalVerdict (C.csM4 s)
              ]
  in C.finalVerdict s == ind

run :: [TimedEvent] -> C.ComposedState
run = foldl C.step (C.initial defaultConfig)
