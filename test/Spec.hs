-- | Entry point da suite de testes Tasty.
module Main (main) where

import           Test.Tasty
import qualified ExampleTraces
import qualified CompositionProps
import qualified AbsorbingProps

main :: IO ()
main = do
  egTests <- ExampleTraces.tests
  defaultMain $ testGroup "lab-monitor"
    [ egTests
    , CompositionProps.tests
    , AbsorbingProps.tests
    ]
