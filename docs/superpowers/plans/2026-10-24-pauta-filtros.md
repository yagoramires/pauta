# Pauta: abas, busca e ajustes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pílulas por serviço e busca por texto no topo do popover, mais cinco ajustes novos (menções em canais, cards
livres, densidade, intervalo, notificações).

**Architecture:**
- **Regras puras.** Preferências, contagens, filtragem e busca são funções puras, testadas no `SelfTest`:
  - `Prefs.swift`: preferências e o efeito delas;
  - `Filter.swift`: busca e filtro.
- **Estado.** As preferências vivem num `PrefsStore` (ObservableObject, `UserDefaults`), criado no `AppDelegate`. O
  filtro e a busca são `@ViewState` do `PopoverView`, que já é recriado a cada abertura (`refreshContent()` com
  `.id(generation)`), então zeram sozinhos.
- **Views.** As seções recebem as listas já filtradas, em vez de ler `store.items` direto.

**Tech Stack:** Swift 6 toolchain (modo de linguagem v5), SwiftUI e AppKit, só Command Line Tools. Testes com
`precondition` em `SelfTest.swift` (`--selftest`). Revisão visual com `--snapshots`.

**Spec:** `docs/superpowers/specs/2026-10-24-pauta-filtros-design.md`, sobre a base
`docs/superpowers/specs/2026-10-24-pauta-redesign-design.md`. Mockups em
`.superpowers/brainstorm/41459-1792886008/content/`: `a-com-busca.html` para o comportamento e `inputs.html` opção 3
para o visual.

## Global Constraints

- **Branch e commits:**
  - branch `pauta`;
  - commits em português no estilo do repo, terminando com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - sem push.
- **Estilo grafite:**
  - fonte do sistema, sem mono nem serifa, e nada de CAIXA ALTA;
  - cores só semânticas. A única cor fixa são os logos (Slack `#4A154B`/`#E01E5A`, Jira `#0052CC`/`#4C9AFF`, GitHub
    `#181717`/`#F2F2F4`);
  - links e controles em `.secondary`/`.primary`, nunca o azul de destaque.
- **Animação:** só pelo `.motion(_:)`, que respeita "reduzir movimento".
- **Fora de escopo:**
  - nenhuma busca nova nas APIs;
  - nenhum atalho além de ⌘F e Esc;
  - nenhum avatar.
- **Verificação padrão:** `scripts/build.sh debug && build/Pauta.app/Contents/MacOS/Pauta --selftest` → última linha
  `selftest ok`. Capturas: `build/Pauta.app/Contents/MacOS/Pauta --snapshots /tmp/<pasta>`.
- **Nunca rodar `scripts/build.sh --run`.** O app real do usuário está rodando, e o controlador faz isso no fim.

## Review Focus

1. **Desligar "Menções em canais" com o destaque sendo uma menção:** o destaque passa para o próximo item visível, e a
   menção some de tudo (lista, pílula, barra, notificação). Teste em `visibleItems` (Tarefa 3) e em `notifiable`
   (Tarefa 1).
2. **Busca com acento e maiúscula** ("BOTAO" acha "Botão") e com várias palavras fora de ordem. Teste de `matches`
   (Tarefa 3).
3. **Sub-tarefa livre encontrada cujo pai não é livre:** aparece sob o título apagado do pai, como no `groupFree`. Teste
   de `visibleItems` + `groupFree` (Tarefa 3).
4. **Trocar o intervalo com o app rodando:** o timer antigo é cancelado e não ficam dois timers. Teste do `Poller`
   (Tarefa 1).
5. **Notificações desligadas e religadas:** não chega enxurrada, porque o registro de "já notificado" anda mesmo
   desligado. Teste de `notifiable` mais o fluxo existente `notifierFirstRunIsSilent` (Tarefa 1).

---

### Task 1: Preferências (modelo, persistência e efeitos fora da tela)

