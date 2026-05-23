{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída detalhado ("emulador"), default a partir da
-- Fase 7. Inspirado no exemplo do prompt de tarefa: cabeçalho,
-- identificação do traço, parâmetros do monitor, M_dec do header,
-- processamento evento-a-evento, vereditos por propriedade, veredito
-- composto e decisão do gate.
--
-- Campos que dependeriam de dados ausentes do header (impacto contábil,
-- ações operacionais detalhadas) são omitidos — só renderizamos o que
-- temos.
module Output.Detailed
  ( renderDetailed
  ) where

import qualified Data.Map.Strict        as Map
import qualified Data.Text              as T
import qualified Monitor.Automata.A1    as A1
import qualified Monitor.Automata.A2    as A2
import qualified Monitor.Automata.A3    as A3
import qualified Monitor.Automata.A4    as A4
import qualified Monitor.Automata.A6    as A6
import qualified Monitor.Automata.A7    as A7
import qualified Monitor.Automata.A8    as A8
import           Monitor.Composed       ( ComposedState (..)
                                        , Step (..)
                                        , finalVerdict
                                        , summary
                                        )
import           Monitor.Header         (TraceHeader (..))
import qualified Monitor.Multiset       as MS
import           Monitor.Multiset       (Multiset)
import           Monitor.Types          ( Config (..)
                                        , Event
                                        , Verdict (..)
                                        , showEvent
                                        , showVerdict
                                        )

version :: String
version = "0.7.0"

sep, halfSep :: String
sep     = replicate 67 '='
halfSep = replicate 67 '-'

renderDetailed
  :: FilePath
  -> Maybe TraceHeader
  -> Config
  -> [Step]
  -> Verdict             -- ^ veredito final composto
  -> Maybe Int           -- ^ índice 1-based da primeira violação no stream
  -> [String]            -- ^ regras violadas
  -> String
renderDetailed filepath mHdr cfg steps v mFirst rules =
  unlines $ concat
    [ headerLines
    , identification filepath mHdr
    , parameters cfg
    , declaredLines mHdr
    , [""]
    , [halfSep, "Processamento evento-a-evento:", ""]
    , map renderStep steps
    , [""]
    , finalSection steps
    , [""]
    , [halfSep, "Vereditos por propriedade:", ""]
    , perPropertyVerdicts (lastState steps)
    , [""]
    , ["VEREDITO COMPOSTO (Proposição 2: ínfimo): " ++ showVerdict v]
    , [""]
    , [halfSep, "Decisão do gate (§5.4 do artigo):", ""]
    , gateDecision v mFirst rules
    , [""]
    , [sep, "Resultado: " ++ showVerdict v
      , "Código de saída: " ++ show (exitCodeOf v)
      , sep
      ]
    ]

headerLines :: [String]
headerLines =
  [ sep
  , "EMULADOR LTL/TLTL — Monitor de Apontamento de Produção"
  , "Versão " ++ version ++ " — A1, A2, A3, A4, A5 + extensões A6, A7, A8"
  , "Referência: Miozzi (2026), §4–6"
  , sep
  , ""
  ]

identification :: FilePath -> Maybe TraceHeader -> [String]
identification fp mHdr =
  [ "Arquivo : " ++ fp
  ] ++ headerField "Cenário" thCenario mHdr
    ++ headerField "Máquina" thMaquina mHdr
    ++ headerInt   "Braço"   thBraco   mHdr

headerField :: String -> (TraceHeader -> Maybe T.Text) -> Maybe TraceHeader -> [String]
headerField label _    Nothing    = ["" ++ label ++ " : (não informado)"]
headerField label getf (Just hdr) = case getf hdr of
  Nothing -> []
  Just t  -> [label ++ " : " ++ T.unpack t]

headerInt :: String -> (TraceHeader -> Maybe Int) -> Maybe TraceHeader -> [String]
headerInt _     _ Nothing = []
headerInt label getf (Just hdr) = case getf hdr of
  Nothing -> []
  Just n  -> [label ++ "   : " ++ show n]

parameters :: Config -> [String]
parameters cfg =
  [ ""
  , "Parâmetros do monitor:"
  , "  T_cls    = " ++ show (cfgTcls cfg)   ++ " ms   (A2)"
  , "  T_pcp    = " ++ show (cfgTpcp cfg)   ++ " ms   (A4)"
  , "  T_h      = " ++ show (cfgTh cfg)     ++ " ms   (A6)"
  , "  T_rej    = " ++ show (cfgTrej cfg)   ++ " ms   (A7)"
  , "  T_ab_max = " ++ show (cfgTabMax cfg) ++ " ms   (A8)"
  , "  τ        = " ++ show (cfgTau cfg)    ++ "        (A5)"
  ]

declaredLines :: Maybe TraceHeader -> [String]
declaredLines (Just hdr) | Just m <- thMdec hdr =
  [ ""
  , "M_dec declarado no MES: " ++ showMultiset m
  ]
declaredLines _ = []

renderStep :: Step -> String
renderStep st =
  formatTime (stepTime st) ++ "  "
    ++ pad 32 (showEvent (stepEvent st))
    ++ " | " ++ summary (stepState st)
    ++ "  V=" ++ verdictSym (stepVerdict st)
    ++ obsTail (stepEvent st) (stepState st)
  where
    obsTail (_) s =
      let obs = csObs s
      in if Map.null obs
           then ""
           else "  | M_obs=" ++ showMultiset obs

finalSection :: [Step] -> [String]
finalSection [] = []
finalSection steps =
  let s = stepState (last steps)
  in [ "M_obs final: " ++ showMultiset (csObs s) ]

perPropertyVerdicts :: Maybe ComposedState -> [String]
perPropertyVerdicts Nothing  = []
perPropertyVerdicts (Just s) =
  [ "  A1 (safety: rem → ab)              : " ++ verdictSymFinal (A1.finalVerdict (csM1 s))
  , "  A2 (TLTL: cls em T_cls)            : " ++ verdictSymFinal (A2.finalVerdict (csM2 s))
  , "  A3 (safety: leave → match ∨ div)   : " ++ verdictSymFinal (A3.finalVerdict (csM3 s))
  , "  A4 (TLTL: esc em T_pcp)            : " ++ verdictSymFinal (A4.finalVerdict (csM4 s))
  , "  A5 (filtro confiança ≥ τ)           : ⊤  (filtro estrutural — sempre OK)"
  , "  A6 (TLTL: heartbeat em T_h)        : " ++ verdictSymFinal (A6.finalVerdict (csM6 s))
  , "  A7 (safety: rej → cls recente)     : " ++ verdictSymFinal (A7.finalVerdict (csM7 s))
  , "  A8 (TLTL: janela ≤ T_ab_max)       : " ++ verdictSymFinal (A8.finalVerdict (csM8 s))
  , "  Veredito final composto            : " ++ verdictSymFinal (finalVerdict s)
  ]

gateDecision :: Verdict -> Maybe Int -> [String] -> [String]
gateDecision Top _ _ =
  [ "  Decisão  : LIBERAR integração MES → ERP"
  , "  Motivo   : todas as propriedades formais satisfeitas (match_i implícito ou explícito)"
  ]
gateDecision Bot mFirst rules =
  [ "  Decisão  : BLOQUEAR integração MES → ERP"
  , "  Motivo   : " ++ ruleSentence rules
  ] ++ locationLine mFirst
gateDecision Inconclusive _ _ =
  [ "  Decisão  : INCONCLUSIVO — aguardando mais eventos"
  ]

ruleSentence :: [String] -> String
ruleSentence []  = "violação detectada (sem detalhe disponível)"
ruleSentence [r] = "propriedade " ++ r ++ " violada"
ruleSentence rs  = "propriedades " ++ unwords rs ++ " violadas (composição)"

locationLine :: Maybe Int -> [String]
locationLine Nothing  = ["  Local    : detectado no fim do traço"]
locationLine (Just i) = ["  Local    : evento #" ++ show i]

-- ---------- Helpers de formatação ----------

formatTime :: Int -> String
formatTime ms = "[t=" ++ pad 8 (show ms) ++ " ms]"

pad :: Int -> String -> String
pad n s = s ++ replicate (n - length s) ' '

verdictSym :: Verdict -> String
verdictSym Top          = "⊤"
verdictSym Inconclusive = "?"
verdictSym Bot          = "⊥"

verdictSymFinal :: Verdict -> String
verdictSymFinal Top          = "⊤  ✓"
verdictSymFinal Inconclusive = "?"
verdictSymFinal Bot          = "⊥  ✗ ← violação"

showMultiset :: Multiset -> String
showMultiset m = "{" ++ inner ++ "}"
  where
    inner = intercalate ", " [T.unpack k ++ ":" ++ show v | (k, v) <- Map.toAscList m]

lastState :: [Step] -> Maybe ComposedState
lastState [] = Nothing
lastState xs = Just (stepState (last xs))

exitCodeOf :: Verdict -> Int
exitCodeOf Top          = 0
exitCodeOf Bot          = 2
exitCodeOf Inconclusive = 1

intercalate :: String -> [String] -> String
intercalate _   []     = ""
intercalate _   [x]    = x
intercalate sep' (x:xs) = x ++ sep' ++ intercalate sep' xs
