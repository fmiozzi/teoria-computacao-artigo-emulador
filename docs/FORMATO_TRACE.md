# Formato de traço

Especificação do formato de arquivo de traço consumido pelo emulador. A
referência normativa é a implementação em `src/Monitor/Parser.hs`
(separação cabeçalho/corpo, timestamps e eventos) e `src/Monitor/Header.hs`
(cabeçalho YAML). Esta especificação descreve o que esses módulos aceitam.

Um arquivo de traço tem duas partes, ambas opcionais para o parser:

1. um cabeçalho YAML inline entre marcadores `---`;
2. um corpo com um evento por linha.

## Estrutura geral

O parser (`Monitor.Parser.parseFile`) descarta linhas em branco iniciais,
e se a primeira linha não vazia for `---`, lê tudo até o próximo `---` como
cabeçalho. Se não houver `---` no topo, o arquivo inteiro é tratado como
corpo e nenhum cabeçalho é produzido. O cabeçalho é parseado por
`Monitor.Header.parseHeader`.

## Cabeçalho YAML

O cabeçalho ocupa as linhas entre dois marcadores `---`. O parser implementa
um subconjunto ad hoc do YAML: pares `chave: valor`, um por linha, com flow
maps inline (`{...}`) e listas inline (`[...]`). Block style com indentação
não é suportado. Linhas em branco e comentários (`#`) são ignorados, e
**chaves desconhecidas são descartadas silenciosamente**, o que permite
adicionar campos futuros sem quebrar arquivos existentes.

Campos reconhecidos:

| Campo                    | Tipo                       | Observação                |
|--------------------------|----------------------------|---------------------------|
| `id`                     | texto                      | ignorado pelo parser      |
| `cenario`                | texto (aspas opcionais)    | descrição livre           |
| `maquina`                | texto                      | identificador da máquina  |
| `braco`                  | inteiro                    | índice do braço `i`       |
| `m_dec`                  | flow map `{sku: int, ...}` | contagem decidida M_dec   |
| `parametros`             | flow map `{chave: num}`    | sobrepõe defaults globais |
| `veredito_esperado`      | `TOP` / `BOT` / `INCONCLUSIVE` | veredito composto de referência |
| `status_esperado`        | status terminal do gate    | status do gate de referência |
| `propriedades_relevantes`| lista inline `[A1, ...]`   | documental                |
| `referencia_artigo`      | texto                      | documental                |

Todos os campos são opcionais na perspectiva do parser: um traço válido pode
dispensar o cabeçalho inteiro. Note, porém, que a suíte de testes
(`ExampleTraces`) exige `veredito_esperado` em cada traço canônico, para
poder comparar o veredito calculado com o esperado. Os campos `id`,
`propriedades_relevantes` e `referencia_artigo` não têm campo correspondente
em `TraceHeader` e servem apenas como documentação no arquivo.

O campo `veredito_esperado` é case-insensitive e aceita também sinônimos
(`T`/`ACEITA`/`⊤`, `F`/`VIOLA`/`⊥`, `?`), por `Monitor.Types.parseVerdict`;
a forma canônica nas tabelas é `TOP` / `BOT` / `INCONCLUSIVE`. Ele declara o
**veredito composto** (ínfimo de M₁ ⊗ M₂ ⊗ M₃ no reticulado `⊥ < ? < ⊤`,
Proposição 2).

### `status_esperado`

O campo `status_esperado` declara o **status terminal do gate** (o efetor
MES↔ERP, §5.4), distinto do veredito composto. É case-insensitive e
parseado por `Monitor.Types.parseStatus` para `MesStatus`; os valores
canônicos são os identificadores do artigo:

- `liberado_integracao` — `match_i` dentro de `T_dec`, sem violação;
- `divergencia_pcp` — `div_i` (`mismatch ∨ fora_ciclo`) ou safety de A1;
- `erro_classificacao` — sumidouro de M₂ (A2): classificação ausente em `T_cls`;
- `erro_decisao` — sumidouro de M₃ (A3): mes-bridge mudo em `T_dec`;
- `pendente_verificacao` — estado transitório (raramente esperado).

Veredito e status **não coincidem em geral**: um `mismatch` tem veredito
composto `TOP` (A1/A2/A3 satisfeitas — a decisão foi tomada em prazo), mas
`status_esperado: divergencia_pcp`, pois `div_i` é decisão de processo, não
violação de propriedade (ver D10 e D11 em `docs/DECISOES.md`). Por isso os
traços canônicos declaram os dois campos.

### `m_dec`

Flow map de SKU para quantidade inteira, por exemplo
`m_dec: {caixa_1000L: 2, caixa_500L: 1}`. Representa a contagem decidida
`M_dec` (a OP do MES) usada pelo mes-bridge para comparar com `M_obs`.

Os SKUs devem pertencer ao catálogo-âncora fechado da Figura 12
(`Monitor.Types.anchorCatalog`), com 7 entradas: `caixa_500L`,
`caixa_1000L`, `tampa_1000L`, `molde_caixa_500L_vazio`,
`molde_caixa_1000L_vazio`, `molde_tampa_500L_vazio`,
`molde_tampa_1000L_abastecido`. (O parser não valida o SKU contra o
catálogo — o campo `cfgValidSKUs` foi removido de `Config` —, mas os traços
canônicos usam apenas esses identificadores.)

### `parametros` e a sobreposição de defaults

O campo `parametros` é um flow map com valores numéricos que sobrepõe os
defaults globais de `Monitor.Types.Config`, por traço, via
`Monitor.Header.applyParams` (ver D6 em `docs/DECISOES.md`). Chaves ausentes
mantêm o default; `applyParams` é usado tanto pela CLI quanto pela suíte de
testes, garantindo vereditos idênticos entre as duas. Os parâmetros do
monitor verificado (recorte A1–A3 + A5), com os defaults do cenário-âncora
(§4) em `Monitor.Types.defaultConfig`:

