# Pauta: abas, busca e ajustes

Data: 2026-10-24. Vem depois do redesign (`2026-10-24-pauta-redesign-design.md`, branch `pauta`), que continua valendo:
destaque no topo, estilo grafite, logos coloridos, ícone `checklist`. Este documento acrescenta filtros e opções.
Mockups aprovados em `.superpowers/brainstorm/41459-1792886008/content/`: `a-com-busca.html` para o comportamento e
`inputs.html` opção 3 para o visual do topo.

## Por quê

Abrindo o Pauta com os dados reais, o usuário achou a tela "sem sal". Faltavam filtros e opções. Ele quer recortar
rápido o que vê (por serviço ou por texto) e ajustar alguns comportamentos sem mexer no código.

## Objetivos

- Uma linha de **pílulas** no topo para filtrar por serviço, e uma **busca** por texto.
- Cinco **ajustes** novos no ⚙︎: menções em canais, cards livres, densidade, intervalo de atualização e notificações do
  Slack.

## Não objetivos

- Atalhos de teclado além de ⌘F e Esc (nada de setas, Enter ou Delete).
- Rosto ou avatar de pessoa. As linhas continuam com os logos dos serviços.
- Rascunhos, canais silenciados, desligar o destaque, escolher o que a barra conta: o usuário recusou.
- Buscar dados novos nas APIs.

## Anti-objetivos

- Topo pesado, com duas faixas de controles empilhadas quando ninguém está buscando.
- Cor fora dos logos. O estilo continua grafite.
- Perder o estado de "vistos" ou as credenciais por causa dos ajustes novos.

## Topo do popover (mockup `inputs.html`, opção 3)

- **Parado:** uma linha só, com margem de 12 e espaço de 6 entre os itens, contendo:
  - um botão redondo com a lupa (28×26, fundo `.primary` a 5%);
  - as pílulas **Tudo N**, **[logo Slack] N**, **[logo GitHub] N** e **[logo Jira] N**.
- **Pílulas:**
  - formato de cápsula com 26 de altura, fonte 12 e número em 11 com largura fixa;
  - a selecionada tem fundo `.primary` com texto invertido;
  - as outras têm fundo `.primary` a 5% e o logo na cor da marca;
  - só aparecem as pílulas dos serviços **conectados**. "Tudo" sempre aparece.
- **Contagens:**
  - Slack: as mensagens visíveis, respeitando o ajuste de menções;
  - GitHub: os PRs;
  - Jira: seus cards mais os livres, se os livres estiverem ligados;
  - Tudo: a soma.
- **Busca aberta** (clique na lupa ou ⌘F com o popover aberto):
  - a linha vira um campo arredondado (altura 30, fundo `.primary` a 5%) com a lupa, o texto e um ⊗ à direita para
    limpar;
  - as pílulas descem para a linha de baixo.
  - **Esc:** limpa o texto. Com o campo vazio, Esc ou o ⊗ fecham a busca.
- **Ao reabrir o popover**, volta para **Tudo** e a busca começa fechada e vazia.

## Filtrar por serviço (pílulas)

- **Tudo:** é a tela de hoje.
- **Slack:**
  - o destaque é a mensagem mais recente do Slack, e só aparece a seção Slack;
  - se não houver mensagem, aparece "Nada no Slack." em cinza, no lugar do destaque.
- **GitHub:** a mesma regra, com Revisões. O texto vazio é "Nenhum PR esperando você.".
- **Jira:**
  - sem destaque, porque card nunca é destaque;
  - mostra "Seus cards" e, abaixo, os livres já **abertos** (não recolhidos), se os livres estiverem ligados.
- Os estados de conectar, de erro e de carregando de cada seção continuam iguais dentro do filtro.

## Buscar por texto

- **Onde procura:**
  - Slack: nome da pessoa, nome do canal e texto;
  - PR: título, repositório (`shortId`) e autor;
  - Jira: chave e título, nos seus cards **e** nos livres (incluindo sub-tarefas).
