{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Monitor.Gate
Description : Efetor (gate MES↔ERP) — laço de monitoramento online (Algoritmo 1).
Copyright   : (c) Flávio Miozzi Batista, 2026
License     : ver LICENSE
Maintainer  : fmiozzi@gmail.com
Stability   : experimental

Bloco arquitetural na figura de arquitetura do artigo: "Gate MES↔ERP
(decisão em tempo real)". Referência canônica: Algoritmo 1
(@alg-monitor-online@, §5.4) e Figura 9 (fluxograma do gate).

Este módulo é o /efetor/: consome, evento a evento, o produto sincronizado
@M = M₁ ⊗ M₂ ⊗ M₃@ ("Monitor.Composed") e o fluxo enriquecido pelo
mes-bridge ("Monitor.MesBridge"), e transita o apontamento de produção do
estado @pendente_verificacao@ a UM dos quatro status terminais (§5.4,
Tabela 4), anexando o diagnóstico de causa-raiz auditável:

  * 'LiberadoIntegracao'  — match_i dentro de T_dec, sem violação: prossegue à
    integração nativa MES→ERP;
  * 'DivergenciaPcp'      — div_i (mismatch ∨ fora_ciclo) ou violação de safety
    de A1 (diag @safety_A1@): tratativa manual no PCP;
  * 'ErroClassificacao'   — sumidouro de M₂ (timeout_cls): classificação ausente
    em T_cls, escala ao time de visão;
  * 'ErroDecisao'         — sumidouro de M₃ (leave_ab_silent): mes-bridge mudo em
    T_dec, escala à TI.

A ordem de prioridade entre os modos de falha segue exatamente o
Algoritmo 1 (sinkM1 → sinkM2 → sinkM3 → div → match). Crucialmente,
@div_i@ é uma /decisão de processo/ (a obrigação de A3 foi cumprida por um
pronunciamento), não uma violação de propriedade: o veredito composto pode
ser ⊤ enquanto o gate roteia o apontamento a @divergencia_pcp@.
-}
module Monitor.Gate
  ( -- * Traço passo a passo
    Step (..)
    -- * Resultado do gate
  , GateResult (..)
  , run
    -- * Decisão pura (Algoritmo 1, roteamento de status)
  , decide
  ) where

import qualified Monitor.Automata.A1    as A1
import qualified Monitor.Automata.A2    as A2
import qualified Monitor.Automata.A3    as A3
import qualified Monitor.Composed       as C
import           Monitor.Composed       (ComposedState (..))
import           Monitor.Classification (isValidCls)
import qualified Monitor.MesBridge      as MB
import           Monitor.MesBridge      (Pronouncement (..), StructuralCtx (..))
import qualified Monitor.Multiset       as MS
import           Monitor.Multiset       (Multiset)
import           Monitor.Types          ( Config (..)
                                        , Diag (..)
                                        , Event (..)
                                        , MesStatus (..)
                                        , TimedEvent (..)
                                        , Verdict (..)
                                        )

-- ---------------------------------------------------------------------------
-- Traço passo a passo
-- ---------------------------------------------------------------------------

-- | Um passo da execução do monitor composto sobre o fluxo /enriquecido/
-- (i.e., já com os pronunciamentos do mes-bridge injetados).
data Step = Step
  { stepIdx     :: !Int            -- ^ índice 1-based no fluxo enriquecido
  , stepTime    :: !Int            -- ^ instante do evento (ms desde t=0)
  , stepEvent   :: !Event          -- ^ evento processado
  , stepState   :: !ComposedState  -- ^ estado do produto após o passo
  , stepVerdict :: !Verdict        -- ^ veredito de stream (ínfimo, domínio {⊥, ?})
  , stepRules   :: ![String]       -- ^ componentes em ⊥ neste passo
  } deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Resultado do gate
-- ---------------------------------------------------------------------------

-- | Saída completa do laço de monitoramento online (Algoritmo 1).
data GateResult = GateResult
  { grSteps      :: ![Step]            -- ^ processamento evento a evento (fluxo enriquecido)
  , grVerdict    :: !Verdict           -- ^ veredito composto /terminal/ (Proposição 2; ∈ {⊥, ⊤})
  , grStatus     :: !MesStatus         -- ^ status terminal do apontamento (§5.4)
  , grDiag       :: !(Maybe Diag)      -- ^ diagnóstico de causa-raiz ('Nothing' sse liberado)
  , grRules      :: ![String]          -- ^ componentes formais violados (terminal)
  , grFirstViol  :: !(Maybe Int)       -- ^ índice 1-based da primeira violação de stream
  , grDivAt      :: !(Maybe Int)       -- ^ índice do passo em que @div_i@ se materializou
  , grFinalState :: !ComposedState     -- ^ estado final do produto
  } deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Execução (Algoritmo 1)
