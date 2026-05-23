# Emulador — Peça 1: Monitor LTL para a propriedade A1

Pasta **autossuficiente** com um monitor de *runtime verification* em Haskell
para a propriedade A1 do artigo "Verificação de Restrições Operacionais em
Agentes de Visão Computacional via Autômatos de Monitoramento":

> **A1 (safety):**  $G(rem_i \to ab_i)$
> *"Toda retirada de peça deve ocorrer dentro da janela de abastecimento."*

Esta é a **primeira de seis peças** da construção incremental do monitor
composto $M = M_1 \otimes M_2 \otimes M_3 \otimes M_4$ descrito no artigo.

A pasta não depende do `lab1` nem de qualquer outra pasta do projeto: tem
seu próprio `flake.nix`, seu próprio `lab-monitor.cabal`, e seus próprios
exemplos.

---

## Estrutura

```
Emulador/
├── flake.nix                      # Ambiente Nix (GHC 9.4 + Cabal + HLS)
├── lab-monitor.cabal              # Configuração de build
├── README.md                      # Este arquivo
├── src/
│   └── Main.hs                    # Monitor A1 (AFD de 2 estados)
├── Files/
│   └── Traces/                    # Traços de exemplo (texto)
│       ├── trace_01_aceita_simples.txt
│       ├── trace_02_aceita_multiplas.txt
│       ├── trace_03_viola_a1_inicio.txt
│       ├── trace_04_viola_a1_apos_leave.txt
│       └── trace_05_aceita_vazio.txt
└── Exec/
    ├── monitor.sh                 # Roda o monitor sobre um único traço
    └── batch.sh                   # Roda todos os traços de Files/Traces/
```

A organização espelha a do `lab1`, então tudo deve ser familiar.

---

## O que esta peça implementa

Um AFD de 2 estados (Figura 3 do artigo):

```
       ¬rem_i ∨ ab_i              ⊤
         ┌──┐                   ┌──┐
         ▼  │                   ▼  │
        ╭───╮  rem_i ∧ ¬ab_i  ╭────╮
   ──▶ │ q0│ ─────────────▶  │ q⊥ │
        ╰───╯                 ╰────╯
      aceitante              sumidouro
```

- `q0` é inicial e aceitante.
- `q⊥` é sumidouro absorvente (uma vez violada, A1 nunca volta a aceitar).
- A transição é capturada pela função `step :: MonitorState -> Event -> MonitorState`
  em `src/Main.hs`.

---

## Como rodar

Dentro do diretório `Emulador/`:

> **Pré-requisito:** os arquivos da pasta precisam estar **rastreados pelo Git**,
> caso contrário o Nix flakes não os enxerga e falha com
> `error: Path 'Emulador/flake.nix' ... is not tracked by Git`.
> Se acabou de clonar/criar a pasta, rode antes (a partir da raiz do repositório):
>
> ```bash
> git add -N Emulador/   # intent-to-add: torna visível ao Nix sem stagear o conteúdo
> # ou, para já versionar de vez:
> git add Emulador/ && git commit -m "add Emulador"
> ```

```bash
# 1) Ativar o ambiente Nix (na primeira vez baixa GHC; depois é instantâneo)
nix develop

# 2) Compilar
cabal build

# 3) Rodar um traço individual
./Exec/monitor.sh Files/Traces/trace_01_aceita_simples.txt

# 4) Rodar todos os traços de uma vez (esperado: 3 aceitas + 2 violadas)
./Exec/batch.sh
```

Os scripts em `Exec/` ativam o ambiente Nix automaticamente, então você
pode invocá-los sem precisar rodar `nix develop` antes.

### Saída esperada para o traço 1 (aceitação)

```
Arquivo  : Files/Traces/trace_01_aceita_simples.txt
Eventos  : 5
Veredito : ACEITA (T)
```

### Saída esperada para o traço 3 (violação)

