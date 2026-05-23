{-# LANGUAGE OverloadedStrings #-}

-- | Cabeçalho YAML opcional do arquivo de traço.
--
-- O cabeçalho fica entre duas linhas @---@ no topo do arquivo:
--
-- @
--   ---
--   cenario: "Molde vazio esquecido no MES"
--   maquina: ROTO-01
--   braco: 1
--   m_dec: {caixa_1000L: 2, caixa_2000L: 1}
--   veredito_esperado: TOP
--   ---
--   # eventos abaixo
--   ab_i
-- @
--
-- O parser implementa um subset ad-hoc do YAML suficiente para os campos
-- usados pelo emulador. Block style com indentação não é suportado
-- nesta fase (apenas flow style inline para o @m_dec@). Se houver
-- necessidade futura, migrar para a lib @yaml@ é trivial — esta
-- implementação fica encapsulada aqui.
module Monitor.Header
  ( TraceHeader (..)
  , emptyHeader
  , parseHeader
  ) where

import qualified Data.Map.Strict     as Map
import           Data.Map.Strict     (Map)
import qualified Data.Text           as T
import           Monitor.Multiset    (Multiset)
import           Monitor.Types       (Verdict, parseVerdict)

-- | Campos extraídos do cabeçalho YAML. Todos opcionais — um traço
-- válido pode dispensar o cabeçalho inteiro.
data TraceHeader = TraceHeader
  { thCenario  :: Maybe T.Text
  , thMaquina  :: Maybe T.Text
  , thBraco    :: Maybe Int
  , thMdec     :: Maybe Multiset
  , thExpected :: Maybe Verdict
  } deriving (Eq, Show)

emptyHeader :: TraceHeader
emptyHeader = TraceHeader Nothing Nothing Nothing Nothing Nothing

-- | Parseia o miolo do cabeçalho (sem os marcadores @---@). Linhas
-- vazias e comentários (@#@) são ignorados; chaves desconhecidas são
-- descartadas silenciosamente para permitir extensões futuras sem
-- quebrar arquivos existentes.
parseHeader :: T.Text -> Either String TraceHeader
parseHeader src = foldl step (Right emptyHeader) entries
  where
    entries =
      [ (T.strip k, T.strip v)
      | l <- map T.strip (T.lines src)
      , not (T.null l)
      , not ("#" `T.isPrefixOf` l)
      , let (k, rest) = T.breakOn ":" l
      , not (T.null rest)
      , let v = T.drop 1 rest
      ]

    step (Left e)  _      = Left e
    step (Right h) (k, v) = applyEntry h k v

applyEntry :: TraceHeader -> T.Text -> T.Text -> Either String TraceHeader
applyEntry h k v = case k of
  "cenario"           -> Right h { thCenario  = Just (unquote v) }
  "maquina"           -> Right h { thMaquina  = Just (unquote v) }
  "braco"             -> (\n -> h { thBraco = Just n }) <$> readInt (T.unpack v)
  "m_dec"             -> (\m -> h { thMdec  = Just m }) <$> parseFlowMap v
  "veredito_esperado" -> (\d -> h { thExpected = Just d }) <$> parseVerdict (T.unpack v)
  _                   -> Right h   -- ignora chaves desconhecidas

-- | Remove aspas duplas envolventes (se houver). Strings YAML sem aspas
-- são aceitas como literais.
unquote :: T.Text -> T.Text
unquote t
  | T.length t >= 2
  , T.head t == '"'
  , T.last t == '"'  = T.tail (T.init t)
  | otherwise        = t

readInt :: String -> Either String Int
readInt s = case reads s :: [(Int, String)] of
  [(n, rest)] | all (== ' ') rest -> Right n
  _                               -> Left ("inteiro inválido: " ++ s)

-- | Parser de @{k1: v1, k2: v2}@ (flow style YAML inline).
parseFlowMap :: T.Text -> Either String (Map T.Text Int)
parseFlowMap raw = do
  body <- stripBraces (T.strip raw)
  let pairs = map T.strip (T.splitOn "," body)
  entries <- mapM parsePair (filter (not . T.null) pairs)
  Right (Map.fromList entries)
  where
    stripBraces t
      | T.isPrefixOf "{" t && T.isSuffixOf "}" t =
          Right (T.drop 1 (T.dropEnd 1 t))
      | otherwise =
          Left ("m_dec deve estar entre chaves: " ++ T.unpack t)

    parsePair p = case T.breakOn ":" p of
      (k, rest)
        | T.null rest -> Left ("entrada sem ':': " ++ T.unpack p)
        | otherwise   -> do
            let kStr = T.strip k
                vStr = T.strip (T.drop 1 rest)
            n <- readInt (T.unpack vStr)
            Right (kStr, n)
