{-# LANGUAGE OverloadedStrings #-}

-- | CLI do emulador LTL/TLTL.
--
-- Modos de saída:
--
-- * default — formato detalhado tipo "emulador" ("Output.Detailed");
-- * @--quiet@ — formato curto compatível com a Peça 1 ("Output.Plain");
-- * @--json@  — JSON estruturado ("Output.Json").
--
-- Códigos de saída:
--
-- * 0 — traço aceito (⊤);
-- * 1 — erro de parsing/uso ou veredito inconclusivo;
-- * 2 — traço violado (⊥).
module Main (main) where

import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs)
import           System.Exit        (ExitCode (..), exitWith)
import           System.IO          (hPutStrLn, stderr)

import           Monitor.Composed   (runMonitor, runMonitorTrace)
import           Monitor.MesBridge  (injectMesBridge)
import           Monitor.Parser     (parseFile)
import           Monitor.Types      (Verdict (..), defaultConfig)
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
  hPutStrLn stderr "  --json    JSON estruturado"
  exitWith (ExitFailure 1)

processFile :: Mode -> FilePath -> IO ()
processFile mode filepath = do
  content <- TIO.readFile filepath
  case parseFile content of
    Left err -> do
      hPutStrLn stderr ("Erro ao parsear traço: " ++ err)
      exitWith (ExitFailure 1)
    Right (hdr, events) -> do
      let cfg     = defaultConfig
          events' = injectMesBridge cfg hdr events
      case mode of
        ModeQuiet -> do
          let (v, viol, rules) = runMonitor cfg events'
          putStr (Plain.renderReport filepath (length events') v viol rules)
          exitOn v
        ModeDetailed -> do
          let (steps, v, mFirst, rules) = runMonitorTrace cfg events'
          putStr (Det.renderDetailed filepath hdr cfg steps v mFirst rules)
          exitOn v
        ModeJson -> do
          let (steps, v, mFirst, rules) = runMonitorTrace cfg events'
          putStrLn (Js.renderJson filepath hdr cfg steps v mFirst rules)
          exitOn v

exitOn :: Verdict -> IO ()
exitOn Top          = exitWith ExitSuccess
exitOn Bot          = exitWith (ExitFailure 2)
exitOn Inconclusive = exitWith (ExitFailure 1)
