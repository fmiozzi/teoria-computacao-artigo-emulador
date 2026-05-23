{-# LANGUAGE OverloadedStrings #-}

-- | Tipos centrais do monitor LTL/TLTL.
--
-- 'Event' corresponde ao conjunto AP do artigo (§3.2). 'Verdict' implementa
-- a semântica LTL_3 de Bauer, Leucker e Schallhart (2011): reticulado
-- ⊥ < ? < ⊤ que sustenta o ínfimo da Proposição 2 (composição).
--
-- 'Config' agrega os parâmetros temporais e o limiar de A5. Na Peça 1
-- (atual) só a estrutura existe; as próximas peças passam a consumi-la.
module Monitor.Types
  ( -- * Eventos
    Event (..)
  , showEvent
    -- * Veredito
  , Verdict (..)
  , showVerdict
    -- * Configuração
  , Config (..)
  , defaultConfig
  ) where

import qualified Data.Text as T

-- | Eventos atômicos emitidos pelo agente de visão.
--
-- 'AbI' e 'LeaveAbI' são os eventos de borda da janela de abastecimento;
-- a proposição @ab_i@ é verdadeira no intervalo entre os dois.
data Event
  = AbI                  -- ^ ab_i: braço entrou na janela de abastecimento
  | RemI                 -- ^ rem_i: peça retirada
  | LeaveAbI             -- ^ leave_ab_i: fim da janela
  | MatchI               -- ^ match_i: M_obs = M_dec
  | DivI                 -- ^ div_i: M_obs ≠ M_dec
  | EscPcpI              -- ^ esc_pcp_i: escalação ao PCP
  | ClsPI T.Text Double  -- ^ cls_{p,i}: classificação (SKU + confiança)
  | Heartbeat            -- ^ heartbeat: sinal de vida do agente (A6)
  deriving (Eq, Show)

-- | Veredito LTL_3 (Bauer, Leucker, Schallhart 2011).
-- Ordem do reticulado: 'Bot' < 'Inconclusive' < 'Top'.
data Verdict = Bot | Inconclusive | Top
  deriving (Eq, Ord, Show)

-- | Parâmetros do monitor (defaults definidos por 'defaultConfig').
data Config = Config
  { cfgTcls      :: Int       -- ^ T_cls (ms): latência máxima de classificação (A2)
  , cfgTpcp      :: Int       -- ^ T_pcp (ms): prazo de escalação ao PCP (A4)
  , cfgTh        :: Int       -- ^ T_h (ms): período máximo entre heartbeats (A6)
  , cfgTabMax    :: Int       -- ^ T_ab_max (ms): duração máxima da janela (A8)
  , cfgTau       :: Double    -- ^ τ: limiar de confiança da CNN (A5)
  , cfgValidSKUs :: [T.Text]  -- ^ SKUs aceitos pelo classificador
  } deriving (Eq, Show)

defaultConfig :: Config
defaultConfig = Config
  { cfgTcls      = 30000      -- 30 s
  , cfgTpcp      = 300000     -- 5 min
  , cfgTh        = 5000       -- 5 s
  , cfgTabMax    = 900000     -- 15 min
  , cfgTau       = 0.85
  , cfgValidSKUs =
      [ "caixa_500L", "caixa_1000L", "caixa_2000L"
      , "caixa_3000L", "caixa_5000L", "molde_vazio"
      ]
  }

showVerdict :: Verdict -> String
showVerdict Top          = "ACEITA (T)"
showVerdict Bot          = "VIOLA  (F)"
showVerdict Inconclusive = "INCONCLUSIVO (?)"

showEvent :: Event -> String
showEvent AbI         = "ab_i"
showEvent RemI        = "rem_i"
showEvent LeaveAbI    = "leave_ab_i"
showEvent MatchI      = "match_i"
showEvent DivI        = "div_i"
showEvent EscPcpI     = "esc_pcp_i"
showEvent Heartbeat   = "heartbeat"
showEvent (ClsPI s c) = "cls_p_i " ++ T.unpack s ++ " " ++ show c
