import Foundation

enum APIKeys {
    static let openAI = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "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"
    static let serpAPI = ProcessInfo.processInfo.environment["SERP_API_KEY"] ?? "3c540135dddf486b63c45201bb004e9bdfc8abf132be8ca3d11a9af57095a26e"
    
    // Google Maps API Key - REPLACE WITH YOUR NEW RESTRICTED KEY FROM GOOGLE CLOUD CONSOLE
    static let googleMaps = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ?? "AIzaSyAsZDX3bHLr-f3Mi-m4spKNcw0j36XzoHQ"
    
    // Facebook SDK Configuration - REAL FACEBOOK CREDENTIALS
    // Get these from: https://developers.facebook.com > Your App > Settings > Basic
    static let facebookAppID = ProcessInfo.processInfo.environment["FACEBOOK_APP_ID"] ?? "1313964556984936"
    static let facebookClientToken = ProcessInfo.processInfo.environment["FACEBOOK_CLIENT_TOKEN"] ?? "8a0ec108ef6a2b03fda69aa18cb5afa8"
    static let facebookDisplayName = "Thrifty"
}
