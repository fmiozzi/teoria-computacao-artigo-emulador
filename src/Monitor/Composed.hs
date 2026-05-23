{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos M_k (Proposição 2 do artigo).
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente, basta o autômato individual mais
-- pessimista para determinar o veredito composto.
--
-- A partir da Fase 4 'step' recebe 'TimedEvent' (não só 'Event'),
-- porque os autômatos TLTL (A2 já implementado, A4 a partir da Fase 5)
-- consomem o timestamp.
module Monitor.Composed
  ( ComposedState (..)
  , initial
  , step
  , verdict
  , finalVerdict
  , violatingRules
  , finalViolatingRules
  , runMonitor
  ) where

import           Monitor.Types          ( Config
                                        , Event
                                        , TimedEvent (..)
                                        , Verdict (..)
                                        )
import qualified Monitor.Automata.A1 as A1
import qualified Monitor.Automata.A2 as A2
import qualified Monitor.Automata.A3 as A3
import qualified Monitor.Automata.A4 as A4

-- | Estado do monitor composto. Adicionar M4..M8 = adicionar um campo
-- aqui e atualizar 'step' / vereditos — a Proposição 2 garante
-- corretude composicional.
data ComposedState = ComposedState
  { csM1 :: !A1.M1
  , csM2 :: !A2.M2
  , csM3 :: !A3.M3
  , csM4 :: !A4.M4
  } deriving (Eq, Show)

initial :: Config -> ComposedState
initial cfg = ComposedState
  { csM1 = A1.initial
  , csM2 = A2.initial cfg
  , csM3 = A3.initial
  , csM4 = A4.initial cfg
  }

step :: ComposedState -> TimedEvent -> ComposedState
step s te = s
  { csM1 = A1.step (csM1 s) (teEvent te)
  , csM2 = A2.step (csM2 s) te
  , csM3 = A3.step (csM3 s) (teEvent te)
  , csM4 = A4.step (csM4 s) te
  }

-- | Ínfimo dos vereditos de stream (Proposição 2).
verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s)
  , A2.verdict (csM2 s)
  , A3.verdict (csM3 s)
  , A4.verdict (csM4 s)
  ]

-- | Ínfimo dos vereditos finais — avaliado uma única vez, ao consumir
-- o último 'TimedEvent' do traço.
finalVerdict :: ComposedState -> Verdict
finalVerdict s = minimum
  [ A1.finalVerdict (csM1 s)
  , A2.finalVerdict (csM2 s)
  , A3.finalVerdict (csM3 s)
  , A4.finalVerdict (csM4 s)
  ]

-- | Nomes dos componentes cujo 'verdict' está em ⊥.
violatingRules :: ComposedState -> [String]
violatingRules s =
  [ name
  | (v, name) <-
      [ (A1.verdict (csM1 s), "A1")
      , (A2.verdict (csM2 s), "A2")
      , (A3.verdict (csM3 s), "A3")
      , (A4.verdict (csM4 s), "A4")
      ]
  , v == Bot
  ]

-- | Análogo a 'violatingRules' mas avaliando 'finalVerdict' de cada
-- componente. Usado quando a violação só se manifesta no fim do traço.
finalViolatingRules :: ComposedState -> [String]
finalViolatingRules s =
  [ name
  | (v, name) <-
      [ (A1.finalVerdict (csM1 s), "A1")
      , (A2.finalVerdict (csM2 s), "A2")
      , (A3.finalVerdict (csM3 s), "A3")
      , (A4.finalVerdict (csM4 s), "A4")
      ]
  , v == Bot
  ]

-- | Roda o monitor evento a evento.
--
-- Em caso de violação durante o stream, retorna a posição (1-indexada),
-- o evento ofensor e as regras violadas. Se a violação só surgir no
-- veredito final, devolve 'Nothing' como posição.
runMonitor :: Config -> [TimedEvent] -> (Verdict, Maybe (Int, Event), [String])
runMonitor cfg = go 1 (initial cfg)
  where
    go _ s [] =
      let fv = finalVerdict s
      in case fv of
        Bot -> (Bot, Nothing, finalViolatingRules s)
        v   -> (v, Nothing, [])
    go i s (te : tes) =
      let e  = teEvent te
          s' = step s te
      in if verdict s' == Bot && verdict s /= Bot
           then (Bot, Just (i, e), violatingRules s')
           else go (i + 1) s' tes
