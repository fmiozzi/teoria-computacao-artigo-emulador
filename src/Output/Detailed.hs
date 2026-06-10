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
--
-- | Bloco arquitetural na figura de arquitetura (v2) do artigo: "ERP".
-- Referência: §5.2; fig-fluxograma-gate.
module Output.Detailed
  ( renderDetailed
  ) where

import qualified Data.Map.Strict        as Map
import qualified Data.Text              as T
import qualified Monitor.Automata.A1    as A1
import qualified Monitor.Automata.A2    as A2
import qualified Monitor.Automata.A3    as A3
import qualified Monitor.Automata.A4    as A4
import           Monitor.Composed       ( ComposedState (..)
                                        , Step (..)
                                        , finalVerdict
                                        , summary
                                        )
import qualified Monitor.Gate           as Gate
import           Monitor.Header         (TraceHeader (..))
import           Monitor.Multiset       (Multiset)
import           Monitor.Types          ( Config (..)
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
  , "Versão " ++ version ++ " — monitor composto M₁⊗M₂⊗M₃⊗M₄ (A1–A4) + filtro A5"
  , "Referência: Miozzi (2026), Tabela 2 (A1–A5)"
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
  , "  T_dec    = " ++ show (cfgTdec cfg)   ++ " ms   (A3)"
  , "  T_pcp    = " ++ show (cfgTpcp cfg)   ++ " ms   (A4)"
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
  [ "  A1 (safety: rem → ab)                  : " ++ verdictSymFinal (A1.finalVerdict (csM1 s))
  , "  A2 (liveness temp.: cls^≥τ em T_cls)   : " ++ verdictSymFinal (A2.finalVerdict (csM2 s))
  , "  A3 (liveness temp.: match∨div em T_dec): " ++ verdictSymFinal (A3.finalVerdict (csM3 s))
  , "  A4 (liveness temp.: esc em T_pcp)      : " ++ verdictSymFinal (A4.finalVerdict (csM4 s))
  , "  A5 (filtro confiança ≥ τ)              : ⊤  (filtro estrutural a montante)"
  , "  Veredito final composto                : " ++ verdictSymFinal (finalVerdict s)
  ]

-- | Renderiza a decisão do gate (Algoritmo 1) a partir de
-- 'Monitor.Gate.decide'.
gateDecision :: Verdict -> Maybe Int -> [String] -> [String]
gateDecision v mFirst rules = case Gate.decide v rules of
  Gate.Liberar ->
    [ "  Decisão  : LIBERAR integração MES → ERP"
    , "  Motivo   : todas as propriedades formais satisfeitas (match_i implícito ou explícito)"
    ]
  Gate.Bloquear _ | v == Inconclusive ->
    [ "  Decisão  : INCONCLUSIVO — aguardando mais eventos"
    ]
  Gate.Bloquear rs ->
    [ "  Decisão  : BLOQUEAR integração MES → ERP"
    , "  Motivo   : " ++ ruleSentence rs
    ] ++ locationLine mFirst

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
exitCodeOf Inconclusive = 3

intercalate :: String -> [String] -> String
intercalate _   []     = ""
intercalate _   [x]    = x
intercalate sep' (x:xs) = x ++ sep' ++ intercalate sep' xs