**Files:**
- Create: `Sources/Pauta/Prefs.swift`
- Modify: `Sources/Pauta/AppDelegate.swift` (criar o `PrefsStore`, a closure `notify` do `SlackStore`, `updateBar`, o
  intervalo do poller), `Sources/Pauta/Poller.swift`, `Sources/Pauta/SelfTest.swift` (novo `prefsRules()` em `run()`)

**Interfaces — Produces:**
```swift
enum Density: String, CaseIterable { case comfortable, compact }
struct Prefs: Equatable {
    var channelMentions = true      // "Menções em canais"
    var freeCards = true            // "Cards livres"
    var density: Density = .comfortable
    var refreshMinutes = 2          // só 1, 2 ou 5
    var slackNotifications = true   // "Notificações do Slack"
    static func load(_ defaults: UserDefaults = .standard) -> Prefs
    func save(_ defaults: UserDefaults = .standard)
}
@MainActor final class PrefsStore: ObservableObject { init(defaults: UserDefaults = .standard); @Published var prefs: Prefs }  // salva a cada mudança
func visibleSlack(_ items: [SlackItem], prefs: Prefs) -> [SlackItem]               // tira menções se channelMentions == false
func notifiable(_ items: [SlackItem], prefs: Prefs) -> [SlackItem]                 // [] se slackNotifications == false
func barCounts(slack: [SlackItem], freeCount: Int, prs: Int, prefs: Prefs) -> (slack: Int, jira: Int, github: Int)
extension Poller { func setInterval(minutes: Int) }
```
- Chaves do `UserDefaults`: `prefs.channelMentions`, `prefs.freeCards`, `prefs.density`, `prefs.refreshMinutes` e
  `prefs.slackNotifications`.
- Um `refreshMinutes` fora de {1, 2, 5} carrega como 2.

- [ ] **Step 1: Testes que falham**

  `prefsRules()` usa uma suíte de `UserDefaults` temporária (`UserDefaults(suiteName: "pauta-test-\(UUID())")`):

  ```swift
  precondition(Prefs.load(d) == Prefs())                                   // padrões
  var p = Prefs(); p.channelMentions = false; p.refreshMinutes = 5; p.density = .compact; p.save(d)
  precondition(Prefs.load(d) == p)
  d.set(7, forKey: "prefs.refreshMinutes"); precondition(Prefs.load(d).refreshMinutes == 2)
  // dm = SlackItem DM; mention = SlackItem em canal
  precondition(visibleSlack([dm, mention], prefs: Prefs()) == [dm, mention])
  precondition(visibleSlack([dm, mention], prefs: p) == [dm])
  var off = Prefs(); off.slackNotifications = false
  precondition(notifiable([dm, mention], prefs: off).isEmpty)
  precondition(notifiable([dm, mention], prefs: p) == [dm])
  var noFree = Prefs(); noFree.freeCards = false
  precondition(barCounts(slack: [dm, mention], freeCount: 6, prs: 3, prefs: Prefs()) == (2, 6, 3))
  precondition(barCounts(slack: [dm, mention], freeCount: 6, prs: 3, prefs: noFree) == (2, 0, 3))
  precondition(barCounts(slack: [dm, mention], freeCount: 6, prs: 3, prefs: p) == (1, 6, 3))
  ```

  Para tuplas, compare campo a campo ou use um struct `BarCounts: Equatable`. Fica a critério do implementador, desde
  que `updateBar` use o resultado.

  **Poller:** depois de `start()`, `setInterval(minutes: 5)` deixa um timer com `timeInterval == 300`, e o anterior é
  invalidado. Para testar, exponha `var timerInterval: TimeInterval?` só para leitura.

