{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída JSON estruturado (@--json@) — log auditável.
--
-- Implementação ad-hoc — sem 'aeson' — porque o esquema é fixo e pequeno.
--
-- Esquema (top-level):
--
-- @
-- {
--   "file": "Files/Traces/trace_08_...",
--   "header": { ... | null },
--   "config": { "t_cls": 1500, "t_dec": 1700, "delta_mb": 100, "tau": 0.85 },
--   "steps":  [ { "i": 1, "t_ms": 0, "event": "ab_i", "verdict": "INCONCLUSIVE", ... }, ... ],
--   "verdict": "TOP",                      // veredito composto (Proposição 2)
--   "gate": {
--     "decision": "BLOQUEAR",
--     "status":   "divergencia_pcp",       // §5.4, Tabela 4
--     "diag":     "mismatch" | null,
--     "escala":   "PCP (Planejamento e Controle da Produção)"
--   },
--   "first_violation_idx": 4 | null,
--   "div_materialized_idx": 9 | null,
--   "violating_rules": ["A1", "A3"]
-- }
-- @
--
-- | Bloco arquitetural na figura de arquitetura do artigo: "ERP".
-- Referência: §5.4 (log auditável do gate).
module Output.Json
  ( renderJson
  ) where

import qualified Data.Map.Strict      as Map
import qualified Data.Text            as T
import           Monitor.Composed     (ComposedState (..), summary)
import           Monitor.Gate         (GateResult (..), Step (..))
import           Monitor.Header       (TraceHeader (..))
import           Monitor.Multiset     (Multiset)
import           Monitor.Types        ( Config (..)
                                      , Event (..)
                                      , MesStatus (..)
                                      , Verdict (..)
                                      , showDiag
                                      , showStatus
                                      , statusEscala
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
  -> GateResult
  -> String
renderJson fp mHdr cfg res =
  renderJValue 0 $ JObj
    [ ("file"               , JStr fp)
    , ("header"             , maybe JNull headerToJValue mHdr)
    , ("config"             , configToJValue cfg)
    , ("steps"              , JArr (map stepToJValue (grSteps res)))
    , ("verdict"            , JStr (verdictTag (grVerdict res)))
    , ("gate"               , gateToJValue res)
    , ("first_violation_idx", maybe JNull JInt (grFirstViol res))
    , ("div_materialized_idx", maybe JNull JInt (grDivAt res))
    , ("violating_rules"    , JArr (map JStr (grRules res)))
    ]

gateToJValue :: GateResult -> JValue
gateToJValue res = JObj
  [ ("decision", JStr (decisionWord (grStatus res)))
  , ("status"  , JStr (showStatus (grStatus res)))
  , ("diag"    , maybe JNull (JStr . showDiag) (grDiag res))
  , ("escala"  , JStr (statusEscala (grStatus res)))
  ]

decisionWord :: MesStatus -> String
decisionWord LiberadoIntegracao  = "LIBERAR"
decisionWord PendenteVerificacao = "PENDENTE"
decisionWord _                   = "BLOQUEAR"

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
  [ ("t_cls"   , JInt (cfgTcls cfg))
  , ("t_dec"   , JInt (cfgTdec cfg))
  , ("delta_mb", JInt (cfgDeltaMb cfg))
  , ("tau"     , JDbl (cfgTau cfg))
  ]

stepToJValue :: Step -> JValue
stepToJValue st = JObj
  [ ("i"            , JInt (stepIdx st))
  , ("t_ms"         , JInt (stepTime st))
  , ("event"        , JStr (eventTag (stepEvent st)))
  , ("event_repr"   , JStr (eventRepr (stepEvent st)))
  , ("verdict"      , JStr (verdictTag (stepVerdict st)))
  , ("state_summary", JStr (summary (stepState st)))
  , ("m_obs"        , multisetToJValue (csObs (stepState st)))
  , ("violating_rules", JArr (map JStr (stepRules st)))
  ]

multisetToJValue :: Multiset -> JValue
multisetToJValue m = JObj
  [ (T.unpack k, JInt v) | (k, v) <- Map.toAscList m ]

verdictTag :: Verdict -> String
verdictTag Top          = "TOP"
verdictTag Bot          = "BOT"
verdictTag Inconclusive = "INCONCLUSIVE"

eventTag :: Event -> String
eventTag AbI         = "ab_i"
eventTag RemI        = "rem_i"
eventTag LeaveAbI    = "leave_ab_i"
eventTag MatchI      = "match_i"
eventTag DivI        = "div_i"
eventTag EscPcpI     = "esc_pcp_i"
eventTag Heartbeat   = "heartbeat"
eventTag RejI        = "rej_i"
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
