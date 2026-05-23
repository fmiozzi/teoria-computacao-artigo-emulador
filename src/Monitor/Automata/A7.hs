{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M7 — propriedade A7 (extensão) do artigo:
--
-- @
--   A7 : G(rej_i → ∃ recent cls_{p,i})
-- @
--
-- "Toda rejeição refere-se a uma classificação recente (em janela
-- T_rej)."
--
-- Modelagem:
--
-- * 'M7State' carrega o último @cls_p_i@ aceito por A5 — timestamp e
--   SKU — para que @rej_i@ posterior possa referenciá-lo.
-- * 'RejI' verifica se há tal classificação dentro de T_rej. Em caso
--   positivo, a memória é consumida (a referência foi "gasta"). Em
--   caso negativo, o monitor vai ao sumidouro.
--
-- Adicionalmente, 'lastClsValid' expõe o SKU pendente para que o
-- composer decremente 'csObs' (a peça refugada não conta como produto
-- válido).
module Monitor.Automata.A7
  ( M7State (..)
  , M7
  , initial
  , step
  , verdict
  , finalVerdict
  , summary
  , lastClsValid
  ) where

import qualified Data.Text     as T
import           Monitor.Types ( Config (..), Event (..)
                               , TimedEvent (..), Verdict (..)
                               )

data M7State
  = M7Idle (Maybe (Int, T.Text))   -- ^ último cls aceito (timestamp, SKU)
  | M7Violated
  deriving (Eq, Show)

data M7 = M7
  { m7State :: !M7State
  , m7Trej  :: !Int
  , m7Tau   :: !Double
  } deriving (Eq, Show)

initial :: Config -> M7
initial cfg = M7
  { m7State = M7Idle Nothing
  , m7Trej  = cfgTrej cfg
  , m7Tau   = cfgTau  cfg
  }

step :: M7 -> TimedEvent -> M7
step m (TimedEvent now evt) = case m7State m of
  M7Violated -> m
  M7Idle mLast -> case evt of
    ClsPI sku conf
      | conf >= m7Tau m -> m { m7State = M7Idle (Just (now, sku)) }
      | otherwise       -> m
    RejI -> case mLast of
      Just (ts, _) | now - ts <= m7Trej m -> m { m7State = M7Idle Nothing }
      _                                   -> m { m7State = M7Violated }
    _ -> m

verdict :: M7 -> Verdict
verdict m = case m7State m of
  M7Violated -> Bot
  _          -> Top

finalVerdict :: M7 -> Verdict
finalVerdict = verdict

-- | Retorna o SKU da última classificação válida (em janela T_rej) se
-- houver — usado pelo composer para decrementar @M_obs@ quando o
-- @rej_i@ é aceito por A7.
lastClsValid :: M7 -> Int -> Maybe T.Text
lastClsValid m now = case m7State m of
  M7Idle (Just (ts, sku)) | now - ts <= m7Trej m -> Just sku
  _                                              -> Nothing

summary :: M7 -> String
summary m = case m7State m of
  M7Idle Nothing       -> "idle"
  M7Idle (Just (t, _)) -> "tracking(t=" ++ show t ++ ")"
  M7Violated           -> "viol"
