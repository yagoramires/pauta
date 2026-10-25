import NeyKit
import SwiftUI

/// Peças comuns às seções do popover e da tela, no tema Grafite do NeyKit (sempre escuro). As únicas cores fora dele
/// fixas da tela são os logos dos serviços.

func agoText(_ date: Date?) -> String {
    guard let date else { return "Ainda não atualizado" }
    let seconds = Int(Date().timeIntervalSince(date))
    return seconds < 60 ? "Atualizado agora" : seconds < 3600 ? "Atualizado há \(seconds / 60) min" : "Atualizado há \(seconds / 3600) h"
}

/// "agora" ou "há 2 h" (as linhas usam frase, não só a abreviação).
func agoShort(_ date: Date, now: Date = Date()) -> String {
    let short = relativeTime(date, now: now)
    return short == "agora" ? short : "há \(short)"
}

private struct DensityKey: EnvironmentKey { static let defaultValue = Density.comfortable }

extension EnvironmentValues {
    /// Densidade da tela, posta pelo PopoverView a partir das preferências.
    var density: Density {
        get { self[DensityKey.self] }
        set { self[DensityKey.self] = newValue }
    }
}

/// Quantas linhas uma seção compacta mostra antes do "Ver mais".
let compactVisibleRows = 4

/// As linhas à mostra e quantas o "Ver mais" esconde. Na busca tudo aparece, sem o botão.
func visibleRows<T>(_ rows: [T], showAll: Bool, query: String) -> (shown: [T], hidden: Int) {
    if isSearching(query) { return (rows, 0) }
    return (showAll ? rows : Array(rows.prefix(compactVisibleRows)), max(rows.count - compactVisibleRows, 0))
}

// MARK: Serviços

enum HubService: CaseIterable {
    case slack, jira, github

    var name: String { self == .slack ? "Slack" : self == .jira ? "Jira" : "GitHub" }
}

extension HubService {
    /// Slack #4A154B (escuro #E01E5A), Jira #0052CC (#4C9AFF), GitHub #181717 (#F2F2F4).
    var logoColor: Color {
        switch self {
        case .slack: dynamicColor(light: 0x4A154B, dark: 0xE01E5A)
        case .jira: dynamicColor(light: 0x0052CC, dark: 0x4C9AFF)
        case .github: dynamicColor(light: 0x181717, dark: 0xF2F2F4)
        }
    }
}

func dynamicColor(light: UInt32, dark: UInt32) -> Color {
    func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
    })
}

/// O logo do serviço na cor da marca (ou em `color`, numa pílula selecionada).
struct ServiceLogo: View {
    var service: HubService
    var size: CGFloat = 14
    var color: Color? = nil

    var body: some View {
        Image(nsImage: Logos.image(service)).renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(color ?? service.logoColor).frame(width: size, height: size)
            .accessibilityLabel(service.name)
    }
}

/// Botão grafite: primário claro com tinta escura (o `.btn` do mockup); secundário no fundo de card com borda.
struct GraphiteButtonStyle: ButtonStyle {
    var primary: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primary ? Grafite.onAccent : Grafite.text)
            .padding(.vertical, 4).padding(.horizontal, 11)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Grafite.text : Grafite.card))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? .clear : Grafite.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Movimento

extension View {
    /// Animação só quando o usuário não pediu menos movimento.
    func motion<V: Equatable>(_ value: V) -> some View { modifier(Motion(value: value)) }
}

private struct Motion<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    var value: V
    func body(content: Content) -> some View { content.animation(reduced ? nil : .default, value: value) }
}

// MARK: Blocos

/// Faixa discreta de aviso/erro.
struct Banner<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(6)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Grafite.cardBorder, lineWidth: 1))
    }
}

/// "Atualizado há X" (ou "N resultados", durante a busca) à esquerda; ⟳ e ⚙︎ sem moldura à direita.
struct FooterBar: View {
    var updatedAt: Date?
    var results: Int? = nil
    var refresh: () -> Void
    var settings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(results.map(resultsText) ?? agoText(updatedAt)).font(.caption).foregroundStyle(Grafite.muted)
            Spacer()
            iconButton("arrow.clockwise", help: "Atualizar", action: refresh)
            iconButton("gearshape", help: "Ajustes", action: settings)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Grafite.muted).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Título cinza de uma seção, com detalhes à direita (contagem, link).
