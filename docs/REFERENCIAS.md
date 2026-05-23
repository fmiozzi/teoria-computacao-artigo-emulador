# Referências

Bibliografia consultada na construção do emulador e do artigo associado.

## Lógicas temporais e monitoramento

**Pnueli, A. (1977).** *The temporal logic of programs.* In Proceedings
of the 18th Annual Symposium on Foundations of Computer Science (FOCS),
46–57. IEEE.
> Artigo seminal introduzindo LTL. Origem do operador G (*always*) usado
> em A1, A3, A6, A7.

**Vardi, M. Y., & Wolper, P. (1986).** *An automata-theoretic approach
to automatic program verification.* In Proceedings of the 1st Annual
IEEE Symposium on Logic in Computer Science (LICS), 332–344.
> Estabelece a correspondência LTL ↔ autômatos de Büchi. Base teórica
> para a construção de $M_k$ a partir de cada $A_k$.

**Bauer, A., Leucker, M., & Schallhart, C. (2011).** *Runtime
verification for LTL and TLTL.* ACM Transactions on Software Engineering
and Methodology (TOSEM), 20(4), 1–64.
> Define a semântica LTL$_3$ usada pelo emulador — reticulado
> $\bot < \text{?} < \top$ implementado em `Monitor.Types.Verdict`.
> Vereditos finais inconclusivos representados em $?$.

**Bauer, A., & Falcone, Y. (2016).** *Decentralised LTL monitoring.*
Formal Methods in System Design, 48(1), 46–93.
> Discute composição de monitores LTL — relevante para a Proposição 2 do
> artigo (produto sincronizado ↔ ínfimo dos vereditos).

**Alur, R., & Dill, D. L. (1994).** *A theory of timed automata.*
Theoretical Computer Science, 126(2), 183–235.
> Fundamenta TLTL e autômatos temporizados. Inspira o tratamento dos
> relógios em A2 (T_cls), A4 (T_pcp), A6 (T_h), A8 (T_ab_max).

**Bouyer, P., Markey, N., & Reynier, P.-A. (2008).** *Robust analysis
of timed automata via channel machines.* In Foundations of Software
Science and Computational Structures (FoSSaCS), LNCS 4962, 157–171.

**Maler, O., & Nickovic, D. (2004).** *Monitoring temporal properties
of continuous signals.* In Joint International Conferences on Formal
Modeling and Analysis of Timed Systems and Formal Techniques in
Real-Time and Fault-Tolerant Systems (FORMATS/FTRTFT), LNCS 3253,
152–166.
> Aborda monitoramento de sinais temporais (Signal Temporal Logic) —
> referência para extensões futuras que tratem grandezas contínuas
> (temperatura, pressão) ao invés de eventos discretos.

## Ferramentas

**Duret-Lutz, A., Lewkowicz, A., Fauchille, A., Michaud, T.,
Renault, É., & Xu, L. (2016).** *Spot 2.0 — a framework for LTL and
ω-automata manipulation.* In Automated Technology for Verification and
Analysis (ATVA), LNCS 9938, 122–129.
> Spot é a ferramenta referenciada na §6 do artigo como base potencial
> para verificação simbólica das fórmulas. Este emulador implementa o
> mesmo formalismo em Haskell, à mão, para fins pedagógicos.

## Verificação em manufatura e Indústria 4.0

**Van Brussel, H., Wyns, J., Valckenaers, P., Bongaerts, L., &
Peeters, P. (1998).** *Reference architecture for holonic manufacturing
systems: PROSA.* Computers in Industry, 37(3), 255–274.
> Arquitetura referência discutida na §6 do artigo. O *gate* do
> emulador mapeia 1:1 ao "holon de validação" do PROSA.

**Rocchetto, M., & Tippenhauer, N. O. (2017).** *Towards formal security
analysis of industrial control systems.* In ACM Asia Conference on
Computer and Communications Security (AsiaCCS), 114–126.
> Aproximação de runtime verification a sistemas industriais.

## Visão computacional para apontamento

**Redmon, J., Divvala, S., Girshick, R., & Farhadi, A. (2016).** *You
only look once: Unified, real-time object detection.* In IEEE Conference
on Computer Vision and Pattern Recognition (CVPR), 779–788.
> Família YOLO — referência para detectores que podem ser usados como
> "agente de visão" emitindo os eventos `ab_i`, `rem_i`, `cls_p_i` do
> conjunto AP.

## Haskell e runtime verification

**Stewart, D., & Sjödin, U. (2017).** *Haskell for runtime monitoring.*
In Runtime Verification (RV), LNCS 10548, 263–278.
> Padrões de design para implementar monitores LTL/TLTL em Haskell —
> reflete-se na estrutura modular `Monitor.Automata.A*`.

**Marlow, S. (2010).** *Parallel and concurrent programming in Haskell.*
O'Reilly Media.
> Base técnica para uma evolução futura do emulador (modo stream,
> múltiplos braços em paralelo).

## Próximos passos bibliográficos

Para a discussão (§6) e os trabalhos futuros, vale revisitar:

- **Falcone, Y., Mariani, L., Rollet, A., & Saha, S. (2018).**
  *Runtime failure prevention and reaction.* In Lectures on Runtime
  Verification, LNCS 10457, 103–134.
- **Sánchez, C., et al. (2019).** *A survey of challenges for runtime
  verification from advanced application domains.* Formal Methods in
  System Design, 54(3), 279–335.
- Trabalhos sobre **STL** (Signal Temporal Logic) para futuras extensões
  com grandezas contínuas (temperatura do forno, pressão do molde).

---

## Como ler este código a partir das referências

| Trecho do código | Referência |
|------------------|-----------|
| `data Verdict = Bot \| Inconclusive \| Top` (`Monitor.Types`) | Bauer, Leucker & Schallhart (2011) — LTL$_3$ |
| Ínfimo em `Composed.verdict` | Proposição 2 do artigo, base em Bauer & Falcone (2016) |
| Relógios `M2.m2State = M2Pending clock` etc. | Alur & Dill (1994), TLTL |
| Mes-bridge (`Monitor.MesBridge`) | §5.4 do artigo, PROSA holon de validação |
| Sumidouro `Violated` absorvente | Construção clássica de Vardi–Wolper para safety |

A Tabela 3 do artigo (correlatos) lista trabalhos comparáveis em runtime
verification industrial; é o ponto de partida para uma revisão de
literatura mais profunda na dissertação.
