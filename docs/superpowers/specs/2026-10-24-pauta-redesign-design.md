# Pauta: novo nome, ícone e tela do Radar

Data: 2026-10-24. Base: o Radar como está em `main` (commit `48c7624`), descrito no README e em
`docs/superpowers/specs/2026-10-23-radar-design.md`. Os mockups aprovados ficam em
`.superpowers/brainstorm/58692-1792857910/content/` (`c-estados.html`, `logos.html`; o estilo escolhido é o "grafite").

## Por quê

O usuário achou o app "sem sal, parece feito por uma criança", e o nome "Radar", fraco. Hoje o popover é uma lista
padrão do SwiftUI: três chips cinzas no topo, barrinhas coloridas por seção, tudo com o mesmo peso, e nada diz o que é
mais urgente. O ícone da barra é um radar desenhado à mão, sem identidade.

O trabalho do app é responder em um olhar: **"quem está esperando por mim agora?"**. A tela nova coloca a coisa mais
recente que alguém espera de você em destaque, com ação direta, e o resto compacto embaixo.

## Objetivos

- Renomear o app para **Pauta**.
- Ícone: SF Symbol **`checklist`**. Na barra de menus, como template. Como ícone do app, branco sobre um quadrado
  grafite (referência: `tile-grafite.png` nos mockups).
- Popover no formato **"destaque + resto compacto"** (formato C), no estilo **grafite**, com os **logos coloridos** de
  Slack, Jira e GitHub no lugar dos símbolos de hoje.
- Funcionar igual de bem no claro e no escuro (o app segue o modo do Mac).

## Não objetivos

- Nenhuma mudança no que o app busca, em como conecta ou em quando atualiza ou notifica. Polling, notificações, o
  fluxo "Conectar" (vigia da área de transferência), as credenciais e as APIs ficam como estão.
- Nenhuma ação nova (responder no Slack, "visto" para PR, adiar). O Slack continua só leitura.

## Anti-objetivos (falhou mesmo se "funcionar")

- Tela com cara de kit genérico: cartões iguais com sombra, chips cinzas, gradientes, rótulos em CAIXA ALTA.
- Perder dados ao renomear: o usuário não pode ter que reconectar Slack ou Jira, nem perder o estado de "vistos".
- Cor espalhada. Os logos dos serviços são as únicas cores da tela.

## A tela (popover)

Largura de 360 como hoje, com rolagem e altura máxima como hoje. De cima para baixo:

### 1. Destaque

- **Quem entra:** o item mais recente (por data) entre as mensagens não lidas do Slack (DMs e menções) e os PRs que
  esperam sua revisão. Card do Jira nunca vira destaque. O item em destaque **não se repete** na lista da sua seção.
- **Data do PR:** é o `updatedAt` que o app já busca, a última mudança no PR. O GitHub não informa quando pediram a
  revisão, e buscar isso está fora do escopo. Decisão do usuário: aceitar que um PR antigo com commit novo às vezes
  tome o destaque de uma mensagem do Slack.
- **Slack:**
  - linha pequena em cinza: logo do Slack, depois "Marina Duarte, na DM, há 2 min" ou "…em #canal" / "…numa thread", como
    o contexto de hoje;
  - o texto da mensagem entre aspas, grande (cerca de 18 pt, semibold, tracking levemente negativo), até umas 4 linhas
    e depois reticências;
  - botões **"Abrir no Slack"** (primário) e **"Marcar como visto"** (secundário). Marcou: o próximo item mais recente
    sobe para o destaque.
- **PR:**
  - linha pequena: logo do GitHub, depois "de marina-duarte, atualizado há 25 min" (o autor do PR e o `updatedAt`);
  - o título do PR, grande;
  - embaixo, em cinza, `repo#número`, mais "rascunho" se for rascunho;
  - um botão, **"Abrir no GitHub"**.
- **Ninguém esperando** (Slack e GitHub vazios, ou desconectados): o destaque vira a frase "Ninguém esperando você.",
  em cinza escuro, sem botões, e embaixo, em cinza, "Slack e revisões em dia."
- **Sem caixa:** o destaque não é um cartão. É o próprio topo do popover, com o texto grande sobre o fundo.

### 2. Seções compactas, nesta ordem

Cada seção tem um título pequeno em cinza (cerca de 11,5 pt, semibold; não é caixa alta), com um complemento à direita
em cinza regular. Seção sem itens **não aparece**: a tela encolhe conforme você limpa.

- **Slack**, com "mais N" à direita (N = não lidas fora o destaque).
  - Cada linha: logo, primeiro nome em negrito, o texto numa linha com reticências, idade à direita.
  - Mostra até 4 linhas, depois "ver mais N", que expande como hoje.
  - "Marcar tudo como visto" continua existindo; onde fica é decisão do builder.
- **Revisões** (era "GitHub"), com a contagem à direita.
  - Cada linha: logo, título com reticências, "rascunho" (pílula) se for rascunho, idade.
  - Clicar abre o PR.
- **Seus cards** (Jira), com "Sprint Lince, faltam 4 dias" à direita.
  - Cada linha: logo do Jira, título com reticências, pílula com o status e ▾ que muda o status, como hoje.
  - Abrir o detalhe do card continua como hoje.
  - Embaixo, uma linha "N cards livres no projeto ▸" que abre os livres (agrupados como hoje, com a ação de pegar o
    card). Isso substitui as abas Meus/Livres.
  - **Sai** a linha de resumo da sprint ("To Do 9, Em andamento 6, Review 4, Done 14").