-- ---------------------------------------------------------------------------

-- | Laço de monitoramento online do gate (Algoritmo 1). Recebe a
-- configuração, o multiconjunto declarado @M_dec@ (do apontamento, quando
-- presente no cabeçalho) e o traço de eventos AP em ordem cronológica.
--
-- Passos (cf. Algoritmo 1): (i) o mes-bridge enriquece o fluxo, injetando o
-- pronunciamento de coerência (@match_i@/@div_i@) em @τ_b + T_cls + δ_mb@
-- sobre a janela @[τ_a, τ_b + T_cls]@ e @div_i@ (@fora_ciclo@) em exceções
-- estruturais; (ii) o produto @M₁ ⊗ M₂ ⊗ M₃@ é atualizado por @δ@; (iii) o
-- efetor roteia o status conforme o componente que detecta a falha.
run :: Config -> Maybe Multiset -> [TimedEvent] -> GateResult
run cfg mDec events =
  let enriched   = enrich cfg mDec events
      steps      = scan cfg (map fst enriched)
      finalState = if null steps then C.initial cfg else stepState (last steps)
      -- div materializado: primeiro evento div_i no fluxo enriquecido (e seu diag)
      divInfo    = firstDiv enriched
      divAt      = fst <$> divInfo
      divDiag    = snd =<< divInfo
      (status, diag) = decide finalState (divAt /= Nothing) divDiag
  in GateResult
       { grSteps      = steps
       , grVerdict    = C.finalVerdict finalState
       , grStatus     = status
       , grDiag       = diag
       , grRules      = C.finalViolatingRules finalState
       , grFirstViol  = firstViolationIdx steps
       , grDivAt      = divAt
       , grFinalState = finalState
       }

-- | Roteamento de status do Algoritmo 1 (linhas 24–39), na ordem de
-- prioridade normativa: sumidouro de M₁ → M₂ → M₃ → @div_i@ → @match_i@.
--
-- O sumidouro de cada componente é detectado via 'A1.finalVerdict' etc.,
-- que captura tanto a expiração de relógio /durante/ o stream quanto a
-- obrigação pendente ao /fim/ do traço (leitura estrita de @F_{[0,T]}@).
decide :: ComposedState -> Bool -> Maybe Diag -> (MesStatus, Maybe Diag)
decide s divMaterialized divDiag
  | A1.finalVerdict (csM1 s) == Bot = (DivergenciaPcp,    Just SafetyA1)
  | A2.finalVerdict (csM2 s) == Bot = (ErroClassificacao, Just TimeoutCls)
  | A3.finalVerdict (csM3 s) == Bot = (ErroDecisao,       Just LeaveAbSilent)
  | divMaterialized                 = (DivergenciaPcp,    Just (maybe Mismatch id divDiag))
  | otherwise                       = (LiberadoIntegracao, Nothing)

-- ---------------------------------------------------------------------------
-- Varredura do produto sincronizado
-- ---------------------------------------------------------------------------

