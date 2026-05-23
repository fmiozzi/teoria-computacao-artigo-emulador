{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída JSON estruturado (@--json@).
--
-- Implementação ad-hoc — sem 'aeson' — porque o esquema é fixo e
-- pequeno. Se a Fase 11/Fase 12 precisar de schema validation ou
-- streaming, trocar por 'aeson' afeta só este módulo.
--
-- Esquema (top-level):
--
-- @
-- {
--   "file": "Files/Traces/trace_08_...",
--   "header": { ... | null },
--   "config": { "t_cls": 30000, "t_pcp": 300000, "tau": 0.85 },
--   "steps":  [ { "i": 1, "t": 0, "event": "ab_i", "verdict": "T", ... }, ... ],
--   "verdict": "F",
--   "first_violation_idx": 4 | null,
--   "violating_rules": ["A1", "A3"]
-- }
-- @
module Output.Json
  ( renderJson
  ) where

import qualified Data.Map.Strict      as Map
import qualified Data.Text            as T
import           Monitor.Composed     (ComposedState (..), Step (..), summary)
import           Monitor.Header       (TraceHeader (..))
import           Monitor.Multiset     (Multiset)
import           Monitor.Types        ( Config (..)
                                      , Event (..)
                                      , Verdict (..)
                                      )

data JValue
  = JStr  String
  | JInt  Int
  | JDbl  Double
  | JNull
  | JArr  [JValue]
  | JObj  [(String, JValue)]

renderJson
  :: FilePath
  -> Maybe TraceHeader
  -> Config
  -> [Step]
  -> Verdict
  -> Maybe Int
  -> [String]
  -> String
renderJson fp mHdr cfg steps v mFirst rules =
  renderJValue 0 $ JObj
    [ ("file"               , JStr fp)
    , ("header"             , maybe JNull headerToJValue mHdr)
    , ("config"             , configToJValue cfg)
    , ("steps"              , JArr (map stepToJValue steps))
    , ("verdict"            , JStr (verdictTag v))
    , ("first_violation_idx", maybe JNull JInt mFirst)
    , ("violating_rules"    , JArr (map JStr rules))
    ]

headerToJValue :: TraceHeader -> JValue
headerToJValue h = JObj
  [ ("cenario"          , maybe JNull (JStr . T.unpack) (thCenario h))
  , ("maquina"          , maybe JNull (JStr . T.unpack) (thMaquina h))
  , ("braco"            , maybe JNull JInt              (thBraco h))
  , ("m_dec"            , maybe JNull multisetToJValue  (thMdec h))
  , ("veredito_esperado", maybe JNull (JStr . verdictTag) (thExpected h))
  ]

configToJValue :: Config -> JValue
configToJValue cfg = JObj
  [ ("t_cls", JInt (cfgTcls cfg))
  , ("t_pcp", JInt (cfgTpcp cfg))
  , ("t_h"  , JInt (cfgTh cfg))
  , ("t_ab_max", JInt (cfgTabMax cfg))
  , ("tau"  , JDbl (cfgTau cfg))
  ]

stepToJValue :: Step -> JValue
stepToJValue st = JObj
  [ ("i"           , JInt (stepIdx st))
  , ("t_ms"        , JInt (stepTime st))
  , ("event"       , JStr (eventTag (stepEvent st)))
  , ("event_repr"  , JStr (eventRepr (stepEvent st)))
  , ("verdict"     , JStr (verdictTag (stepVerdict st)))
  , ("state_summary", JStr (summary (stepState st)))
  , ("m_obs"       , multisetToJValue (csObs (stepState st)))
  , ("violating_rules", JArr (map JStr (stepRules st)))
  ]

multisetToJValue :: Multiset -> JValue
multisetToJValue m = JObj
  [ (T.unpack k, JInt v) | (k, v) <- Map.toAscList m ]

verdictTag :: Verdict -> String
verdictTag Top          = "T"
verdictTag Bot          = "F"
verdictTag Inconclusive = "?"

eventTag :: Event -> String
eventTag AbI         = "ab_i"
eventTag RemI        = "rem_i"
eventTag LeaveAbI    = "leave_ab_i"
eventTag MatchI      = "match_i"
eventTag DivI        = "div_i"
eventTag EscPcpI     = "esc_pcp_i"
eventTag Heartbeat   = "heartbeat"
eventTag (ClsPI _ _) = "cls_p_i"

eventRepr :: Event -> String
eventRepr (ClsPI s c) = "cls_p_i " ++ T.unpack s ++ " " ++ show c
eventRepr e           = eventTag e

-- ---------- JSON pretty printer ad-hoc ----------

renderJValue :: Int -> JValue -> String
renderJValue _ (JStr s)  = '"' : escape s ++ "\""
renderJValue _ (JInt n)  = show n
renderJValue _ (JDbl d)  = show d
renderJValue _ JNull     = "null"
renderJValue _ (JArr []) = "[]"
renderJValue d (JArr xs) =
  "[\n"
  ++ indent (d + 1)
  ++ intercalateStr (",\n" ++ indent (d + 1)) (map (renderJValue (d + 1)) xs)
  ++ "\n" ++ indent d ++ "]"
renderJValue _ (JObj []) = "{}"
renderJValue d (JObj fs) =
  "{\n"
  ++ indent (d + 1)
  ++ intercalateStr (",\n" ++ indent (d + 1))
       [ "\"" ++ k ++ "\": " ++ renderJValue (d + 1) v | (k, v) <- fs ]
  ++ "\n" ++ indent d ++ "}"

indent :: Int -> String
indent n = replicate (n * 2) ' '

escape :: String -> String
escape = concatMap esc
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc '\n' = "\\n"
    esc '\t' = "\\t"
    esc c    = [c]

intercalateStr :: String -> [String] -> String
intercalateStr _   []     = ""
intercalateStr _   [x]    = x
intercalateStr sep (x:xs) = x ++ sep ++ intercalateStr sep xs
