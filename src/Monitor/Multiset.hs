{-# LANGUAGE OverloadedStrings #-}

-- | Multiconjuntos sobre SKUs.
--
-- Modela @M_obs@ (peças observadas pelo agente) e @M_dec@ (peças
-- declaradas no MES). A comparação retorna o delta por SKU; igualdade
-- significa que o agente pode emitir @match_i@, divergência exige
-- @div_i@ (e, em seguida, @esc_pcp_i@ em até T_pcp, via A4).
--
-- A Peça 1 ainda não consome este módulo; ele é usado a partir da
-- Fase 6 (composição com M_dec lido do cabeçalho YAML).
module Monitor.Multiset
  ( SKU
  , Multiset
  , Diff
  , empty
  , addCls
  , compareMs
  , showDiff
  ) where

import qualified Data.Map.Strict as Map
import           Data.Map.Strict (Map)
import qualified Data.Text       as T

type SKU      = T.Text
type Multiset = Map SKU Int

-- | Diferença por SKU: @M_dec - M_obs@. Positivo = falta no observado;
-- negativo = sobra no observado. Chaves com valor zero são omitidas.
type Diff = Map SKU Int

empty :: Multiset
empty = Map.empty

-- | Contabiliza uma classificação aceita (A5 já filtrou por confiança).
addCls :: SKU -> Multiset -> Multiset
addCls sku = Map.insertWith (+) sku 1

-- | Compara @M_obs@ com @M_dec@. @Right ()@ = iguais; @Left diff@ = diverge.
compareMs :: Multiset -> Multiset -> Either Diff ()
compareMs obs dec =
  let diff = Map.filter (/= 0) (Map.unionWith (+) dec (Map.map negate obs))
  in if Map.null diff then Right () else Left diff

showDiff :: Diff -> String
showDiff = unwords . map render . Map.toList
  where
    render (sku, n) = T.unpack sku ++ ":" ++ showSigned n
    showSigned n | n >= 0    = "+" ++ show n
                 | otherwise = show n
