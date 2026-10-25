import AppKit

enum CatcherPoll: Equatable {
    case idle
    case expired
    case token(String, changeCount: Int)
}

/// Vigia a área de transferência até aparecer um token do serviço (o usuário clicou em Copiar na página).
/// A regra é `poll` (testada no selftest); o resto é só o relógio. Para ao `stop()`, no prazo (10 min) ou ao ser solto.
@MainActor
final class TokenCatcher {
    let service: Service
    var onToken: (String, Int) -> Void = { _, _ in }
    var onTimeout: () -> Void = {}

    private let pasteboard: NSPasteboard
    private let timeout: TimeInterval
    private var lastCount: Int
    private var deadline: Date
    private var timer: Timer?

    init(service: Service, pasteboard: NSPasteboard = .general, timeout: TimeInterval = 600) {
        self.service = service
        self.pasteboard = pasteboard
        self.timeout = timeout
        lastCount = pasteboard.changeCount
        deadline = Date().addingTimeInterval(timeout)
    }

    /// O que já estava copiado antes de começar não conta: só uma cópia nova.
    func start() {
        stop()
        lastCount = pasteboard.changeCount
        deadline = Date().addingTimeInterval(timeout)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common: o menu/popover em uso não pode parar a vigia.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch poll() {
        case .idle: break
        case .expired: stop(); onTimeout()
        case .token(let text, let count): onToken(text, count)
        }
    }

    /// Um passo da vigia: a área de transferência mudou e o texto novo é um token deste serviço?
    func poll(now: Date = Date()) -> CatcherPoll {
        if now >= deadline { return .expired }
        let count = pasteboard.changeCount
        guard count != lastCount else { return .idle }
        lastCount = count
        // Cópia que não é texto (imagem, arquivo): nem lê.
        guard pasteboard.types?.contains(.string) == true else { return .idle }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              tokenKind(text) == service else { return .idle }
        return .token(text, changeCount: count)
    }

    /// Só limpa se ninguém copiou outra coisa depois do token (senão apagaria o que o usuário copiou em seguida).
    func clearIfUnchanged(_ count: Int) {
        if pasteboard.changeCount == count { pasteboard.clearContents() }
    }
}
