{-# LANGUAGE OverloadedStrings #-}

-- | Absorção do sumidouro: uma vez que o monitor composto chegou a ⊥
-- /no veredito de stream/, nenhum evento posterior o tira desse estado.
-- Isso é consequência direta de cada componente individual ter
-- 'Violated' como sumidouro absorvente.
--
-- /Não/ vale o mesmo para 'finalVerdict' isoladamente: estados como
-- 'M3Awaiting' ou 'M4Pending' têm 'finalVerdict' = ⊥ mas podem
-- /sair/ desse estado num step posterior. Por isso a propriedade
-- da absorção é, formalmente, do veredito de stream — e o que
-- garantimos no terminal é a implicação "stream ⊥ ⇒ terminal ⊥".
module AbsorbingProps (tests) where

import           Test.Tasty             (TestTree, testGroup)
import           Test.Tasty.QuickCheck  (testProperty, withMaxSuccess)
import           Test.QuickCheck        (Property, (==>))

import qualified Monitor.Composed       as C
import           Monitor.Types

import           CompositionProps       ()  -- importa as instâncias de Arbitrary

tests :: TestTree
tests = testGroup "AbsorbingProps (sumidouro)"
  [ testProperty "verdict ⊥ é absorvente (stream)"
      (withMaxSuccess 200 prop_streamAbsorbs)
  , testProperty "verdict ⊥ implica finalVerdict ⊥ (terminal só piora)"
      (withMaxSuccess 200 prop_streamImpliesFinal)
  ]

-- | Se um prefixo já levou o veredito de stream a ⊥, qualquer sufixo
-- mantém ⊥. (Sumidouro 'Violated' absorvente em cada componente.)
prop_streamAbsorbs :: [TimedEvent] -> [TimedEvent] -> Property
prop_streamAbsorbs prefix suffix =
  let sPrefix = run prefix
  in C.verdict sPrefix == Bot ==>
       C.verdict (foldl C.step sPrefix suffix) == Bot

-- | 'verdict' é uma cota superior de 'finalVerdict' (no reticulado).
-- Se 'verdict' já é ⊥, 'finalVerdict' também é (porque algum componente
-- está em 'Violated', cujo 'finalVerdict' é ⊥).
prop_streamImpliesFinal :: [TimedEvent] -> Property
prop_streamImpliesFinal events =
  let s = run events
  in C.verdict s == Bot ==> C.finalVerdict s == Bot

run :: [TimedEvent] -> C.ComposedState
run = foldl C.step (C.initial defaultConfig)
