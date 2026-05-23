{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M2 — propriedade A2 (TLTL) do artigo:
--
-- @
--   A2 : G(rem_i → F_{[0, T_cls]} ∨_p cls_{p,i})
-- @
--
-- "Toda retirada deve ser seguida de uma classificação dentro de
-- T_cls unidades de tempo, com confiança ≥ τ."
--
-- Modelado com 3 estados:
--
-- * 'M2Idle' — sem rem_i pendente;
-- * 'M2Pending clock' — rem_i ocorreu em @clock@ ms, aguardando cls;
-- * 'M2Violated' — sumidouro absorvente.
--
-- O filtro A5 (limiar de confiança @τ@) está embutido aqui: cls com
-- @conf < τ@ /não/ resolve a pendência. Isso preserva a semântica de
-- "classificação confiável" sem precisar de um autômato M5 separado.
--
-- /Política para fim de traço/: se o último estado é 'M2Pending', o
-- 'finalVerdict' retorna ⊥ — interpreta como "rem_i sem classificação".
-- Isto é a leitura estrita do operador @F_{[0, T_cls]}@ para um traço
-- finito: a obrigação não foi cumprida.
module Monitor.Automata.A2
  ( M2State (..)
  , M2
  , initial
  , step
  , verdict
  , finalVerdict
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M2State
  = M2Idle
  | M2Pending !Int   -- ^ timestamp (ms) do rem_i pendente
  | M2Violated
  deriving (Eq, Show)

-- | Estado de M2 + parâmetros (T_cls, τ) embutidos. Isso evita que o
-- composer precise propagar a 'Config' a cada step.
data M2 = M2
  { m2State :: !M2State
  , m2Tcls  :: !Int     -- ^ T_cls em ms
  , m2Tau   :: !Double  -- ^ limiar de A5
  } deriving (Eq, Show)

initial :: Config -> M2
initial cfg = M2
  { m2State = M2Idle
  , m2Tcls  = cfgTcls cfg
  , m2Tau   = cfgTau  cfg
  }

step :: M2 -> TimedEvent -> M2
step m (TimedEvent now evt) = case m2State m of
  M2Violated -> m
  M2Idle -> case evt of
    RemI -> m { m2State = M2Pending now }
    _    -> m
  M2Pending clock
    -- Prazo expirado: viola assim que o tempo de qualquer evento
    -- ultrapassa a janela T_cls — o próprio evento já não importa.
    | now - clock > m2Tcls m -> m { m2State = M2Violated }
    | otherwise -> case evt of
        -- Classificação confiável (A5) resolve a pendência.
        ClsPI _ conf | conf >= m2Tau m -> m { m2State = M2Idle }
        -- Demais eventos (inclusive cls com conf < τ) não alteram.
        _                              -> m

verdict :: M2 -> Verdict
verdict m = case m2State m of
  M2Violated -> Bot
  _          -> Top

-- | Em 'M2Pending' ao fim do traço também viola — a obrigação F[…]
-- não foi cumprida dentro do horizonte observado.
finalVerdict :: M2 -> Verdict
finalVerdict m = case m2State m of
  M2Violated  -> Bot
  M2Pending _ -> Bot
  M2Idle      -> Top
