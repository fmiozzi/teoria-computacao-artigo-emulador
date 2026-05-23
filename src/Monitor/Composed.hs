{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos M_k (Proposição 2 do artigo) +
-- extensões A6/A7/A8 da Fase 10.
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente em cada componente, basta o autômato
-- individual mais pessimista para determinar o veredito composto.
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
import qualified Monitor.Automata.A6 as A6
import qualified Monitor.Automata.A7 as A7
import qualified Monitor.Automata.A8 as A8
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
  , csM6   :: !A6.M6
  , csM7   :: !A7.M7
  , csM8   :: !A8.M8
  , csObs  :: !Multiset
  , csTau  :: !Double
  } deriving (Eq, Show)

initial :: Config -> ComposedState
initial cfg = ComposedState
  { csM1  = A1.initial
  , csM2  = A2.initial cfg
  , csM3  = A3.initial
  , csM4  = A4.initial cfg
  , csM6  = A6.initial cfg
  , csM7  = A7.initial cfg
  , csM8  = A8.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }

step :: ComposedState -> TimedEvent -> ComposedState
step s te =
  let evt  = teEvent te
      now  = teTime te
      obs' = case evt of
        ClsPI sku conf
          | conf >= csTau s -> MS.addCls sku (csObs s)
          | otherwise       -> csObs s
        RejI -> case A7.lastClsValid (csM7 s) now of
          Just sku -> MS.removeCls sku (csObs s)
          Nothing  -> csObs s
        _ -> csObs s
  in s
    { csM1  = A1.step (csM1 s) evt
    , csM2  = A2.step (csM2 s) te
    , csM3  = A3.step (csM3 s) evt
    , csM4  = A4.step (csM4 s) te
    , csM6  = A6.step (csM6 s) te
    , csM7  = A7.step (csM7 s) te
    , csM8  = A8.step (csM8 s) te
    , csObs = obs'
    }

verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s), A2.verdict (csM2 s)
  , A3.verdict (csM3 s), A4.verdict (csM4 s)
  , A6.verdict (csM6 s), A7.verdict (csM7 s)
  , A8.verdict (csM8 s)
  ]

finalVerdict :: ComposedState -> Verdict
finalVerdict s = minimum
  [ A1.finalVerdict (csM1 s), A2.finalVerdict (csM2 s)
  , A3.finalVerdict (csM3 s), A4.finalVerdict (csM4 s)
  , A6.finalVerdict (csM6 s), A7.finalVerdict (csM7 s)
  , A8.finalVerdict (csM8 s)
  ]

violatingRules :: ComposedState -> [String]
violatingRules s =
  [ n | (v, n) <-
      [ (A1.verdict (csM1 s), "A1"), (A2.verdict (csM2 s), "A2")
      , (A3.verdict (csM3 s), "A3"), (A4.verdict (csM4 s), "A4")
      , (A6.verdict (csM6 s), "A6"), (A7.verdict (csM7 s), "A7")
      , (A8.verdict (csM8 s), "A8")
      ], v == Bot
  ]

finalViolatingRules :: ComposedState -> [String]
finalViolatingRules s =
  [ n | (v, n) <-
      [ (A1.finalVerdict (csM1 s), "A1"), (A2.finalVerdict (csM2 s), "A2")
      , (A3.finalVerdict (csM3 s), "A3"), (A4.finalVerdict (csM4 s), "A4")
      , (A6.finalVerdict (csM6 s), "A6"), (A7.finalVerdict (csM7 s), "A7")
      , (A8.finalVerdict (csM8 s), "A8")
      ], v == Bot
  ]

summary :: ComposedState -> String
summary s = unwords
  [ "M1:" ++ A1.summary (csM1 s)
  , "M2:" ++ A2.summary (csM2 s)
  , "M3:" ++ A3.summary (csM3 s)
  , "M4:" ++ A4.summary (csM4 s)
  , "M6:" ++ A6.summary (csM6 s)
  , "M7:" ++ A7.summary (csM7 s)
  , "M8:" ++ A8.summary (csM8 s)
  ]

data Step = Step
  { stepIdx     :: !Int
  , stepTime    :: !Int
  , stepEvent   :: !Event
  , stepState   :: !ComposedState
  , stepVerdict :: !Verdict
  , stepRules   :: ![String]
  } deriving (Eq, Show)

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

runMonitorTrace
  :: Config
  -> [TimedEvent]
  -> ([Step], Verdict, Maybe Int, [String])
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
