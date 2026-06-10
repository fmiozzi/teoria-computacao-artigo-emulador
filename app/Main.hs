{-# LANGUAGE OverloadedStrings #-}

-- | CLI do emulador LTL/TLTL.
--
-- Modos de saída:
--
-- * default — formato detalhado tipo "emulador" ("Output.Detailed");
-- * @--quiet@ — formato curto, 1 bloco por traço ("Output.Plain");
-- * @--json@  — JSON estruturado, log auditável ("Output.Json").
--
-- Códigos de saída (derivados do status do gate, §5.4):
--
-- * 0 — LIBERAR (liberado_integracao);
-- * 2 — BLOQUEAR (divergencia_pcp | erro_classificacao | erro_decisao);
-- * 3 — PENDENTE (apontamento sem decisão terminal);
-- * 1 — erro de parsing/IO/uso.
module Main (main) where

import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs)
import           System.Exit        (ExitCode (..), exitWith)
import           System.IO          (hPutStrLn, stderr)

import           Monitor.Gate       (GateResult (..), run)
import           Monitor.Header     (TraceHeader (..), applyParams)
import           Monitor.Parser     (parseFile)
import           Monitor.Types      (MesStatus (..), defaultConfig)
import qualified Output.Detailed    as Det
import qualified Output.Json        as Js
import qualified Output.Plain       as Plain

data Mode = ModeDetailed | ModeQuiet | ModeJson
  deriving (Eq, Show)

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left msg -> usage msg
    Right (mode, filepath) -> processFile mode filepath

parseArgs :: [String] -> Either String (Mode, FilePath)
parseArgs = go ModeDetailed
  where
    go :: Mode -> [String] -> Either String (Mode, FilePath)
    go _ []             = Left "esperado um arquivo de traço"
    go _ ("-h":_)       = Left "help"
    go _ ("--help":_)   = Left "help"
    go _ ("--quiet":xs) = go ModeQuiet xs
    go _ ("--json":xs)  = go ModeJson  xs
    go m [fp]           = Right (m, fp)
    go _ (x:_)          = Left ("argumento desconhecido: " ++ x)

usage :: String -> IO ()
usage msg = do
  case msg of
    "help" -> return ()
    _      -> hPutStrLn stderr ("erro: " ++ msg)
  hPutStrLn stderr "Uso: lab-monitor [--quiet|--json] <arquivo_de_traço>"
  hPutStrLn stderr ""
  hPutStrLn stderr "Modos:"
  hPutStrLn stderr "  (padrão)  formato detalhado tipo \"emulador\""
  hPutStrLn stderr "  --quiet   formato curto (1 bloco por traço — uso em batch)"
  hPutStrLn stderr "  --json    JSON estruturado (log auditável)"
  exitWith (ExitFailure 1)

processFile :: Mode -> FilePath -> IO ()
processFile mode filepath = do
  content <- TIO.readFile filepath
  case parseFile content of
    Left err -> do
      hPutStrLn stderr ("Erro ao parsear traço: " ++ err)
      exitWith (ExitFailure 1)
    Right (hdr, events) -> do
      let cfg = applyParams hdr defaultConfig
          res = run cfg (hdr >>= thMdec) events
      case mode of
        ModeQuiet    -> putStr   (Plain.renderReport filepath res)
        ModeDetailed -> putStr   (Det.renderDetailed filepath hdr cfg res)
        ModeJson     -> putStrLn (Js.renderJson filepath hdr cfg res)
      exitOn (grStatus res)

-- | Código de saída derivado do status terminal do gate (§5.4).
exitOn :: MesStatus -> IO ()
exitOn LiberadoIntegracao  = exitWith ExitSuccess
exitOn PendenteVerificacao = exitWith (ExitFailure 3)
exitOn _                   = exitWith (ExitFailure 2)
