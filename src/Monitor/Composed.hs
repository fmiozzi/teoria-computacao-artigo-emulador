{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos M_k (Proposição 2 do artigo).
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente, basta o autômato individual mais
-- pessimista para determinar o veredito composto.
--
-- A partir da Fase 3 expomos:
--
-- * 'verdict' — veredito de stream (a cada evento processado);
-- * 'finalVerdict' — veredito ao fim do traço, que pode ser pior
--   (autômatos como M3 têm estado "pendente" que vira ⊥ no fim);
-- * 'violatingRules' / 'finalViolatingRules' — quais regras estão em ⊥
--   num dado momento, para enriquecer o relatório de violação.
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

import           Monitor.Types          (Event, TimedEvent (..), Verdict (..))
import qualified Monitor.Automata.A1 as A1
import qualified Monitor.Automata.A3 as A3

-- | Estado do monitor composto.
data ComposedState = ComposedState
  { csM1 :: !A1.M1
  , csM3 :: !A3.M3
  } deriving (Eq, Show)

initial :: ComposedState
initial = ComposedState
  { csM1 = A1.initial
  , csM3 = A3.initial
  }

step :: ComposedState -> Event -> ComposedState
step s evt = s
  { csM1 = A1.step (csM1 s) evt
  , csM3 = A3.step (csM3 s) evt
  }

-- | Ínfimo dos vereditos de stream (Proposição 2).
verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s)
  , A3.verdict (csM3 s)
  ]

-- | Ínfimo dos vereditos finais — chamado uma única vez, ao consumir o
-- último 'TimedEvent' do traço.
finalVerdict :: ComposedState -> Verdict
finalVerdict s = minimum
  [ A1.finalVerdict (csM1 s)
  , A3.finalVerdict (csM3 s)
  ]

-- | Nomes dos componentes cujo 'verdict' está em ⊥.
violatingRules :: ComposedState -> [String]
violatingRules s =
  [ name
  | (v, name) <-
      [ (A1.verdict (csM1 s), "A1")
      , (A3.verdict (csM3 s), "A3")
      ]
  , v == Bot
  ]

-- | Análogo a 'violatingRules' mas avaliando 'finalVerdict' de cada
-- componente. Usado quando a violação só se manifesta no fim do traço
-- (M3 em estado @Awaiting@ após o último evento, por exemplo).
finalViolatingRules :: ComposedState -> [String]
finalViolatingRules s =
  [ name
  | (v, name) <-
      [ (A1.finalVerdict (csM1 s), "A1")
      , (A3.finalVerdict (csM3 s), "A3")
      ]
  , v == Bot
  ]

-- | Roda o monitor evento a evento.
--
-- Em caso de violação durante o stream, retorna a posição (1-indexada),
-- o evento ofensor e as regras violadas. Se a violação só surgir no
-- veredito final, devolve 'Nothing' como posição.
runMonitor :: [TimedEvent] -> (Verdict, Maybe (Int, Event), [String])
runMonitor = go 1 initial
  where
    go _ s [] =
      let fv = finalVerdict s
      in case fv of
        Bot -> (Bot, Nothing, finalViolatingRules s)
        v   -> (v, Nothing, [])
    go i s (te : tes) =
      let e  = teEvent te
          s' = step s e
      in if verdict s' == Bot && verdict s /= Bot
           then (Bot, Just (i, e), violatingRules s')
           else go (i + 1) s' tes
