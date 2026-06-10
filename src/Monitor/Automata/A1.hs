{-# LANGUAGE OverloadedStrings #-}

-- | Autômato M1 — propriedade A1 (safety) do artigo:
--
-- @
--   A1 : G(rem_i → ab_i)
-- @
--
-- "Toda retirada deve ocorrer dentro da janela de abastecimento."
--
-- @
--       ¬rem_i ∨ ab_i              ⊤
--         ┌──┐                   ┌──┐
--         ▼  │                   ▼  │
--        ╭───╮   rem_i ∧ ¬ab_i  ╭────╮
--    ──▶ │ q0│ ─────────────▶  │ q⊥ │
--        ╰───╯                  ╰────╯
--      aceitante              sumidouro
-- @
--
-- | Bloco arquitetural na figura de arquitetura (v2) do artigo: "Monitor LTL/TLTL".
-- Referência: Tabela 2 (A1); fig-automato-a1-safety.
module Monitor.Automata.A1
  ( M1State (..)
  , M1
  , initial
  , step
  , verdict
  , finalVerdict
  , isViolation
  , summary
  , m1State
  , m1AbActive
  ) where

import Monitor.Types (Event (..), Verdict (..))

-- | Estado do AFD de A1 (2 estados, Figura 3).
data M1State = M1Ok | M1Violated
  deriving (Eq, Show)

-- | Estado completo de M1: AFD + flag @ab_i@ ativo.
--
-- O flag materializa a proposição @ab_i@ ao longo do tempo, alternando
-- entre 'True' (entre @ab_i@ e @leave_ab_i@) e 'False' fora desse
-- intervalo.
data M1 = M1
  { m1State    :: !M1State
  , m1AbActive :: !Bool
  } deriving (Eq, Show)

initial :: M1
initial = M1 M1Ok False

step :: M1 -> Event -> M1
step m evt = case m1State m of
  M1Violated -> m
  M1Ok -> case evt of
    AbI      -> m { m1AbActive = True  }
    LeaveAbI -> m { m1AbActive = False }
    RemI
      | m1AbActive m -> m
      | otherwise    -> m { m1State = M1Violated }
    _        -> m

-- | Veredito de /stream/ (LTL₃). A1 é safety não-co-safety: sobre prefixo
-- finito o veredito ⊤ não é alcançável (qualquer prolongamento pode
-- violar), de modo que o domínio é {⊥, ?} (§2.3, §5.3). Enquanto o
-- autômato não atinge o sumidouro, o veredito é ? ("ainda não há violação,
-- mas ainda pode haver"); ao atingir o sumidouro, ⊥.
verdict :: M1 -> Verdict
verdict m = case m1State m of
  M1Ok       -> Inconclusive
  M1Violated -> Bot

-- | Veredito /terminal/. Ao encerrar o prefixo observado, A1 (safety sem
-- obrigação pendente) é aceita (⊤) se nunca atingiu o sumidouro; ⊥ caso
-- contrário.
finalVerdict :: M1 -> Verdict
finalVerdict m = case m1State m of
  M1Ok       -> Top
  M1Violated -> Bot

-- | 'True' sse o autômato está em estado de sumidouro.
isViolation :: M1 -> Bool
isViolation m = m1State m == M1Violated

-- | Descrição curta do estado para o output detalhado.
summary :: M1 -> String
summary m = case m1State m of
  M1Ok       | m1AbActive m -> "ok(ab)"
             | otherwise    -> "ok"
  M1Violated                -> "viol"
