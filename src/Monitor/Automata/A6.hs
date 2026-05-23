{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M6 — propriedade A6 (extensão TLTL) do artigo:
--
-- @
--   A6 : G F_{[0, T_h]} heartbeat_i
-- @
--
-- "O agente publica um heartbeat ao menos a cada T_h ms."
--
-- /Semântica operacional adotada/: A6 fica /desarmada/ até o primeiro
-- 'Heartbeat' do traço. Antes disso, o veredito é ⊤ vacuosamente —
-- traços que nunca incluem heartbeats (caso dos exemplos 01–05, do
-- smoke e de boa parte dos cenários do artigo) não são afetados.
-- Quando o primeiro heartbeat chega, o monitor "arma" e a partir daí
-- exige cadência ≤ T_h ms entre heartbeats consecutivos.
--
-- A interpretação literal "G F[…] heartbeat em qualquer traço" seria
-- estrita demais para o emulador, que deve tolerar cenários históricos
-- sem heartbeat e ao mesmo tempo capturar agentes "mortos" quando o
-- traço se propõe a ser monitorado por A6.
module Monitor.Automata.A6
  ( M6State (..)
  , M6
  , initial
  , step
  , verdict
  , finalVerdict
  , summary
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M6State
  = M6Unarmed         -- ^ nenhum heartbeat ainda — A6 vacuosa
  | M6Armed !Int      -- ^ timestamp do último heartbeat
  | M6Violated
  deriving (Eq, Show)

data M6 = M6
  { m6State :: !M6State
  , m6Th    :: !Int
  } deriving (Eq, Show)

initial :: Config -> M6
initial cfg = M6
  { m6State = M6Unarmed
  , m6Th    = cfgTh cfg
  }

step :: M6 -> TimedEvent -> M6
step m (TimedEvent now evt) = case m6State m of
  M6Violated -> m
  M6Unarmed -> case evt of
    Heartbeat -> m { m6State = M6Armed now }
    _         -> m
  M6Armed lastHb
    | now - lastHb > m6Th m -> m { m6State = M6Violated }
    | otherwise -> case evt of
        Heartbeat -> m { m6State = M6Armed now }
        _         -> m

verdict :: M6 -> Verdict
verdict m = case m6State m of
  M6Violated -> Bot
  _          -> Top

-- | 'finalVerdict' = 'verdict' (safety simples na fronteira do stream).
finalVerdict :: M6 -> Verdict
finalVerdict = verdict

summary :: M6 -> String
summary m = case m6State m of
  M6Unarmed   -> "unarmed"
  M6Armed n   -> "armed(hb=" ++ show n ++ ")"
  M6Violated  -> "viol"
