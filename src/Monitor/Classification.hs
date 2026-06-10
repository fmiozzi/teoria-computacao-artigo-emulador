{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Monitor.Classification
Description : Filtro de confiança (propriedade A5) do pipeline de inferência.
Copyright   : (c) Flávio Miozzi Batista, 2026
License     : <a definir>
Maintainer  : fmiozzi@gmail.com
Stability   : experimental

Bloco arquitetural na figura de arquitetura (v2) do artigo: "Pipeline de
inferência (CNN) — classificação de produto".
Referência canônica: Tabela 2 (A5).

A5 é uma restrição estrutural (filtro semântico a montante), não uma
fórmula LTL/TLTL: apenas classificações com confiança @≥ τ@ contribuem
para @M_obs@ e satisfazem a obrigação de A2.
-}
module Monitor.Classification
  ( isValidCls
  , filterByTau
  ) where

import Monitor.Types (Event (..))

-- | Predicado A5: o evento é uma classificação confiável (@conf ≥ τ@)?
-- Falso para classificações fracas e para eventos que não são @cls_p_i@.
isValidCls :: Double -> Event -> Bool
isValidCls tau (ClsPI _ conf) = conf >= tau
isValidCls _   _              = False

-- | Filtro A5: descarta @cls_p_i@ com confiança @< τ@, preservando os
-- demais eventos. Aplicado /antes/ de alimentar @M_obs@.
filterByTau :: Double -> [Event] -> [Event]
filterByTau tau = filter keep
  where
    keep (ClsPI _ conf) = conf >= tau
    keep _              = True