-- | Aplica o produto @M₁ ⊗ M₂ ⊗ M₃@ evento a evento, materializando o
-- traço passo a passo.
scan :: Config -> [TimedEvent] -> [Step]
scan cfg = go 1 (C.initial cfg)
  where
    go _ _ [] = []
    go i s (te : tes) =
      let s'  = C.step s te
          stp = Step i (teTime te) (teEvent te) s' (C.verdict s') (C.violatingRules s')
      in stp : go (i + 1) s' tes

-- | Índice 1-based do primeiro passo em que o veredito de stream passa a ⊥.
firstViolationIdx :: [Step] -> Maybe Int
firstViolationIdx = gov Top
  where
    gov _    [] = Nothing
    gov prev (st : rest)
      | stepVerdict st == Bot && prev /= Bot = Just (stepIdx st)
      | otherwise                            = gov (stepVerdict st) rest

-- | Primeiro @div_i@ no fluxo enriquecido: índice 1-based e diagnóstico
-- (mismatch ∨ fora_ciclo). Um @div_i@ explícito do traço (sem etiqueta) é
-- tratado como divergência de multiconjunto ('Mismatch').
firstDiv :: [(TimedEvent, Maybe Diag)] -> Maybe (Int, Maybe Diag)
firstDiv = goD 1
  where
    goD _ [] = Nothing
    goD i ((te, tag) : rest)
      | teEvent te == DivI = Just (i, Just (maybe Mismatch id tag))
      | otherwise          = goD (i + 1) rest

-- ---------------------------------------------------------------------------
-- Mes-bridge: enriquecimento do fluxo (§3.4)
-- ---------------------------------------------------------------------------

-- | Estado interno do enriquecimento.
data EnrichSt = EnrichSt
  { esObs        :: !Multiset        -- ^ M_obs (cls^{≥τ}) da janela corrente
  , esTb         :: !(Maybe Int)     -- ^ τ_b da janela pendente (leave_ab visto, sem pronunciamento)
  , esPronounced :: !Bool            -- ^ o traço já pronunciou (match/div) na janela pendente?
  , esCtx        :: !StructuralCtx   -- ^ contexto do detector de exceções estruturais
  }

initEnrich :: EnrichSt
initEnrich = EnrichSt MS.empty Nothing False (StructuralCtx False False)

-- | Enriquecimento do fluxo pelo mes-bridge (§3.4 do artigo). Produz a
-- sequência cronológica de eventos com os pronunciamentos sintéticos
-- injetados, cada injeção etiquetada com seu diagnóstico ('Just'):
--
--   * pronunciamento de coerência em @τ_b + T_cls + δ_mb@: 'match_i'
--     (M_obs[τ_a, τ_b+T_cls] = M_dec) ou 'div_i' por @mismatch@ (diferença);
--   * 'div_i' por @fora_ciclo@ ao detectar exceção estrutural do ciclo.
--
-- O pronunciamento de coerência só é injetado quando há @M_dec@ declarado e
-- o traço /não/ pronuncia explicitamente na janela (caminho legado: o traço
-- prevalece). A detecção de exceções estruturais ocorre independentemente.
enrich :: Config -> Maybe Multiset -> [TimedEvent] -> [(TimedEvent, Maybe Diag)]
enrich cfg mDec = go initEnrich
  where
    tau  = cfgTau cfg
    tcls = cfgTcls cfg
    dmb  = cfgDeltaMb cfg

    -- instante do pronunciamento de coerência da janela com fecho em tb
    emitAt tb = tb + tcls + dmb

    -- constrói o pronunciamento de coerência a partir de M_obs vs M_dec
    coherence obs dec tb =
      let te = TimedEvent (emitAt tb) ev
          (ev, tag) = case MB.pronounce obs dec of
            PMatch    -> (MatchI, Nothing)
            PMismatch -> (DivI, Just Mismatch)
      in (te, tag)

    -- flush do pronunciamento pendente (quando há M_dec e o traço calou)
    flush st = case (esTb st, mDec) of
      (Just tb, Just dec) | not (esPronounced st) -> [coherence (esObs st) dec tb]
      _                                           -> []

    go st [] = flush st
    go st (te : rest) =
      let now = teTime te
          evt = teEvent te
          ctx = esCtx st

          -- (1) há pronunciamento pendente cujo instante já passou? injeta antes de `te`.
          (preInj, st1) = case (esTb st, mDec) of
            (Just tb, Just dec)
              | now > emitAt tb ->
                  ( if esPronounced st then [] else [coherence (esObs st) dec tb]
                  , st { esTb = Nothing } )
            _ -> ([], st)

          -- (2) exceção estrutural disparada por `te`? injeta div_i (fora_ciclo) antes de `te`.
          structInj = case MB.structuralException ctx evt of
            Just d  -> [(TimedEvent now DivI, Just d)]
            Nothing -> []

          -- (3) atualização do estado de enriquecimento conforme `te`
          st2 = stepEnrich st1 now evt

      in preInj ++ structInj ++ [(te, Nothing)] ++ go st2 rest

    -- transição do estado de enriquecimento
    stepEnrich st now evt = case evt of
      AbI ->
        st { esObs        = MS.empty
           , esTb         = Nothing
           , esPronounced = False
           , esCtx        = StructuralCtx True False
           }
      LeaveAbI ->
        st { esTb         = case mDec of Just _ -> Just now; Nothing -> Nothing
           , esPronounced = False
           , esCtx        = StructuralCtx False True
           }
      MatchI -> markPronounced st
      DivI   -> markPronounced st
      ClsPI sku _
        | isValidCls tau evt && withinWindow st now ->
            st { esObs = MS.addCls sku (esObs st) }
        | otherwise -> st
      _ -> st

    -- cls residual conta para M_obs sse ainda dentro de [τ_a, τ_b+T_cls]
    withinWindow st now = case esTb st of
      Just tb -> now <= tb + tcls
      Nothing -> True

    markPronounced st = case esTb st of
      Just _  -> st { esPronounced = True }
      Nothing -> st
