# Corpus aleatório — Proposição 2 (property-based testing materializado)

Total de casos: **400** (semente fixa `25214903917`, reproduzível por `cabal run corpus-gen`).

Proposição 2 (veredito composto = ínfimo de M₁⊗M₂⊗M₃) confirmada em **400/400** casos.

## Distribuição por veredito composto

| Veredito | Casos |
|----------|-------|
| TOP | 208 |
| INCONCLUSIVE | 0 |
| BOT | 192 |

## Distribuição por status do gate (§5.4)

| Status | Casos |
|--------|-------|
| liberado_integracao | 138 |
| divergencia_pcp | 70 |
| erro_classificacao | 155 |
| erro_decisao | 37 |

## Como reproduzir

```sh
cabal run corpus-gen      # regenera Files/Corpus/ de forma idêntica
```

Os 400 traços em `traces/` são re-executáveis pelo CLI:

```sh
lab-monitor Files/Corpus/traces/corpus_001.txt
```
