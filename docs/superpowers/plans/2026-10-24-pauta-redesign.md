# Pauta (redesign do Radar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renomear o Radar para Pauta, sem perder dados. Trocar os ícones pelo SF Symbol `checklist` e refazer o popover
no formato "destaque + resto compacto", no estilo grafite, com os logos coloridos dos serviços.

**Architecture:**
- **Regras de tela em funções puras:** quem vira destaque, os textos, quando uma seção aparece e o desbotamento.
  Elas ficam em `Highlight.swift` e são testadas no `SelfTest`. As views só montam.
- **`PopoverView`:** calcula o destaque uma vez e passa o id do item destacado para as seções, que o escondem da lista.
- **Logos:** são SVGs embutidos como texto, e o `NSImage` abre SVG nativamente. Viram imagem template, pintada na cor
  da marca.

**Tech Stack:** Swift 6 toolchain (modo de linguagem v5), SwiftUI e AppKit, só Command Line Tools (sem Xcode e sem
XCTest).
- Os testes rodam com `--selftest`, que usa `precondition`.
- A revisão visual é pelo `--snapshots`.

**Spec:** `docs/superpowers/specs/2026-10-24-pauta-redesign-design.md`. Os mockups aprovados estão em
`.superpowers/brainstorm/58692-1792857910/content/` (`c-estados.html`, `logos.html`, estilo "grafite").

## Global Constraints

- **Nomes:** o app se chama **Pauta**, com bundle id `local.pauta`, executável `Pauta` e pacote/target `Pauta`.
- **Visual:**
  - fonte do sistema em tudo, sem serifa e sem mono, e nenhum rótulo em CAIXA ALTA;
  - cores só semânticas (`.primary`, `.secondary`). As únicas cores fixas da tela são os logos:
    - Slack: claro `#4A154B`, escuro `#E01E5A`;
    - Jira: claro `#0052CC`, escuro `#4C9AFF`;
    - GitHub: claro `#181717`, escuro `#F2F2F4`.
  - botão primário: fundo `.primary` com o texto invertido. Botão secundário: fundo `.primary` a 8%;
  - medidas: destaque com cerca de 18 pt semibold e tracking −0,25. Linhas com 13 pt. Títulos de seção e metadados com
    cerca de 11,5 pt. Margens laterais de 16;
  - seções separadas por espaço, sem `Divider`.
- **Não mexer** em polling, notificações, no fluxo de conectar, em credenciais ou nas APIs. Nada de ação nova.
- **Movimento:** qualquer animação passa pelo `.motion(_:)` que já existe, que respeita "reduzir movimento".
- **Textos** em pt-BR, com as frases exatas definidas nas tarefas.
- **Commits:**
  - numa branch `pauta`, criada a partir de `main` antes da Tarefa 1;
  - mensagens no estilo do repo (`feat: …`, em português), sem coautoria;
  - sem push.

**Verificação padrão** (vale para "rodar os testes" em toda tarefa):
`scripts/build.sh debug && build/Pauta.app/Contents/MacOS/Pauta --selftest`. Espera-se a última linha `selftest ok`.
Até a Tarefa 1 terminar, o binário é `build/Radar.app/Contents/MacOS/Radar`.

## Review Focus

1. **Dados de quem já usa o Radar:** `~/Library/Application Support/Radar` precisa estar movida **antes** do primeiro
   `Credentials.load()`, que roda na inicialização das propriedades do `AppDelegate`. Senão o app abre como se não
   tivesse credenciais. Teste na Tarefa 1, e a chamada fica no `main.swift` antes de qualquer modo que leia
   credenciais.
2. **O item do destaque reaparecer na lista:** ao marcar como visto, o próximo sobe, e o item destacado nunca se repete
   na lista da seção. Testes de `pickHighlight` e de `heroState` na Tarefa 3, e a exclusão por id nas Tarefas 4 e 5.
3. **Mensagem longa ou com quebras de linha no destaque:** trocar `\n` por espaço e limitar a 4 linhas com
   reticências. O snapshot `tela-longa.png` (Tarefa 6) usa um texto de cerca de 400 caracteres com `\n`.
