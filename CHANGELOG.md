# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

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
