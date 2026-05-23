{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos M_k (Proposição 2 do artigo).
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente, basta o autômato individual mais
-- pessimista para deteminar o veredito composto.
--
-- Na Peça 1 só M1 está implementado, mas a estrutura já é polimórfica
-- na lista de componentes para receber M2..M8 nas próximas fases.
module Monitor.Composed
  ( ComposedState (..)
  , initial
  , step
  , verdict
  , runMonitor
  ) where

import           Monitor.Types          (Event, Verdict (..))
import qualified Monitor.Automata.A1 as A1

-- | Estado do monitor composto.
--
-- Cada componente é mantido em paralelo. Adicionar M2..M8 = adicionar
-- um campo aqui, atualizar 'step' e 'verdict' — a Proposição 2 garante
-- corretude composicional.
newtype ComposedState = ComposedState
  { csM1 :: A1.M1
  } deriving (Eq, Show)

initial :: ComposedState
initial = ComposedState
  { csM1 = A1.initial
  }

step :: ComposedState -> Event -> ComposedState
step s evt = s
  { csM1 = A1.step (csM1 s) evt
  }

-- | Ínfimo dos vereditos individuais (Proposição 2).
verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s)
  ]

-- | Roda o monitor evento a evento. Em caso de violação, retorna a
-- posição (1-indexada) e o evento ofensor — útil para o output detalhado.
runMonitor :: [Event] -> (Verdict, Maybe (Int, Event))
runMonitor = go 1 initial
  where
    go _ s [] = (verdict s, Nothing)
    go i s (e : es) =
      let s' = step s e
      in if verdict s' == Bot && verdict s /= Bot
           then (Bot, Just (i, e))
           else go (i + 1) s' es