4. **Sem cards seus, mas com livres:** a seção "Seus cards" continua aparecendo só com a linha "N cards livres ▸",
   porque o total da barra conta os livres. Teste de `showsSection` na Tarefa 3.
5. **Logo do GitHub no escuro:** precisa ser `#F2F2F4`, senão some no fundo. Snapshot `tela-tudo-escuro.png`
   (Tarefa 6), conferido a olho.

---

### Task 1: Renomear para Pauta e migrar a pasta de dados

**Files:**
- Rename: `Sources/Radar/` → `Sources/Pauta/` (`git mv`)
- Create: `Sources/Pauta/AppPaths.swift`
- Modify: `Package.swift`, `Resources/Info.plist`, `scripts/build.sh`, `Sources/Pauta/main.swift`,
  `Sources/Pauta/Credentials.swift:13-14`, `Sources/Pauta/Slack/SlackStore.swift:119-120`, `Sources/Pauta/Log.swift`,
  `Sources/Pauta/StatusBar.swift:18-23`, `Sources/Pauta/Connect/Connect.swift` (o manifesto embutido, `name: Radar`, e
  as frases que dizem "o Radar"), `slack-manifest.yml`, `README.md`, `Sources/Pauta/SelfTest.swift`

**Interfaces:**
- Produces:
  - `enum AppPaths { static let support: URL; static let legacySupport: URL }`. Os valores são
    `~/Library/Application Support/Pauta` e `…/Radar`;
  - `func migrateLegacyFolder(from old: URL, to new: URL, fileManager: FileManager = .default) -> Bool`.

- [ ] **Step 1: Branch e renomeação mecânica**
  - `git checkout -b pauta`;
  - `git mv Sources/Radar Sources/Pauta`;
  - no `Package.swift`, `name: "Pauta"`, com o target `Pauta` e `path: "Sources/Pauta"`;
  - no `Info.plist`:
    - `CFBundleName` e `CFBundleDisplayName` passam a `Pauta`;
    - `CFBundleIdentifier` passa a `local.pauta`;
    - `CFBundleExecutable` passa a `Pauta`, se a chave existir.
  - no `build.sh`:
    - os nomes viram `Pauta` (`/Pauta` do binário, `build/Pauta.app`, `dist/Pauta-$VERSION.zip`);
    - no `--run`, encerrar `Pauta` **e** `Radar` (`pkill -x Radar` também) e apagar `build/Radar.app` se existir.

- [ ] **Step 2: Testes que falham**

  Em `SelfTest.swift`, criar `legacyFolderMigration()` e chamar em `run()`:

  ```swift
  private static func legacyFolderMigration() {
      let fm = FileManager.default
      let root = fm.temporaryDirectory.appendingPathComponent("pauta-mig-\(UUID().uuidString)")
      let old = root.appendingPathComponent("Radar"), new = root.appendingPathComponent("Pauta")
      func mode(_ url: URL) -> Int { (try! fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue }
      // Sem pasta antiga: nada a fazer.
      precondition(!migrateLegacyFolder(from: old, to: new))
      try! fm.createDirectory(at: old, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      fm.createFile(atPath: old.appendingPathComponent("credentials.json").path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o600])
      precondition(migrateLegacyFolder(from: old, to: new))
      precondition(!fm.fileExists(atPath: old.path))
      precondition(fm.fileExists(atPath: new.appendingPathComponent("credentials.json").path))
      precondition(mode(new) == 0o700 && mode(new.appendingPathComponent("credentials.json")) == 0o600)
      // Já migrado: não mexe de novo.
      precondition(!migrateLegacyFolder(from: old, to: new))
      // As duas existem: a antiga fica intacta, a nova vence.
      try! fm.createDirectory(at: old, withIntermediateDirectories: true)
      precondition(!migrateLegacyFolder(from: old, to: new) && fm.fileExists(atPath: old.path))
      try? fm.removeItem(at: root)
  }
  ```

  Em `barSegmentRules()`, trocar o prefixo esperado de `"Radar: …"` por `"Pauta: …"` nas quatro asserções de
  `barDescription`.

