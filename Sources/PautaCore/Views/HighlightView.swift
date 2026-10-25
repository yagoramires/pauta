import NeyKit
import SwiftUI

/// O destaque do topo, sem caixa: a coisa mais recente que espera por você, em letra grande, com as ações embaixo.
struct HighlightView: View {
    var state: HeroState
    var filter: ServiceFilter
    @ObservedObject var slack: SlackStore
    @ObservedObject var github: GitHubStore
    @Environment(\.density) private var density
    private var bigSize: CGFloat { density == .compact ? 16 : 18 }

    init(state: HeroState, filter: ServiceFilter = .all, slack: SlackStore, github: GitHubStore) {
        self.state = state; self.filter = filter; self.slack = slack; self.github = github
    }

    var body: some View {
        Group {
            switch state {
            case .loading: EmptyView()
            case .item(.slack(let item)):
                block(.slack, context: highlightContext(item),
                      text: "“\(item.text.replacingOccurrences(of: "\n", with: " "))”") {
                    Button("Abrir no Slack") { slack.open(item) }.buttonStyle(GraphiteButtonStyle())
                    Button("Marcar como visto") { slack.dismiss(item) }.buttonStyle(GraphiteButtonStyle(primary: false))
                }
            case .item(.pr(let pr)):
                block(.github, context: highlightContext(pr), text: pr.title,
                      detail: pr.shortId + (pr.draft ? " · rascunho" : "")) {
                    Button("Abrir no GitHub") { github.open(pr) }.buttonStyle(GraphiteButtonStyle())
                }
            case .clear:
                VStack(alignment: .leading, spacing: 4) {
                    Text(clearTitle(filter)).font(.system(size: bigSize, weight: .semibold)).tracking(-0.25)
                    // Numa pílula o título já diz o serviço; o subtítulo é só do "Tudo".
                    if filter == .all, let subtitle = clearSubtitle(slackConnected: slack.configured, githubConnected: !github.needsLogin) {
                        Text(subtitle).font(.system(size: 12))
                    }
                }
                .foregroundStyle(Grafite.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
            }
        }
        .motion(state)
    }

    private func block<Actions: View>(_ service: HubService, context: String, text: String, detail: String? = nil,
                                      @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ServiceLogo(service: service)
                Text(context).lineLimit(1)
            }
            .font(.system(size: 11.5)).foregroundStyle(Grafite.muted)
            .padding(.bottom, 6)
            Text(text).font(.system(size: bigSize, weight: .semibold)).tracking(-0.25).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Grafite.muted).padding(.top, 4)
            }
            HStack(spacing: 8) { actions() }.padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    }
}
