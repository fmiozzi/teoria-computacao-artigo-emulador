{-# LANGUAGE OverloadedStrings #-}

-- | Parser do formato de traço (Peça 1 + extensões da Fase 2).
--
-- Um arquivo válido tem duas partes opcionais:
--
-- 1. /Cabeçalho YAML/ entre marcadores @---@ (parseado por
--    "Monitor.Header"). Pode estar ausente — neste caso o parser
--    devolve 'Nothing' no primeiro elemento da tupla.
--
-- 2. /Corpo/ com um evento por linha. Cada evento pode ser prefixado
--    por timestamp em ms:
--
--    * @[t=1500] rem_i@ (forma com colchetes)
--    * @1500 rem_i@ (primeiro token inteiro)
--    * @rem_i@ (sem timestamp — assume @i * 1000@ ms onde @i@ é o
--      índice 0-based do evento)
--
-- Comentários iniciam com @#@. Linhas em branco são ignoradas.
module Monitor.Parser
  ( parseFile
  , parseEvent
  ) where

import qualified Data.Text       as T
import           Monitor.Header  (TraceHeader, parseHeader)
import           Monitor.Types   (Event (..), TimedEvent (..))

-- | Entrada principal: separa cabeçalho YAML (se houver) do corpo e
-- atribui timestamp a cada evento.
parseFile :: T.Text -> Either String (Maybe TraceHeader, [TimedEvent])
parseFile src = do
  let (mHdrTxt, bodyLines) = splitHeader (T.lines src)
  hdr <- traverse parseHeader mHdrTxt
  body <- parseBody bodyLines
  Right (hdr, body)

-- | Separa o cabeçalho YAML do corpo. Retorna o miolo (sem marcadores)
-- ou 'Nothing' quando o arquivo não tem cabeçalho.
splitHeader :: [T.Text] -> (Maybe T.Text, [T.Text])
splitHeader ls = case dropWhile isBlank ls of
  (l : rest)
    | T.strip l == "---" ->
        let (hdr, more) = break (\x -> T.strip x == "---") rest
        in (Just (T.unlines hdr), drop 1 more)
  _ -> (Nothing, ls)
  where
    isBlank l = T.null (T.strip l)

-- | Linhas relevantes (não vazias, não comentário) viram 'TimedEvent's.
-- O índice avança apenas em eventos válidos, de forma que linhas em
-- branco e comentários não "consomem" um slot de timestamp implícito.
--
-- Comentários inline (@\#@ no meio da linha) são removidos antes do
-- parsing — útil para anotar timestamps grandes.
parseBody :: [T.Text] -> Either String [TimedEvent]
parseBody = go 0 . map (T.strip . stripInlineComment)
  where
    go _ [] = Right []
    go evtIdx (l : rest)
      | T.null l             = go evtIdx rest
      | "#" `T.isPrefixOf` l = go evtIdx rest
      | otherwise = do
          te <- parseTimedEvent evtIdx l
          (te :) <$> go (evtIdx + 1) rest

-- | Remove o sufixo de comentário inline (@\# ...@) de uma linha.
-- Não temos literais com @\#@ no nosso vocabulário, então um corte
-- direto no primeiro @\#@ é seguro.
stripInlineComment :: T.Text -> T.Text
stripInlineComment = T.takeWhile (/= '#')

parseTimedEvent :: Int -> T.Text -> Either String TimedEvent
parseTimedEvent implicitIdx line = do
  (mTs, rest) <- extractTimestamp line
  evt <- parseEvent rest
  let ts = case mTs of
        Just n  -> n
        Nothing -> implicitIdx * 1000
  Right (TimedEvent ts evt)

-- | Reconhece @[t=NNN]@ ou um inteiro líder. Retorna (Nothing, line) se
-- não houver timestamp.
extractTimestamp :: T.Text -> Either String (Maybe Int, T.Text)
extractTimestamp line
  | "[t=" `T.isPrefixOf` line = parseBracket line
  | otherwise = case T.words line of
      (w : _)
        | Just n <- readIntMaybe (T.unpack w) ->
            Right (Just n, T.stripStart (T.drop (T.length w) line))
      _ -> Right (Nothing, line)
  where
    parseBracket l = case T.breakOn "]" (T.drop 3 l) of
      (_, rest) | T.null rest ->
        Left ("colchete não fechado em: " ++ T.unpack line)
      (numTxt, rest) -> case readIntMaybe (T.unpack (T.strip numTxt)) of
        Just n  -> Right (Just n, T.stripStart (T.drop 1 rest))
        Nothing -> Left ("timestamp inválido em: " ++ T.unpack line)

readIntMaybe :: String -> Maybe Int
readIntMaybe s = case reads s :: [(Int, String)] of
  [(n, "")] -> Just n
  _         -> Nothing

-- | Sintaxe dos eventos:
--
-- @
--   ab_i | rem_i | leave_ab_i | match_i | div_i | esc_pcp_i | heartbeat
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
  ["rej_i"]              -> Right RejI
  ["cls_p_i", sku, conf] -> case reads (T.unpack conf) :: [(Double, String)] of
    [(c, "")] -> Right (ClsPI sku c)
    _         -> Left ("confiança inválida: " <> T.unpack conf)
  ws -> Left ("evento desconhecido: " <> T.unpack (T.unwords ws))