- [ ] **Step 3: Rodar e confirmar que falha**
  - Comando: `scripts/build.sh debug && build/Pauta.app/Contents/MacOS/Pauta --selftest`.
  - Esperado: erro de compilação, porque `migrateLegacyFolder` ainda não existe.

- [ ] **Step 4: Implementar**
  - **`AppPaths.swift`:** as duas URLs e `migrateLegacyFolder`, que move com `moveItem`, porque mover mantém as
    permissões. Ele devolve `false` sem tocar em nada quando a nova pasta já existe ou quando a antiga não existe.
    Uma falha no `moveItem` vai para o `Log` e devolve `false`.
  - **Caminhos:** `Credentials.url` e `SlackStore.defaultStateURL` passam a usar `AppPaths.support`. O `Log.url` passa a
    `~/Library/Logs/Pauta/pauta.log`, e o label da fila passa a `local.pauta.log`.
  - **Tooltip:** `barDescription` passa a usar o prefixo `Pauta:`.
  - **Textos:** os que diziam "o Radar" passam a dizer "o Pauta". O manifesto embutido e o `slack-manifest.yml` passam
    a ter `name: Pauta`.
  - **`main.swift`:** logo depois dos blocos `--selftest` e `--snapshots`, e antes de `--check`, `--dump` e do
    `AppDelegate`, chamar `_ = migrateLegacyFolder(from: AppPaths.legacySupport, to: AppPaths.support)`. Mova o bloco
    `--snapshots` para antes dele, se precisar.

- [ ] **Step 5: README**
  - Trocar Radar por Pauta, inclusive os caminhos da tabela.
  - Acrescentar: "na primeira vez, a pasta do Radar é movida para a do Pauta, sem reconectar nada; o macOS pede de
    novo a permissão de notificações e a de colar; se sobrar 'Radar' em Ajustes do Sistema → Geral → Itens de Início,
    remova".

- [ ] **Step 6: Rodar os testes**
  - Comando: a verificação padrão.
  - Esperado: `selftest ok`.

- [ ] **Step 7: Commit**: `git add -A && git commit -m "feat: o Radar vira Pauta, com migração da pasta de dados"`

---

### Task 2: Ícones (barra e app)

**Files:**
- Modify: `Sources/Pauta/StatusBar.swift`, `Sources/Pauta/SelfTest.swift` (`barSegmentRules`), `Resources/Info.plist`
- Create: `scripts/make-icon.swift`, `Resources/AppIcon.icns`

**Interfaces:**
- Produces: `let appGlyph = "checklist"`, que substitui `radarGlyph`. `radarImage(blip:)` é apagado.

- [ ] **Step 1: Teste que falha.** Em `barSegmentRules()`, `let base = appGlyph`.
- [ ] **Step 2: Rodar.** Esperado: erro de compilação, porque `appGlyph` não existe.
- [ ] **Step 3: Implementar**
  - `appGlyph = "checklist"`, e `barState` usa esse símbolo;
  - `barImage` desenha qualquer símbolo como SF Symbol, com o mesmo `SymbolConfiguration(pointSize: 13, weight:
    .regular)` do triângulo;
  - apagar `radarImage` e a constante antiga.
- [ ] **Step 4: Ícone do app**
  - `scripts/make-icon.swift` (roda com `swift scripts/make-icon.swift <pasta.iconset>`) desenha o quadrado grafite:
    - cantos de raio 58/256 do lado;
    - gradiente vertical de `#3D4045`, em cima, para `#1C1C1F`, embaixo;
    - o `checklist` branco, peso medium, com cerca de 46% do lado, centralizado.
  - Gera os 10 PNGs de um `.iconset` (16, 32, 128, 256 e 512, cada um @1x e @2x).
  - Depois rodar `iconutil -c icns <pasta.iconset> -o Resources/AppIcon.icns`.
  - Deixar o comando num comentário no topo do script.
  - No `Info.plist`, `CFBundleIconFile` = `AppIcon`. O `build.sh` já copia o arquivo se ele existir.
- [ ] **Step 5: Rodar os testes** (verificação padrão) → `selftest ok`. Abrir o `build/Pauta.app` no Finder e
  conferir o ícone.
