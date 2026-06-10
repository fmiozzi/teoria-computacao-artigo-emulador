{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M2 — propriedade A2 (liveness temporizada, TLTL) do artigo (v2):
--
-- @
--   A2 : G(leave_ab_i → F_{[0, T_cls]} ∨_{j∈M, p∈P} cls_{p,i,j}^{≥τ})
-- @
--
-- "Ao encerrar a janela de abastecimento (leave_ab_i), deve existir ao
-- menos uma classificação válida (confiança ≥ τ) dentro de T_cls
-- unidades de tempo." A ancoragem temporal é o /encerramento da janela/,
-- não a retirada individual (cf. fig-automato-a2-tltl, caption v2).
--
-- Modelado com 3 estados:
--
-- * 'M2Idle' — q_0, ocioso/aceitante (sem janela pendente);
-- * 'M2Pending clock' — q_p, leave_ab_i ocorreu em @clock@ ms (relógio
--   x := 0), aguardando classificação válida sob a guarda x ≤ T_cls;
-- * 'M2Violated' — q_⊥, sumidouro absorvente (promove timeout_cls_i).
--
-- O filtro A5 (limiar de confiança @τ@) está embutido aqui: cls com
-- @conf < τ@ /não/ resolve a pendência (acceptance usa cls^{≥τ}).
--
-- /Política para fim de traço/: se o último estado é 'M2Pending', o
-- 'finalVerdict' retorna ⊥ — interpreta como "janela encerrada sem
-- classificação válida". Leitura estrita de @F_{[0, T_cls]}@ num traço
-- finito: a obrigação não foi cumprida.
module Monitor.Automata.A2
  ( M2State (..)
  , M2
  , initial
  , step
  , verdict
  , finalVerdict
  , summary
  ) where

import Monitor.Types (Config (..), Event (..), TimedEvent (..), Verdict (..))

data M2State
  = M2Idle
  | M2Pending !Int   -- ^ timestamp (ms) do leave_ab_i pendente (x := 0 nesse instante)
  | M2Violated
  deriving (Eq, Show)

-- | Estado de M2 + parâmetros (T_cls, τ) embutidos. Isso evita que o
-- composer precise propagar a 'Config' a cada step.
--
-- 'm2SeenValid' materializa a /existência agregada/ da legenda da figura:
-- registra se já houve @cls^{≥τ}@ desde a abertura da janela (@ab_i@). No
-- @leave_ab_i@, se a flag está ativa, A2 é satisfeita de imediato (a
-- classificação ocorreu /durante/ a janela); caso contrário inicia-se o
-- relógio, dando até @T_cls@ para uma classificação tardia.
--
-- 'm2SawRem' condiciona a obrigação à existência de retirada: uma janela
-- /vazia/ (nenhum @rem_i@) é vacuosamente aceita — não há peça a
-- classificar (refinamento operacional registrado em docs/DECISOES.md).
data M2 = M2
  { m2State     :: !M2State
  , m2SeenValid :: !Bool    -- ^ viu cls com conf ≥ τ desde a abertura da janela
  , m2SawRem    :: !Bool    -- ^ houve rem_i desde a abertura da janela
  , m2Tcls      :: !Int     -- ^ T_cls em ms
  , m2Tau       :: !Double  -- ^ limiar de A5
  } deriving (Eq, Show)

initial :: Config -> M2
initial cfg = M2
  { m2State     = M2Idle
  , m2SeenValid = False
  , m2SawRem    = False
  , m2Tcls      = cfgTcls cfg
  , m2Tau       = cfgTau  cfg
  }

step :: M2 -> TimedEvent -> M2
step m (TimedEvent now evt) = case m2State m of
  M2Violated -> m
  M2Idle -> case evt of
    -- Abertura de janela: zera a evidência agregada e a marca de retirada.
    AbI  -> m { m2SeenValid = False, m2SawRem = False }
    -- Retirada na janela: arma a obrigação de classificação.
    RemI -> m { m2SawRem = True }
    -- Classificação confiável (A5) durante a janela registra a evidência.
    ClsPI _ conf | conf >= m2Tau m -> m { m2SeenValid = True }
    -- Encerramento da janela: decide pela existência agregada.
    LeaveAbI
      -- Janela vazia (sem retirada): vacuosamente aceita.
      | not (m2SawRem m) -> m { m2SeenValid = False, m2SawRem = False }
      -- Houve retirada e classificação válida: satisfeita.
      | m2SeenValid m    -> m { m2State = M2Idle, m2SeenValid = False, m2SawRem = False }
      -- Houve retirada sem classificação válida ainda: aguarda tardia.
      | otherwise        -> m { m2State = M2Pending now }
    _ -> m
  M2Pending clock
    -- Prazo expirado: viola assim que o tempo de qualquer evento
    -- ultrapassa a janela T_cls — o próprio evento já não importa.
    | now - clock > m2Tcls m -> m { m2State = M2Violated }
    | otherwise -> case evt of
        -- Classificação confiável tardia (A5) resolve a pendência.
        ClsPI _ conf | conf >= m2Tau m ->
          m { m2State = M2Idle, m2SeenValid = False, m2SawRem = False }
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

summary :: M2 -> String
summary m = case m2State m of
  M2Idle           -> "idle"
  M2Pending clock  -> "pending(x=" ++ show clock ++ ")"
  M2Violated       -> "viol"
