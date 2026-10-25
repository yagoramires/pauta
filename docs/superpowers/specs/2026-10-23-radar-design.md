# Radar: Jira e Slack na barra de menu (design)

Data: 2026-10-23 · Nome "Radar" é provisório.

## Intenção

O usuário trabalha com Jira (sprints, cards ACME-xxxx) e Slack num workspace da empresa. Ele quer bater o olho na barra de menu e saber:

- se tem **coisa nova pra fazer** (cards livres na sprint),
- **como estão os cards dele** e mudar o status sem abrir o Jira,
- se alguém **mandou DM ou marcou ele** no Slack, mesmo com o app do Slack fechado.

O sucesso é parar de abrir o Jira só pra ver se tem algo pra pegar e parar de perder mensagem porque o Slack tava fechado.

## Metas

1. **Dois ícones separados** na barra de menu (o usuário escolheu entre um e dois, com mockup): 📋 Jira e 💬 Slack, cada um com o seu popover.
2. **Jira, sprint ativa:**
   - Aba **Meus**: cards da sprint atribuídos ao usuário, com o status atual. O status é um menu que lista as transições disponíveis daquele card, e escolher uma transiciona ali mesmo.
   - Aba **Livres**: cards e sub-tarefas da sprint sem responsável, ainda não concluídos, cada um com um botão **Pegar** que atribui o card ao usuário.
   - **Resumo da sprint** no rodapé: contagem por coluna/status e dias restantes.
   - Clicar num card abre ele no navegador.
   - Ícone mostra o número de cards livres (some quando é zero).
