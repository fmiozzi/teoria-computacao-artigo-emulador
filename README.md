# Emulador — Monitor LTL/TLTL para Agentes de Visão em Manufatura

Implementação em Haskell de um monitor de verificação em tempo de execução
(*runtime verification*) para as restrições operacionais especificadas no
artigo. O emulador concretiza, em código executável, a arquitetura de
referência: um agente de visão computacional observa uma máquina de
rotomoldagem multi-braço, e cada classificação de produto é submetida a um
monitor de autômatos que decide, em tempo real, se o apontamento de produção
pode prosseguir do MES ao ERP.

O núcleo verificado é o monitor composto `M = M1 ⊗ M2 ⊗ M3`, produto
sincronizado de três componentes que formalizam as propriedades A1
(*safety*), A2 (*liveness* temporizada, relógio `T_cls`) e A3 (*liveness*
temporizada, relógio `T_dec`), com o filtro estrutural A5 (limiar de
confiança da CNN, `τ`) aplicado a montante. A numeração salta A4 (nota de
rodapé 4 do artigo): este é o recorte verificado e avaliado — A1–A3 + A5. O
veredito do produto é o ínfimo dos vereditos individuais no reticulado de
três valores `⊥ < ? < ⊤` (Bauer, Leucker e Schallhart, 2011), resultado
estabelecido pela Proposição 2. Como `⊥` é absorvente em cada componente,
basta o autômato mais pessimista para determinar o veredito composto. As
cotas são imediatas: o produto tem no máximo `2×3×3 = 18` estados, contra a
cota binária `2^|Φ| = 8` com `|Φ| = 3`.

O monitor consome traços de eventos atômicos com marcação temporal e produz
um veredito de três valores, traduzido por um *gate* de decisão (Algoritmo 1)
que transita o apontamento de `pendente_verificacao` a um de quatro status
terminais por causa-raiz (ver abaixo). As propriedades A4, A6, A7 e A8 são
extensões **prospectivas** (artigo §6), fora do recorte avaliado: seus
autômatos (`Monitor.Automata.A4/A6/A7/A8`) permanecem no repositório como
protótipos isolados, não importados pelo monitor composto.

## Mapeamento módulo → bloco da arquitetura

| Bloco da arquitetura de referência         | Módulo(s)                                  |
|--------------------------------------------|--------------------------------------------|
| Máquina de rotomoldagem multi-braço        | `Monitor.Types`                            |
| Câmera + agente de visão                   | `Monitor.Parser`                           |
| Pipeline de inferência (CNN) — A5          | `Monitor.Classification` (`filterByTau`)   |
| MES (apontamento, `M_obs`/`M_dec`)         | `Monitor.Multiset`, `Monitor.MesBridge`    |
| Monitor LTL/TLTL (ínfimo, Proposição 2)    | `Monitor.Automata.A1`–`A3`, `Monitor.Composed` |
| Gate MES↔ERP (efetor, Algoritmo 1)         | `Monitor.Gate`                             |
| ERP (renderização do veredito)             | `Output.Plain`, `Output.Detailed`, `Output.Json` |
| Ponto de entrada (CLI)                      | `app/Main.hs`                              |

