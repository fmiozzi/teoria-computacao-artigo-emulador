{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída plain text (curto), compatível com a Peça 1.
--
-- A Fase 7 troca este formato pelo output detalhado tipo "emulador";
-- este módulo continuará disponível atrás da flag @--quiet@.
module Output.Plain
  ( renderReport
  ) where

import Monitor.Types (Event, Verdict, showEvent, showVerdict)

-- | Renderiza o relatório de uma execução.
--
-- Quando há violação:
--
-- * Se houve evento ofensor durante o stream, mostra a posição e o
--   evento.
-- * Caso a violação só se manifeste no fim do traço (ex.: A3 em
--   @awaiting@), reporta "no fim do traço".
-- * Em qualquer caso, lista as regras violadas e suas fórmulas.
renderReport
  :: FilePath
  -> Int                  -- ^ número de eventos processados
  -> Verdict
  -> Maybe (Int, Event)   -- ^ posição (1-indexada) e evento ofensor
  -> [String]             -- ^ regras violadas (vazio quando @v ≠ Bot@)
  -> String
renderReport filepath n v mViol rules = unlines $
  [ ""
  , "Arquivo  : " ++ filepath
  , "Eventos  : " ++ show n
  , "Veredito : " ++ showVerdict v
  ] ++ violationLines mViol rules

violationLines :: Maybe (Int, Event) -> [String] -> [String]
violationLines _        []    = []
violationLines mViol    rules =
    locationLine mViol
  : ("Regra(s) violada(s): " ++ unwords rules)
  : map describeRule rules

locationLine :: Maybe (Int, Event) -> String
locationLine (Just (i, e)) = "Violacao no evento #" ++ show i ++ ": " ++ showEvent e
locationLine Nothing       = "Violacao detectada no fim do traço."

describeRule :: String -> String
describeRule "A1" = "  A1: G(rem_i -> ab_i)                       (rem_i fora da janela)"
describeRule "A2" = "  A2: G(rem_i -> F[0,T_cls] cls_p_i)          (cls atrasada ou ausente)"
describeRule "A3" = "  A3: G(leave_ab_i -> match_i v div_i)        (fim da janela sem pronunciamento)"
describeRule "A4" = "  A4: G(div_i -> F[0,T_pcp] esc_pcp_i)        (escalação ao PCP atrasada ou ausente)"
describeRule "A6" = "  A6: G F[0,T_h] heartbeat                    (agente sem sinal de vida)"
describeRule "A7" = "  A7: G(rej_i -> cls recente em T_rej)        (rejeição sem classificação prévia)"
describeRule "A8" = "  A8: G(ab_i -> F[0,T_ab_max] leave_ab_i)     (janela longa demais)"
describeRule r    = "  " ++ r