struct SectionTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Spacer(minLength: 8)
            trailing.font(.system(size: 11.5))
        }
        .foregroundStyle(Grafite.muted)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

/// Título cinza de uma seção ainda sem dados (conectar, ajustes), com o logo do serviço antes.
struct ServiceTitle<Trailing: View>: View {
    var service: HubService
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            ServiceLogo(service: service)
            SectionTitle(service.name) { trailing }
        }
    }
}

extension ServiceTitle where Trailing == EmptyView {
    init(_ service: HubService) { self.init(service: service) { EmptyView() } }
}

/// Frase curta e discreta no lugar de uma lista vazia.
struct Note: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Grafite.muted).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Linha de uma linha só: logo, nome (se houver), texto com reticências, pílula e o lado direito. O destaque ao passar
/// o mouse estende 8 pt para fora para o texto alinhar com o título. Com `query`, os trechos achados ganham fundo.
struct CompactRow<Trailing: View>: View {
    var service: HubService
    var name: String?
    var text: String
    var query: String
    var badge: String?
    var dim: Bool
    /// O lado direito tem controle próprio (botão/menu): então a linha clicável é só a esquerda.
    var trailingIsControl: Bool
    var action: () -> Void
    @ViewBuilder var trailing: Trailing
    @ViewState private var hovering = false
    @Environment(\.density) private var density

    init(service: HubService, name: String? = nil, text: String, query: String = "", badge: String? = nil, dim: Bool = false,
         trailingIsControl: Bool = false, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.service = service; self.name = name; self.text = text; self.query = query; self.badge = badge; self.dim = dim
        self.trailingIsControl = trailingIsControl; self.action = action; self.trailing = trailing()
    }

    var body: some View {
        Group {
            if trailingIsControl {
                HStack(spacing: 8) { Button(action: action) { main }.buttonStyle(.plain); trailing }
            } else {
                Button(action: action) { HStack(spacing: 8) { main; trailing } }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, density == .compact ? 3 : 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Grafite.selected : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
        .opacity(dim ? 0.5 : 1)
    }

    private var main: some View {
        HStack(spacing: 8) {
            ServiceLogo(service: service)
            if let name { Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1).layoutPriority(1) }
            Text(marked).font(.system(size: 13))
                .foregroundStyle(name == nil ? Grafite.text : Grafite.muted).lineLimit(1).truncationMode(.tail)
            if let badge {
                Text(badge).font(.system(size: 10)).foregroundStyle(Grafite.muted)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Grafite.selected, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var marked: AttributedString {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        let ranges = matchRanges(line, query: query)
        var result = AttributedString(line)
        for range in ranges {
            if let r = Range(range, in: result) { result[r].backgroundColor = Grafite.accent.opacity(0.25) }
        }
        // Trecho achado longe do começo sumiria nas reticências: a linha passa a começar umas palavras antes dele.
        // Com nome na frente sobra menos largura para o texto.
        if let start = searchExcerptStart(line, firstMatch: ranges.first, budget: name == nil ? 38 : 28),
           let cut = Range(line.startIndex..<start, in: result) {
            result.replaceSubrange(cut, with: AttributedString("…"))
        }
        return result
    }
}

// MARK: Campos de texto

/// Visual único dos campos: sem borda do sistema, fundo suave e fio que vira cor de destaque com o foco.
struct InputBox: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Grafite.card))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Grafite.accent : Grafite.cardBorder, lineWidth: focused ? 1.5 : 1))
    }
}

extension View {
    func inputBox() -> some View { modifier(InputBox()) }
}

/// Rótulo pequeno 4 pt acima do campo.
struct LabeledField<Input: View>: View {
    var label: String
    @ViewBuilder var input: Input

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Grafite.muted)
            input
        }
    }
}

/// Hospedado sem permissão de notificações: o "Ligar" leva à tela de Permissões do NeyHub (o Pauta nunca pede ao sistema).
struct PermissionNote: View {
    var openPermissions: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.slash").font(.system(size: 11))
            Text("Notificações desligadas").font(.caption)
            Text("·").font(.caption)
            Button("Ligar", action: openPermissions).buttonStyle(.link).font(.caption).foregroundStyle(Grafite.accent)
        }
        .foregroundStyle(Grafite.muted)
    }
}
