{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M8 — propriedade A8 (extensão TLTL) do artigo:
--
-- @
--   A8 : G(ab_i → F_{[0, T_ab_max]} leave_ab_i)
-- @
--
-- "A janela de abastecimento deve fechar em até T_ab_max ms."
--
-- Estrutura idêntica a A2/A4 — só muda o par de eventos (ab/leave) e
-- o parâmetro (T_ab_max em vez de T_cls/T_pcp).
module Monitor.Automata.A8
  ( M8State (..)
  , M8
  , initial
  , step
  , verdict
  , finalVerdict
  , summary
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M8State
  = M8Idle
  | M8Pending !Int   -- ^ timestamp (ms) do ab_i pendente
  | M8Violated
  deriving (Eq, Show)

data M8 = M8
  { m8State   :: !M8State
  , m8TabMax  :: !Int
  } deriving (Eq, Show)

initial :: Config -> M8
initial cfg = M8
  { m8State  = M8Idle
  , m8TabMax = cfgTabMax cfg
  }

step :: M8 -> TimedEvent -> M8
step m (TimedEvent now evt) = case m8State m of
  M8Violated -> m
  M8Idle -> case evt of
    AbI -> m { m8State = M8Pending now }
    _   -> m
  M8Pending clock
    | now - clock > m8TabMax m -> m { m8State = M8Violated }
    | otherwise -> case evt of
        LeaveAbI -> m { m8State = M8Idle }
        _        -> m

verdict :: M8 -> Verdict
verdict m = case m8State m of
  M8Violated -> Bot
  _          -> Top

finalVerdict :: M8 -> Verdict
finalVerdict m = case m8State m of
  M8Violated  -> Bot
  M8Pending _ -> Bot
  M8Idle      -> Top

summary :: M8 -> String
summary m = case m8State m of
  M8Idle           -> "idle"
  M8Pending clock  -> "pending(x=" ++ show clock ++ ")"
  M8Violated       -> "viol"
