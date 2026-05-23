{-# LANGUAGE OverloadedStrings #-}

-- | Para cada @Files/Traces/*.txt@ e @Files/Smoke/*.txt@, executa o
-- monitor e verifica que o veredito final bate com @veredito_esperado@
-- do cabeçalho YAML. Traços sem @veredito_esperado@ são pulados (e
-- contabilizados em uma label informativa).
module ExampleTraces (tests) where

import qualified Data.Text.IO       as TIO
import           System.Directory   (doesDirectoryExist, listDirectory)
import           System.FilePath    ((</>), takeExtension)
import           Test.Tasty         (TestTree, testGroup)
import           Test.Tasty.HUnit   (testCase, assertEqual, assertFailure)

import           Monitor.Composed   (runMonitor)
import           Monitor.Header     (TraceHeader (..))
import           Monitor.MesBridge  (injectMesBridge)
import           Monitor.Parser     (parseFile)
import           Monitor.Types      (defaultConfig)

tests :: IO TestTree
tests = do
  txt   <- listTxt "Files/Traces"
  smoke <- listTxt "Files/Smoke"
  let all_ = txt ++ smoke
  pure $ testGroup "ExampleTraces" (map mkTest all_)

listTxt :: FilePath -> IO [FilePath]
listTxt dir = do
  exists <- doesDirectoryExist dir
  if not exists then pure [] else do
    entries <- listDirectory dir
    pure [ dir </> e | e <- entries, takeExtension e == ".txt" ]

mkTest :: FilePath -> TestTree
mkTest fp = testCase fp $ do
  content <- TIO.readFile fp
  case parseFile content of
    Left err -> assertFailure ("erro de parsing: " ++ err)
    Right (hdr, events) -> do
      let cfg     = defaultConfig
          events' = injectMesBridge cfg hdr events
          (v, _, _) = runMonitor cfg events'
      case hdr >>= thExpected of
        Nothing       -> pure ()  -- sem veredito_esperado: só checamos parsing
        Just expected ->
          assertEqual ("veredito divergente em " ++ fp) expected v
