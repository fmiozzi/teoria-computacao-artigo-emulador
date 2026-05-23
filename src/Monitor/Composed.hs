{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos M_k (Proposição 2 do artigo).
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente, basta o autômato individual mais
-- pessimista para determinar o veredito composto.
--
-- A Fase 7 acrescenta:
--
-- * @csObs@/@csTau@ — acumula 'Multiset' de classificações confiáveis
--   (A5) para o output detalhado;
-- * 'Step' e 'runMonitorTrace' — captura o estado pós-step de cada
--   evento, permitindo renderizar o trace evento-a-evento.
module Monitor.Composed
  ( -- * Estado
    ComposedState (..)
  , initial
  , step
    -- * Vereditos
  , verdict
  , finalVerdict
  , violatingRules
  , finalViolatingRules
  , summary
    -- * Execução
  , Step (..)
  , runMonitor
  , runMonitorTrace
  ) where

import qualified Monitor.Automata.A1 as A1
import qualified Monitor.Automata.A2 as A2
import qualified Monitor.Automata.A3 as A3
import qualified Monitor.Automata.A4 as A4
import qualified Monitor.Multiset    as MS
import           Monitor.Multiset    (Multiset)
import           Monitor.Types       ( Config (..)
                                     , Event (..)
                                     , TimedEvent (..)
                                     , Verdict (..)
                                     )

data ComposedState = ComposedState
  { csM1   :: !A1.M1
  , csM2   :: !A2.M2
  , csM3   :: !A3.M3
  , csM4   :: !A4.M4
  , csObs  :: !Multiset
  , csTau  :: !Double
  } deriving (Eq, Show)

initial :: Config -> ComposedState
initial cfg = ComposedState
  { csM1  = A1.initial
  , csM2  = A2.initial cfg
  , csM3  = A3.initial
  , csM4  = A4.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }

step :: ComposedState -> TimedEvent -> ComposedState
step s te =
  let evt  = teEvent te
      obs' = case evt of
        ClsPI sku conf | conf >= csTau s -> MS.addCls sku (csObs s)
        _                                -> csObs s
  in s
    { csM1  = A1.step (csM1 s) evt
    , csM2  = A2.step (csM2 s) te
    , csM3  = A3.step (csM3 s) evt
    , csM4  = A4.step (csM4 s) te
    , csObs = obs'
    }

verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s), A2.verdict (csM2 s)
  , A3.verdict (csM3 s), A4.verdict (csM4 s)
  ]

finalVerdict :: ComposedState -> Verdict
finalVerdict s = minimum
  [ A1.finalVerdict (csM1 s), A2.finalVerdict (csM2 s)
  , A3.finalVerdict (csM3 s), A4.finalVerdict (csM4 s)
  ]

violatingRules :: ComposedState -> [String]
violatingRules s =
  [ n | (v, n) <-
      [ (A1.verdict (csM1 s), "A1"), (A2.verdict (csM2 s), "A2")
      , (A3.verdict (csM3 s), "A3"), (A4.verdict (csM4 s), "A4")
      ], v == Bot
  ]

finalViolatingRules :: ComposedState -> [String]
finalViolatingRules s =
  [ n | (v, n) <-
      [ (A1.finalVerdict (csM1 s), "A1"), (A2.finalVerdict (csM2 s), "A2")
      , (A3.finalVerdict (csM3 s), "A3"), (A4.finalVerdict (csM4 s), "A4")
      ], v == Bot
  ]

-- | Sumário inline dos 4 autômatos (usado pelo output detalhado).
summary :: ComposedState -> String
summary s =
  "M1:" ++ A1.summary (csM1 s) ++
  " M2:" ++ A2.summary (csM2 s) ++
  " M3:" ++ A3.summary (csM3 s) ++
  " M4:" ++ A4.summary (csM4 s)

-- | Captura, por evento processado, o estado pós-step + vereditos.
-- Usado pelo output detalhado e pelo JSON.
data Step = Step
  { stepIdx     :: !Int
  , stepTime    :: !Int
  , stepEvent   :: !Event
  , stepState   :: !ComposedState
  , stepVerdict :: !Verdict
  , stepRules   :: ![String]
  } deriving (Eq, Show)

-- | Versão "leve" usada pelo modo @--quiet@: só veredito final, ofensor
-- e regras. Compatível com a API da Peça 1.
runMonitor :: Config -> [TimedEvent] -> (Verdict, Maybe (Int, Event), [String])
runMonitor cfg = go 1 (initial cfg)
  where
    go _ s [] = case finalVerdict s of
      Bot -> (Bot, Nothing, finalViolatingRules s)
      v   -> (v, Nothing, [])
    go i s (te : tes) =
      let e  = teEvent te
          s' = step s te
      in if verdict s' == Bot && verdict s /= Bot
           then (Bot, Just (i, e), violatingRules s')
           else go (i + 1) s' tes

-- | Versão "rica": além do veredito final, devolve a sequência de
-- 'Step's para inspeção. A execução não pára na primeira violação —
-- o trace completo é entregue, com o veredito agregado refletindo o
-- estado final (incluindo 'finalVerdict').
runMonitorTrace
  :: Config
  -> [TimedEvent]
  -> ([Step], Verdict, Maybe Int, [String])
  -- ^ (trace, veredito final, índice 1-based da primeira violação se
  -- detectada no stream, regras violadas no estado final)
runMonitorTrace cfg tes =
  let (steps, sFinal) = scanTrace cfg tes
      mFirst = firstViolationIdx steps
      fv     = finalVerdict sFinal
      rules  = if fv == Bot then finalViolatingRules sFinal else []
  in (steps, fv, mFirst, rules)

scanTrace :: Config -> [TimedEvent] -> ([Step], ComposedState)
scanTrace cfg = go 1 (initial cfg)
  where
    go _ s [] = ([], s)
    go i s (te : tes) =
      let s'   = step s te
          stp  = Step i (teTime te) (teEvent te) s' (verdict s') (violatingRules s')
          (rest, sFinal) = go (i + 1) s' tes
      in (stp : rest, sFinal)

firstViolationIdx :: [Step] -> Maybe Int
firstViolationIdx = go Top
  where
    go _ [] = Nothing
    go prev (st : rest)
      | stepVerdict st == Bot && prev /= Bot = Just (stepIdx st)
      | otherwise = go (stepVerdict st) rest
