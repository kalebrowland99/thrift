import Foundation

enum APIKeys {
    static let openAI = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    static let serpAPI = ProcessInfo.processInfo.environment["SERP_API_KEY"] ?? ""
}
