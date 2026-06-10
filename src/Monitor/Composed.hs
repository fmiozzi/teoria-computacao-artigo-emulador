{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos de monitoramento — o monitor
-- composto M = M_1 ⊗ M_2 ⊗ M_3 ⊗ M_4 do artigo (v2).
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤. Como ⊥ é absorvente em cada componente, basta o autômato
-- individual mais pessimista para determinar o veredito composto.
--
-- /Eventos derivados/: o sumidouro de M_2 (timeout_cls_i) e o de M_3
-- (leave_ab_silent_i) são disjuntos de @div_i@ (cf. definição de div_i no
-- artigo). Quando M_2 ou M_3 viola por expiração de relógio, esta
-- composição promove um @div_i@ sintético no mesmo instante, armando M_4
-- (escalação ao PCP).
--
-- As propriedades A6/A7/A8 são extensões de trabalho futuro (artigo §6) e
-- /não/ fazem parte do monitor composto da v2 — vivem em
-- "Monitor.Automata.A6"/"A7"/"A8" isoladas.
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
import qualified Monitor.Automata.A4   as A4
import           Monitor.Classification (isValidCls)
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
  , csM3  = A3.initial cfg
  , csM4  = A4.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }

step :: ComposedState -> TimedEvent -> ComposedState
step s te =
  let evt  = teEvent te
      now  = teTime te
      -- M_obs acumula apenas classificações confiáveis (filtro A5).
      obs' = case evt of
        ClsPI sku _
          | isValidCls (csTau s) evt -> MS.addCls sku (csObs s)
          | otherwise                -> csObs s
        _ -> csObs s
      m1' = A1.step (csM1 s) evt
      m2' = A2.step (csM2 s) te
      m3' = A3.step (csM3 s) te
      -- div_i sintético: timeout de M_2 (timeout_cls_i) ou de M_3
      -- (leave_ab_silent_i) arma M_4 no mesmo instante.
      a2JustViolated = A2.verdict m2' == Bot && A2.verdict (csM2 s) /= Bot
      a3JustViolated = A3.verdict m3' == Bot && A3.verdict (csM3 s) /= Bot
      m4Base = A4.step (csM4 s) te
      m4' | a2JustViolated || a3JustViolated = A4.step m4Base (TimedEvent now DivI)
          | otherwise                        = m4Base
  in s
    { csM1  = m1'
    , csM2  = m2'
    , csM3  = m3'
    , csM4  = m4'
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

summary :: ComposedState -> String
summary s = unwords
  [ "M1:" ++ A1.summary (csM1 s)
  , "M2:" ++ A2.summary (csM2 s)
  , "M3:" ++ A3.summary (csM3 s)
  , "M4:" ++ A4.summary (csM4 s)
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
