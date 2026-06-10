{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída curto (@--quiet@), 1 bloco por traço — uso em batch.
--
-- Reporta o veredito composto (Proposição 2) e a decisão do gate (§5.4):
-- status terminal do apontamento, diagnóstico de causa-raiz e área de
-- escalação.
--
-- | Bloco arquitetural na figura de arquitetura do artigo: "ERP".
-- Referência: §5.4 (renderização da decisão do gate).
module Output.Plain
  ( renderReport
  ) where

import Monitor.Gate   (GateResult (..), Step (..))
import Monitor.Types  ( MesStatus (..)
                      , showDiag
                      , showEvent
                      , showStatus
                      , showVerdict
                      , statusEscala
                      )

-- | Renderiza o relatório curto de uma execução.
renderReport :: FilePath -> GateResult -> String
renderReport filepath res = unlines $
  [ ""
  , "Arquivo  : " ++ filepath
  , "Eventos  : " ++ show (length (grSteps res))
  , "Veredito : " ++ showVerdict (grVerdict res) ++ "   (composto, Proposição 2)"
  , "Decisão  : " ++ decisionWord (grStatus res) ++ " — " ++ showStatus (grStatus res)
  ] ++ gateLines res

gateLines :: GateResult -> [String]
gateLines res = case grStatus res of
  LiberadoIntegracao  -> ["Escala   : " ++ statusEscala LiberadoIntegracao]
  PendenteVerificacao -> []
  status ->
    [ "Causa    : " ++ maybe "(não diagnosticada)" showDiag (grDiag res)
    , "Escala   : " ++ statusEscala status
    , locationLine (grSteps res) (grFirstViol res) (grDivAt res)
    ] ++ map describeRule (grRules res)

decisionWord :: MesStatus -> String
decisionWord LiberadoIntegracao  = "LIBERAR"
decisionWord PendenteVerificacao = "PENDENTE"
decisionWord _                   = "BLOQUEAR"

locationLine :: [Step] -> Maybe Int -> Maybe Int -> String
locationLine steps (Just i) _ =
  "Local    : violação de stream no evento #" ++ show i ++ atEvent steps i
locationLine _ Nothing (Just j) =
  "Local    : div_i materializado no evento #" ++ show j
locationLine _ Nothing Nothing =
  "Local    : detectado ao fim do traço"

atEvent :: [Step] -> Int -> String
atEvent steps i = case [ st | st <- steps, stepIdx st == i ] of
  (st : _) -> ": " ++ showEvent (stepEvent st)
  []       -> ""

describeRule :: String -> String
describeRule "A1" = "  A1: G(rem_i → ab_i)                          (rem_i fora da janela)"
describeRule "A2" = "  A2: G((leave_ab_i ∧ houve_rem_i) → F[0,T_cls] cls^≥τ)  (classificação ausente/tardia)"
describeRule "A3" = "  A3: G(leave_ab_i → F[0,T_dec] (match∨div))   (decisão do mes-bridge ausente/tardia)"
describeRule r    = "  " ++ r
