# Como contribuir

Obrigado pelo interesse no Emulador LTL/TLTL. Este é, por enquanto, um
projeto de demonstração acadêmica — contribuições são bem-vindas dentro
do escopo do artigo associado.

## Ambiente de desenvolvimento

Pré-requisito: **Nix com flakes habilitado**. Toda a toolchain (GHC
9.4.8, Cabal, HLS) é provisionada automaticamente.

```bash
git clone https://github.com/fmiozzi/teoria-computacao-artigo-emulador.git
cd teoria-computacao-artigo-emulador
nix develop          # entra no shell reproduzível
cabal build          # compila tudo
cabal test           # roda os 31 testes
```

Se você usa VS Code, a configuração em `.vscode/settings.json` é
suficiente — o HLS é detectado a partir do PATH definido pelo Nix
devShell.

## Fluxo de contribuição

1. Crie um branch a partir de `main`:
   ```bash
   git checkout -b feature/<nome-curto>
   ```
2. Implemente a mudança mantendo:
   - `cabal build` limpo (sem warnings sob `-Wall -Wincomplete-patterns
     -Wincomplete-uni-patterns`);
   - `cabal test` verde (31/31);
   - documentação relevante atualizada (README, CHANGELOG,
     docs/CENARIOS, docs/ARQUITETURA).
3. Faça commits pequenos e descritivos.
4. Abra um PR descrevendo o cenário operacional motivador (especialmente
   para novas propriedades).

## Adicionando novos cenários

Para um cenário que **já é capturado pelo recorte verificado (A1–A3 +
filtro A5)**:

1. Crie `Files/Traces/trace_NN_descricao.txt` com cabeçalho YAML
   completo. Declare os dois oráculos:
   - `veredito_esperado: TOP|BOT` — o veredito composto (ínfimo de
     M₁⊗M₂⊗M₃, Proposição 2);
   - `status_esperado: liberado_integracao|divergencia_pcp|erro_classificacao|erro_decisao`
     — o status terminal do gate (§5.4). Lembre que veredito ≠ status:
     um `mismatch` tem veredito ⊤ mas status `divergencia_pcp`.
2. A suite Tasty pega o arquivo automaticamente — não precisa editar
   `test/ExampleTraces.hs` (ela compara veredito **e**, quando
   declarado, `status_esperado`).
3. Adicione uma linha na tabela em [docs/CENARIOS.md](docs/CENARIOS.md).
4. Verifique:
   ```bash
   nix develop --command cabal test
   ./Exec/monitor.sh Files/Traces/trace_NN_descricao.txt   # visualmente
   ```

## Adicionando uma nova propriedade

O recorte **verificado** é o produto sincronizado `M = M₁ ⊗ M₂ ⊗ M₃`
(A1 safety, A2′/A3′ bounded liveness). A4/A6/A7/A8 são **extensões
prospectivas** (§6) e ficam como protótipos isolados em
`Monitor.Automata.A4/A6/A7/A8`, **não** importados pelo produto nem pelo
gate. Antes de mexer no produto, decida em qual dos dois mundos a nova
propriedade vive.

A arquitetura é deliberadamente extensível (Proposição 2 do artigo: o
veredito composto é o ínfimo dos componentes). Para promover uma
propriedade $A_n$ ao **produto verificado**, são 5 passos mecânicos:

1. **Autômato.** Crie `src/Monitor/Automata/An.hs` com:
   - `data MnState = ...`
   - `data Mn = Mn { mnState :: !MnState, ...thresholds... }`
   - `initial :: Config -> Mn`
   - `step :: Mn -> TimedEvent -> Mn`
   - `verdict :: Mn -> Verdict`
   - `finalVerdict :: Mn -> Verdict`
   - `summary :: Mn -> String`

2. **Composer.** Em `src/Monitor/Composed.hs`:
   - Adicione `csMn :: !An.Mn` em `ComposedState`.
   - Atualize `initial`, `step`, `verdict`, `finalVerdict`,
     `violatingRules`, `finalViolatingRules`, `summary`.

3. **Output.** Em `src/Output/Plain.hs`, acrescente uma linha em
   `describeRule`. Em `src/Output/Detailed.hs`, acrescente uma linha em
   `perPropertyVerdicts`. `Output.Json` pega automaticamente (deriva de
   `Composed.violatingRules`).

4. **Cabal.** Adicione `Monitor.Automata.An` à seção
   `exposed-modules` da library em `lab-monitor.cabal`.

5. **Testes + docs.**
   - Adicione `An.verdict` e `An.finalVerdict` ao `minimum` em
     `test/CompositionProps.hs` (ambas as propriedades). Sem isso, a
     suite falha — o ínfimo dos componentes ficaria fora de sintonia
     com `Composed.verdict`.
   - Acrescente `trace_NN_viola_an_*` em `Files/Traces/`.
   - Atualize [docs/CENARIOS.md](docs/CENARIOS.md) (matriz + detalhe)
     e [README.md](README.md) (tabela de propriedades).

Veja [docs/ARQUITETURA.md](docs/ARQUITETURA.md) para o diagrama do
pipeline.

## Estilo de código

- 2 espaços de indentação, sem tabs.
- Linha cabe em ~80 colunas; ~100 OK em assinaturas longas.
- Docstrings em pt-BR (este é um projeto acadêmico brasileiro).
- Importações ordenadas: `Prelude` implícito; libs base/text/containers
  primeiro; módulos do projeto (`Monitor.*`, `Output.*`) por último.
- Use `qualified` para módulos cujos nomes podem conflitar
  (`A1`/`A2`/...).
- Funções helper privadas no fim do arquivo.
- Comentários explicam **por quê**, não **o quê** — a assinatura já
  explica o quê.

## Estilo de commits

Commits descritivos em pt-BR. Padrão usado durante o projeto:

```
fase N: <título curto>

<bloco explicativo: o que mudou, por que, e qualquer pegadinha registrada>
```

Exemplos no [CHANGELOG.md](CHANGELOG.md).

## Reportando bugs ou sugestões

Use as Issues do GitHub:
<https://github.com/fmiozzi/teoria-computacao-artigo-emulador/issues>

Para bugs de comportamento (veredito errado para um cenário, parser
quebrando), anexe o arquivo de traço minimizado e o output esperado vs.
o observado.

## Licença

Ao contribuir, você concorda em licenciar suas mudanças sob a mesma
licença MIT do projeto.