- [ ] **Step 2: Rodar.** Esperado: erro de compilação, porque `Prefs` não existe.
- [ ] **Step 3: Implementar**
  - **`Prefs.swift`:** tudo o que o bloco Produces lista.
  - **Poller:**
    - o `interval` vira `var`;
    - `setInterval(minutes:)` invalida o timer atual e agenda outro com `minutes * 60`, mantendo `tolerance = 10`;
    - se o poller ainda não foi iniciado, só guarda o valor.
  - **AppDelegate:**
    - cria um `PrefsStore` e o poller começa com `prefs.refreshMinutes`;
    - observa `prefsStore.$prefs` para chamar `setInterval` quando o intervalo mudar e para rodar `updateBar()`.
      **Não** chame `refreshContent()` aqui: ele recria o popover e tiraria o usuário da tela de ajustes no meio de
      uma mudança. O `PopoverView` observa o `PrefsStore` e se atualiza sozinho;
    - a closure `notify` do `SlackStore` passa a ser `{ Notifier.postIfSlackClosed(notifiable($0, prefs:
      prefsStore.prefs)) }`. Como o `SlackStore` grava o registro antes de chamar `notify`, o registro continua
      andando;
    - `updateBar` usa `barCounts`.
  - O `prefsStore` precisa ficar acessível às views (Tarefas 2 e 4). Passe ele no `PopoverView` como
    `@ObservedObject var prefs: PrefsStore`, a partir do `refreshContent()`. Os snapshots passam um `PrefsStore` com
    `UserDefaults` temporário, nunca o `.standard`.
- [ ] **Step 4: Rodar a verificação padrão.** Esperado: `selftest ok`.
- [ ] **Step 5: Commit** `feat: preferências do Pauta (menções, livres, densidade, intervalo, notificações)`

---

### Task 2: Seção "Exibição" nos ajustes e densidade aplicada

**Files:**
- Modify: `Sources/Pauta/Views/SettingsView.swift`, `Sources/Pauta/Views/PopoverView.swift`,
  `Sources/Pauta/Views/Shared.swift` (`CompactRow`), `Sources/Pauta/Views/HighlightView.swift`,
  `Sources/Pauta/Snapshots.swift`

**Interfaces:**
- Consumes: `PrefsStore`, `Prefs`, `Density` (Tarefa 1).
- Produces:
  - uma `EnvironmentKey` `density: Density` (padrão `.comfortable`), definida pelo `PopoverView` a partir de
    `prefs.prefs.density`;
  - `SettingsView.init(..., prefs: PrefsStore)`.

- [ ] **Step 1: Implementar**
  - **"Exibição"** é um `SectionTitle("Exibição")` depois das conexões, com nesta ordem:
    - "Menções em canais": `Toggle`, `.toggleStyle(.switch)`, `.controlSize(.mini)`, `.tint(.primary)`;
    - "Cards livres": o mesmo controle;
    - "Densidade": `Picker` segmentado com "Confortável" e "Compacta";
    - "Atualizar a cada": `Picker` segmentado com "1 min", "2 min" e "5 min";
    - "Notificações do Slack": um `Toggle`.

    Cada um vai numa linha, com o rótulo à esquerda em 13 pt e o controle à direita. As mudanças gravam direto no
    `prefs.prefs`, sem botão de salvar.
  - **Densidade compacta:**
    - o `CompactRow` passa de 6 para 3 de padding vertical;
    - o texto grande do `HighlightView` passa de 18 para 16 pt;
    - o espaço entre seções no `PopoverView` passa de 16 para 10.
- [ ] **Step 2: Snapshots**
  - `ajustes.png` passa a mostrar a seção Exibição.
  - Novo `tela-compacta.png`: a tela "tudo" com `density = .compact`.
- [ ] **Step 3: Verificação padrão** → `selftest ok`. Rodar os snapshots e conferir `ajustes.png` e `tela-compacta.png`
  no claro e no escuro: interruptores pretos ou brancos, nada azul.
- [ ] **Step 4: Commit** `feat: seção Exibição nos ajustes e densidade compacta`

---

### Task 3: Regras de filtro e busca (funções puras)

**Files:**
- Create: `Sources/Pauta/Filter.swift`
- Modify: `Sources/Pauta/SelfTest.swift` (novo `filterRules()`)

