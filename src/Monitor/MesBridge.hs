{-# LANGUAGE OverloadedStrings #-}

-- | Mes-bridge — pré-processador estacionário entre o agente de visão e o
-- monitor composto (§3.2, §3.4, Figura 2 do artigo v2_3).
--
-- Este módulo expõe as operações /puras/ do mes-bridge, consumidas pelo
-- laço online do gate ("Monitor.Gate", Algoritmo 1):
--
--   (i)  comparação de coerência multiconjunto: ao final da janela
--        estendida @[τ_a, τ_b + T_cls]@, compara o multiconjunto observado
--        @M_obs@ (já filtrado por A5) com o declarado @M_dec@ (do
--        apontamento, injetado pelo MES), produzindo @match_i@ (igualdade)
--        ou @mismatch_i@ (diferença);
--
--   (ii) detector de exceções estruturais do ciclo operacional, que emite
--        @fora_ciclo_i@.
--
-- O macro-evento derivado é @div_i := mismatch_i ∨ fora_ciclo_i@ (§3.4,
-- apenas DOIS disjuntos). Crucialmente, @timeout_cls_i@ (sumidouro de M₂)
-- e @leave_ab_silent_i@ (sumidouro de M₃) /não/ constituem div_i — são
-- promovidos pelo efetor a @erro_classificacao@ e @erro_decisao@,
-- respectivamente.
module Monitor.MesBridge
  ( Pronouncement (..)
  , pronounce
  , StructuralCtx (..)
  , structuralException
  ) where

import qualified Monitor.Multiset as MS
import           Monitor.Multiset (Multiset)
import           Monitor.Types    (Diag (..), Event (..))

-- | Pronunciamento de coerência emitido pelo mes-bridge ao final da
-- janela: @match_i@ (M_obs = M_dec) ou @mismatch_i@ (M_obs ≠ M_dec).
data Pronouncement = PMatch | PMismatch
  deriving (Eq, Show)

-- | Comparação multiconjunto @M_obs =? M_dec@. A semântica é por SKU
-- (multiplicidades), não por sequência de eventos (§2.4.1). O caso de
-- borda @M_obs = M_dec = ∅@ resolve trivialmente em 'PMatch' (§3.3).
pronounce :: Multiset -> Multiset -> Pronouncement
pronounce obs dec = case MS.compareMs obs dec of
  Right () -> PMatch
  Left _   -> PMismatch

-- | Contexto mínimo para o detector de exceções estruturais do ciclo.
data StructuralCtx = StructuralCtx
  { scWindowOpen :: !Bool   -- ^ há uma janela @ab_i@ aberta (sem @leave_ab_i@ ainda)?
  , scLeftAlready :: !Bool  -- ^ já houve @leave_ab_i@ no ciclo corrente?
  } deriving (Eq, Show)

-- | Detector de exceções estruturais do ciclo operacional (§3.4). A lista
-- é /plugável/; a versão corrente captura os gatilhos verificáveis a partir
-- do traço de eventos AP:
--
--   * duplicação de @leave_ab_i@ no mesmo ciclo (b);
--   * @match_i@/@div_i@ fora de um ciclo armado — pronunciamento espúrio (e).
--
-- Os gatilhos (c) "ausência de @ab_i@ com @rem@/@cls@" e a violação de
-- safety de A1 são capturados pelo sumidouro de M₁ (roteado a
-- @divergencia_pcp@ com diagnóstico @safety_A1@ pelo gate); o gatilho (d)
-- "inconsistência @M_dec@×OP" depende de metadados do MES fora do alfabeto
-- AP e fica como ponto de extensão documentado.
--
-- Retorna @Just ForaCiclo@ quando o evento, no contexto dado, configura uma
-- exceção estrutural.
structuralException :: StructuralCtx -> Event -> Maybe Diag
structuralException ctx e = case e of
  -- (b) leave_ab_i repetido sem ab_i intermediário
  LeaveAbI | scLeftAlready ctx && not (scWindowOpen ctx) -> Just ForaCiclo
  -- (e) pronunciamento (match/div) sem janela encerrada para validar
  MatchI   | not (scLeftAlready ctx)                     -> Just ForaCiclo
  DivI     | not (scLeftAlready ctx)                     -> Just ForaCiclo
  _                                                      -> Nothing