```
Arquivo  : Files/Traces/trace_03_viola_a1_inicio.txt
Eventos  : 3
Veredito : VIOLA  (F)
Violacao no evento #1: rem_i
Regra violada: A1  --  G(rem_i -> ab_i)
(rem_i ocorreu fora da janela de abastecimento)
```

O processo sai com código `0` (aceita), `2` (viola) ou `1` (erro de parsing) —
útil para usar em scripts e CI.

---

## Formato do arquivo de traço

Arquivo de texto, **um evento por linha**. Comentários começam com `#` e
linhas vazias são ignoradas.

```
# Comentário (ignorado)

ab_i
rem_i
cls_p_i caixa_1000L 0.93
leave_ab_i
match_i
```

### Eventos suportados nesta peça

| Sintaxe                       | Significado (artigo §3.2)                              |
|-------------------------------|--------------------------------------------------------|
| `ab_i`                        | Braço entrou na janela de abastecimento                |
| `rem_i`                       | Peça retirada                                          |
| `leave_ab_i`                  | Fim da janela                                          |
| `match_i`                     | $M_{obs} = M_{dec}$                                    |
| `div_i`                       | $M_{obs} \neq M_{dec}$                                 |
| `esc_pcp_i`                   | Escalação ao PCP                                       |
| `heartbeat`                   | Sinal de vida do agente (reservado para A6 futuro)     |
| `cls_p_i <sku> <confiança>`   | Classificação (ex.: `cls_p_i caixa_1000L 0.93`)        |

> **Importante:** todos os eventos acima são parseados, mas nesta peça
> **apenas `ab_i`, `rem_i` e `leave_ab_i` afetam o veredito** (são os
> relevantes para A1). Os demais ficam "passando" pelo monitor sem efeito.
> Isso é intencional — as próximas peças vão usar `match_i`, `div_i`,
> `cls_p_i` e `esc_pcp_i` ao adicionar A2, A3 e A4 sem mudar a estrutura
> do parser.

---

## Conexão com o lab1

Conceitualmente, esta peça é equivalente ao que você implementou no `lab1`:

| Lab 1 (Teoria da Computação)        | Emulador (Peça 1)                              |
|-------------------------------------|------------------------------------------------|
| AFD                                 | Mesmo AFD (2 estados)                          |
| Alfabeto $\Sigma$ (símbolos)        | Conjunto $AP$ (eventos atômicos do agente)     |
| Palavra $w \in \Sigma^*$            | Traço $\sigma \in AP^*$                        |
| Aceita / rejeita ao fim da palavra  | Aceita ($\top$) / viola ($\bot$) ao fim        |
| YAML como formato de entrada        | Texto simples (uma linha por evento)           |

A diferença filosófica é que aqui o AFD não está aceitando uma "linguagem"
no sentido tradicional — ele está verificando uma **propriedade temporal**
sobre um *traço* gerado em tempo de execução por um agente externo (futuramente,
o agente de visão computacional).

---

## Roadmap das próximas peças

| # | Peça | O que muda no `Main.hs` |
|---|------|--------------------------|
| 2 | A3 (safety): $G(leave\_ab_i \to match_i \vee div_i)$         | Adiciona `M3State` e `step3` |
| 3 | A2 (TLTL): $G(rem_i \to F_{[0,T_{cls}]} \bigvee_p cls_{p,i})$ | Acrescenta timestamps ao traço e relógio $x$ |
| 4 | A4 (TLTL): $G(div_i \to F_{[0,T_{pcp}]} esc\_pcp_i)$          | Segundo relógio, mesma estrutura de A2 |
| 5 | Composição $M_1 \otimes M_2 \otimes M_3 \otimes M_4$           | Veredito = `minimum [v1,v2,v3,v4]` (Proposição 2) |
| 6 | Testes QuickCheck                                              | Diretório `test/`, dependência `QuickCheck` |

A passagem para input vindo do agente de visão computacional acontece
**depois da peça 6**: basta substituir o `parseTrace` (que lê arquivo) por
um leitor de stream (stdin, socket, NATS) — o núcleo do monitor permanece
inalterado.
