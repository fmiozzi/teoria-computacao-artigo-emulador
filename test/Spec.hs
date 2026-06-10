-- | Entry point da suite de testes Tasty.
module Main (main) where

import           Test.Tasty
import qualified ExampleTraces
import qualified CompositionProps
import qualified AbsorbingProps
import qualified UnitProps

main :: IO ()
main = do
  egTests <- ExampleTraces.tests
  defaultMain $ testGroup "lab-monitor"
    [ egTests
    , UnitProps.tests
    , CompositionProps.tests
    , AbsorbingProps.tests
    ]
