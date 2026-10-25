import Foundation

enum APIError: Error, Equatable {
    case unauthorized
    /// 403: o token vale, mas falta permissão para aquilo (ex.: atribuir/transicionar no Jira).
    case forbidden
    case rateLimited(retryAfter: Int)
    case server(String)
    case transport(String)

    var userMessage: String {
        switch self {
        case .unauthorized: "acesso negado: confira o token"
        case .forbidden: "sem permissão para isso"
        case .rateLimited(let seconds): "limite de requisições atingido, tente em \(seconds) s"
        case .server(let body): "erro do servidor: \(body)"
        case .transport(let reason): "sem conexão: \(reason)"
        }
    }
}

enum HTTP {
    /// Mapeia o status HTTP para um erro; nil quando deu certo. Puro, para testar sem rede.
    static func error(status: Int, headers: [String: String], body: Data) -> APIError? {
        switch status {
        case ..<400: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429:
            // Cabeçalhos HTTP não diferenciam maiúsculas.
            let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
            return .rateLimited(retryAfter: value.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 30)
        default:
            return .server(String(String(decoding: body, as: UTF8.self).prefix(200)))
        }
    }

    /// `mapError`: regra própria de um serviço, consultada antes da padrão (ex.: limite do GitHub vem como 403).
    static func send(_ request: URLRequest, mapError: ((Int, [String: String], Data) -> APIError?)? = nil) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("resposta inválida") }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
        if let custom = mapError?(http.statusCode, headers, data) { throw custom }
        if let error = error(status: http.statusCode, headers: headers, body: data) { throw error }
        return data
    }
}