| Chave  | Unidade | Default               | Propriedade |
|--------|---------|-----------------------|-------------|
| `Tcls` | ms      | 1500                  | A2          |
| `Tdec` | ms      | 1700 (= T_cls + ε, ε = 200) | A3    |
| `tau`  | —       | 0.85                  | A5          |

O δ_mb (latência de comparação do mes-bridge) tem default 100 ms
(`cfgDeltaMb`, com `δ_mb ≤ T_dec − T_cls = 200 ms`), mas **não** é exposto
como chave de `parametros` — é configurado apenas via `Config`.

Os prazos são lidos como número e arredondados para inteiro em ms; `tau`
permanece `Double`. Exemplo: `parametros: {Tcls: 2000, Tdec: 2200,
tau: 0.85}`. Definir prazos curtos pode ser necessário para exercitar os
relógios temporizados em traços com timestamps fora do regime do
cenário-âncora.

> **Nota (extensões prospectivas, §6).** `applyParams` também aceita a chave
> `Tpcp` (prazo de escalação ao PCP, A4), mas A4 é uma **extensão
> prospectiva** fora do monitor verificado e o artigo **não** fixa `T_pcp`
> (valor ilustrativo). Não a trate como parâmetro do recorte avaliado.

## Corpo

O corpo lista um evento por linha. As regras de `Monitor.Parser.parseBody`:

- Linhas em branco são ignoradas.
- Linhas iniciadas por `#` são comentários e são ignoradas.
- Comentários inline (`#` no meio da linha) são removidos antes do parsing;
  como o vocabulário de eventos não contém `#`, o corte no primeiro `#` é
  seguro.
- O índice de evento (usado para o timestamp implícito) avança apenas em
  eventos válidos, de modo que linhas em branco e comentários não consomem
  um slot de timestamp.

### Timestamps

Cada evento pode ser prefixado por um timestamp em milissegundos desde
`t=0`. São aceitas três formas (`Monitor.Parser.extractTimestamp`):

- `[t=NNNN] ev` — forma com colchetes; o colchete deve ser fechado.
- `NNNN ev` — primeiro token sendo um inteiro.
- `ev` — sem timestamp; assume-se `i * 1000` ms, onde `i` é o índice
  0-based do evento na sequência (forma implícita, compatível com a Peça 1).

### Eventos (proposições atômicas)

A sintaxe de cada evento é reconhecida por `Monitor.Parser.parseEvent`. O
conjunto AP do artigo v2_3 (§3.2) é
`AP = { ab_i, leave_ab_i, match_i, div_i : i ∈ B } ∪ { rem_{i,j},
cls_{p,i,j} }`:

| Evento                      | Significado                              |
|-----------------------------|------------------------------------------|
| `ab_i`                      | braço entrou na janela de abastecimento  |
| `rem_i`                     | peça retirada                            |
| `cls_p_i <sku> <conf>`      | classificação: SKU e confiança (Double)  |
| `leave_ab_i`                | fim da janela de abastecimento           |
| `match_i`                   | M_obs = M_dec                            |
| `div_i`                     | macro-evento derivado: `mismatch ∨ fora_ciclo` (M_obs ≠ M_dec ou exceção estrutural) |

O evento `cls_p_i` exige exatamente dois argumentos: um SKU e uma confiança
parseável como `Double` (por exemplo, `cls_p_i caixa_1000L 0.93`); uma
confiança inválida é erro de parsing.

O parser também reconhece `esc_pcp_i`, `heartbeat` e `rej_i`, mas estes
**não** pertencem a AP (`Monitor.Types.isAP` retorna `False` para eles):
são proposições das extensões prospectivas A4 (escalonamento ao PCP), A6
(heartbeat) e A7 (refugo), fora do monitor verificado (ver D5 em
`docs/DECISOES.md`). O índice de braço `j` é implícito: um traço
corresponde a um braço, e o formato mantém `rem_i` / `cls_p_i` sem `j`
explícito (ver D8).

## Exemplo (formato estendido)

O arquivo `Files/Smoke/smoke_formato_estendido.txt` exercita o formato
estendido com timestamps mistos:

```
---
cenario: "Smoke test do formato estendido (Fase 2)"
maquina: ROTO-01
braco: 1
m_dec: {caixa_1000L: 2, caixa_500L: 1}
veredito_esperado: TOP
---
# Mistura de timestamps explícitos e implícitos.
[t=0]    ab_i
[t=1500] rem_i
[t=2000] cls_p_i caixa_1000L 0.91
[t=3500] rem_i
4000     cls_p_i caixa_1000L 0.95
[t=5500] rem_i
6000     cls_p_i caixa_500L 0.88
[t=8000] leave_ab_i
match_i
```

Pontos a observar:

- O cabeçalho declara `m_dec` com duas 1000L e uma 500L, e
  `veredito_esperado: TOP`.
- A maioria dos eventos usa a forma com colchetes (`[t=NNNN]`), enquanto
  duas classificações usam a forma de inteiro líder (`4000` e `6000`),
  demonstrando que as formas podem se misturar no mesmo traço.
- O evento final `match_i` não traz timestamp. Como é o nono evento válido
  (índice 0-based 8), o timestamp implícito seria `8 * 1000 = 8000` ms,
  coincidindo com o `leave_ab_i` anterior — adequado para um pronunciamento
  no fecho da janela.
- O cenário é o caminho feliz: o braço entra na janela, retira três peças
  classificadas dentro do prazo e sai com `match_i`, resultando em ⊤.
