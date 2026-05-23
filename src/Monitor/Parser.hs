{-# LANGUAGE OverloadedStrings #-}

-- | Parser do formato de traço da Peça 1: uma linha por evento.
--
-- Comentários iniciam com @#@ e linhas vazias são ignoradas. A partir da
-- Fase 2 o parser passa a aceitar cabeçalho YAML opcional e timestamps,
-- mas mantém compatibilidade com este formato textual mínimo.
module Monitor.Parser
  ( parseEvent
  , parseTrace
  ) where

import qualified Data.Text as T
import           Monitor.Types (Event (..))

-- | Sintaxe aceita:
--
-- @
--   ab_i
--   rem_i
--   leave_ab_i
--   match_i
--   div_i
--   esc_pcp_i
--   heartbeat
--   cls_p_i \<sku\> \<confiança\>
-- @
parseEvent :: T.Text -> Either String Event
parseEvent line = case T.words line of
  ["ab_i"]               -> Right AbI
  ["rem_i"]              -> Right RemI
  ["leave_ab_i"]         -> Right LeaveAbI
  ["match_i"]            -> Right MatchI
  ["div_i"]              -> Right DivI
  ["esc_pcp_i"]          -> Right EscPcpI
  ["heartbeat"]          -> Right Heartbeat
  ["cls_p_i", sku, conf] -> case reads (T.unpack conf) :: [(Double, String)] of
    [(c, "")] -> Right (ClsPI sku c)
    _         -> Left ("confiança inválida: " <> T.unpack conf)
  ws -> Left ("evento desconhecido: " <> T.unpack (T.unwords ws))

parseTrace :: T.Text -> Either String [Event]
parseTrace =
    traverse parseEvent
  . filter isEventLine
  . map T.strip
  . T.lines
  where
    isEventLine line = not (T.null line) && not ("#" `T.isPrefixOf` line)
