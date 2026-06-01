module Main where

import System.IO (hFlush, stdout)

-- Pede dois números ao usuário, soma e imprime o resultado
somar :: IO ()
somar = do
  putStr "Digite o primeiro número: "
  hFlush stdout
  entrada1 <- getLine
  putStr "Digite o segundo número: "
  hFlush stdout
  entrada2 <- getLine
  let n1 = read entrada1 :: Double
      n2 = read entrada2 :: Double
  putStrLn ("Resultado: " ++ show (n1 + n2))

main :: IO ()
main = somar