- [ ] **Step 6: Commit**: `feat: ícone de checklist na barra e ícone grafite do app`

---

### Task 3: Regras do destaque e textos (funções puras)

**Files:**
- Create: `Sources/Pauta/Highlight.swift`
- Modify: `Sources/Pauta/SelfTest.swift` (novo `highlightRules()`, chamado em `run()`)

**Interfaces:**
- Consumes: `SlackItem` (`id`, `ts.date`, `userName`, `isDM`, `channelName`, `threadTs`), `PullRequest` (`id`,
  `updatedAt`, `author`), e `agoShort(_:now:)` de `Shared.swift`.
- Produces:
  ```swift
  enum Highlight: Equatable { case slack(SlackItem), pr(PullRequest)
      var id: String { get } }                       // id do SlackItem ou do PullRequest
  enum HeroState: Equatable { case loading, item(Highlight), clear }
  func pickHighlight(slack: [SlackItem], prs: [PullRequest]) -> Highlight?
  /// nil = conectado mas ainda não carregou; desconectado = [].
  func heroState(slack: [SlackItem]?, prs: [PullRequest]?) -> HeroState
  func highlightContext(_ item: SlackItem, now: Date = Date()) -> String
  func highlightContext(_ pr: PullRequest, now: Date = Date()) -> String
  func isStale(_ date: Date, now: Date = Date()) -> Bool  // mais de 24 h
  func sectionCount(_ count: Int, highlighted: Bool) -> String
  func sprintDaysText(_ days: Int) -> String
  func freeCardsText(_ count: Int) -> String
  func showsSection(connected: Bool, loaded: Bool, failed: Bool, rows: Int) -> Bool
  ```

- [ ] **Step 1: Testes que falham** (`highlightRules()`, usando os helpers `slackItem` e `PullRequest(...)` que o
  SelfTest já usa):

  ```swift
  let now = Date(timeIntervalSince1970: 1_000_000)
  // Fixtures: dm = DM da "Marina Duarte" há 120 s; ch = menção de "Rafael Lima" em #frontend há 1500 s;
  // th = thread de "Ana Souza" em #design-system há 7200 s; pr = PR de "marina-duarte" com updatedAt = now - 1500.
  precondition(pickHighlight(slack: [ch, dm], prs: [pr]) == .slack(dm))         // o mais recente vence
  precondition(pickHighlight(slack: [th], prs: [pr]) == .pr(pr))
  precondition(pickHighlight(slack: [], prs: []) == nil)
  // Empate exato: o Slack vence.
  precondition(heroState(slack: nil, prs: nil) == .loading)
  precondition(heroState(slack: nil, prs: [pr]) == .item(.pr(pr)))            // mostra o que já tem
  precondition(heroState(slack: [], prs: nil) == .loading)
  precondition(heroState(slack: [], prs: []) == .clear)
  precondition(highlightContext(dm, now: now) == "Marina Duarte, na DM, há 2 min")
  precondition(highlightContext(ch, now: now) == "Rafael Lima, em #frontend, há 25 min")
  precondition(highlightContext(th, now: now) == "Ana Souza, numa thread em #design-system, há 2 h")
  precondition(highlightContext(pr, now: now) == "de marina-duarte, atualizado há 25 min")
  precondition(!isStale(now.addingTimeInterval(-86_400), now: now) && isStale(now.addingTimeInterval(-86_401), now: now))
  precondition(sectionCount(3, highlighted: true) == "mais 3" && sectionCount(2, highlighted: false) == "2")
  precondition(sprintDaysText(0) == "termina hoje" && sprintDaysText(1) == "falta 1 dia" && sprintDaysText(4) == "faltam 4 dias")
  precondition(freeCardsText(1) == "1 card livre no projeto" && freeCardsText(6) == "6 cards livres no projeto")
  precondition(showsSection(connected: false, loaded: false, failed: false, rows: 0))   // mostra "Conectar"
  precondition(showsSection(connected: true, loaded: false, failed: false, rows: 0))    // "Carregando…"
  precondition(showsSection(connected: true, loaded: true, failed: true, rows: 0))      // faixa de erro
  precondition(!showsSection(connected: true, loaded: true, failed: false, rows: 0))    // limpa: some
  precondition(showsSection(connected: true, loaded: true, failed: false, rows: 1))     // só livres já basta
  ```

  Inclua uma asserção de empate: um item do Slack e um PR com a mesma data, em que `.slack` vence.