3. **Slack:**
   - Lista de **DMs e menções não lidas**: quem, onde (DM ou #canal), trecho e há quanto tempo.
   - Clicar abre a conversa no app do Slack (deep link `slack://`).
   - Ícone mostra o total de não lidas (some quando é zero).
   - **Notificação do macOS** quando chega DM/menção nova.
4. Funciona com o Slack e o Jira fechados, atualizando sozinho de tempos em tempos.

## Fora do escopo (por enquanto)

- Visão do "time todo" com os cards de cada um. O usuário quer só os dele e os livres.
- Mensagens de canal que não mencionam o usuário.
- Responder Slack, comentar ou editar card além do status e do responsável.
- Múltiplos workspaces/sites, GitHub/PRs, publicação no GitHub. Antes de criar um repo, perguntar.

O usuário disse "inicialmente é isso, vamos ajustando depois". Então o v1 deve ser pequeno e fácil de mexer.

## Anti-metas (o que faria ser um fracasso mesmo funcionando)

- **Notificação duplicada** com a do próprio Slack, ou spam de notificação para a mesma mensagem a cada atualização.
- Mudar status ou responsável de um card **sem o usuário ter clicado**, ou errar o card.
- Estourar rate limit do Slack/Jira a ponto de o token ser bloqueado ou de incomodar o workspace da empresa.
- Pedir senha do Keychain a cada rebuild (aconteceu no Hub, ver "Credenciais").
- Contador mostrando coisa já lida como não lida (o usuário para de confiar no número).

## Restrições

- **Workspace do Slack é da empresa.** O usuário acha que as permissões estão no padrão (membros podem instalar apps). Ninguém confirmou. Primeira coisa a testar: criar o app em api.slack.com/apps e ver se aparece "Install to Workspace" ou "Request to Install". Se precisar de aprovação, parar e falar com o usuário (plano B fica pra essa conversa). O app nunca usa token de sessão do navegador/cookies.
- **Jira também tem teste antes de construir** (*decisão do Claude*): o site da empresa pode bloquear API tokens (Atlassian Guard) ou só aceitar tokens com escopo, que vão em `api.atlassian.com/ex/jira/{cloudId}`. Primeiro passo: `curl -u email:token <site>/rest/api/3/myself`. Se bloquear, parar e falar com o usuário (o plano B seria OAuth 3LO).
- **Só APIs oficiais:** Jira Cloud REST (v3 + Agile 1.0) e Slack Web API com **user token** (`xoxp-`).
- Workspace e Jira são da empresa, então tudo roda só na máquina do usuário e nada sai pra serviço de terceiros.

## Como (o que já foi decidido)

**Pelo usuário:**
- Dois ícones separados (mockup B).
- Jira mostra "Meus" e "Livres", com troca de status pelo menu.
- Slack mostra só DMs e menções.

**Pelo Claude (podem ser vetadas):**
- Mesmo stack e padrão dos outros apps de menu bar do usuário (Dose, Hub e Deck): SwiftPM, AppKit `NSStatusItem` + `NSPopover` com SwiftUI, `scripts/build.sh --run`, assinatura "Aero Local Signing", bundle id `local.radar`, pasta `~/Documents/radar`. Copiar `build.sh`, `setup-signing.sh` e `make-icon.swift` do Dose.
- Com só CommandLineTools, o `@State` do SDK do macOS 27 quebra. Usar o wrapper `@ViewState` igual ao `Views/Root.swift` do Dose.
- Fechar o popover clicando fora com um monitor global de NSEvent, como no Dose (`.transient` sozinho não fechou).
- **Atualização a cada 2 min por padrão** e ao abrir o popover. Botão ⟳ manual.
- **"Pegar"** atribui o card ao usuário (`PUT /rest/api/3/issue/{key}/assignee` com o accountId de `/myself`). Não muda o status.
- **Notificação só quando o Slack.app não está rodando** (checar `NSWorkspace.runningApplications` pelo bundle id `com.tinyspeck.slackmacgap`), pra não duplicar com a do Slack. Cada mensagem notifica uma vez só (guardar o `ts` das já notificadas).
- Credenciais coladas na tela de ajustes (⚙︎):
  - Jira: URL do site, e-mail e API token (id.atlassian.com → Security → API tokens).
  - Slack: user token `xoxp-` que aparece em "OAuth & Permissions" depois de instalar o app no workspace. Assim não precisa de fluxo OAuth nem de URL de callback.

## Credenciais

Usar o mesmo esquema do Hub: `~/Library/Application Support/Radar/credentials.json` com permissão 0600, **não o Keychain**. Com certificado que não é da Apple, a partição do Keychain fica presa ao cdhash, e cada rebuild pede a senha. Nunca logar tokens. Log em `~/Library/Logs/Radar/radar.log`.

## Detalhes técnicos que guiam o builder

**Jira**
- "Sprint ativa" = `sprint in openSprints()` restrito a um projeto. O projeto vem do ajuste (padrão `ACME`, *chute*: as chaves de card do usuário são ACME-xxxx). Sem projeto, `openSprints()` pega sprints de outros times.
- Meus: `project = X AND sprint in openSprints() AND assignee = currentUser()`.
- Livres: `... AND assignee is EMPTY AND statusCategory != Done`. **Sub-tarefas entram** (o usuário pediu). Pode estar em qualquer coluna, menos as concluídas (*decisão do Claude*, já que o usuário não respondeu sobre colunas). Assim um card solto em Code Review também aparece. Se virar ruído, trocar para `statusCategory = "To Do"`. Antes do "Pegar", confirmar que o card continua sem responsável.
- **Sub-tarefas em accordion** (o usuário pediu "escondido mas expansível"): as sub-tarefas livres ficam agrupadas embaixo do card pai, fechadas por padrão, com uma seta e a contagem ("▸ 3 sub-tarefas"). Se o pai já tem responsável, ele aparece só como cabeçalho do grupo, sem "Pegar" (*decisão do Claude*). Cada sub-tarefa tem o próprio "Pegar". O número do ícone conta todos os itens livres, cards e sub-tarefas (*decisão do Claude*).
- Resumo: contagem por `status` dos cards da sprint inteira, na ordem das colunas do board quando der (Agile `board/{id}/configuration`). Se não der, ordenar por `statusCategory`.
- Dias restantes: `endDate` da sprint ativa (Agile `board/{id}/sprint?state=active`). O board é descoberto pelo projeto, e se tiver mais de um, o ajuste deixa escolher.
- Transições: `GET/POST /rest/api/3/issue/{key}/transitions`. Mostrar as que vierem, não uma lista fixa. Transição que exige campo (tela de transição) mostra erro amigável e oferece "abrir no Jira".
- Depois de transicionar ou pegar, atualizar a lista na hora.

**Slack (user token; scopes mínimos de leitura)**
- Scopes: `im:read`, `im:history`, `mpim:read`, `mpim:history`, `channels:read`, `channels:history`, `groups:read`, `groups:history`, `users:read`, `search:read`.
- "Não lida" = mensagem de outra pessoa com `ts` maior que o `last_read` da conversa (`conversations.info`). DM/MPIM: todas as não lidas. Canal: só as que contêm `<@meuUserId>`.
- Achar menções: `search.messages` com a menção, recentes. Depois, pra cada canal encontrado, comparar com o `last_read`. Achar DMs com atividade: `conversations.list types=im,mpim` + `conversations.history oldest=last_read`.
- **Threads** (*decisão do Claude*): a API não tem marcador de lido para thread. Menções dentro de thread entram (a `search.messages` acha), e também respostas em thread de DM. Um item sai da lista quando: o `last_read` da conversa passa dele, o usuário clica nele no Radar ou clica em "marcar tudo como visto" no popover. O Radar guarda esses "vistos" localmente. Isso evita o contador preso em coisa já lida pela aba Threads do Slack.
- Respeitar rate limits (Tier 2/3): limitar às conversas com atividade recente, fazer cache de nomes de usuário/canal e tratar 429 com `Retry-After`. Se ficar caro, `shortcut:` documentado (ex.: só DMs com atividade nos últimos N dias).

## O que fica com o builder

- Layout fino do popover (seguir o mockup B: segmento Meus/Livres, pílulas de status, botão Pegar, rodapé com "atualizado há X" + ⟳ + ⚙︎).
- Ícones da barra (SF Symbols) e do app.
- Estrutura de arquivos e nomes.
- Estados de erro/vazio: sem credencial → abre ajustes; token inválido → aviso no popover; sem sprint ativa → "nenhuma sprint ativa".
- Ferramentas de debug no padrão dos outros apps: `Radar --snapshots <dir>` (PNG das telas com dados falsos, sem tocar na tela do usuário), `Radar --selftest` (asserts da lógica de não lida, contagens e dedupe de notificação), `Radar --dump` (o que as APIs retornam, sem tokens).
- O mockup de referência está em `.superpowers/brainstorm/*/content/layout.html` (opção B).
