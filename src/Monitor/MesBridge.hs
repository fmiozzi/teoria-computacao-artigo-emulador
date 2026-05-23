{-# LANGUAGE OverloadedStrings #-}

-- | "Ponte" entre o monitor e o MES (§5.4 do artigo).
--
-- Em produção, a comparação de @M_obs@ com @M_dec@ é feita por um
-- componente externo (mes-bridge), que emite @match_i@ ou @div_i@ ao
-- fim de cada janela. O emulador simula esse papel: se o cabeçalho
-- YAML traz @m_dec@ e o traço não pronuncia match/div logo após o
-- @leave_ab_i@, injetamos automaticamente o evento que o agente
-- /deveria/ ter emitido.
--
-- Política (opção @c@ acordada com o usuário):
--
-- * /Sem cabeçalho ou sem @m_dec@/: não toca no traço (caminho legado).
-- * /Próximo evento após @leave_ab_i@ é match/div/: deixa o traço
--   prevalecer (operador já se pronunciou).
-- * /Caso contrário/: insere @match_i@ se @M_obs = M_dec@ ou @div_i@
--   se diferentes, no mesmo timestamp do @leave_ab_i@.
--
-- O multiset @M_obs@ é construído neste módulo a partir das
-- classificações com confiança ≥ τ (A5), de forma independente de
-- A2 — o atraso de uma classificação não a remove de @M_obs@ porque
-- A2 e o cálculo de divergência são preocupações separadas.
module Monitor.MesBridge
  ( injectMesBridge
  ) where

import qualified Monitor.Multiset as MS
import           Monitor.Header   (TraceHeader (..))
import           Monitor.Multiset (Multiset)
import           Monitor.Types    ( Config (..)
                                  , Event (..)
                                  , TimedEvent (..)
                                  )

injectMesBridge
  :: Config
  -> Maybe TraceHeader
  -> [TimedEvent]
  -> [TimedEvent]
injectMesBridge cfg mHdr tes =
  case mHdr >>= thMdec of
    Nothing   -> tes
    Just mDec -> go mDec MS.empty tes
  where
    tau = cfgTau cfg

    go _    _   []           = []
    go mDec obs (te : rest) = case teEvent te of
      ClsPI sku conf
        | conf >= tau -> te : go mDec (MS.addCls sku obs) rest
        | otherwise   -> te : go mDec obs rest

      LeaveAbI
        | nextIsPronouncement rest -> te : go mDec obs rest
        | otherwise ->
            let injected = TimedEvent (teTime te) (pronounce obs mDec)
            in te : injected : go mDec obs rest

      _ -> te : go mDec obs rest

    nextIsPronouncement (next : _) = case teEvent next of
      MatchI -> True
      DivI   -> True
      _      -> False
    nextIsPronouncement []         = False

    pronounce :: Multiset -> Multiset -> Event
    pronounce obs mDec = case MS.compareMs obs mDec of
      Right () -> MatchI
      Left _   -> DivI
