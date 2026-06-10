{-# LANGUAGE OverloadedStrings #-}

-- | Para cada @Files/Traces/**/*.txt@ e @Files/Smoke/*.txt@, executa o
-- monitor (via 'Monitor.Gate.run') e verifica que:
--
--   * o veredito composto (Proposição 2) bate com @veredito_esperado@; e
--   * o status terminal do gate (§5.4) bate com @status_esperado@, quando
--     declarado.
--
-- Traços sem o campo correspondente pulam a verificação daquele campo
-- (apenas o parsing é exigido).
module ExampleTraces (tests) where

import qualified Data.Text.IO       as TIO
import           System.Directory   (doesDirectoryExist, listDirectory)
import           System.FilePath    ((</>), takeExtension)
import           Test.Tasty         (TestTree, testGroup)
import           Test.Tasty.HUnit   (testCase, assertEqual, assertFailure)

import           Monitor.Gate       (GateResult (..), run)
import           Monitor.Header     (TraceHeader (..), applyParams)
import           Monitor.Parser     (parseFile)
import           Monitor.Types      (defaultConfig, showStatus, showVerdict)

-- | Oráculo canônico: traços do recorte verificado (A1–A3 + A5) no nível
-- superior de @Files/Traces@ e os smokes. Os traços prospectivos em
-- @Files/Traces/extras@ (A4/A6/A7/A8) ficam fora do recorte avaliado e
-- não são exercitados aqui.
tests :: IO TestTree
tests = do
  txt    <- listTxt "Files/Traces"
  smoke  <- listTxt "Files/Smoke"
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
      let cfg = applyParams hdr defaultConfig
          res = run cfg (hdr >>= thMdec) events
      -- (1) veredito composto vs veredito_esperado
      case hdr >>= thExpected of
        Nothing -> pure ()
        Just expected ->
          assertEqual
            ("veredito composto divergente em " ++ fp ++
             " (obtido " ++ showVerdict (grVerdict res) ++ ")")
            expected (grVerdict res)
      -- (2) status do gate vs status_esperado (quando declarado)
      case hdr >>= thStatus of
        Nothing -> pure ()
        Just expectedSt ->
          assertEqual
            ("status do gate divergente em " ++ fp ++
             " (obtido " ++ showStatus (grStatus res) ++ ")")
            expectedSt (grStatus res)
