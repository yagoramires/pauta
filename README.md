# Pauta

Jira, Slack e GitHub numa tela só, pela barra de menus do macOS: o que espera por você, com o mais recente em destaque.

![Pauta](docs/print.png)

O print usa dados de exemplo.

[Baixar a última versão](https://github.com/yagoramires/pauta/releases/latest) · [Reportar problema](https://github.com/yagoramires/pauta/issues/new)

## Instalar

1. Baixe o `Pauta-x.y.z.dmg` (ou o `.zip`) na [página de releases](https://github.com/yagoramires/pauta/releases/latest) e arraste o **Pauta.app** pra pasta **Aplicativos**.
2. Abra o Pauta. Como ele não é assinado com um certificado pago da Apple, na primeira vez o macOS avisa que não conseguiu verificar o desenvolvedor. Vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim**. No macOS 14 também dá para clicar com o botão direito no app → **Abrir**. Pelo Terminal também resolve: `xattr -dr com.apple.quarantine /Applications/Pauta.app`
3. Na primeira execução o Pauta entra nos itens de início do sistema.

Requer macOS 14 ou mais novo. Roda nativo em Apple Silicon e Intel. Também dá pra compilar do código (veja **Build local**).

### Pelo NeyHub

Quem usa o [NeyHub](https://github.com/yagoramires/neyhub) pode instalar o Pauta pela Loja dele (o `Pauta-x.y.z.neyplugin` do release). Aí o Pauta roda dentro do NeyHub, com as mesmas credenciais, estado do Slack e ajustes do avulso: o ícone e o popover da barra são os mesmos, a **tela do Pauta** aparece na janela do NeyHub, a permissão de notificações é a do NeyHub (pela tela **Permissões**), o NeyHub cuida do login, das atualizações e de mostrar ou esconder o ícone, e os ajustes não têm **Onde aparece**, **Sair** nem a linha **Atualização pronta**. Tocar numa notificação com a tela ligada abre a tela do Pauta no NeyHub e a mensagem no Slack. Feche o Pauta avulso antes: se o NeyHub já roda o Pauta, o avulso avisa (um aviso só), sai dos itens de login e fecha.

### Desinstalar

1. Nos ajustes (⚙︎), clique em **Sair do Pauta** e tire o Pauta de **Ajustes do Sistema → Geral → Itens de Início**.
2. Apague o **Pauta.app** de Aplicativos. Pelo NeyHub, é só desinstalar no card do Pauta (para o relógio, a vigia da área de transferência e as notificações na hora).
3. Os dados continuam em `~/Library/Application Support/Pauta/`. Pra apagar tudo (sem volta, inclusive os tokens): `rm -rf ~/Library/Application\ Support/Pauta ~/Library/Logs/Pauta; defaults delete local.pauta`

## Permissões

- **Notificações**: para avisar de mensagens novas do Slack quando o app do Slack está fechado (clicar abre a conversa). Dá pra desligar em Exibição. Dentro do NeyHub a permissão é do NeyHub e o Pauta nunca pede ao sistema.
- **Colar**: ao conectar Slack ou Jira, o macOS pode perguntar "Permitir colar?". Escolha **Permitir**, senão o Pauta não consegue ler o token copiado.
- O Pauta só lê o Slack (user token, sem bot) e só usa as APIs oficiais. O GitHub usa o `gh` que já está logado no terminal.

O app se chamava Radar: na primeira vez, a pasta do Radar é movida para a do Pauta, sem reconectar nada. O macOS pede de novo a permissão de notificações e a de colar; se sobrar "Radar" em Ajustes do Sistema → Geral → Itens de Início, remova.

### Privacidade

Os tokens só existem no arquivo local de credenciais (tabela abaixo), nunca no Keychain, nunca vão pra lugar nenhum além do Jira/Slack e nunca são escritos no log. A área de transferência só é vigiada enquanto um "Conectar" está aguardando (no máximo 10 min).

Tokens, estado e log ficam todos locais, os mesmos no avulso e no NeyHub. Além do Slack, do Jira e da API do GitHub, a única conexão é a consulta à API pública do GitHub (`api.github.com`) pra saber se tem versão nova do Pauta, e o download dela.

| O quê | Onde |
| --- | --- |
| Credenciais | `~/Library/Application Support/Pauta/credentials.json` (arquivo 0600, pasta 0700) |
| Estado do Slack (vistos, notificações já enviadas) | `~/Library/Application Support/Pauta/slack-state.json` |
| Links das notificações (para o toque abrir a mensagem certa, os 200 mais recentes) | `~/Library/Application Support/Pauta/avisos.json` (0600) |
| Log | `~/Library/Logs/Pauta/pauta.log` |

## Como usar

Jira, Slack e GitHub numa tela só, pela barra de menus do macOS. Um ícone (o `checklist`): um clique abre um popover que começa pelo **destaque**, a coisa mais recente que espera por você (uma mensagem do Slack ou um PR pedindo revisão), em letra grande e com as ações embaixo. Sem ninguém esperando, o destaque vira "Ninguém esperando você.". Embaixo ficam as seções, em linhas compactas com o logo de cada serviço, e um rodapé quieto com "Atualizado há X", ⟳ e ⚙︎. Seção sem nada para mostrar some.

- **Slack**: DMs e menções não lidas, sem a que está no destaque, com o texto já limpo (as 4 mais novas; "Ver mais N" mostra o resto). Marcar como visto tira o item da lista; "Marcar tudo como visto" marca só as mensagens que a tela mostra. Chegou algo novo e o Slack está fechado, vem uma notificação (clicar abre a conversa).
- **Revisões** (GitHub): os PRs abertos que esperam a **sua** revisão, sem o que está no destaque (título, há quanto tempo; rascunhos aparecem marcados). Clicar abre o PR. Sem notificação.
- **Tela do Pauta** (modo **Janela**, ou a tela do Pauta dentro do NeyHub): o popover aberto em três colunas, Slack, GitHub e Jira lado a lado, com as pílulas e a busca ("Buscar em tudo…") no topo e o destaque embaixo delas. O que não cabe no popover: a mensagem do Slack inteira, com o canal e a hora; nos PRs, o repositório, o número, o autor e os checks (✓ checks, ✕ N falhou); a seção **Seus PRs**, com os seus PRs abertos, as aprovações e se já estão prontos pra merge; e os seus cards em linhas, com o status mudando pelo menu do card e "N cards livres no projeto ▸". No rodapé, "Atualizado há X", ⟳ e **Configurações**. Numa janela estreita as colunas ficam uma embaixo da outra.
- **Seus cards** (Jira): os seus cards, com o nome da sprint e quantos dias faltam, e uma linha "N cards livres no projeto ▸" que abre os cards livres do projeto (agrupados). Dá pra mudar o status de um card e pegar um card livre sem abrir o navegador. Card do Jira nunca vira destaque.
- **O ícone da barra** é sempre o mesmo símbolo (`checklist`) com o total (Slack + Jira + GitHub) ao lado quando passa de 0, em que o Jira conta seus cards mais os livres, como a pílula Jira; um triângulo no lugar do símbolo avisa quando algum serviço falhou. O detalhe por serviço ("Pauta: Slack 3, Jira 2, GitHub 5") fica no tooltip. O ícone do app é gerado por `scripts/make-icon.swift`.
- **Atualiza sozinho**: a cada 2 minutos (ajustável em Exibição), ao abrir o popover (o que tiver mais de 15 s) e ao acordar o Mac. Na primeira execução o Pauta entra nos itens de início do sistema.
- Só lê o Slack (user token, sem bot) e só usa as APIs oficiais.

### Pílulas e busca

No topo do popover fica uma linha com a lupa e as pílulas **Tudo N**, **[Slack] N**, **[GitHub] N** e **[Jira] N** (só as dos serviços conectados). Cada uma mostra só a sua seção: Slack e GitHub com o destaque do próprio serviço ("Nada no Slack." / "Nenhum PR esperando você." quando vazio), Jira sem destaque e com os cards livres já abertos. As contagens: mensagens visíveis do Slack, PRs, seus cards mais os livres; Tudo é a soma.

A **busca** abre na lupa ou com **⌘F**: o campo "Filtrar por pessoa, canal, card" ocupa a linha de cima e as pílulas descem. Ela procura no nome da pessoa, no canal e no texto do Slack; no título, no repositório e no autor do PR; na chave e no título dos cards (seus e livres, sub-tarefas incluídas). Ignora maiúsculas e acentos; várias palavras exigem todas. Com texto digitado o destaque some, cada seção mostra só o que bate (seção vazia some, o Slack mostra tudo sem "ver mais"), os livres que batem aparecem numa seção "Livres" com o "Pegar", o trecho achado ganha um fundo cinza, as pílulas contam só os resultados e o rodapé diz "N resultados". Sem nada: "Nada com “termo”.". **Esc** (ou o ⊗) limpa o texto; com ele vazio, fecha a busca. Ao reabrir o popover, volta para Tudo com a busca fechada.

### Conectar (só clicar)

Abra o Pauta e clique no ícone: Slack e Jira sem conexão mostram um botão **Conectar Slack** / **Conectar Jira** (também nos ajustes ⚙︎, onde vira **Desconectar** depois de conectado). O Pauta abre a página certa no navegador e fica **"Aguardando você copiar o token…"** (até 10 min, dá pra cancelar). Quando você clica em **Copiar** na página, ele pega o token sozinho da área de transferência, valida na API, salva, limpa a área de transferência (se ela ainda tem o token) e mostra "Conectado como X". Se a validação falhar, mostra o erro e continua esperando. Só texto no formato do token do serviço é considerado (o site do Jira precisa ser https); qualquer outra coisa copiada é ignorada. Na primeira vez o macOS pode perguntar "Permitir colar?": escolha **Permitir**, senão o Pauta não consegue ler o token copiado. O fluxo continua mesmo com o popover fechado (ao ir ao navegador ele fecha sozinho).

#### Slack

1. **Conectar Slack** abre o "criar app a partir de manifesto" do Slack já preenchido (só escopos de leitura, user token).
2. Escolha o workspace da empresa e clique em **Criar**; depois **Install to Workspace** e **Permitir**.
3. Em **User OAuth Token**, clique em **Copy**. Se aparecer **"Request to Install"**, a empresa precisa aprovar: o Pauta fica esperando.

> Se o Slack ignorar o manifesto na URL, crie manualmente: <https://api.slack.com/apps> → **Create New App → From a manifest** e cole o conteúdo de `slack-manifest.yml`.

#### Jira

1. Digite o e-mail e o site do Jira (o endereço que aparece no navegador, com `https://`) e clique em **Conectar Jira**.
2. Na página de tokens, clique em **Criar token de API** (o sem escopos), dê qualquer nome e clique em **Criar**.
3. Clique em **Copiar**. O Pauta valida com `GET /rest/api/3/myself`: e-mail ou token errados aparecem como "e-mail ou token não bateram".

Sem projeto nos ajustes, o Pauta mostra os cards das sprints abertas de todos os projetos. Para um só, preencha a chave do projeto em **Ajustes → Avançado**; se ele tiver mais de um board, escolha o board ali também.

#### GitHub

Sem login nem token para copiar: o Pauta usa o `gh` que já está logado no terminal (`gh auth token`, procurado em `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin`; o token fica só em memória e é relido se a API devolver 401). Sem `gh` ou sem login, a seção mostra: `gh auth login`.

#### Avançado (colar token manualmente)

Em **Ajustes → Avançado (colar token manualmente)** ficam os campos de antes: site, e-mail e API token do Jira, projeto, board e user token do Slack.

## Atalhos

| Atalho | O que faz |
| --- | --- |
| `⌘F` | Abre a busca do popover (ou clique na lupa) |
| `Esc` | Limpa o texto da busca; com ele vazio, fecha a busca |
| `⌘,` | No modo **Janela**: abre as configurações |
| `⌘Q` | No modo **Janela**: fecha o Pauta |

Nos campos de texto valem os atalhos de edição de sempre (`⌘Z`, `⇧⌘Z`, `⌘X`, `⌘C`, `⌘V`, `⌘A`), pelo menu **Editar**.

## Modos de exibição

| Ajuste | Padrão | Efeito |
| --- | --- | --- |
| Menções em canais | ligado | Desligado, o Slack mostra só DMs: no destaque, na lista, na pílula, no número da barra e nas notificações. |
| Cards livres | ligado | Desligado, somem a linha "N cards livres" e os livres da pílula Jira, da busca e do número da barra. |
| Densidade | Confortável | Compacta: linhas mais baixas, destaque menor e menos espaço entre as seções. |
| Atualizar a cada | 2 min | 1, 2 ou 5 min; vale na hora, sem reiniciar. |
| Notificações do Slack | ligado | Desligado, o Pauta não posta notificação nenhuma (o registro de "já notificado" continua andando). |

Os ajustes valem na hora (tela e ícone da barra) e ficam em `UserDefaults` (domínio `local.pauta`, o mesmo no avulso e no NeyHub), separados das credenciais. O visual é o tema Grafite (escuro, com acento verde-limão), o mesmo do NeyHub.

Em **Onde aparece**, nos ajustes do avulso, você escolhe onde o Pauta aparece, e a troca vale na hora:

- **Barra de menus** (o padrão, como na 0.1.0): só o ícone com o popover.
- **Janela**: ícone no Dock e a tela do Pauta. Clicar no ícone do Dock traz a janela de volta; o menu **Pauta → Configurações…** (`⌘,`) abre as configurações.
- **Os dois**.

Desligar os dois não vale: o outro volta a ligar. Dentro do NeyHub o modo é escolhido no card do Pauta, na Loja.

## Atualizações

O Pauta confere o Slack, o Jira e o GitHub sozinho: a cada 2 minutos (ajustável em Exibição), ao abrir o popover (o que tiver mais de 15 s) e ao acordar o Mac.

Desde a 0.2.0, o app também se atualiza: confere 5 s depois de abrir e a cada 6 h se tem versão nova, baixa sozinho e só troca o app quando você fecha o Pauta (ou clica em **Reiniciar agora**, nos ajustes): nunca reinicia sozinho no meio do uso. Na próxima abertura, mostra uma vez a janela **Novidades** com o que mudou. A versão baixada só é instalada se tiver sido assinada pelo mesmo certificado do app em uso, então a permissão de notificações continua valendo. Dentro do NeyHub, quem atualiza é o NeyHub.

Quem está na 0.1.0 precisa instalar a 0.2.0 uma vez à mão (ela ainda não tinha atualização automática). Os dados ficam onde estão.

## Build local

Precisa só das Command Line Tools (sem Xcode).

```sh
git clone https://github.com/yagoramires/pauta.git && cd pauta
scripts/setup-signing.sh   # uma vez: certificado local de assinatura
scripts/build.sh --run     # compila, assina e abre build/Pauta.app
scripts/selftest.sh        # testes; imprime "selftest ok"
```

O NeyKit (tema Grafite, `@ViewState`, contrato de plugin) e o NeyKitApp (atualização, novidades) vêm do checkout do
[neyhub](https://github.com/yagoramires/neyhub) ao lado (`../neyhub`); para outro lugar, defina `NEYHUB_PATH`.

Sem o certificado "Aero Local Signing" o build falha: a permissão de notificações e o item de login ficam presos à assinatura, o NeyHub só carrega plugins e as atualizações só entram com ela.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam o `@ViewState` do NeyKit, que faz a mesma coisa.

### Opções de linha de comando

Rodam sem abrir janela. Binário: `build/Pauta.app/Contents/MacOS/Pauta`.

| Flag | O que faz |
| --- | --- |
| `--check` | Confere as credenciais salvas nas APIs reais (sem credenciais, diz o que falta e sai com 1) |
| `--dump jira` | Imprime boards, sprint ativa, seus cards e os livres |
| `--dump slack` | Imprime DMs e menções não lidas |
| `--dump github` | Imprime os PRs que esperam sua revisão e os seus PRs abertos, `repo#número título` de cada (usa o `gh`) |
| `--snapshots <pasta>` | Desenha cada tela (popover: tudo, cada pílula, busca com e sem resultado, revisão, em dia, sem sprint, conectar, aguardando, erro, compacta, ajustes do avulso e do NeyHub; a tela do Pauta larga, estreita, com busca, Jira, conectar, erro e ajustes; as configurações; o ícone da barra) em PNG com dados de exemplo, sem tocar nas credenciais, na rede, na área de transferência nem no `gh` |
| `--selftest` | Roda as verificações internas e imprime `selftest ok` (rode com `scripts/selftest.sh`; usa pasta e padrões temporários e um centro de notificações falso) |

### Como funciona

O miolo fica em `Sources/PautaCore` e é o mesmo no app avulso e no plugin do NeyHub:

| Arquivo | Papel |
| --- | --- |
| `PautaApp.swift` | Ícone e popover da barra, modos de exibição, configurações, toque nas notificações e `stop()` (desinstalar no NeyHub: para o relógio, o acordar, a vigia da área de transferência e os avisos). Recebe os `UserDefaults`, se está hospedado e a versão. |
| `AppPaths.swift` | Onde ficam os dados (`Application Support/Pauta`) e a migração da pasta do Radar; o selftest troca por uma pasta temporária. |
| `Notifier.swift` | Notificações com o prefixo `local.pauta.` e o `avisos.json`. O centro de notificações fica atrás de um protocolo, que o selftest troca por um falso. Dentro do NeyHub nunca define o delegate nem pede permissão. |
| `Slack/`, `Jira/`, `GitHub/` | Cliente, modelo e estado de cada serviço. O GitHub usa o token do `gh`: a busca REST para as revisões e uma consulta GraphQL para os checks e os seus PRs. |
| `Connect/` | Os fluxos "Conectar" e a vigia da área de transferência. |
| `Views/` | O popover (`PopoverView.swift` e as seções), a tela do Pauta (`ScreenView.swift`) e os ajustes, em SwiftUI no tema Grafite do NeyKit. |
| `SelfTest.swift`, `Snapshots.swift` | `--selftest` e `--snapshots`. |

As cascas: `Sources/Pauta` (app avulso: confere se o NeyHub já roda o Pauta, atualização e novidades do NeyKitApp, e os modos `--selftest`, `--snapshots`, `--check` e `--dump`) e `Sources/PautaPlugin` (o `libPautaPlugin.dylib` que o NeyHub carrega; linka só o NeyKit). O `Info.plist` declara `NeyHubAware = true` porque o avulso chama `HubCheck.leaveForHub` ao abrir: com essa chave o NeyHub não mostra o alerta dele quando o avulso abre.

### Publicar uma versão

1. Suba a versão em `Resources/Info.plist` (`CFBundleShortVersionString` e `CFBundleVersion`) e escreva a seção `## [x.y.z]` do `CHANGELOG.md` (vira a nota do release e a janela Novidades).
2. `scripts/release.sh` gera em `dist/` o `Pauta-x.y.z.dmg`, o `Pauta-x.y.z.zip` (o app, que a atualização automática baixa) e o `Pauta-x.y.z.neyplugin` (o plugin do NeyHub). Só empacota.
3. Commit, push e `NEYHUB_CONFIRM_PUBLISH=yes scripts/release.sh --publish` para criar o release.

O release **precisa ser assinado com o mesmo certificado** das versões anteriores, senão os apps já instalados recusam a atualização automática.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
