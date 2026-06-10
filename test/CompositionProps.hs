{-# LANGUAGE OverloadedStrings #-}

-- | Proposição 2 do artigo via QuickCheck (property-based testing).
--
-- Para qualquer estado do monitor composto @M = M₁ ⊗ M₂ ⊗ M₃@ alcançável
-- por uma sequência de 'TimedEvent's, o veredito composto é o ínfimo dos
-- vereditos individuais dos TRÊS componentes (A1, A2', A3') — e o mesmo
-- vale para 'finalVerdict'. A propriedade A4 é extensão prospectiva (§6) e
-- /não/ integra o produto verificado.
--
-- Os eventos são gerados sobre o conjunto AP do artigo (§3.2) e o catálogo
-- de SKUs do cenário-âncora (Figura 12).
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
import qualified Monitor.Composed         as C
import           Monitor.Types

instance Arbitrary Event where
  -- Apenas o conjunto AP do artigo (§3.2): o produto sincronizado só
  -- consome essas proposições. As proposições prospectivas (esc_pcp/
  -- heartbeat/rej) ficam fora do recorte verificado.
  arbitrary = oneof
    [ pure AbI, pure RemI, pure LeaveAbI
    , pure MatchI, pure DivI
    , ClsPI <$> elements sampleSKUs <*> choose (0.0, 1.0)
    ]

instance Arbitrary TimedEvent where
  -- Timestamps gerados em [0, 10^6] ms; a propriedade da composição vale
  -- ponto a ponto, independentemente da monotonicidade da sequência.
  arbitrary = TimedEvent <$> choose (0, 1000000) <*> arbitrary

-- | SKUs do catálogo-âncora (Figura 12 do artigo).
sampleSKUs :: [T.Text]
sampleSKUs = anchorCatalog

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
              , A3.verdict (C.csM3 s)
              ]
  in C.verdict s == ind

prop_terminal :: [TimedEvent] -> Bool
prop_terminal tes =
  let s   = run tes
      ind = minimum
              [ A1.finalVerdict (C.csM1 s), A2.finalVerdict (C.csM2 s)
              , A3.finalVerdict (C.csM3 s)
              ]
  in C.finalVerdict s == ind

run :: [TimedEvent] -> C.ComposedState
run = foldl C.step (C.initial defaultConfig)
