{-# LANGUAGE OverloadedStrings #-}

-- | CLI do emulador LTL/TLTL.
--
-- Lê um arquivo de traço, roda o monitor composto e imprime o relatório
-- via 'Output.Plain.renderReport'. Códigos de saída:
--
-- * 0 — traço aceito (⊤);
-- * 1 — erro de parsing ou uso;
-- * 2 — traço violado (⊥).
module Main (main) where

import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs)
import           System.Exit        (ExitCode (..), exitWith)
import           System.IO          (hPutStrLn, stderr)

import           Monitor.Parser     (parseFile)
import           Monitor.Composed   (runMonitor)
import           Monitor.Types      (Verdict (..))
import           Output.Plain       (renderReport)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [filepath] -> processFile filepath
    _          -> do
      hPutStrLn stderr "Uso: lab-monitor <arquivo_de_traço>"
      exitWith (ExitFailure 1)

processFile :: FilePath -> IO ()
processFile filepath = do
  content <- TIO.readFile filepath
  case parseFile content of
    Left err -> do
      hPutStrLn stderr ("Erro ao parsear traço: " ++ err)
      exitWith (ExitFailure 1)
    Right (_hdr, events) -> do
      let (v, viol) = runMonitor events
      putStr (renderReport filepath (length events) v viol)
      case v of
        Top -> exitWith ExitSuccess
        Bot -> exitWith (ExitFailure 2)
        _   -> exitWith (ExitFailure 1)