Detalhamento do mapeamento em [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## Propriedades do recorte verificado: A1–A3 + A5 (Tabela 2)

| ID | Tipo                 | Fórmula                                                | Parâm.  |
|----|----------------------|--------------------------------------------------------|---------|
| A1 | safety               | `G(rem_{i,j} → ab_i)`                                   | —       |
| A2 | liveness temporizada | `G(leave_ab_i → F_{[0,T_cls]} ⋁_{j,p} cls_{p,i,j}^{≥τ})` | `T_cls` |
| A3 | liveness temporizada | `G(leave_ab_i → F_{[0,T_dec]} (match_i ∨ div_i))`      | `T_dec` |
| A5 | restrição estrutural | filtro `conf ≥ τ` sobre `cls` antes de `M_obs`         | `τ`     |

`T_dec = T_cls + ε`, com `T_dec ≥ T_cls`. O evento derivado `div_i` (§3.4) é
definido com **exatamente dois disjuntos**:

```
div_i := mismatch_i ∨ fora_ciclo_i
```

- `mismatch_i`: emitido pelo mes-bridge em `τ_b + T_cls + δ_mb` quando
  `M_obs[τ_a, τ_b + T_cls] ≠ M_dec` (`δ_mb ≤ T_dec − T_cls`);
- `fora_ciclo_i`: exceções estruturais do ciclo (ex.: `leave_ab` duplicado,
  pronunciamento espúrio) e a violação de *safety* de A1 (capturada como
  `fora_ciclo` com diagnóstico `safety_A1`).

`timeout_cls_i` (sumidouro de M2) e `leave_ab_silent_i` (sumidouro de M3)
**não** são `div_i`: são eventos sintéticos de diagnóstico roteados pelo gate
a `erro_classificacao` e `erro_decisao`, respectivamente.

A4 — `G(div_i → F_{[0,T_pcp]} esc_pcp_i)` — é extensão prospectiva (§6) e
**não** faz parte do recorte verificado; `esc_pcp_i`, `heartbeat` e `rej_i`
não pertencem a AP.

## Monitor composto (ínfimo de M1 ⊗ M2 ⊗ M3)

```
                     filtro A5 (conf ≥ τ)
                            │
            traço ─────────►│ Monitor.Classification
                            ▼
              ┌─────────────────────────────────┐
              │           Monitor.Composed        │
              │                                   │
              │      ┌────┐   ┌────┐   ┌────┐     │
              │      │ M1 │   │ M2 │   │ M3 │     │
              │      │ A1 │   │ A2 │   │ A3 │     │
              │      └─┬──┘   └─┬──┘   └─┬──┘     │
              │        │        │        │        │
              │        └────────┼────────┘        │
              │                 ▼                 │
              │      veredito = ínfimo (⊥<?<⊤)    │
              │           (Proposição 2)          │
              └─────────────────┬─────────────────┘
                                ▼
                       Monitor.Gate (Alg. 1)
                                │
          ┌──────────────┬──────┴──────┬──────────────┐
          ▼              ▼             ▼              ▼
   liberado_       divergencia_   erro_          erro_
   integracao      pcp            classificacao  decisao
   (MES→ERP)       (→ PCP)        (→ visão)      (→ TI)
```

O *gate* não é binário: o efetor roteia o apontamento para um de quatro
status terminais por causa-raiz, na ordem de prioridade do Algoritmo 1
(`sinkM1 → sinkM2 → sinkM3 → div → match`):

| Status                | Disparo                                              | Diagnóstico                      | Escala para |
|-----------------------|------------------------------------------------------|----------------------------------|-------------|
| `liberado_integracao` | `match_i` dentro de `T_dec`, sem violação            | —                                | integração nativa MES→ERP |
| `divergencia_pcp`     | `div_i` (`mismatch ∨ fora_ciclo`) ou *safety* de A1  | `mismatch` \| `fora_ciclo` \| `safety_A1` | PCP (tratativa manual) |
| `erro_classificacao`  | sumidouro de M2 (classificação ausente em `T_cls`)   | `timeout_cls`                    | time de visão computacional |
| `erro_decisao`        | sumidouro de M3 (mes-bridge mudo em `T_dec`)         | `leave_ab_silent`                | TI |

**Distinção essencial: veredito composto ≠ status do gate.** Um `mismatch`
tem veredito composto `⊤` (A1/A2/A3 satisfeitas — a decisão foi tomada no
prazo) mas o gate **bloqueia** com `divergencia_pcp`, pois `div_i` é uma
decisão de **processo**, não uma violação de propriedade. O motor é
`Monitor.Gate.run :: Config -> Maybe Multiset -> [TimedEvent] -> GateResult`.

## Parâmetros e catálogo de SKUs

Defaults do cenário-âncora do artigo (§4), em `Monitor.Types.defaultConfig`:

| Parâmetro | Valor    | Significado                                          |
|-----------|----------|------------------------------------------------------|
| `T_cls`   | 1500 ms  | latência máxima de classificação (A2)               |
| `ε`       | 200 ms   | folga de decisão                                     |
| `T_dec`   | 1700 ms  | prazo de decisão do mes-bridge; `T_dec = T_cls + ε` |
| `δ_mb`    | 100 ms   | latência de comparação do mes-bridge; `δ_mb ≤ ε`    |
| `τ`       | 0.85     | limiar de confiança da CNN (A5)                      |

`T_pcp` (A4) não é fixado pelo artigo: é prospectivo/ilustrativo, fora do
recorte verificado. Os parâmetros podem ser sobrescritos pelo cabeçalho do
traço.

O catálogo-âncora é **fechado** com 7 SKUs (Figura 12 do artigo,
`Monitor.Types.anchorCatalog`), classificados por um MobileNetV3-Small:
`caixa_500L`, `caixa_1000L`, `tampa_1000L`, `molde_caixa_500L_vazio`,
`molde_caixa_1000L_vazio`, `molde_tampa_500L_vazio` e
`molde_tampa_1000L_abastecido`.

## Build e execução

Toolchain: GHC 9.4.8 e Cabal 3.10, provisionados de forma reproduzível pelo
Nix (flakes). Não há dependências de sistema fora do Nix.

```bash
# Compilar
nix develop --command cabal build

# Suíte de testes (verifica os 12 traços canônicos + composição + absorção)
nix develop --command cabal test

# Rodar todos os traços canônicos em modo curto
./Exec/batch.sh Files/Traces

# Rodar um traço específico
./Exec/monitor.sh Files/Traces/trace_08_divergencia_molde_vazio.txt
./Exec/monitor.sh --quiet Files/Traces/trace_08_divergencia_molde_vazio.txt
./Exec/monitor.sh --json  Files/Traces/trace_08_divergencia_molde_vazio.txt
```

> Nota (Nix flakes): o Nix só enxerga arquivos rastreados pelo Git. Em um
> repositório novo, rode `git add -N Emulador/` (intent-to-add) antes de
> `nix develop`.

### Modos da CLI

A interface é `lab-monitor [--quiet|--json] <arquivo_de_traço>`.

| Modo      | Saída |
|-----------|-------|
| (padrão)  | Relatório detalhado: parâmetros, eventos, vereditos por propriedade e gate. |
| `--quiet` | Bloco curto com o veredito e as regras violadas (usado por `batch.sh`). |
| `--json`  | JSON estruturado: cabeçalho, configuração, passos, veredito e regras. |

### Códigos de saída

Derivados do **status do gate** (§5.4), não do veredito composto:

| Código | Status do gate                                                      |
|--------|--------------------------------------------------------------------|
| 0      | `liberado_integracao` (LIBERAR)                                    |
| 2      | BLOQUEAR (`divergencia_pcp` \| `erro_classificacao` \| `erro_decisao`) |
| 3      | `pendente_verificacao` (sem decisão terminal)                     |
| 1      | erro de parsing/IO/uso                                             |

## Cenários canônicos

A suíte canônica reúne **12 traços** do recorte verificado (A1–A3 + A5) em
`Files/Traces/`, todos com `veredito_esperado` (veredito composto) e
`status_esperado` (status terminal do gate) no cabeçalho YAML e verificados
por `cabal test`. Note que veredito e status são dimensões independentes: o
`mismatch` dos traços 08/09 tem veredito `⊤`, mas o gate bloqueia em
`divergencia_pcp`.

| Traço | Cenário                          | Veredito | Status do gate (diag)               |
|-------|----------------------------------|----------|-------------------------------------|
| 01    | aceita simples                   | `⊤`      | `liberado_integracao`               |
| 02    | aceita múltiplas                 | `⊤`      | `liberado_integracao`               |
| 05    | aceita vazio (janela vacuosa)    | `⊤`      | `liberado_integracao`               |
| 06    | aceita braço 1 (mix)             | `⊤`      | `liberado_integracao`               |
| 07    | aceita braço 2 (uniforme)        | `⊤`      | `liberado_integracao`               |
| 03    | viola A1 (retirada no início)    | `⊥`      | `divergencia_pcp` (`safety_A1`)     |
| 04    | viola A1 (retirada após leave)   | `⊥`      | `divergencia_pcp` (`safety_A1`)     |
| 08    | divergência: molde vazio no MES  | `⊤`      | `divergencia_pcp` (`mismatch`)      |
| 09    | divergência: OP errada           | `⊤`      | `divergencia_pcp` (`mismatch`)      |
| 13    | deriva da CNN (A5 → A2)          | `⊥`      | `erro_classificacao` (`timeout_cls`)|
| 14    | classificação atrasada (A2)      | `⊥`      | `erro_classificacao`                |
| 16    | decisão atrasada (A3)            | `⊥`      | `erro_decisao` (`leave_ab_silent`)  |

Os cenários que exercitam as extensões **prospectivas** (artigo §6), **fora
do recorte verificado**, ficam em `Files/Traces/extras/`: `trace_10` (A7,
refugo), `trace_11` (A8, janela longa), `trace_12` (A6, agente morto) e
`trace_15` (A4, escalação atrasada).

Esses números são as métricas reais do emulador. O artigo cita "15 cenários"
como métrica narrativa; o repositório materializa 12 cenários canônicos
curados (recorte A1–A3 + A5), mais 4 traços prospectivos em `extras/` (§6), e
ainda o corpus de 400 traços aleatórios descrito abaixo. Análise detalhada em
[docs/CENARIOS.md](docs/CENARIOS.md); decisões de projeto em
[docs/DECISOES.md](docs/DECISOES.md); formato de traço em
[docs/FORMATO_TRACE.md](docs/FORMATO_TRACE.md); arquitetura em
[docs/ARQUITETURA.md](docs/ARQUITETURA.md); referências em
[docs/REFERENCIAS.md](docs/REFERENCIAS.md). Para depurar via GHCi, ver
[debug.md](debug.md).

## Corpus aleatório (Proposição 2 — PBT materializado)

Além dos cenários curados, o repositório inclui um corpus de **400 traços
aleatórios** em `Files/Corpus/`, gerado de forma determinística (PRNG com
semente fixa, reproduzível):

```bash
# Regenera Files/Corpus/ de forma idêntica (traces/, resultados.csv, RELATORIO.md)
nix develop --command cabal run corpus-gen
```

O corpus materializa o *property-based testing* da Proposição 2 (veredito
composto = ínfimo de M1 ⊗ M2 ⊗ M3), **confirmada em 400/400** casos. A
distribuição registrada em `Files/Corpus/RELATORIO.md`: 208 `⊤` / 192 `⊥` por
veredito composto; 138 `liberado_integracao` / 70 `divergencia_pcp` / 155
`erro_classificacao` / 37 `erro_decisao` por status do gate. Cada traço é
re-executável pelo CLI (`lab-monitor Files/Corpus/traces/corpus_001.txt`).

## Como citar

```bibtex
@mastersthesis{miozzi2026monitor,
  author  = {Batista, Fl{\'a}vio Miozzi},
  title   = {Verifica{\c c}{\~a}o de Restri{\c c}{\~o}es Operacionais em
             Agentes de Vis{\~a}o Computacional via Aut{\^o}matos de
             Monitoramento},
  school  = {Programa de P{\'o}s-Gradua{\c c}{\~a}o em Computa{\c c}{\~a}o
             Aplicada (PPComp), Instituto Federal do Esp{\'i}rito Santo (Ifes)},
  year    = {2026},
  doi     = {TODO: preencher com o DOI assim que emitido},
  url     = {TODO: URL do registro com DOI}
}
```

> O artefato de software (este emulador) recebe um DOI próprio no
> depósito (Zenodo/figshare); atualize os campos `doi`/`url` acima quando
> emitido.

## Licença

Licenciado sob a **Licença MIT** — ver [LICENSE](LICENSE).
