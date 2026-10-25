import SwiftUI

/// Topo do popover (mockup `inputs.html`, opção 3): a lupa redonda e as pílulas "Tudo N" e logo + N por serviço conectado.
/// A selecionada é `.primary` com texto e logo invertidos; as outras, `.primary` a 5% com o logo na cor da marca.
/// Com a busca aberta (lupa ou ⌘F), a linha de cima vira o campo e as pílulas descem.
struct FilterBar: View {
    @Binding var filter: ServiceFilter
    var counts: [ServiceFilter: Int]
    var services: [ServiceFilter]
    @Binding var searchOpen: Bool
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchOpen { field.padding([.horizontal, .top], 12) }
            HStack(spacing: 6) {
                if !searchOpen {
                    Button { searchOpen = true } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 26)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
                    .help("Buscar (⌘F)").accessibilityLabel("Buscar")
                }
                pill(.all)
                ForEach(services, id: \.self) { pill($0) }
                Spacer(minLength: 0)
            }
            .padding([.horizontal, .top], 12)
        }
        .motion(searchOpen)
    }

    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField("Filtrar por pessoa, canal, card", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13)).tint(.primary)
                .focused($focused)
                .onExitCommand(perform: clearOrClose)
                // O campo acabou de entrar na tela: o foco só pega no ciclo seguinte.
                .onAppear { DispatchQueue.main.async { focused = true } }
            Button(action: clearOrClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help(query.isEmpty ? "Fechar busca" : "Limpar")
            .accessibilityLabel(query.isEmpty ? "Fechar busca" : "Limpar")
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    /// ⊗ e Esc: limpa o texto; com ele já vazio, fecha a busca.
    private func clearOrClose() {
        if query.isEmpty { searchOpen = false } else { query = "" }
    }

    private func pill(_ option: ServiceFilter) -> some View {
        let selected = filter == option
        let ink = selected ? Color(nsColor: .windowBackgroundColor) : Color.primary
        let count = counts[option] ?? 0
        return Button { filter = option } label: {
            HStack(spacing: 5) {
                if let service = option.service {
                    ServiceLogo(service: service, size: 13, color: selected ? ink : nil)
                } else {
                    Text("Tudo")
                }
                Text("\(count)").font(.system(size: 11)).monospacedDigit().opacity(0.7)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(ink)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(selected ? Color.primary : Color.primary.opacity(0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.service?.name ?? "Tudo"), \(count)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension ServiceFilter {
    var service: HubService? {
        switch self {
        case .all: nil
        case .slack: .slack
        case .github: .github
        case .jira: .jira
        }
    }
}
