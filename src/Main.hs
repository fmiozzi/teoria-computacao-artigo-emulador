{-# LANGUAGE OverloadedStrings #-}

-- ============================================================================
-- Lab Monitor — Peça 1: Monitor LTL para a propriedade A1 (safety)
--
--   A1:  G(rem_i → ab_i)
--   "Toda retirada de peça deve ocorrer dentro da janela de abastecimento."
--
-- O monitor é um AFD de 2 estados (Figura 3 do artigo):
--
--             ¬rem_i ∨ ab_i              ⊤
--               ┌──┐                   ┌──┐
--               ▼  │                   ▼  │
--              ╭───╮   rem_i ∧ ¬ab_i  ╭────╮
--          ──▶ │ q0│ ─────────────▶  │ q⊥ │
--              ╰───╯                  ╰────╯
--           aceitante              sumidouro
--
-- Entrada : arquivo de texto com um evento por linha.
-- Saída   : veredito (ACEITA / VIOLA) + posição da violação, se houver.
-- ============================================================================

module Main where

import qualified Data.Text     as T
import qualified Data.Text.IO  as TIO
import           System.Environment (getArgs)
import           System.Exit        (ExitCode (..), exitWith)
import           System.IO          (hPutStrLn, stderr)

-- ============================================================================
-- 1. Tipos
-- ============================================================================

-- | Eventos atômicos emitidos pelo agente de visão. Correspondem ao
--   conjunto AP do artigo (§3.2).
--
--   Observação: tratamos 'AbI' e 'LeaveAbI' como eventos de borda — eles
--   marcam, respectivamente, o início e o fim do período em que a proposição
--   ab_i é verdadeira. Entre esses dois eventos, mantemos um flag interno
--   ('msAbActive') que indica se a proposição ab_i está atualmente válida.
data Event
  = AbI                  -- ^ ab_i:       braço entrou na janela de abastecimento
  | RemI                 -- ^ rem_i:      peça retirada
  | LeaveAbI             -- ^ leave_ab_i: fim da janela
  | MatchI               -- ^ match_i:    M_obs = M_dec
  | DivI                 -- ^ div_i:      M_obs ≠ M_dec
  | EscPcpI              -- ^ esc_pcp_i:  escalação ao PCP
  | ClsPI T.Text Double  -- ^ cls_{p,i}:  classificação (SKU + confiança)
  | Heartbeat            -- ^ heartbeat:  sinal de vida do agente
  deriving (Eq, Show)

-- | Veredito LTL_3 (Bauer, Leucker, Schallhart 2011).
--   Ordem do reticulado: Bot < Inconclusive < Top  (necessária para o
--   ínfimo da Proposição 2 — útil já a partir da peça 5).
data Verdict = Bot | Inconclusive | Top
  deriving (Eq, Ord, Show)

-- | Estado do autômato M1 (Figura 3 do artigo).
data M1State = M1Ok | M1Violated
  deriving (Eq, Show)

-- | Estado completo do monitor: o autômato M1 + contexto (ab_i ativo?).
data MonitorState = MonitorState
  { msM1       :: M1State
  , msAbActive :: Bool
  } deriving (Eq, Show)

initialState :: MonitorState
initialState = MonitorState M1Ok False

-- ============================================================================
-- 2. Função de transição do monitor
-- ============================================================================

-- | Aplica um evento ao estado do monitor.
--   Esta é a função δ do autômato M1, estendida com a manutenção do flag
--   'msAbActive' que materializa a proposição ab_i ao longo do tempo.
step :: MonitorState -> Event -> MonitorState
step s evt = case msM1 s of
  -- Sumidouro absorvente: nada reabilita a aceitação.
  M1Violated -> s

  M1Ok -> case evt of
    AbI       -> s { msAbActive = True  }
    LeaveAbI  -> s { msAbActive = False }
    RemI
      | msAbActive s -> s                              -- dentro da janela: OK
      | otherwise    -> s { msM1 = M1Violated }        -- fora da janela: viola A1
    _         -> s                                     -- demais eventos não afetam A1

-- | Veredito de M1 sobre o estado corrente.
verdictM1 :: M1State -> Verdict
verdictM1 M1Ok       = Top
verdictM1 M1Violated = Bot

-- ============================================================================
-- 3. Execução sobre um traço
-- ============================================================================

-- | Roda o monitor evento a evento. Retorna o veredito final e, em caso
--   de violação, a posição (1-indexed) e o evento ofensor.
runMonitor :: [Event] -> (Verdict, Maybe (Int, Event))
runMonitor = go 1 initialState
  where
    go _ s [] = (verdictM1 (msM1 s), Nothing)
    go i s (e:es) =
      let s' = step s e
      in if msM1 s' == M1Violated && msM1 s == M1Ok
           then (Bot, Just (i, e))
           else go (i + 1) s' es

-- ============================================================================
-- 4. Parser do arquivo de traço
-- ============================================================================

-- | Formato:
--   - uma linha por evento;
--   - linhas iniciadas com '#' são comentários;
--   - linhas vazias são ignoradas.
--
--   Sintaxe dos eventos:
--     ab_i
--     rem_i
--     leave_ab_i
--     match_i
--     div_i
--     esc_pcp_i
--     heartbeat
--     cls_p_i <sku> <confiança>
parseEvent :: T.Text -> Either String Event
parseEvent line = case T.words line of
  ["ab_i"]               -> Right AbI
  ["rem_i"]              -> Right RemI
  ["leave_ab_i"]         -> Right LeaveAbI
  ["match_i"]            -> Right MatchI
  ["div_i"]              -> Right DivI
  ["esc_pcp_i"]          -> Right EscPcpI
  ["heartbeat"]          -> Right Heartbeat
  ["cls_p_i", sku, conf] -> case reads (T.unpack conf) :: [(Double, String)] of
    [(c, "")] -> Right (ClsPI sku c)
    _         -> Left ("confiança inválida: " <> T.unpack conf)
  ws -> Left ("evento desconhecido: " <> T.unpack (T.unwords ws))

parseTrace :: T.Text -> Either String [Event]
parseTrace =
    traverse parseEvent
  . filter isEventLine
  . map T.strip
  . T.lines
  where
    isEventLine line = not (T.null line) && not ("#" `T.isPrefixOf` line)

-- ============================================================================
-- 5. Entrada principal
-- ============================================================================

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
  case parseTrace content of
    Left err -> do
      hPutStrLn stderr ("Erro ao parsear traço: " ++ err)
      exitWith (ExitFailure 1)
    Right events -> do
      let (verdict, violation) = runMonitor events
      putStrLn ""
      putStrLn $ "Arquivo  : " ++ filepath
      putStrLn $ "Eventos  : " ++ show (length events)
      putStrLn $ "Veredito : " ++ showVerdict verdict
      case violation of
        Just (i, e) -> do
          putStrLn $ "Violacao no evento #" ++ show i ++ ": " ++ showEvent e
          putStrLn   "Regra violada: A1  --  G(rem_i -> ab_i)"
          putStrLn   "(rem_i ocorreu fora da janela de abastecimento)"
          exitWith (ExitFailure 2)
        Nothing -> exitWith ExitSuccess

showVerdict :: Verdict -> String
showVerdict Top          = "ACEITA (T)"
showVerdict Bot          = "VIOLA  (F)"
showVerdict Inconclusive = "INCONCLUSIVO (?)"

showEvent :: Event -> String
showEvent AbI         = "ab_i"
showEvent RemI        = "rem_i"
showEvent LeaveAbI    = "leave_ab_i"
showEvent MatchI      = "match_i"
showEvent DivI        = "div_i"
showEvent EscPcpI     = "esc_pcp_i"
showEvent Heartbeat   = "heartbeat"
showEvent (ClsPI s c) = "cls_p_i " ++ T.unpack s ++ " " ++ show c