**Interfaces:**
- Consumes: `Prefs` e `visibleSlack` (Tarefa 1), `groupFree` (`JiraModel.swift`).
- Produces:
  ```swift
  enum ServiceFilter: CaseIterable, Equatable { case all, slack, github, jira }
  func normalized(_ s: String) -> String                       // folding(.caseInsensitive, .diacriticInsensitive)
  func matches(_ query: String, _ fields: [String]) -> Bool   // query vazia/só espaços = true; toda palavra em algum campo
  func searchFields(_ item: SlackItem) -> [String]            // [userName, channelName ?? "", text]
  func searchFields(_ pr: PullRequest) -> [String]            // [title, shortId, author]
  func searchFields(_ issue: JiraIssue) -> [String]           // [key, summary]
  struct VisibleItems: Equatable { var slack: [SlackItem]; var prs: [PullRequest]; var mine: [JiraIssue]; var free: [JiraIssue] }
  func visibleItems(slack: [SlackItem], prs: [PullRequest], mine: [JiraIssue], free: [JiraIssue],
                    prefs: Prefs, query: String) -> VisibleItems  // aplica visibleSlack, freeCards e a busca
  func pillCounts(_ v: VisibleItems) -> [ServiceFilter: Int]  // .jira = mine + free; .all = soma
  func matchRanges(_ text: String, query: String) -> [Range<String.Index>]  // trechos a marcar, ignorando acento/caixa
  func clearTitle(_ filter: ServiceFilter) -> String
  func resultsText(_ count: Int) -> String
  ```

- [ ] **Step 1: Testes que falham** (`filterRules()`)

  ```swift
  precondition(matches("BOTAO", ["Botão de voltar some no checkout"]))
  precondition(matches("checkout botão", ["Botão de voltar some no checkout"]))     // fora de ordem
  precondition(!matches("checkout cupom", ["Botão de voltar some no checkout"]))     // exige todas
  precondition(matches("  ", ["qualquer"]))
  precondition(matches("frontend", searchFields(mentionInFrontend)))                 // canal
  precondition(matches("4821", searchFields(pr4821)) && matches("marina", searchFields(pr4821)))
  precondition(matches("acme-1287", searchFields(issue1287)))
  let v = visibleItems(slack: [dm, mention], prs: [pr4821], mine: [issue1287], free: [free1, sub1], prefs: Prefs(), query: "checkout")
  // dm fala de checkout; issue1287 "Botão de voltar some no checkout"; free1 "Erro 500 no checkout sem cupom"; sub1 não bate
  precondition(v.slack == [dm] && v.prs.isEmpty && v.mine == [issue1287] && v.free == [free1])
  precondition(pillCounts(v) == [.all: 3, .slack: 1, .github: 0, .jira: 2])
  var noFree = Prefs(); noFree.freeCards = false
  precondition(visibleItems(slack: [], prs: [], mine: [], free: [free1], prefs: noFree, query: "").free.isEmpty)
  var dmsOnly = Prefs(); dmsOnly.channelMentions = false
  precondition(visibleItems(slack: [dm, mention], prs: [], mine: [], free: [], prefs: dmsOnly, query: "").slack == [dm])
  // sub-tarefa livre cujo pai não é livre: o grupo sai com headIssue == nil (título apagado)
  let g = groupFree(visibleItems(slack: [], prs: [], mine: [], free: [orphanSub], prefs: Prefs(), query: "ícones").free)
  precondition(g.count == 1 && g[0].headIssue == nil && g[0].subtasks == [orphanSub])
  let text = "Botão de voltar some no checkout"
  precondition(matchRanges(text, query: "botao").map { String(text[$0]) } == ["Botão"])
  precondition(matchRanges(text, query: "").isEmpty)
  precondition(clearTitle(.slack) == "Nada no Slack." && clearTitle(.github) == "Nenhum PR esperando você.")
  precondition(clearTitle(.all) == "Ninguém esperando você.")
  precondition(resultsText(1) == "1 resultado" && resultsText(3) == "3 resultados")
  ```

  Monte as fixtures com os helpers que o `SelfTest` já tem (`slackItem`, `issue(_:...)`, `PullRequest(...)`).
  `orphanSub` é uma sub-tarefa com `parent` apontando para um card que não está na lista e com o resumo "Trocar ícones
  do menu lateral".

