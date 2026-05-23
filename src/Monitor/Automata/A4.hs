{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M4 — propriedade A4 (TLTL) do artigo:
--
-- @
--   A4 : G(div_i → F_{[0, T_pcp]} esc_pcp_i)
-- @
--
-- "Toda divergência declarada deve ser escalada ao PCP em até T_pcp
-- unidades de tempo."
--
-- A construção é estruturalmente idêntica a 'Monitor.Automata.A2', mas
-- sem o filtro A5: @esc_pcp_i@ não carrega confiança da CNN — é um
-- ato administrativo do agente/integrador.
module Monitor.Automata.A4
  ( M4State (..)
  , M4
  , initial
  , step
  , verdict
  , finalVerdict
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M4State
  = M4Idle
  | M4Pending !Int   -- ^ timestamp (ms) do div_i pendente
  | M4Violated
  deriving (Eq, Show)

data M4 = M4
  { m4State :: !M4State
  , m4Tpcp  :: !Int     -- ^ T_pcp em ms
  } deriving (Eq, Show)

initial :: Config -> M4
initial cfg = M4
  { m4State = M4Idle
  , m4Tpcp  = cfgTpcp cfg
  }

step :: M4 -> TimedEvent -> M4
step m (TimedEvent now evt) = case m4State m of
  M4Violated -> m
  M4Idle -> case evt of
    DivI -> m { m4State = M4Pending now }
    _    -> m
  M4Pending clock
    | now - clock > m4Tpcp m -> m { m4State = M4Violated }
    | otherwise -> case evt of
        EscPcpI -> m { m4State = M4Idle }
        _       -> m

verdict :: M4 -> Verdict
verdict m = case m4State m of
  M4Violated -> Bot
  _          -> Top

-- | 'M4Pending' no fim do traço também viola — a obrigação F[…] não
-- foi cumprida dentro do horizonte observado.
finalVerdict :: M4 -> Verdict
finalVerdict m = case m4State m of
  M4Violated  -> Bot
  M4Pending _ -> Bot
  M4Idle      -> Top