**Idade:** item com mais de 24 h aparece desbotado (cerca de 50% de opacidade).

### 3. Rodapé

Igual ao de hoje: "Atualizado há X", ⟳ e ⚙︎.

### O que sai

- A faixa de três chips do topo (`HubStrip`), e com ela a rolagem até a seção.
- As barrinhas coloridas ao lado dos títulos das seções.

### Estados de serviço

Desconectado, aguardando token, erro e sem `gh`: o comportamento e os textos são os de hoje, mas no estilo novo. Eles
aparecem na seção do serviço; o Slack e o GitHub ganham uma seção mesmo sem itens nesse caso. Um serviço desconectado
nunca alimenta o destaque.

### Ajustes

Mesmo conteúdo e mesmo fluxo de hoje, com a tipografia, os botões e as cores do estilo grafite. Onde aparecer "Radar",
passa a ser "Pauta".

## Estilo grafite (tokens)

- **Fonte:** a do sistema (SF Pro) em tudo. Sem serifa e sem fonte mono. Hierarquia por tamanho e peso:
  - destaque: ~18 pt semibold;
  - linhas: 13 pt;
  - títulos de seção e metadados: ~11,5 pt;
  - nomes de pessoa nas linhas: semibold.
- **Cores:**
  - só as semânticas do sistema (`primary`, `secondary`, `tertiary`; fundo do popover como hoje);
  - botão primário: preenchido com a cor do texto (preto no claro, quase branco no escuro) e texto invertido;
  - botão secundário: fundo cinza translúcido;
  - pílulas (status, rascunho): fundo cinza translúcido;
  - sem acento colorido.
- **Logos** (14 pt, nas cores das marcas):

  | Logo | Claro | Escuro |
  | --- | --- | --- |
  | Slack | `#4A154B` | `#E01E5A` |
  | Jira | `#0052CC` | `#4C9AFF` |
  | GitHub | `#181717` | `#F2F2F4` |

  Desenhos: os do Simple Icons (CC0), já baixados em `logo-slack.svg`, `logo-jira.svg` e `logo-github.svg` na pasta
  dos mockups.
- **Espaço:** margens laterais de 16, linhas com ~6 de respiro vertical, seções separadas por espaço e não por
  divisórias.

## Barra de menus

Mesmo comportamento de hoje: símbolo e total quando passa de 0, e o triângulo no lugar do símbolo quando algum serviço
falhou. Muda só o símbolo, que passa a ser o SF Symbol `checklist` em template, no lugar do `radarImage`. O tooltip
passa a dizer "Pauta: Slack 3, Jira 2, GitHub 5".

## Renomear para Pauta

- **Onde muda:**
  - nome exibido e do bundle;
  - executável e target do Swift Package;
  - `build/Pauta.app`, o zip de `dist/` e o `pkill` do `build.sh`;
  - textos da interface, tooltip, README e o nome no `slack-manifest.yml`.
- **Bundle id:** `local.pauta`. Com isso o macOS pede de novo a permissão de notificações e de colar. Isso é aceitável,
  mas o README deve avisar.
- **Dados sem perda:**
  - na primeira execução, se `~/Library/Application Support/Pauta` não existir e `…/Radar` existir, mover a pasta e
    manter as permissões (pasta 0700, `credentials.json` 0600);
  - o log passa a ir para `~/Library/Logs/Pauta/pauta.log`; o log antigo pode ficar onde está.
- **Item de início:** o app novo se registra sozinho, como hoje. O build deve encerrar e apagar o `build/Radar.app`
  antigo, para não ficarem dois rodando. O README deve dizer como tirar o "Radar" que sobrar em Ajustes do Sistema →
  Itens de Início.
- **Ícone do app:** gerar um `AppIcon.icns` (o `checklist` branco sobre o quadrado grafite) no build ou como arquivo em
  `Resources/`, e apontar o `CFBundleIconFile` para ele.

## Fica com o builder

- Como os logos SVG entram no SwiftUI: shape a partir do path, PDF ou asset rasterizado. Vale qualquer um que fique
  nítido em 14 pt e aceite cor.
- Como gerar o `.icns`: script com `iconutil` ou arquivo pronto.
- Onde fica "Marcar tudo como visto" e o desenho exato do "ver mais N" e do "N cards livres ▸".
- Animação ao trocar o destaque, se houver alguma. Ela deve respeitar "reduzir movimento".
- Atualizar `Snapshots.swift` com os estados novos e o `SelfTest` onde mudarem as regras: a escolha do destaque, a
  migração da pasta e o nome no tooltip.

## Decisões minhas (o usuário não escolheu explicitamente)

- O destaque nunca é card do Jira, e o item em destaque não se repete na lista.
- A seção "GitHub" passa a se chamar "Revisões".
- Some a linha de resumo da sprint.
- Desbotar o que tem mais de 24 h.
- Bundle id `local.pauta`, migração da pasta e caminho do log.
- Se você não tem cards mas existem livres, "Seus cards" aparece só com a linha "N cards livres ▸", porque o total
  da barra conta os livres.
- Antes da primeira carga, o destaque não mostra "Ninguém esperando você.".
- O desbotamento de 24 h vale só para Slack e PRs, porque card do Jira não tem data.
- A faixa de erro, que hoje é laranja, fica cinza.
- O nome do app Slack muda no `slack-manifest.yml` e na cópia do manifesto em `Connect.swift`.
- O diretório do projeto continua `~/Documents/radar` por enquanto. Renomear para `~/Documents/pauta` fica como último
  passo, se o usuário quiser.