- **Como compara:** ignora maiúsculas e acentos e procura o termo em qualquer parte. Várias palavras exigem todas
  ("botão checkout").
- **Com texto digitado:**
  - o destaque some e tudo vira lista;
  - as seções mostram só o que bate, e seção sem resultado some;
  - os livres que batem aparecem numa seção **"Livres"**, abertos e com o botão "Pegar";
  - o trecho encontrado aparece com fundo `.primary` a 10% no texto da linha;
  - as pílulas passam a contar só o que bate e continuam filtrando por serviço;
  - o rodapé troca "Atualizado há X" por "N resultados" (ou "1 resultado").
- **Sem resultado:** "Nada com “<termo>”." em cinza.
- O "ver mais N" do Slack não se aplica durante a busca: mostra todos os resultados.

## Ajustes (⚙︎)

Uma seção nova, **"Exibição"**, depois das conexões, com:

| Ajuste | Controle | Padrão | Efeito |
| --- | --- | --- | --- |
| Menções em canais | interruptor | ligado | Desligado, o Slack mostra só DMs: no destaque, na lista, na pílula, no número da barra e nas notificações. |
| Cards livres | interruptor | ligado | Desligado, some a linha "N cards livres" e os livres saem da pílula Jira, da busca e do número da barra. |
| Densidade | segmentado Confortável / Compacta | Confortável | Compacta: linhas com 3 de respiro vertical (em vez de 6), destaque em 16 pt (em vez de 18) e 10 entre seções (em vez de 16). |
| Atualizar a cada | segmentado 1 / 2 / 5 min | 2 min | Muda o intervalo do poller. Vale na hora, sem reiniciar. |
| Notificações do Slack | interruptor | ligado | Desligado, o Pauta não posta notificação nenhuma. O registro de "já notificado" continua andando, para não chegar uma enxurrada quando religar. |

- **Onde guardar:** em `UserDefaults` (domínio `local.pauta`), não no `credentials.json`.
- **Efeito imediato:** mudar um ajuste atualiza a tela e o ícone da barra na hora.

## Fica com o builder

- Animação ao abrir e fechar a busca, que deve respeitar "reduzir movimento".
- Como o ⌘F chega ao popover (atalho local enquanto o popover tem foco) e o foco no campo ao abrir.
- A estrutura das funções de filtro. Precisam ser puras e testadas no `SelfTest`: busca normalizada, contagens das
  pílulas, efeito de cada ajuste nas listas e no total da barra.
- Atualizar `Snapshots.swift` com os estados novos: busca aberta com resultado, sem resultado, cada pílula, ajustes
  com a seção Exibição, densidade compacta. Atualizar também o README.

## Decisões minhas (o usuário não escolheu explicitamente)

- Só aparecem pílulas de serviços conectados.
- O filtro e a busca zeram ao reabrir o popover.
- A busca ignora acentos e maiúsculas, e várias palavras exigem todas.
- Durante a busca, os livres aparecem abertos numa seção "Livres".
- Desligar um tipo de item tira ele também do número da barra e das notificações.
- Os textos vazios: "Nada no Slack.", "Nenhum PR esperando você." e "Nada com “x”.".
- Os valores da densidade compacta.
- O número da barra conta mensagens do Slack, mais PRs, mais os seus cards e os cards livres, como a pílula Jira.
  Os ajustes só tiram o que desligam ("Cards livres" desligado tira só os livres).
  - Nota de 2026-10-24: antes a barra contava só os cards **livres** (não os seus) e podia ser diferente de "Tudo N".
    O usuário mudou isso em 2026-10-24 para a barra bater com a pílula Jira.
- "Marcar tudo como visto" marca só as mensagens visíveis. Menções escondidas pelo ajuste não são marcadas.
- Uma sub-tarefa livre encontrada pela busca aparece sob o título apagado do card pai, como na lista de livres de hoje.
