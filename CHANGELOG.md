# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-10-25

### Adicionado
- Pauta no NeyHub: instale o `Pauta-0.2.0.neyplugin` pela Loja e ele roda dentro do NeyHub, com as mesmas credenciais e ajustes do avulso.
- Tela do Pauta (janela do NeyHub, ou o modo Janela no avulso): Slack, GitHub e Jira lado a lado, com o destaque no topo, os filtros e a busca. A mensagem do Slack aparece inteira, os PRs mostram autor e checks, e os seus cards vêm em linhas com o status no menu.
- "Seus PRs": os seus PRs abertos, com as aprovações e se já estão prontos pra merge (pelo mesmo `gh`).
- Modos de exibição no avulso: Janela, Barra de menus ou os dois, nos ajustes.
- Atualização automática: confere sozinho se tem versão nova, baixa e troca o app quando você fecha o Pauta (ou em "Reiniciar agora"), e mostra as novidades na abertura seguinte.
- "Sair do Pauta" nos ajustes.

### Alterado
- Visual no tema Grafite do NeyHub (sempre escuro, acento verde-limão).
- Tocar numa notificação abre a mensagem certa mesmo depois de reiniciar: o link fica guardado em `avisos.json` (os 200 mais recentes).
- O build exige o certificado local de assinatura (sem fallback ad-hoc).

## [0.1.0] - 2026-10-25

### Adicionado
- Primeira versão do Pauta (antes chamado Radar): Jira, Slack e GitHub numa tela só, pela barra de menus.
- Destaque com a coisa mais recente que espera por você, em letra grande e com as ações embaixo.
- Slack: DMs e menções não lidas, marcar como visto e notificação de mensagem nova.
- Revisões do GitHub: PRs que esperam a sua revisão, pelo `gh`.
- Jira: seus cards da sprint, troca de status, cards livres do projeto e pegar um card.
- Conectar só clicando: o Pauta pega o token da área de transferência e valida na API.
- Pílulas por serviço e busca por pessoa, canal, PR ou card, com os trechos achados marcados.
- Ajustes de exibição: menções em canais, cards livres, densidade, intervalo e notificações.
- Ícone de checklist na barra com o total, e visual grafite.
- Modos de terminal (`--check`, `--dump`, `--snapshots`, `--selftest`).

### Alterado
- O Radar virou Pauta, com migração da pasta de dados.