- [ ] **Step 2: Rodar.** Esperado: erro de compilação, porque as funções ainda não existem.
- [ ] **Step 3: Implementar em `Highlight.swift`**
  - `pickHighlight` compara `ts.date` com `updatedAt`, e o empate vai para o Slack.
  - `heroState` decide em três passos:
    - primeiro tenta `pickHighlight` com as listas que não são `nil`;
    - sem item e com alguma lista `nil`, devolve `.loading`;
    - nos outros casos, devolve `.clear`.
  - `failed` em `showsSection` quer dizer `error != nil || notice != nil`.
- [ ] **Step 4: Rodar os testes** → `selftest ok`.
- [ ] **Step 5: Commit**: `feat: regras do destaque e textos do Pauta`

---

### Task 4: Peças grafite, destaque, Slack e Revisões

**Files:**
- Create: `Sources/Pauta/Logos.swift`, `Sources/Pauta/Views/HighlightView.swift`
- Modify: `Sources/Pauta/Views/Shared.swift`, `Sources/Pauta/Views/SlackView.swift`,
  `Sources/Pauta/Views/GitHubView.swift`, `Sources/Pauta/Views/PopoverView.swift`
- Delete: `Sources/Pauta/Views/HubStrip.swift`, mais `HubChip`, `hubChip` e `HubService.tint/symbol` em `Shared.swift`,
  e as asserções de `hubChip` em `barSegmentRules()`

**Interfaces:**
- Consumes: tudo o que a Tarefa 3 produz.
- Produces (em `Shared.swift`, para a Tarefa 5 usar):
  ```swift
  extension HubService { var logoColor: Color }            // dynamicColor com os hex da Global Constraints
  struct ServiceLogo: View { var service: HubService; var size: CGFloat = 14 }
  struct GraphiteButtonStyle: ButtonStyle { var primary: Bool = true }
  struct SectionTitle<Trailing: View>: View   // init(_ title: String, @ViewBuilder trailing: () -> Trailing)
  struct CompactRow<Trailing: View>: View     // init(service: HubService, name: String? = nil, text: String,
                                              //      badge: String? = nil, dim: Bool = false, trailingIsControl: Bool = false,
                                              //      action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing)
  struct HighlightView: View                  // init(state: HeroState, slack: SlackStore, github: GitHubStore)
  ```
  `SlackView` e `GitHubView` ganham `var highlightedId: String?`.

- [ ] **Step 1: Logos**
  - `Logos.swift`: `enum Logos { static func image(_ service: HubService) -> NSImage }`.
  - Os três documentos SVG entram como string literal, copiados verbatim de
    `.superpowers/brainstorm/58692-1792857910/content/logo-{slack,jira,github}.svg` (Simple Icons, CC0; anote a
    licença num comentário).
  - O `NSImage(data:)` deles sai com `isTemplate = true` e fica em cache estático.
  - Asserção nova no SelfTest: `HubService.allCases.allSatisfy { Logos.image($0).size.width > 0 }`.
- [ ] **Step 2: Peças em `Shared.swift`**
  - **`ServiceLogo`:** `Image(nsImage:)` com `.renderingMode(.template)`, `.foregroundStyle(service.logoColor)` e
    moldura `size`.
  - **`GraphiteButtonStyle`:** fonte 12 medium, padding 4×11 e raio 6.
    - primário: fundo `.primary`, texto `Color(nsColor: .windowBackgroundColor)`;
    - secundário: fundo `.primary.opacity(0.08)`, texto `.primary`;
    - pressionado: opacidade 0,7.
  - **`SectionTitle`:** título em 11,5 semibold `.secondary`, e o trailing em 11,5 regular `.secondary`.
  - **`CompactRow`:** uma linha só, com:
    - `ServiceLogo`;
    - o nome em 13 semibold, se houver;
    - o texto em 13, numa linha só, com `\n` trocado por espaço e reticências no fim, e cor `.secondary` se houver
      nome;
    - a pílula de `badge`, igual à do `HubRow`;
    - o trailing.

    O hover e o comportamento de `trailingIsControl` seguem o `HubRow`. O padding vertical é 6, e `dim` aplica
    `.opacity(0.5)` na linha toda.
  - **`Banner`:** o fundo passa a `.primary.opacity(0.06)`, no lugar do laranja.
