{-# LANGUAGE OverloadedStrings #-}

-- | Produto sincronizado dos autômatos de monitoramento — o monitor
-- composto @M = M₁ ⊗ M₂ ⊗ M₃@ do artigo v2_3 (§5.2).
--
-- São TRÊS componentes (A1 safety, A2′ e A3′ bounded liveness). A
-- propriedade A4 (escalonamento ao PCP) é extensão prospectiva (§6) e
-- /não/ integra o produto — a escalada ao PCP é ação determinística do
-- gate (§5.4), não obrigação verificada por autômato.
--
-- O veredito composto é o ínfimo dos vereditos individuais no reticulado
-- ⊥ < ? < ⊤ (Proposição 2). Como ⊥ é absorvente em cada componente, basta
-- o autômato mais pessimista para determinar o veredito composto. O
-- /stream/ opera em {⊥, ?} e o /terminal/ em {⊥, ⊤} (§5.3).
--
-- Este módulo é puramente o produto declarativo: ele NÃO fabrica match/div
-- (papel do mes-bridge) nem promove sumidouros a status (papel do gate,
-- "Monitor.Gate"). O macro-evento derivado div_i (§3.4) é consumido por M₃
-- como qualquer outra letra.
module Monitor.Composed
  ( -- * Estado
    ComposedState (..)
  , initial
  , step
    -- * Vereditos (Proposição 2: ínfimo)
  , verdict
  , finalVerdict
  , violatingRules
  , finalViolatingRules
    -- * Sumidouros por componente (consumidos pelo gate)
  , sinkM1
  , sinkM2
  , sinkM3
  , summary
  ) where

import qualified Monitor.Automata.A1 as A1
import qualified Monitor.Automata.A2 as A2
import qualified Monitor.Automata.A3 as A3
import           Monitor.Classification (isValidCls)
import qualified Monitor.Multiset    as MS
import           Monitor.Multiset    (Multiset)
import           Monitor.Types       ( Config (..)
                                     , Event (..)
                                     , TimedEvent (..)
                                     , Verdict (..)
                                     )

data ComposedState = ComposedState
  { csM1   :: !A1.M1
  , csM2   :: !A2.M2
  , csM3   :: !A3.M3
  , csObs  :: !Multiset   -- ^ multiconjunto observado da janela corrente (A5), só para exibição
  , csTau  :: !Double
  } deriving (Eq, Show)

initial :: Config -> ComposedState
initial cfg = ComposedState
  { csM1  = A1.initial
  , csM2  = A2.initial cfg
  , csM3  = A3.initial cfg
  , csObs = MS.empty
  , csTau = cfgTau cfg
  }

-- | Passo do produto sincronizado sobre um evento. Cada componente
-- consome o evento via sua própria função de transição. @csObs@ acumula as
-- classificações confiáveis (filtro A5) da janela corrente, reiniciando a
-- cada @ab_i@ — é informação de exibição; a comparação multiconjunto
-- M_obs vs M_dec é responsabilidade do gate.
step :: ComposedState -> TimedEvent -> ComposedState
step s te =
  let evt  = teEvent te
      obs' = case evt of
        AbI                                    -> MS.empty
        ClsPI sku _ | isValidCls (csTau s) evt -> MS.addCls sku (csObs s)
        _                                      -> csObs s
  in s
    { csM1  = A1.step (csM1 s) evt
    , csM2  = A2.step (csM2 s) te
    , csM3  = A3.step (csM3 s) te
    , csObs = obs'
    }

-- | Veredito de stream (ínfimo dos componentes), domínio {⊥, ?}.
verdict :: ComposedState -> Verdict
verdict s = minimum
  [ A1.verdict (csM1 s), A2.verdict (csM2 s), A3.verdict (csM3 s) ]

-- | Veredito terminal (ínfimo dos componentes), domínio {⊥, ⊤}.
finalVerdict :: ComposedState -> Verdict
finalVerdict s = minimum
  [ A1.finalVerdict (csM1 s), A2.finalVerdict (csM2 s), A3.finalVerdict (csM3 s) ]

violatingRules :: ComposedState -> [String]
violatingRules s =
  [ n | (v, n) <-
      [ (A1.verdict (csM1 s), "A1"), (A2.verdict (csM2 s), "A2")
      , (A3.verdict (csM3 s), "A3") ], v == Bot
  ]

finalViolatingRules :: ComposedState -> [String]
finalViolatingRules s =
  [ n | (v, n) <-
      [ (A1.finalVerdict (csM1 s), "A1"), (A2.finalVerdict (csM2 s), "A2")
      , (A3.finalVerdict (csM3 s), "A3") ], v == Bot
  ]

-- | Sumidouro de M₁ (violação de safety A1, capturada como fora_ciclo).
sinkM1 :: ComposedState -> Bool
sinkM1 = A1.isViolation . csM1

-- | Sumidouro de M₂ (A2 violada → erro_classificacao via timeout_cls_i).
sinkM2 :: ComposedState -> Bool
sinkM2 = A2.isViolation . csM2

-- | Sumidouro de M₃ (A3 violada → erro_decisao via leave_ab_silent_i).
sinkM3 :: ComposedState -> Bool
sinkM3 = A3.isViolation . csM3

summary :: ComposedState -> String
summary s = unwords
  [ "M1:" ++ A1.summary (csM1 s)
  , "M2:" ++ A2.summary (csM2 s)
  , "M3:" ++ A3.summary (csM3 s)
  ]
