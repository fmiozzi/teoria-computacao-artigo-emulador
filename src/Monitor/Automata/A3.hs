{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M3 — propriedade A3 (safety) do artigo:
--
-- @
--   A3 : G(leave_ab_i → match_i ∨ div_i)
-- @
--
-- "Toda saída da janela de abastecimento deve ser seguida de
-- pronunciamento (match ou div)."
--
-- Modelado com 3 estados:
--
-- @
--                       ¬(leave_ab_i)
--                       ┌──┐
--                       ▼  │
--                      ╭───╮       leave_ab_i           ╭──────────╮
--                  ──▶ │ q0│ ─────────────────────────▶ │ awaiting │
--                      ╰───╯       match_i ∨ div_i      ╰──────────╯
--                       ▲                                     │
--                       │      (qualquer outro evento ou      │
--                       └─────────── fim do traço) ──────────▶│
--                       match/div                             │
--                                                             ▼
--                                                       ╭─────────╮
--                                                       │ q⊥      │
--                                                       ╰─────────╯
--                                                       sumidouro
-- @
--
-- O estado 'M3Awaiting' tem veredito 'Top' durante o stream (pode ainda
-- ser resolvido), mas 'finalVerdict' retorna 'Bot' se o traço terminar
-- nesse estado — capturando o "silêncio ao fim da janela" da Situação 2
-- da análise de cenários.
module Monitor.Automata.A3
  ( M3State (..)
  , M3
  , initial
  , step
  , verdict
  , finalVerdict
  ) where

import Monitor.Types (Event (..), Verdict (..))

data M3State = M3Ok | M3Awaiting | M3Violated
  deriving (Eq, Show)

newtype M3 = M3 { m3State :: M3State }
  deriving (Eq, Show)

initial :: M3
initial = M3 M3Ok

step :: M3 -> Event -> M3
step m evt = case m3State m of
  M3Violated -> m
  M3Ok -> case evt of
    LeaveAbI -> M3 M3Awaiting
    _        -> m
  M3Awaiting -> case evt of
    MatchI -> M3 M3Ok
    DivI   -> M3 M3Ok
    _      -> M3 M3Violated

-- | Veredito durante o stream. 'M3Awaiting' não viola ainda — o próximo
-- evento (match/div) pode resolver.
verdict :: M3 -> Verdict
verdict m = case m3State m of
  M3Violated -> Bot
  _          -> Top

-- | Veredito ao fim do traço. 'M3Awaiting' agora viola (leave_ab_i sem
-- pronunciamento até o fim do stream).
finalVerdict :: M3 -> Verdict
finalVerdict m = case m3State m of
  M3Violated -> Bot
  M3Awaiting -> Bot
  M3Ok       -> Top