- [ ] **Step 3: `HighlightView`**
  - **Sem caixa.** Padding 16 nas laterais, 16 em cima e 8 embaixo.
  - **`.item(.slack(i))`:**
    - linha de contexto: `ServiceLogo` + `highlightContext(i)`, em 11,5 `.secondary`;
    - o texto entre aspas curvas (“ ”), em 18 semibold, tracking −0,25, até 4 linhas, com `\n` trocado por espaço;
    - os botões "Abrir no Slack" (primário, `slack.open(i)`) e "Marcar como visto" (secundário, `slack.dismiss(i)`).
  - **`.item(.pr(p))`:**
    - contexto: `highlightContext(p)`;
    - o título, sem aspas;
    - embaixo, `p.shortId` em 11,5 `.secondary`, mais " · rascunho" se for rascunho;
    - um botão, "Abrir no GitHub" (`github.open(p)`).
  - **`.clear`:** "Ninguém esperando você." em 18 semibold `.secondary`, e embaixo "Slack e revisões em dia." em 12
    `.secondary`.
  - **`.loading`:** `EmptyView`.
  - Troca de destaque com `.motion(state)`.
- [ ] **Step 4: Seções**
  - **Slack:**
    - `SectionTitle("Slack")`, com o trailing `sectionCount(restantes, highlighted: o destaque é do Slack)`;
    - o botão "Marcar tudo como visto" (estilo `.link`, 11,5) fica no trailing, antes da contagem;
    - linhas `CompactRow(service: .slack, name: primeiro nome, text:, dim: isStale(ts.date))`, sem o item destacado;
    - `visibleRows = 4`, depois "Ver mais N" / "Ver menos";
    - a seção inteira some quando `!showsSection(connected: configured, loaded:, failed:, rows: restantes)`;
    - sai "Nada novo no Slack". Os estados de conectar e de erro continuam como hoje.
  - **GitHub:**
    - título "Revisões" e as mesmas regras do Slack, com `connected: !needsLogin`;
    - linhas com `badge: draft ? "rascunho" : nil` e a idade em `agoShort` no trailing;
    - `needsLogin` continua mostrando "Entre no GitHub pelo terminal:" e `gh auth login`.
- [ ] **Step 5: `PopoverView`**
  - Tirar o `HubStrip`, o `ScrollViewReader` e os `Divider`s.
  - Calcular `heroState(slack: slack.configured ? (slack.loaded ? slack.items : nil) : [], prs: github.needsLogin ? [] :
    (github.loaded ? github.items : nil))`.
  - Ordem dentro da rolagem: `HighlightView`, Slack, Revisões e Jira (a Tarefa 5 refaz o Jira). Espaço de 16 entre as
    seções.
- [ ] **Step 6: Rodar os testes** → `selftest ok`. Depois
  `build/Pauta.app/Contents/MacOS/Pauta --snapshots /tmp/pauta-snap`, abrir `tela-tudo.png` e comparar com
  `logos.html` (coluna "Logos coloridos").
- [ ] **Step 7: Commit**: `feat: destaque e seções compactas no estilo grafite`

---

### Task 5: Seção "Seus cards" (Jira)

**Files:**
- Modify: `Sources/Pauta/Views/JiraView.swift`, `Sources/Pauta/Views/PopoverView.swift`,
  `Sources/Pauta/Snapshots.swift` (troca do parâmetro `jiraTab`)

**Interfaces:**
- Consumes: `SectionTitle`, `CompactRow`, `ServiceLogo` e `GraphiteButtonStyle` (Tarefa 4); `sprintDaysText`,
  `freeCardsText` e `showsSection` (Tarefa 3).
