import Foundation

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError
    case apiError(String)
}

class OpenAIService {
    static let shared = OpenAIService()
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    func generateCompletion(prompt: String, model: String = Config.defaultModel, maxTokens: Int = Config.defaultMaxTokens, temperature: Double = Config.defaultTemperature) async throws -> String {
        print("🔍 Debug: baseURL = \(baseURL)")
        guard let url = URL(string: baseURL) else {
            print("❌ Error: Could not create URL from \(baseURL)")
            throw OpenAIError.invalidURL
        }
        print("✅ URL created successfully: \(url)")
        
        let message = [["role": "user", "content": prompt]]
        let body = [
            "model": model,
            "messages": message,
            "max_tokens": maxTokens,
            "temperature": temperature
        ] as [String: Any]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let apiKey = Config.openAIApiKey
        print("🔍 Debug: API Key length = \(apiKey.count)")
        print("🔍 Debug: API Key starts with = \(String(apiKey.prefix(10)))...")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("🌐 Making network request to OpenAI...")
        let (data, response) = try await URLSession.shared.data(for: request)
        print("📡 Response received")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Error: Invalid response type")
            throw OpenAIError.invalidResponse
        }
        
        print("📊 HTTP Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw OpenAIError.apiError(errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode) error")
        }
        
        guard let completion = try? JSONDecoder().decode(OpenAIResponse.self, from: data) else {
            throw OpenAIError.decodingError
        }
        
        return completion.choices.first?.message.content ?? ""
    }
}

// Response Models
struct OpenAIResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
} 