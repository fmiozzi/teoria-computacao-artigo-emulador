{-# LANGUAGE OverloadedStrings #-}

-- | Tipos centrais do monitor LTL/TLTL — alinhados ao artigo v2_3.
--
-- 'Event' corresponde ao conjunto de proposições atômicas AP do artigo
-- (§3.2). 'Verdict' implementa a semântica LTL₃ de Bauer, Leucker e
-- Schallhart (2011): o reticulado ⊥ < ? < ⊤ que sustenta o ínfimo da
-- Proposição 2 (composição).
--
-- 'MesStatus' e 'Diag' materializam o /gate/ MES↔ERP (§5.4, Algoritmo 1,
-- Figura 9, Tabelas 3 e 4): o efetor roteia cada modo de falha a um
-- status terminal distinto, anexando o diagnóstico de causa-raiz
-- auditável.
--
-- 'Config' agrega os parâmetros temporais (T_cls, T_dec, δ_mb) e o limiar
-- de A5 (τ). Os parâmetros das extensões prospectivas (§6) — T_pcp (A4),
-- T_h (A6), T_rej (A7), T_ab_max (A8) — residem aqui apenas para os
-- módulos isolados de prova de conceito; não fazem parte do monitor
-- verificado M = M₁ ⊗ M₂ ⊗ M₃.
module Monitor.Types
  ( -- * Eventos (AP do artigo, §3.2)
    Event (..)
  , showEvent
  , isAP
  , TimedEvent (..)
  , Clock
    -- * Veredito LTL₃
  , Verdict (..)
  , showVerdict
  , parseVerdict
    -- * Gate MES↔ERP (§5.4)
  , MesStatus (..)
  , showStatus
  , parseStatus
  , statusEscala
  , Diag (..)
  , showDiag
    -- * Configuração
  , Config (..)
  , defaultConfig
  , anchorCatalog
  ) where

import qualified Data.Text as T

-- | Eventos atômicos produzidos pelo agente de visão e pelo mes-bridge.
--
-- O conjunto AP do artigo v2_3 (§3.2) é
--
-- @
--   AP = { ab_i, leave_ab_i, match_i, div_i : i ∈ B }
--      ∪ { rem_{i,j}, cls_{p,i,j} : i ∈ B, j ∈ M, p ∈ P }
-- @
--
-- div_i é um /macro-evento derivado/ (§3.4), materializado pelo mes-bridge
-- como @div_i := mismatch_i ∨ fora_ciclo_i@; seus dois sub-eventos não
-- pertencem a AP. 'AbI' e 'LeaveAbI' são os eventos de borda da janela de
-- abastecimento; a proposição @ab_i@ é verdadeira no intervalo entre eles.
--
-- Os construtores 'EscPcpI', 'Heartbeat' e 'RejI' /não/ pertencem a AP:
-- são proposições das extensões prospectivas (§6) A4 (escalonamento ao
-- PCP), A6 (heartbeat) e A7 (refugo), implementadas apenas nos módulos
-- isolados @Monitor.Automata.A4/A6/A7@, fora do monitor verificado.
data Event
  = -- AP do artigo v2_3 (§3.2)
    AbI                  -- ^ ab_i: braço entrou na janela de abastecimento
  | RemI                 -- ^ rem_{i,j}: peça retirada do molde j
  | LeaveAbI             -- ^ leave_ab_i: fim da janela de abastecimento
  | MatchI               -- ^ match_i: M_obs = M_dec (pronunciado pelo mes-bridge)
  | DivI                 -- ^ div_i: macro-evento derivado (mismatch ∨ fora_ciclo)
  | ClsPI T.Text Double  -- ^ cls_{p,i,j}: classificação (SKU + confiança)
    -- Proposições FORA de AP (extensões prospectivas §6)
  | EscPcpI              -- ^ esc_pcp_i: escalação ao PCP (A4, prospectiva)
  | Heartbeat            -- ^ heartbeat_i: sinal de vida do agente (A6, prospectiva)
  | RejI                 -- ^ rej_i: peça marcada como refugo (A7, prospectiva)
  deriving (Eq, Show)

-- | 'True' sse o evento pertence ao conjunto AP do artigo v2_3 (§3.2).
-- Falso para as proposições das extensões prospectivas (esc_pcp/heartbeat/rej).
isAP :: Event -> Bool
isAP EscPcpI   = False
isAP Heartbeat = False
isAP RejI      = False
isAP _         = True

-- | Relógio do monitor temporizado, em milissegundos desde o início do
-- traço. Usado pelas guardas dos autômatos TLTL (A2, A3).
type Clock = Int

-- | Evento com timestamp em milissegundos desde t=0.
--
-- O regime temporal do cenário-âncora (§3.1) tem o stream de visão a
-- 500 ms e prazos T_cls = 1500 ms / T_dec = 1700 ms. Os traços de exemplo
-- trazem timestamps explícitos; quando ausentes, o parser atribui um
-- tempo implícito (ver 'Monitor.Parser').
data TimedEvent = TimedEvent
  { teTime  :: !Int    -- ^ ms desde t=0
  , teEvent :: !Event
  } deriving (Eq, Show)

-- | Veredito LTL₃ (Bauer, Leucker, Schallhart 2011).
-- Ordem do reticulado: 'Bot' < 'Inconclusive' < 'Top'.
--
-- Para os componentes A1, A2' e A3' (safety não-co-safety, §5.3), o
-- veredito ⊤ /não/ é alcançável sobre prefixo finito: o domínio efetivo
-- de cada sub-monitor no /stream/ é {⊥, ?}. O ⊤ surge apenas no veredito
-- /terminal/, quando o prefixo encerra sem obrigação pendente.
data Verdict = Bot | Inconclusive | Top
  deriving (Eq, Ord, Show)

-- | Status terminal do apontamento de produção no ciclo de vida do MES
-- (§5.4, Figura 9, Tabela 4). O efetor (gate) transita o apontamento de
-- @pendente_verificacao@ para um destes estados, roteando cada modo de
-- falha à área responsável.
data MesStatus
  = PendenteVerificacao   -- ^ estado transitório (sede do gate); ainda sem decisão
  | LiberadoIntegracao    -- ^ ⊤: match_i dentro de T_dec, sem violação → integração MES→ERP
  | DivergenciaPcp        -- ^ div_i (mismatch ∨ fora_ciclo) → tratativa manual no PCP
  | ErroClassificacao     -- ^ sumidouro de M₂ (A2): classificação ausente em T_cls → time de visão
  | ErroDecisao           -- ^ sumidouro de M₃ (A3): mes-bridge mudo em T_dec → TI
  deriving (Eq, Show)

-- | Diagnóstico de causa-raiz auditável anexado pelo gate ao bloquear
-- (§5.4, Algoritmo 1). Identifica /qual fonte/ disparou a transição.
data Diag
  = SafetyA1        -- ^ violação de safety de A1 (rem fora da janela), capturada como fora_ciclo
  | Mismatch        -- ^ M_obs ≠ M_dec (divergência de multiconjunto)
  | ForaCiclo       -- ^ exceção estrutural do ciclo operacional
  | TimeoutCls      -- ^ expiração de T_cls sem classificação válida (sumidouro de M₂)
  | LeaveAbSilent   -- ^ expiração de T_dec sem pronunciamento (sumidouro de M₃)
  deriving (Eq, Show)

-- | Parâmetros do monitor (defaults por 'defaultConfig').
--
-- Os três primeiros campos e 'cfgTau' parametrizam o monitor verificado
-- (A1–A3 + filtro A5). Os demais (T_pcp/T_h/T_rej/T_ab_max) pertencem às
-- extensões prospectivas (§6) e só são consumidos pelos módulos isolados.
data Config = Config
  { cfgTcls    :: Int       -- ^ T_cls (ms): latência máxima de classificação (A2)
  , cfgTdec    :: Int       -- ^ T_dec (ms): prazo de decisão do mes-bridge (A3); T_dec = T_cls + ε
  , cfgDeltaMb :: Int       -- ^ δ_mb (ms): latência de comparação do mes-bridge; δ_mb ≤ T_dec − T_cls
  , cfgTau     :: Double    -- ^ τ: limiar de confiança da CNN (A5)
    -- Parâmetros das extensões prospectivas (§6) — fora do monitor verificado
  , cfgTpcp    :: Int       -- ^ T_pcp (ms): prazo de escalação ao PCP (A4, prospectiva)
  , cfgTh      :: Int       -- ^ T_h (ms): período máximo entre heartbeats (A6, prospectiva)
  , cfgTrej    :: Int       -- ^ T_rej (ms): janela em que rej_i pode se referir a cls (A7, prospectiva)
  , cfgTabMax  :: Int       -- ^ T_ab_max (ms): duração máxima da janela (A8, prospectiva)
  } deriving (Eq, Show)

-- | Defaults do cenário-âncora do artigo (§4): rotomoldagem, ciclo ~90 s,
-- janela ~60 s. Valores típicos: T_cls = 1500 ms, ε = 200 ms,
-- T_dec = T_cls + ε = 1700 ms. δ_mb (latência do mes-bridge) ≤ ε = 200 ms;
-- adotamos 100 ms.
defaultConfig :: Config
defaultConfig = Config
  { cfgTcls    = 1500       -- 1,5 s (§4)
  , cfgTdec    = 1700       -- T_cls + ε, com ε = 200 ms (§4)
  , cfgDeltaMb = 100        -- ≤ ε = T_dec − T_cls = 200 ms (§3.4)
  , cfgTau     = 0.85
    -- prospectivos (§6)
  , cfgTpcp    = 300000     -- 5 min (A4, ilustrativo — o artigo não fixa T_pcp)
  , cfgTh      = 5000       -- 5 s   (A6)
  , cfgTrej    = 10000      -- 10 s  (A7)
  , cfgTabMax  = 90000      -- ~ciclo da máquina (A8)
  }

-- | Catálogo de SKUs do cenário-âncora (Figura 12 do artigo): caixas e
-- tampas de 500/1000 L e os respectivos moldes vazios/abastecido,
-- classificados por um MobileNetV3-Small. Usado pelos traços de exemplo e
-- pelo gerador do corpus aleatório.
anchorCatalog :: [T.Text]
anchorCatalog =
  [ "caixa_500L"
  , "caixa_1000L"
  , "tampa_1000L"
  , "molde_caixa_500L_vazio"
  , "molde_caixa_1000L_vazio"
  , "molde_tampa_500L_vazio"
  , "molde_tampa_1000L_abastecido"
  ]

-- | Inverso parcial de 'showVerdict' para tokens do cabeçalho YAML
-- (case-insensitive). Aceita: @TOP@/@T@/@ACEITA@/@⊤@, @BOT@/@F@/@VIOLA@/@⊥@,
-- @INCONCLUSIVE@/@?@. Útil para o campo @veredito_esperado@.
parseVerdict :: String -> Either String Verdict
parseVerdict s = case map toUpper (trim s) of
  "TOP"          -> Right Top
  "T"            -> Right Top
  "ACEITA"       -> Right Top
  "⊤"            -> Right Top
  "BOT"          -> Right Bot
  "F"            -> Right Bot
  "VIOLA"        -> Right Bot
  "⊥"            -> Right Bot
  "INCONCLUSIVE" -> Right Inconclusive
  "?"            -> Right Inconclusive
  other          -> Left ("veredito desconhecido: " ++ other)
  where
    toUpper c | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
              | otherwise            = c
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse

-- | Renderização canônica LTL₃ (símbolo + nome), sem variações regionais
-- e sem o sufixo booleano @(T)@/@(F)@ — ⊤/⊥ não são "true/false" em LTL₃.
showVerdict :: Verdict -> String
showVerdict Top          = "⊤  (Top — Aceita)"
showVerdict Bot          = "⊥  (Bot — Viola)"
showVerdict Inconclusive = "?  (Inconclusive)"

showEvent :: Event -> String
showEvent AbI         = "ab_i"
showEvent RemI        = "rem_i"
showEvent LeaveAbI    = "leave_ab_i"
showEvent MatchI      = "match_i"
showEvent DivI        = "div_i"
showEvent EscPcpI     = "esc_pcp_i"
showEvent Heartbeat   = "heartbeat"
showEvent RejI        = "rej_i"
showEvent (ClsPI s c) = "cls_p_i " ++ T.unpack s ++ " " ++ show c

-- | Nome canônico do status terminal do MES (igual ao identificador do
-- artigo, §5.4).
showStatus :: MesStatus -> String
showStatus PendenteVerificacao = "pendente_verificacao"
showStatus LiberadoIntegracao  = "liberado_integracao"
showStatus DivergenciaPcp      = "divergencia_pcp"
showStatus ErroClassificacao   = "erro_classificacao"
showStatus ErroDecisao         = "erro_decisao"

-- | Inverso parcial de 'showStatus' para o campo @status_esperado@ do
-- cabeçalho YAML (case-insensitive nos identificadores do artigo, §5.4).
parseStatus :: String -> Either String MesStatus
parseStatus s = case map toLower (trim s) of
  "liberado_integracao"  -> Right LiberadoIntegracao
  "divergencia_pcp"      -> Right DivergenciaPcp
  "erro_classificacao"   -> Right ErroClassificacao
  "erro_decisao"         -> Right ErroDecisao
  "pendente_verificacao" -> Right PendenteVerificacao
  other                  -> Left ("status desconhecido: " ++ other)
  where
    toLower c | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
              | otherwise            = c
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse

-- | Área para a qual o efetor escala o apontamento, por status (§5.4).
statusEscala :: MesStatus -> String
statusEscala PendenteVerificacao = "—"
statusEscala LiberadoIntegracao  = "integração nativa MES→ERP"
statusEscala DivergenciaPcp      = "PCP (Planejamento e Controle da Produção)"
statusEscala ErroClassificacao   = "time de visão computacional"
statusEscala ErroDecisao         = "TI (Tecnologia da Informação)"

-- | Nome canônico do diagnóstico de causa-raiz (§5.4, Algoritmo 1).
showDiag :: Diag -> String
showDiag SafetyA1      = "safety_A1"
showDiag Mismatch      = "mismatch"
showDiag ForaCiclo     = "fora_ciclo"
showDiag TimeoutCls    = "timeout_cls"
showDiag LeaveAbSilent = "leave_ab_silent"
