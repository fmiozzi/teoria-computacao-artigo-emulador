{-# LANGUAGE OverloadedStrings #-}

-- | Formato de saída plain text (curto), compatível com a Peça 1.
--
-- A Fase 7 troca este formato pelo output detalhado tipo "emulador";
-- este módulo continuará disponível atrás da flag @--quiet@.
module Output.Plain
  ( renderReport
  ) where

import Monitor.Types (Event, Verdict, showEvent, showVerdict)

-- | Renderiza o relatório de uma execução. Para violações de A1, inclui
-- a posição do evento ofensor e a fórmula da regra violada.
renderReport
  :: FilePath
  -> Int                  -- ^ número de eventos processados
  -> Verdict
  -> Maybe (Int, Event)   -- ^ posição (1-indexada) e evento ofensor
  -> String
renderReport filepath n v mViol = unlines $
  [ ""
  , "Arquivo  : " ++ filepath
  , "Eventos  : " ++ show n
  , "Veredito : " ++ showVerdict v
  ] ++ violationLines mViol

violationLines :: Maybe (Int, Event) -> [String]
violationLines Nothing = []
violationLines (Just (i, e)) =
  [ "Violacao no evento #" ++ show i ++ ": " ++ showEvent e
  , "Regra violada: A1  --  G(rem_i -> ab_i)"
  , "(rem_i ocorreu fora da janela de abastecimento)"
  ]
