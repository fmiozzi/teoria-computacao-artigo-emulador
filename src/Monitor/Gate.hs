{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Monitor.Gate
Description : Gate de decisão MES↔ERP (Algoritmo 1 do artigo).
Copyright   : (c) Flávio Miozzi Batista, 2026
License     : <a definir>
Maintainer  : fmiozzi@gmail.com
Stability   : experimental

Bloco arquitetural na figura de arquitetura (v2) do artigo: "Gate MES↔ERP
(decisão em tempo real)".
Referência canônica: Algoritmo 1 (alg-monitor-online); fig-fluxograma-gate.

O gate traduz o veredito composto (ínfimo de M_1..M_4) em uma decisão
operacional sobre a integração MES → ERP.
-}
module Monitor.Gate
  ( GateDecision (..)
  , decide
  ) where

import Monitor.Types (Verdict (..))

-- | Decisão do gate: liberar a integração, ou bloqueá-la listando as
-- propriedades (A_k) violadas.
data GateDecision
  = Liberar
  | Bloquear [String]
  deriving (Eq, Show)

-- | Algoritmo 1 (decisão online): ⊤ libera; ⊥ bloqueia com as regras
-- violadas; ? é tratado com cautela como bloqueio sem regras (a decisão
-- final aguarda mais eventos).
decide :: Verdict -> [String] -> GateDecision
decide Top          _     = Liberar
decide Bot          rules = Bloquear rules
decide Inconclusive _     = Bloquear []
