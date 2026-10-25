import Foundation

/// `Pauta --check`: confere as credenciais salvas nas APIs reais. Nunca imprime tokens.
enum Check {
    /// Código de saída: 0 tudo certo, 1 algum erro ou credencial faltando.
    static func run() async -> Int32 {
        let credentials = Credentials.load()
        var failed = false

        if credentials.jiraReady {
            do {
                let me = try await JiraClient(credentials).myself()
                print("jira ok \(me.name.isEmpty ? "?" : me.name)")
            } catch {
                failed = true
                print("jira erro: \((error as? APIError)?.userMessage ?? "\(error)")")
            }
        } else {
            failed = true
            print("sem credenciais do Jira")
        }

        if credentials.slackReady {
            do {
                let who = try await SlackClient(token: credentials.slackToken).authTest()
                print("slack ok \(who.userId)@\(who.teamURL.host ?? who.teamId)")
            } catch {
                failed = true
                print("slack erro: \((error as? APIError)?.userMessage ?? "\(error)")")
            }
        } else {
            failed = true
            print("sem credenciais do Slack")
        }
        return failed ? 1 : 0
    }
}