- Produces: `JiraView.init(store:connector:openSettings:freeOpen: Bool = false, expanded:)`. Ele substitui
  `tab: Tab`, e o `enum Tab` é apagado. `PopoverView.init` troca `jiraTab:` por `jiraFreeOpen: Bool = false`.

- [ ] **Step 1: Implementar**
  - **Título:** `SectionTitle("Seus cards")`, com o trailing "\(sprint.name), \(sprintDaysText(dias))". Sem sprint,
    usar `store.project`.
  - **Linhas:** `store.mine` vira `CompactRow(service: .jira, text: summary, trailingIsControl: true)`, com o
    `StatusMenu` atual no trailing. Clicar abre o card.
  - **Livres:**
    - abaixo das linhas, um botão estilo link com `freeCardsText(store.freeCount)` + " ▸" (ou " ▾" aberto), em 12
      `.secondary`;
    - aberto, mostra os grupos atuais de livres (`groupView`), com as linhas trocadas por `CompactRow` e o botão
      "Pegar" no `GraphiteButtonStyle(primary: false)`.
  - **Apagar:** o `Picker` Meus/Livres e o `summary`.
  - **Visibilidade:** a seção some quando
    `!showsSection(connected: configured, loaded:, failed:, rows: mine.count + freeCount)`.
  - `sprintIsEmpty` continua mostrando "Nenhuma sprint ativa em …".
- [ ] **Step 2: Snapshots**
  - Trocar `jiraTab: .free` por `jiraFreeOpen: true` em `tela-tudo-livres.png`.
  - Acrescentar um caso sem cards seus e com livres, `tela-so-livres.png`.
- [ ] **Step 3: Rodar os testes** → `selftest ok`. Rodar os snapshots e conferir `tela-tudo-livres.png` e
  `tela-so-livres.png`.
- [ ] **Step 4: Commit**: `feat: Seus cards com livres recolhidos e prazo da sprint`

---

### Task 6: Estados, ajustes, snapshots e README

**Files:**
- Modify: `Sources/Pauta/Views/ConnectView.swift` (`:26`, `:55`), `Sources/Pauta/Views/SettingsView.swift` (`:77`,
  `:104`), `Sources/Pauta/Snapshots.swift`, `README.md`
- Delete: `HubRow`, `RowSymbol` e `SectionHeader` de `Shared.swift`, se não sobrar uso (`grep` para conferir)

**Interfaces:**
- Consumes: `GraphiteButtonStyle`, `SectionTitle` e `ServiceLogo` (Tarefa 4).

- [ ] **Step 1: Estilo nos estados e nos ajustes**
  - `.borderedProminent` vira `GraphiteButtonStyle()`.
  - Os textos de erro em `.orange` passam a `.secondary`, com o símbolo `exclamationmark.triangle` antes.
  - O `ConnectCard` e os títulos dos ajustes usam `SectionTitle` e `ServiceLogo`.
- [ ] **Step 2: Snapshots**
  - Novos casos:
    - `tela-revisao.png`: Slack sem itens, então o destaque é um PR;
    - `tela-em-dia.png`: Slack e GitHub carregados e vazios, então aparece "Ninguém esperando você.".
  - O `tela-longa.png` passa a ter, no item mais recente do Slack, um texto de cerca de 400 caracteres com dois `\n`.
  - Manter os outros nomes.
- [ ] **Step 3: README**
  - Reescrever o parágrafo de abertura e os itens de "Slack", "Jira" e "GitHub" para a tela nova: destaque, "Revisões",
    "Seus cards", "N cards livres ▸", logos e o ícone `checklist`.
  - Acrescentar uma linha sobre `scripts/make-icon.swift`.
- [ ] **Step 4: Rodar tudo**
  - `selftest ok`;
  - `--snapshots /tmp/pauta-snap`, conferindo todos os PNGs no claro e no escuro contra `c-estados.html` e
    `logos.html`. Os itens 3 e 5 da Review Focus são conferidos aqui;
  - `scripts/build.sh --run`: o app abre, o ícone da barra é o checklist, os dados antigos aparecem sem reconectar, e só
    um processo `Pauta` roda.
- [ ] **Step 5: Commit**: `feat: estados e ajustes no estilo grafite, snapshots e README do Pauta`
