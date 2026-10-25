import Foundation

/// Os serviços que o Pauta conecta copiando um token (o GitHub usa o `gh`, não passa por aqui).
enum Service: Hashable { case slack, jira }

/// Que serviço gera um token com esse formato? Só o que casa por inteiro vale; qualquer outra coisa copiada é ignorada.
func tokenKind(_ text: String) -> Service? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Texto grande copiado por acaso nem entra na expressão regular.
    guard s.utf8.count <= 600 else { return nil }
    func matches(_ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) == s.startIndex..<s.endIndex }
    if matches("^xoxp-[A-Za-z0-9-]{20,}$") { return .slack }
    if matches("^ATATT[A-Za-z0-9_=-]{20,}$") { return .jira }
    return nil
}

/// E-mail e site do Jira digitados no assistente: sem espaços, e-mail com "@", site https (obrigatório: não há site padrão).
func jiraConnectInput(email: String, site: String) -> (email: String, site: String)? {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
    guard email.contains("@"), !email.contains(" ") else { return nil }
    let chosen = site.isEmpty ? defaultJiraSite : site
    // Só https: senão o e-mail:token iria em texto puro.
    guard Credentials.jiraBase(site: chosen) != nil else { return nil }
    return (email, chosen)
}

let defaultJiraSite = ""
let jiraTokenPage = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

/// Mesmo conteúdo do `slack-manifest.yml` (só escopos de leitura, user token), sem o comentário do topo.
let slackManifest = """
display_information:
  name: Pauta
oauth_config:
  scopes:
    user:
      - im:read
      - im:history
      - mpim:read
      - mpim:history
      - channels:read
      - channels:history
      - groups:read
      - groups:history
      - users:read
      - search:read
settings:
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false

"""

/// Página do Slack que cria o app já com o manifesto preenchido.
// shortcut: o parâmetro `manifest_yaml` não foi confirmado ao vivo; se o Slack o ignorar, a saída é mostrar o passo
// "From a manifest" (colar o conteúdo de slack-manifest.yml) em vez de depender da URL.
func slackManifestURL() -> URL {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let encoded = slackManifest.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    return URL(string: "https://api.slack.com/apps?new_app=1&manifest_yaml=" + encoded)!
}

/// Passos mostrados enquanto o Pauta espera o token.
func connectSteps(_ service: Service) -> [String] {
    switch service {
    case .slack:
        ["Escolha o workspace da empresa e clique em Criar",
         "Clique em Install to Workspace e Permitir",
         "Em User OAuth Token, clique em Copy"]
    case .jira:
        ["Clique em Criar token de API (o sem escopos)",
         "Dê qualquer nome e clique em Criar",
         "Clique em Copiar"]
    }
}

let slackApprovalNote = "Se aparecer Request to Install, a empresa precisa aprovar — o Pauta fica esperando."

/// Texto para uma validação que falhou, com o que fazer em seguida. O Pauta continua vigiando, mas o mesmo token
/// não é tentado de novo sozinho: é preciso copiar outra vez.
func connectErrorMessage(_ error: Error, service: Service) -> String {
    let retry = " · copie de novo para tentar"
    guard let api = error as? APIError else { return "não consegui validar o token" + retry }
    if api == .unauthorized {
        return service == .jira ? "e-mail ou token não bateram · cancele e confira o e-mail" : "o Slack não aceitou esse token" + retry
    }
    return api.userMessage + retry
}