- [ ] **Step 2: Rodar.** Esperado: erro de compilação.
- [ ] **Step 3: Implementar em `Filter.swift`**
  - `matches` normaliza a query, separa por espaços e exige que cada palavra apareça na junção normalizada dos campos.
  - `matchRanges` busca cada palavra com `range(of:options:[.caseInsensitive, .diacriticInsensitive])` e devolve os
    trechos no texto original, ordenados e sem sobreposição.
- [ ] **Step 4: Verificação padrão** → `selftest ok`.
- [ ] **Step 5: Commit** `feat: regras de filtro e busca do Pauta`

---

### Task 4: Pílulas por serviço (topo, sem busca ainda)

**Files:**
- Create: `Sources/Pauta/Views/FilterBar.swift`
- Modify: `Sources/Pauta/Views/PopoverView.swift`, `SlackView.swift`, `GitHubView.swift`, `JiraView.swift`,
  `HighlightView.swift`, `Sources/Pauta/Snapshots.swift`

**Interfaces:**
- Consumes: `ServiceFilter`, `visibleItems`, `pillCounts`, `clearTitle` (Tarefa 3); `PrefsStore` (Tarefa 1);
  `ServiceLogo`, `HubService.logoColor` (Shared).
- Produces:
  - `FilterBar(filter: Binding<ServiceFilter>, counts: [ServiceFilter: Int], services: [ServiceFilter], searchOpen:
    Binding<Bool>, query: Binding<String>)`. Nesta tarefa a lupa já aparece, mas só alterna `searchOpen`; a Tarefa 5
    liga o campo.
  - As seções passam a receber as listas:
    - `SlackView(store:connector:items:highlightedId:openSettings:showAll:)`;
    - `GitHubView(store:items:highlightedId:showAll:)`;
    - `JiraView(store:connector:mine:free:openSettings:freeOpen:expanded:)`.

    Elas usam essas listas no lugar de `store.items`, `store.mine` e `store.free`. O `showsSection` usa a contagem
    recebida.
  - `HighlightView(state:filter:slack:github:)`: no estado `.clear`, mostra `clearTitle(filter)`, e
    `clearSubtitle(...)` só quando `filter == .all`.
  - `PopoverView.init` ganha `filter: ServiceFilter = .all`, só para os snapshots.

- [ ] **Step 1: Implementar o `FilterBar`** (mockup `inputs.html`, opção 3)
  - **Linha:** margem de 12, espaço de 6. Primeiro o botão redondo com a lupa: SF Symbol `magnifyingglass`, 28×26,
    fundo `.primary` a 5%.
  - **Pílulas:**
    - 26 de altura, padding horizontal de 10, fonte 12, número em 11 com `.monospacedDigit()`;
    - "Tudo N", e depois logo + N para cada serviço em `services`;
    - a selecionada tem fundo `.primary` com o texto e o logo em `Color(nsColor: .windowBackgroundColor)`;
    - as outras têm fundo `.primary` a 5% e o logo na cor da marca.
  - `services` traz só os conectados: Slack se `configured`, GitHub se `!needsLogin`, Jira se `configured`.
- [ ] **Step 2: Ligar no `PopoverView`**
  - Guarda `@ViewState filter`, `searchOpen` e `query`.
  - Calcula `visibleItems(..., prefs: prefs.prefs, query: "")`.
  - Monta o destaque conforme o filtro:
    - `.all`: a regra de hoje, com as listas visíveis;
    - `.slack`: só o Slack (`prs: []`);
    - `.github`: só os PRs (`slack: []`);
    - `.jira`: sem destaque.
  - Mostra só as seções do filtro escolhido. Em `.jira`, os livres já vêm abertos (`freeOpen: true`).
  - Com `freeCards` desligado, a linha de livres não aparece.
