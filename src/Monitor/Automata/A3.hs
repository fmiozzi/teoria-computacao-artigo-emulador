{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M3 — propriedade A3 (liveness temporizada, TLTL) do artigo (v2):
--
-- @
--   A3 : G(leave_ab_i → F_{[0, T_dec]} (match_i ∨ div_i))
-- @
--
-- "Ao encerrar a janela de abastecimento (leave_ab_i), o mes-bridge deve
-- emitir um pronunciamento (match_i ou div_i) em até T_dec unidades de
-- tempo." O prazo T_dec = T_cls + ε (com T_dec ≥ T_cls) acomoda a latência
-- do mes-bridge no cômputo da comparação multiconjunto (cf.
-- fig-automato-a3-tltl, v2).
--
-- Modelado com 3 estados:
--
-- * 'M3Ok' — q_0, ocioso/aceitante;
-- * 'M3Pending clock' — q_p, leave_ab_i ocorreu em @clock@ ms (relógio
--   x := 0), aguardando match/div sob a guarda x ≤ T_dec;
-- * 'M3Violated' — q_⊥, sumidouro absorvente (promove leave_ab_silent_i,
--   consumido por M4).
--
-- /Política para fim de traço/: se o último estado é 'M3Pending', o
-- 'finalVerdict' retorna ⊥ — janela encerrada sem pronunciamento dentro
-- do horizonte observado (leitura estrita de @F_{[0, T_dec]}@).
module Monitor.Automata.A3
  ( M3State (..)
  , M3
  , initial
  , step
  , verdict
  , finalVerdict
  , summary
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M3State
  = M3Ok
  | M3Pending !Int   -- ^ timestamp (ms) do leave_ab_i pendente (x := 0 nesse instante)
  | M3Violated
  deriving (Eq, Show)

-- | Estado de M3 + parâmetro T_dec embutido (evita propagar 'Config' a
-- cada step, como em 'Monitor.Automata.A2'/'Monitor.Automata.A4').
data M3 = M3
  { m3State :: !M3State
  , m3Tdec  :: !Int     -- ^ T_dec em ms
  } deriving (Eq, Show)

initial :: Config -> M3
initial cfg = M3
  { m3State = M3Ok
  , m3Tdec  = cfgTdec cfg
  }

step :: M3 -> TimedEvent -> M3
step m (TimedEvent now evt) = case m3State m of
  M3Violated -> m
  M3Ok -> case evt of
    LeaveAbI -> m { m3State = M3Pending now }
    _        -> m
  M3Pending clock
    -- Prazo expirado: viola quando o tempo ultrapassa T_dec sem decisão.
    | now - clock > m3Tdec m -> m { m3State = M3Violated }
    | otherwise -> case evt of
        MatchI -> m { m3State = M3Ok }
        DivI   -> m { m3State = M3Ok }
        _      -> m

-- | Veredito durante o stream. 'M3Pending' não viola ainda — match/div
-- pode chegar dentro do prazo.
verdict :: M3 -> Verdict
verdict m = case m3State m of
  M3Violated -> Bot
  _          -> Top

-- | Veredito ao fim do traço. 'M3Pending' agora viola (leave_ab_i sem
-- pronunciamento dentro do horizonte observado).
finalVerdict :: M3 -> Verdict
finalVerdict m = case m3State m of
  M3Violated  -> Bot
  M3Pending _ -> Bot
  M3Ok        -> Top

summary :: M3 -> String
summary m = case m3State m of
  M3Ok            -> "ok"
  M3Pending clock -> "pending(x=" ++ show clock ++ ")"
  M3Violated      -> "viol"
