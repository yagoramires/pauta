import AppKit

/// O que o ícone único mostra: sempre UM símbolo fixo do Pauta e o total (Slack + Jira + GitHub) quando passa de 0.
/// Erro em algum serviço troca o símbolo pelo triângulo (o total continua).
struct BarState: Equatable {
    var symbol: String
    var total: Int?
}

/// SF Symbol fixo do Pauta na barra.
let appGlyph = "checklist"

func barState(slack: Int, jira: Int, github: Int, failed: Bool) -> BarState {
    let total = slack + jira + github
    return BarState(symbol: failed ? "exclamationmark.triangle" : appGlyph, total: total > 0 ? total : nil)
}

/// Detalhe por serviço (tooltip e VoiceOver): "Pauta: Slack 3, Jira 2, GitHub 5"; serviço zerado não aparece.
func barDescription(slack: Int, jira: Int, github: Int, failed: Bool) -> String {
    let parts = [("Slack", slack), ("Jira", jira), ("GitHub", github)].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
    let detail = parts.isEmpty ? "nada pendente" : parts.joined(separator: ", ")
    return failed ? "Pauta: erro em algum serviço · \(detail)" : "Pauta: \(detail)"
}

/// Imagem template (o macOS pinta de acordo com o tema da barra): o símbolo e, se houver, o total ao lado.
func barImage(_ state: BarState, description: String) -> NSImage {
    let font = NSFont.menuBarFont(ofSize: 0)
    let icon = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    let count = state.total.map { NSAttributedString(string: "\($0)", attributes: [.font: font, .foregroundColor: NSColor.black]) }
    let gap: CGFloat = 3
    let width = (icon?.size.width ?? 0) + (count.map { gap + $0.size().width } ?? 0)
    let image = NSImage(size: NSSize(width: ceil(width), height: 18), flipped: false) { rect in
        var x: CGFloat = 0
        if let icon {
            icon.draw(in: NSRect(x: 0, y: (rect.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            x = icon.size.width + gap
        }
        if let count {
            let size = count.size()
            count.draw(at: NSPoint(x: x, y: (rect.height - size.height) / 2))
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = description
    return image
}