- [ ] **Step 3: Snapshots:** `tela-filtro-slack.png`, `tela-filtro-revisoes.png` e `tela-filtro-jira.png`. A `tela-tudo`
  passa a ter as pílulas.
- [ ] **Step 4: Verificação padrão** → `selftest ok`. Rodar os snapshots e comparar com `inputs.html` (opção 3, parado)
  e com `a-com-busca.html` (tela 3): logos coloridos nas pílulas não escolhidas e nada azul.
- [ ] **Step 5: Commit** `feat: pílulas por serviço no topo do Pauta`

---

### Task 5: Busca, README e acabamento

**Files:**
- Modify: `Sources/Pauta/Views/FilterBar.swift`, `PopoverView.swift`, `Shared.swift` (`CompactRow` com texto
  marcado), `SlackView.swift`, `GitHubView.swift`, `JiraView.swift`, `Sources/Pauta/Snapshots.swift`, `README.md`

**Interfaces:**
- Consumes: `matches`, `visibleItems(query:)`, `matchRanges`, `resultsText` (Tarefa 3); o `FilterBar` (Tarefa 4).
- Produces:
  - `CompactRow` ganha `query: String = ""` e marca os trechos de `matchRanges` com fundo `.primary` a 10%, via
    `AttributedString`;
  - `PopoverView.init` ganha `searchQuery: String = ""`, só para os snapshots.

- [ ] **Step 1: Implementar**
  - **Campo de busca:** com a busca aberta, a linha de cima vira um campo arredondado com:
    - altura 30, raio 15 e fundo `.primary` a 5%;
    - a lupa;
    - um `TextField` sem borda e com o placeholder "Filtrar por pessoa, canal, card";
    - um botão ⊗ (`xmark.circle.fill`, `.secondary`) que limpa o texto. Com o texto já vazio, o ⊗ fecha a busca.

    As pílulas descem para a linha de baixo. Ao abrir, o campo ganha foco.
  - **Teclado:**
    - ⌘F (`.keyboardShortcut("f", modifiers: .command)` na lupa) abre a busca;
    - Esc (`.onExitCommand`) limpa o texto, ou fecha a busca se ele já estiver vazio.
  - **Com texto digitado:**
    - sem destaque;
    - as seções mostram só o que bate, e seção vazia some;
    - o Slack mostra tudo, sem "ver mais";
    - os livres que batem aparecem numa seção com o título "Livres", abertos e com o "Pegar";
    - as pílulas contam com `pillCounts` do resultado e continuam filtrando;
    - o rodapé troca "Atualizado há X" por `resultsText(total)`;
    - sem resultado, aparece `Nada com “\(query)”.` em 13 pt `.secondary`, com padding 16.
  - **"Marcar tudo como visto":** marca só as mensagens visíveis. Acrescente `markSeen(_ items: [SlackItem])` público no
    `SlackStore`, ou um parâmetro no `markAllSeen`.
- [ ] **Step 2: Snapshots:** `tela-busca.png` (busca aberta com "checkout") e `tela-busca-vazia.png` (sem resultado).
- [ ] **Step 3: README:** descrever as pílulas, a busca (⌘F e Esc, o que ela procura) e a seção Exibição com os cinco
  ajustes e seus padrões.
- [ ] **Step 4: Verificação padrão** → `selftest ok`. Rodar todos os snapshots e conferir no claro e no escuro
  `tela-busca`, `tela-busca-vazia`, `tela-filtro-*`, `tela-compacta` e `ajustes` contra os mockups.
- [ ] **Step 5: Commit** `feat: busca no Pauta, com trechos marcados e README`
