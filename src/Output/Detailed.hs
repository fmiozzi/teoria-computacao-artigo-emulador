{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída detalhado ("emulador"), modo default.
--
-- Estrutura: cabeçalho, identificação do traço, parâmetros do monitor,
-- @M_dec@ declarado, processamento evento-a-evento sobre o fluxo
-- /enriquecido/ pelo mes-bridge, vereditos por propriedade (A1–A3, A5),
-- veredito composto (Proposição 2) e decisão do gate (§5.4, Algoritmo 1).
--
-- Campos que dependeriam de dados ausentes do cabeçalho são omitidos.
--
-- | Bloco arquitetural na figura de arquitetura do artigo: "ERP".
-- Referência: §5.4 (gate MES↔ERP); Figura 9 (fluxograma do gate).
module Output.Detailed
  ( renderDetailed
  ) where

import qualified Data.Map.Strict        as Map
import qualified Data.Text              as T
import qualified Monitor.Automata.A1    as A1
import qualified Monitor.Automata.A2    as A2
import qualified Monitor.Automata.A3    as A3
import           Monitor.Composed       (ComposedState (..), finalVerdict, summary)
import           Monitor.Gate           ( GateResult (..)
                                        , Step (..)
                                        )
import           Monitor.Header         (TraceHeader (..))
import           Monitor.Multiset       (Multiset)
import           Monitor.Types          ( Config (..)
                                        , Diag
                                        , MesStatus (..)
                                        , Verdict (..)
                                        , showDiag
                                        , showEvent
                                        , showStatus
                                        , showVerdict
                                        , statusEscala
                                        )

version :: String
version = "0.8.0"

sep, halfSep :: String
sep     = replicate 67 '='
halfSep = replicate 67 '-'

renderDetailed
  :: FilePath
  -> Maybe TraceHeader
  -> Config
  -> GateResult
  -> String
renderDetailed filepath mHdr cfg res =
  unlines $ concat
    [ headerLines
    , identification filepath mHdr
    , parameters cfg
    , declaredLines mHdr
    , [""]
    , [halfSep, "Processamento evento-a-evento (fluxo enriquecido pelo mes-bridge):", ""]
    , map renderStep steps
    , [""]
    , finalSection steps
    , [""]
    , [halfSep, "Vereditos por propriedade:", ""]
    , perPropertyVerdicts (lastState steps)
    , [""]
    , ["VEREDITO COMPOSTO (Proposição 2: ínfimo de M₁⊗M₂⊗M₃): " ++ showVerdict v]
    , [""]
    , [halfSep, "Decisão do gate (§5.4, Algoritmo 1):", ""]
    , gateDecision res
    , [""]
    , [ sep
      , "Resultado: " ++ decisionWord status ++ "  (veredito composto " ++ showVerdict v ++ ")"
      , "Status do apontamento: " ++ showStatus status
      , "Código de saída: " ++ show (exitCodeOf status)
      , sep
      ]
    ]
  where
    steps  = grSteps res
    v      = grVerdict res
    status = grStatus res

headerLines :: [String]
headerLines =
  [ sep
  , "EMULADOR LTL/TLTL — Monitor de Apontamento de Produção"
  , "Versão " ++ version ++ " — monitor composto M₁⊗M₂⊗M₃ (A1–A3) + filtro A5"
  , "Referência: Miozzi (2026), Tabela 2 (A1–A3 e A5); gate §5.4 (Algoritmo 1)"
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
  , "Parâmetros do monitor (cenário-âncora, §4):"
  , "  T_cls    = " ++ show (cfgTcls cfg)    ++ " ms   (A2: orçamento de classificação)"
  , "  T_dec    = " ++ show (cfgTdec cfg)    ++ " ms   (A3: horizonte de decisão; T_dec = T_cls + ε)"
  , "  δ_mb     = " ++ show (cfgDeltaMb cfg) ++ " ms    (mes-bridge: latência de comparação; δ_mb ≤ T_dec − T_cls)"
  , "  τ        = " ++ show (cfgTau cfg)     ++ "        (A5: limiar de confiança)"
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
    ++ obsTail (stepState st)
  where
    obsTail s =
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
  [ "  A1 (safety: rem_i → ab_i)                  : " ++ verdictSymFinal (A1.finalVerdict (csM1 s))
  , "  A2 (liveness temp.: cls^≥τ em T_cls)       : " ++ verdictSymFinal (A2.finalVerdict (csM2 s))
  , "  A3 (liveness temp.: match∨div em T_dec)    : " ++ verdictSymFinal (A3.finalVerdict (csM3 s))
  , "  A5 (filtro confiança ≥ τ)                  : ⊤  (filtro estrutural a montante)"
  , "  Veredito final composto                    : " ++ verdictSymFinal (finalVerdict s)
  ]

-- | Renderiza a decisão do gate (Algoritmo 1) a partir do 'GateResult':
-- um dos quatro status terminais, com diagnóstico de causa-raiz e área de
-- escalação.
gateDecision :: GateResult -> [String]
gateDecision res = case grStatus res of
  LiberadoIntegracao ->
    [ "  Decisão  : LIBERAR integração MES → ERP"
    , "  Status   : " ++ showStatus LiberadoIntegracao
    , "  Motivo   : pronunciamento match_i dentro de T_dec; A1–A3 satisfeitas"
    ]
  PendenteVerificacao ->
    [ "  Decisão  : PENDENTE — apontamento sem decisão terminal no horizonte observado"
    , "  Status   : " ++ showStatus PendenteVerificacao
    ]
  status ->
    [ "  Decisão  : BLOQUEAR integração MES → ERP"
    , "  Status   : " ++ showStatus status
    , "  Causa    : " ++ maybe "(não diagnosticada)" showDiag (grDiag res)
    , "  Escala   : " ++ statusEscala status
    , "  Motivo   : " ++ diagSentence (grDiag res)
    ] ++ locationLine (grFirstViol res) (grDivAt res)

diagSentence :: Maybe Diag -> String
diagSentence Nothing  = "violação detectada (sem diagnóstico)"
diagSentence (Just d) = case showDiag d of
  "safety_A1"       -> "A1 violada — rem_i fora da janela de abastecimento (exceção estrutural)"
  "mismatch"        -> "M_obs ≠ M_dec — divergência de multiconjunto"
  "fora_ciclo"      -> "exceção estrutural do ciclo operacional"
  "timeout_cls"     -> "A2 violada — classificação válida ausente em T_cls"
  "leave_ab_silent" -> "A3 violada — mes-bridge sem pronunciamento em T_dec"
  other             -> other

locationLine :: Maybe Int -> Maybe Int -> [String]
locationLine (Just i) _        = ["  Local    : violação de stream no evento #" ++ show i]
locationLine Nothing (Just j)  = ["  Local    : div_i materializado no evento #" ++ show j ++ " (fluxo enriquecido)"]
locationLine Nothing Nothing   = ["  Local    : detectado ao fim do traço"]

-- ---------- Helpers de formatação ----------

decisionWord :: MesStatus -> String
decisionWord LiberadoIntegracao  = "LIBERAR"
decisionWord PendenteVerificacao = "PENDENTE"
decisionWord _                   = "BLOQUEAR"

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
    inner = intercalate ", " [T.unpack k ++ ":" ++ show val | (k, val) <- Map.toAscList m]

lastState :: [Step] -> Maybe ComposedState
lastState [] = Nothing
lastState xs = Just (stepState (last xs))

-- | Código de saída do processo, derivado do status do gate:
-- 0 = liberado; 2 = bloqueado (qualquer das três causas-raiz);
-- 3 = pendente (sem decisão terminal).
exitCodeOf :: MesStatus -> Int
exitCodeOf LiberadoIntegracao  = 0
exitCodeOf PendenteVerificacao = 3
exitCodeOf _                   = 2

intercalate :: String -> [String] -> String
intercalate _   []      = ""
intercalate _   [x]     = x
intercalate sep' (x:xs) = x ++ sep' ++ intercalate sep' xs
