{-# LANGUAGE OverloadedStrings #-}

-- | Gerador do corpus aleatório de 400 traços — materialização do
-- property-based testing citado em §5/§7 do artigo ("verifica
-- empiricamente a Proposição 2 por property-based testing sobre 400
-- traços aleatórios").
--
-- O gerador é /reproduzível/: usa um PRNG determinístico (LCG) com semente
-- fixa, de modo que `cabal run corpus-gen` produz exatamente o mesmo corpus
-- a cada execução — requisito para o artefato com DOI.
--
-- Saída em @Files/Corpus/@:
--
--   * @traces/corpus_NNN.txt@   — os 400 traços gerados (re-executáveis pelo
--                                 CLI @lab-monitor@);
--   * @resultados.csv@          — uma linha por caso (veredito composto,
--                                 ínfimo dos componentes, Prop. 2, status do
--                                 gate, nº de eventos);
--   * @RELATORIO.md@            — sumário (distribuição de vereditos/status,
--                                 taxa de confirmação da Proposição 2).
--
-- Cada caso confirma a Proposição 2: o veredito composto (Proposição 2:
-- ínfimo) coincide com o ínfimo independente dos vereditos terminais de
-- M₁, M₂ e M₃.
module Main (main) where

import           Data.Bits          (shiftR, xor)
import qualified Data.Map.Strict    as Map
import qualified Data.Text          as T
import           Data.Word          (Word64)
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    ((</>))
import           Text.Printf        (printf)

import qualified Monitor.Automata.A1 as A1
import qualified Monitor.Automata.A2 as A2
import qualified Monitor.Automata.A3 as A3
import           Monitor.Composed    (ComposedState (..))
import           Monitor.Gate        (GateResult (..), run)
import           Monitor.Multiset    (Multiset)
import           Monitor.Types

-- ---------------------------------------------------------------------------
-- PRNG determinístico (LCG de 64 bits — constantes de Knuth/MMIX)
-- ---------------------------------------------------------------------------

newtype Gen a = Gen { runGen :: Word64 -> (a, Word64) }

instance Functor Gen where
  fmap f (Gen g) = Gen $ \s -> let (a, s') = g s in (f a, s')

instance Applicative Gen where
  pure x = Gen $ \s -> (x, s)
  Gen gf <*> Gen ga = Gen $ \s ->
    let (f, s')  = gf s
        (a, s'') = ga s'
    in (f a, s'')

instance Monad Gen where
  Gen g >>= k = Gen $ \s -> let (a, s') = g s in runGen (k a) s'

-- | Passo do LCG e extração de bits altos (mais aleatórios).
nextWord :: Gen Word64
nextWord = Gen $ \s ->
  let s' = s * 6364136223846793005 + 1442695040888963407
      out = (s' `xor` (s' `shiftR` 31))
  in (out, s')

-- | Inteiro uniforme em [lo, hi].
genInt :: Int -> Int -> Gen Int
genInt lo hi
  | hi <= lo  = pure lo
  | otherwise = do
      w <- nextWord
      pure (lo + fromIntegral (w `mod` fromIntegral (hi - lo + 1)))

-- | Double uniforme em [0,1] (resolução 1/10^6).
genDouble :: Gen Double
genDouble = do
  w <- nextWord
  pure (fromIntegral (w `mod` 1000001) / 1000000)

-- | 'True' com probabilidade @p@.
genBool :: Double -> Gen Bool
genBool p = (< p) <$> genDouble

genChoice :: [a] -> Gen a
genChoice xs = do
  i <- genInt 0 (length xs - 1)
  pure (xs !! i)

-- ---------------------------------------------------------------------------
-- Geração de um caso
-- ---------------------------------------------------------------------------

-- | Um caso gerado: a sequência de eventos e o @M_dec@ declarado (se houver).
data Case = Case ![TimedEvent] !(Maybe Multiset)

skus :: [T.Text]
skus = anchorCatalog

tau :: Double
tau = cfgTau defaultConfig

-- | Gera um caso aleatório: uma janela de abastecimento com 0–4 retiradas,
-- classificações de confiança variável, fecho da janela e — opcionalmente —
-- pronunciamento explícito do agente e/ou @M_dec@ declarado. A variação
-- cobre aceitações, divergências (mismatch) e violações temporizadas
-- (A2/A3) conforme o regime de tempo do cenário-âncora.
genCase :: Gen Case
genCase = do
  nRem  <- genInt 0 4
  -- timestamps crescentes: passo entre 200 e 2500 ms
  let stepT prev = do d <- genInt 200 2500; pure (prev + d)
  (evsRev, obs, tEnd) <- genWindow nRem
  -- fecho da janela
  tLeave <- stepT tEnd
  let evs1 = TimedEvent tLeave LeaveAbI : evsRev
  -- M_dec declarado?
  declare <- genBool 0.7
  (mDec, _matchByObs) <-
    if not declare
      then pure (Nothing, True)
      else do
        coherent <- genBool 0.55
        if coherent
          then pure (Just obs, True)
          else do
            -- perturba: acrescenta uma unidade de um SKU (mismatch garantido)
            sku <- genChoice skus
            pure (Just (Map.insertWith (+) sku 1 obs), False)
  -- pronunciamento explícito do agente?
  pronounce <- genBool 0.5
  evs2 <-
    if not pronounce
      then pure evs1  -- silêncio: o mes-bridge decide (se houver M_dec)
      else do
        -- às vezes pronuncia tarde (após T_dec) para exercitar A3
        late <- genBool 0.25
        let tP = if late then tLeave + cfgTdec defaultConfig + 500
                         else tLeave
        -- coerente com obs vs mDec quando declarado
        let ev = case mDec of
                   Just d | Map.toAscList d /= Map.toAscList obs -> DivI
                   _                                             -> MatchI
        pure (TimedEvent tP ev : evs1)
  pure (Case (reverse evs2) mDec)
  where
    -- gera as retiradas + classificações, devolvendo (eventos rev, M_obs, t)
    genWindow :: Int -> Gen ([TimedEvent], Multiset, Int)
    genWindow nRem = go nRem [TimedEvent 0 AbI] Map.empty 0
      where
        go 0 acc obs t = pure (acc, obs, t)
        go k acc obs t = do
          dt  <- genInt 200 2000
          let tr = t + dt
          -- classificação após a retirada?
          hasCls <- genBool 0.85
          if not hasCls
            then go (k - 1) (TimedEvent tr RemI : acc) obs tr
            else do
              sku  <- genChoice skus
              conf <- (\d -> 0.5 + d * 0.5) <$> genDouble  -- conf ∈ [0.5,1.0]
              dt2  <- genInt 100 600
              let tc  = tr + dt2
                  obs' = if conf >= tau then Map.insertWith (+) sku 1 obs else obs
                  acc' = TimedEvent tc (ClsPI sku conf) : TimedEvent tr RemI : acc
              go (k - 1) acc' obs' tc

-- ---------------------------------------------------------------------------
-- Execução do corpus
-- ---------------------------------------------------------------------------

data Row = Row
  { rIdx       :: !Int
  , rNEvents   :: !Int
  , rVerdict   :: !Verdict
  , rInfimo    :: !Verdict
  , rProp2     :: !Bool
  , rStatus    :: !MesStatus
  , rDiag      :: !(Maybe Diag)
  }

evalCase :: Int -> Case -> (Row, GateResult)
evalCase idx (Case evs mDec) =
  let res    = run defaultConfig mDec evs
      fs     = grFinalState res
      infimo = minimum [ A1.finalVerdict (csM1 fs)
                       , A2.finalVerdict (csM2 fs)
                       , A3.finalVerdict (csM3 fs) ]
      row = Row
        { rIdx     = idx
        , rNEvents = length (grSteps res)
        , rVerdict = grVerdict res
        , rInfimo  = infimo
        , rProp2   = grVerdict res == infimo
        , rStatus  = grStatus res
        , rDiag    = grDiag res
        }
  in (row, res)

nCases :: Int
nCases = 400

seed0 :: Word64
seed0 = 0x5DEECE66D  -- semente fixa (reprodutibilidade do artefato)

-- | Gera os @nCases@ casos com sementes derivadas determinísticamente.
genAll :: [Case]
genAll = go seed0 1
  where
    go _ i | i > nCases = []
    go s i =
      let (c, s') = runGen genCase s
      in c : go s' (i + 1)

main :: IO ()
main = do
  let dir       = "Files" </> "Corpus"
      traceDir  = dir </> "traces"
      cases     = genAll
      evaluated = zipWith evalCase [1 ..] cases
      rows      = map fst evaluated
  createDirectoryIfMissing True traceDir
  -- (1) escreve os 400 traços
  mapM_ (writeTrace traceDir) (zip3 [1 ..] cases rows)
  -- (2) CSV de resultados
  writeFile (dir </> "resultados.csv") (csv rows)
  -- (3) relatório
  writeFile (dir </> "RELATORIO.md") (relatorio rows)
  -- (4) sumário em stdout
  let ok = length (filter rProp2 rows)
  printf "Corpus gerado: %d traços em %s\n" nCases traceDir
  printf "Proposição 2 confirmada em %d/%d casos.\n" ok nCases
  printf "Resultados: %s  |  Relatório: %s\n"
    (dir </> "resultados.csv") (dir </> "RELATORIO.md")
  if ok == nCases
    then printf "OK — todos os casos satisfazem o veredito composto = ínfimo.\n"
    else printf "FALHA — %d casos violam a Proposição 2 (ver CSV).\n" (nCases - ok)

-- ---------------------------------------------------------------------------
-- Renderização
-- ---------------------------------------------------------------------------

writeTrace :: FilePath -> (Int, Case, Row) -> IO ()
writeTrace traceDir (i, Case evs mDec, row) =
  writeFile (traceDir </> printf "corpus_%03d.txt" i) (renderTrace i evs mDec row)

renderTrace :: Int -> [TimedEvent] -> Maybe Multiset -> Row -> String
renderTrace i evs mDec row = unlines $
  [ "---"
  , printf "cenario: \"Corpus aleatório — caso %03d (semente %s)\"" i (show seed0)
  ] ++
  mDecLine mDec ++
  [ "veredito_esperado: " ++ verdictTag (rVerdict row)
  , "status_esperado: " ++ showStatus (rStatus row)
  , "---"
  , "# Caso gerado por corpus-gen (PRNG determinístico). Veredito e status"
  , "# abaixo foram computados pelo próprio monitor (oráculo reproduzível)."
  ] ++ map renderEvent evs

mDecLine :: Maybe Multiset -> [String]
mDecLine Nothing  = []
mDecLine (Just m) =
  [ "m_dec: {" ++ intercalateStr ", "
      [ T.unpack k ++ ": " ++ show v | (k, v) <- Map.toAscList m ] ++ "}" ]

renderEvent :: TimedEvent -> String
renderEvent (TimedEvent t e) = printf "[t=%6d] %s" t (showEvent e)

verdictTag :: Verdict -> String
verdictTag Top          = "TOP"
verdictTag Bot          = "BOT"
verdictTag Inconclusive = "INCONCLUSIVE"

csv :: [Row] -> String
csv rows = unlines (header : map line rows)
  where
    header = "id,n_eventos,veredito_composto,infimo_componentes,prop2_ok,status_gate,diag"
    line r = intercalateStr ","
      [ printf "%03d" (rIdx r)
      , show (rNEvents r)
      , verdictTag (rVerdict r)
      , verdictTag (rInfimo r)
      , if rProp2 r then "OK" else "FALHA"
      , showStatus (rStatus r)
      , maybe "-" showDiag (rDiag r)
      ]

relatorio :: [Row] -> String
relatorio rows = unlines $
  [ "# Corpus aleatório — Proposição 2 (property-based testing materializado)"
  , ""
  , printf "Total de casos: **%d** (semente fixa `%s`, reproduzível por `cabal run corpus-gen`)." nCases (show seed0)
  , ""
  , printf "Proposição 2 (veredito composto = ínfimo de M₁⊗M₂⊗M₃) confirmada em **%d/%d** casos."
      (length (filter rProp2 rows)) nCases
  , ""
  , "## Distribuição por veredito composto"
  , ""
  , "| Veredito | Casos |"
  , "|----------|-------|"
  ] ++
  [ printf "| %s | %d |" (verdictTag v) (count (\r -> rVerdict r == v))
  | v <- [Top, Inconclusive, Bot] ] ++
  [ ""
  , "## Distribuição por status do gate (§5.4)"
  , ""
  , "| Status | Casos |"
  , "|--------|-------|"
  ] ++
  [ printf "| %s | %d |" (showStatus st) (count (\r -> rStatus r == st))
  | st <- [LiberadoIntegracao, DivergenciaPcp, ErroClassificacao, ErroDecisao, PendenteVerificacao]
  , count (\r -> rStatus r == st) > 0 ] ++
  [ ""
  , "## Como reproduzir"
  , ""
  , "```sh"
  , "cabal run corpus-gen      # regenera Files/Corpus/ de forma idêntica"
  , "```"
  , ""
  , "Os 400 traços em `traces/` são re-executáveis pelo CLI:"
  , ""
  , "```sh"
  , "lab-monitor Files/Corpus/traces/corpus_001.txt"
  , "```"
  ]
  where
    count p = length (filter p rows)

intercalateStr :: String -> [String] -> String
intercalateStr _   []     = ""
intercalateStr _   [x]    = x
intercalateStr sep (x:xs) = x ++ sep ++ intercalateStr sep xs
