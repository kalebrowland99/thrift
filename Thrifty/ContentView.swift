//
//  ContentView.swift
//  Thrifty
//
//  Created by Eliana Silva on 8/19/24.
//

import SwiftUI
import StoreKit
import AVKit
import ConfettiSwiftUI
import AVFoundation
import PhotosUI
import AuthenticationServices
import CryptoKit
import FirebaseCore
import GoogleMaps
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import MapKit
import CoreLocation
import UIKit

// MARK: - Analysis Results Cache
class AnalysisResultsCache {
    static let shared = AnalysisResultsCache()
    private init() {}
    
    private var clothingDetailsCache: [String: ClothingDetails] = [:]
    private var titleCache: [String: String] = [:]
    
    func storeClothingDetails(_ details: ClothingDetails, for image: UIImage) {
        let key = imageKey(for: image)
        clothingDetailsCache[key] = details
    }
    
    func storeGeneratedTitle(_ title: String, for image: UIImage) {
        let key = imageKey(for: image)
        titleCache[key] = title
    }
    
    func getClothingDetails(for image: UIImage) -> ClothingDetails? {
        let key = imageKey(for: image)
        return clothingDetailsCache[key]
    }
    
    func getGeneratedTitle(for image: UIImage) -> String? {
        let key = imageKey(for: image)
        return titleCache[key]
    }
    
    private func imageKey(for image: UIImage) -> String {
        // Create a simple hash based on image data
        guard let data = image.jpegData(compressionQuality: 0.1) else { return UUID().uuidString }
        return String(data.hashValue)
    }
    
    func clearCache() {
        clothingDetailsCache.removeAll()
        titleCache.removeAll()
    }
}

// MARK: - SerpAPI Service
class SerpAPIService: ObservableObject {
    private let apiKey = "3c540135dddf486b63c45201bb004e9bdfc8abf132be8ca3d11a9af57095a26e"
    private let baseURL = "https://serpapi.com/search"
    
    // MARK: - Text-based Search Methods
    
    func searchEBayItems(query: String, condition: String = "used") async throws -> SerpSearchResult {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "engine", value: "ebay"),
            URLQueryItem(name: "ebay_domain", value: "ebay.com"),
            URLQueryItem(name: "_nkw", value: query), // eBay uses _nkw for search query
            URLQueryItem(name: "_salic", value: "1"), // Used items only
            URLQueryItem(name: "_pgn", value: "1") // First page
        ]
        
        guard let url = components.url else {
            print("🔍 Failed to create URL for eBay search")
            throw PlacesAPIError.invalidURL
        }
        
        print("🔍 Making eBay search request: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔍 Invalid HTTP response from eBay")
            throw PlacesAPIError.invalidResponse
        }
        
        print("🔍 eBay response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔍 eBay error response: \(errorString)")
            }
            throw PlacesAPIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(SerpSearchResult.self, from: data)
        return result
    }
    
    func searchGoogleShopping(query: String) async throws -> SerpSearchResult {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "engine", value: "google_shopping"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "50")
        ]
        
        guard let url = components.url else {
            print("🔍 Failed to create URL for Google Shopping")
            throw PlacesAPIError.invalidURL
        }
        
        print("🔍 Making Google Shopping request: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔍 Invalid HTTP response from Google Shopping")
            throw PlacesAPIError.invalidResponse
        }
        
        print("🔍 Google Shopping response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔍 Google Shopping error response: \(errorString)")
            }
            throw PlacesAPIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(SerpSearchResult.self, from: data)
        return result
    }
    
    // MARK: - Image-based Search Methods
    
    func searchWithImage(imageData: Data) async throws -> SerpSearchResult {
        print("🔍 Using Google Lens API for visual product identification...")
        
        // Use Google Lens API for the best visual product matching
        do {
            return try await searchGoogleLens(imageData: imageData)
        } catch {
            print("🔍 Google Lens search failed: \(error)")
            
            // Fallback to eBay for vintage items if Google Lens fails
            print("🔍 Falling back to eBay for vintage items")
            return try await searchEBayItems(query: "vintage fashion clothing accessories", condition: "used")
        }
    }
    
    private func searchGoogleLens(imageData: Data) async throws -> SerpSearchResult {
        // Convert Data to UIImage for Firebase Storage
        guard let uiImage = UIImage(data: imageData) else {
            print("🔍 Failed to convert image data to UIImage")
            throw PlacesAPIError.invalidResponse
        }
        
        print("🔍 Uploading image to Firebase Storage for Google Lens...")
        
        // Upload image to Firebase Storage and get public URL
        let publicImageURL = try await FirebaseStorageService.shared.uploadForReverseImageSearch(image: uiImage)
        
        print("🔍 Image uploaded successfully, making Google Lens request with URL: \(publicImageURL)")
        
        // Make Google Lens API call with image URL - pure visual search
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "engine", value: "google_lens"),
            URLQueryItem(name: "url", value: publicImageURL),
            URLQueryItem(name: "num", value: "50"),
            URLQueryItem(name: "hl", value: "en"),  // Language
            URLQueryItem(name: "gl", value: "us")   // Country
        ]
        
        guard let url = components.url else {
            print("🔍 Failed to create URL for Google Lens search")
            throw PlacesAPIError.invalidURL
        }
        
        print("🔍 Making Google Lens request: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔍 Invalid HTTP response from Google Lens")
            throw PlacesAPIError.invalidResponse
        }
        
        print("🔍 Google Lens response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔍 Google Lens error response: \(errorString)")
            }
            throw PlacesAPIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(SerpSearchResult.self, from: data)
        
        // Debug logging for Google Lens results
        let visualCount = result.visualMatches?.count ?? 0
        let organicCount = result.organicResults?.count ?? 0
        let imageCount = result.imageResults?.count ?? 0
        let totalCount = visualCount + organicCount + imageCount
        
        print("🔍 Google Lens API Results:")
        print("   📸 Visual Matches: \(visualCount)")
        print("   🔗 Organic Results: \(organicCount)")
        print("   🖼️ Image Results: \(imageCount)")
        print("   📊 Total Results: \(totalCount)")
        
        return result
    }
    

    

}

// MARK: - Cache Models
struct CachedMarketData: Codable {
    let searchResult: SerpSearchResult
    let cachedAt: Date
    let searchQuery: String
    let hasCustomImage: Bool
    
    // Cache persists indefinitely - only cleared manually when new photos are added
    var isValid: Bool {
        return true // Never expires
    }
}

struct CachedOpenAIResponse: Codable {
    let response: String
    let prompt: String
    let tool: String
    let input: String
    let cachedAt: Date
    
    // Check if cache is still valid (7 days for OpenAI responses)
    var isValid: Bool {
        Date().timeIntervalSince(cachedAt) < 7 * 24 * 60 * 60 // 7 days
    }
}

// MARK: - Market Data Cache Service
class MarketDataCache {
    static let shared = MarketDataCache()
    private init() {}
    
    private let userDefaults = UserDefaults.standard
    private let marketDataKey = "cached_market_data"
    private let openaiResponseKey = "cached_openai_responses"
    private let searchQueryCacheKey = "cached_search_queries" // New: Cache by search query as fallback
    
    // MARK: - Market Data Caching
    
    func saveMarketData(_ data: SerpSearchResult, for songId: String, searchQuery: String, hasCustomImage: Bool) {
        let cacheKey = generateMarketDataCacheKey(songId: songId, hasCustomImage: hasCustomImage)
        let searchQueryKey = generateSearchQueryCacheKey(searchQuery: searchQuery, hasCustomImage: hasCustomImage)
        
        let cachedData = CachedMarketData(
            searchResult: data,
            cachedAt: Date(),
            searchQuery: searchQuery,
            hasCustomImage: hasCustomImage
        )
        
        do {
            let encoded = try JSONEncoder().encode(cachedData)
            
            // Save by song ID (primary cache)
            var allCachedData = getAllMarketData()
            allCachedData[cacheKey] = encoded
            
            // Save by search query (fallback cache)
            var searchQueryCache = getAllSearchQueryCache()
            searchQueryCache[searchQueryKey] = encoded
            
            // Clean up expired entries
            cleanupExpiredMarketData(&allCachedData)
            cleanupExpiredSearchQueryCache(&searchQueryCache)
            
            userDefaults.set(allCachedData, forKey: marketDataKey)
            userDefaults.set(searchQueryCache, forKey: searchQueryCacheKey)
            
            print("✅ Market data cached for song ID key: \(cacheKey)")
            print("✅ Market data cached for search query key: \(searchQueryKey)")
            print("🗂️ Total cached entries: \(allCachedData.count) songs, \(searchQueryCache.count) queries")
        } catch {
            print("❌ Failed to cache market data: \(error)")
        }
    }
    
    func getMarketData(for songId: String, hasCustomImage: Bool) -> SerpSearchResult? {
        let cacheKey = generateMarketDataCacheKey(songId: songId, hasCustomImage: hasCustomImage)
        let allCachedData = getAllMarketData()
        
        guard let data = allCachedData[cacheKey],
              let cachedData = try? JSONDecoder().decode(CachedMarketData.self, from: data) else {
            print("🔍 No cached market data found for song ID: \(songId)")
            return nil
        }
        
        if cachedData.isValid {
            print("✅ Found valid cached market data for song ID: \(songId)")
            return cachedData.searchResult
        } else {
            print("⏰ Cached market data expired for song ID: \(songId)")
            // Remove expired entry
            removeMarketData(for: songId, hasCustomImage: hasCustomImage)
            return nil
        }
    }
    
    // New: Get market data by search query as fallback
    func getMarketDataByQuery(searchQuery: String, hasCustomImage: Bool) -> SerpSearchResult? {
        let searchQueryKey = generateSearchQueryCacheKey(searchQuery: searchQuery, hasCustomImage: hasCustomImage)
        let searchQueryCache = getAllSearchQueryCache()
        
        guard let data = searchQueryCache[searchQueryKey],
              let cachedData = try? JSONDecoder().decode(CachedMarketData.self, from: data) else {
            print("🔍 No cached market data found for search query: \(searchQuery)")
            return nil
        }
        
        if cachedData.isValid {
            print("✅ Found valid cached market data for search query: \(searchQuery)")
            return cachedData.searchResult
        } else {
            print("⏰ Cached market data expired for search query: \(searchQuery)")
            // Remove expired entry
            removeMarketDataByQuery(searchQuery: searchQuery, hasCustomImage: hasCustomImage)
            return nil
        }
    }
    
    func removeMarketData(for songId: String, hasCustomImage: Bool) {
        let cacheKey = generateMarketDataCacheKey(songId: songId, hasCustomImage: hasCustomImage)
        var allCachedData = getAllMarketData()
        allCachedData.removeValue(forKey: cacheKey)
        userDefaults.set(allCachedData, forKey: marketDataKey)
        print("🗑️ Removed cached market data for song ID: \(songId)")
    }
    
    // New: Remove market data by search query
    func removeMarketDataByQuery(searchQuery: String, hasCustomImage: Bool) {
        let searchQueryKey = generateSearchQueryCacheKey(searchQuery: searchQuery, hasCustomImage: hasCustomImage)
        var searchQueryCache = getAllSearchQueryCache()
        searchQueryCache.removeValue(forKey: searchQueryKey)
        userDefaults.set(searchQueryCache, forKey: searchQueryCacheKey)
        print("🗑️ Removed cached market data for search query: \(searchQuery)")
    }
    
    // MARK: - OpenAI Response Caching
    
    func saveOpenAIResponse(_ response: String, for tool: String, input: String, prompt: String) {
        let cacheKey = generateOpenAICacheKey(tool: tool, input: input)
        let cachedResponse = CachedOpenAIResponse(
            response: response,
            prompt: prompt,
            tool: tool,
            input: input,
            cachedAt: Date()
        )
        
        do {
            let encoded = try JSONEncoder().encode(cachedResponse)
            var allCachedResponses = getAllOpenAIResponses()
            allCachedResponses[cacheKey] = encoded
            
            // Clean up expired entries
            cleanupExpiredOpenAIResponses(&allCachedResponses)
            
            userDefaults.set(allCachedResponses, forKey: openaiResponseKey)
            print("✅ OpenAI response cached for tool: \(tool), input: \(input.prefix(50))...")
        } catch {
            print("❌ Failed to cache OpenAI response: \(error)")
        }
    }
    
    func getOpenAIResponse(for tool: String, input: String) -> String? {
        let cacheKey = generateOpenAICacheKey(tool: tool, input: input)
        let allCachedResponses = getAllOpenAIResponses()
        
        guard let data = allCachedResponses[cacheKey],
              let cachedResponse = try? JSONDecoder().decode(CachedOpenAIResponse.self, from: data) else {
            return nil
        }
        
        if cachedResponse.isValid {
            print("✅ Found valid cached OpenAI response for tool: \(tool)")
            return cachedResponse.response
        } else {
            print("⏰ Cached OpenAI response expired for tool: \(tool)")
            // Remove expired entry
            removeOpenAIResponse(for: tool, input: input)
            return nil
        }
    }
    
    func removeOpenAIResponse(for tool: String, input: String) {
        let cacheKey = generateOpenAICacheKey(tool: tool, input: input)
        var allCachedResponses = getAllOpenAIResponses()
        allCachedResponses.removeValue(forKey: cacheKey)
        userDefaults.set(allCachedResponses, forKey: openaiResponseKey)
        print("🗑️ Removed cached OpenAI response for tool: \(tool)")
    }
    
    // MARK: - Cache Management
    
    func clearAllCache() {
        userDefaults.removeObject(forKey: marketDataKey)
        userDefaults.removeObject(forKey: openaiResponseKey)
        userDefaults.removeObject(forKey: searchQueryCacheKey)
        print("🗑️ Cleared all cache data")
    }
    
    func getCacheStats() -> (marketDataCount: Int, openaiResponseCount: Int, searchQueryCount: Int) {
        let marketDataCount = getAllMarketData().count
        let openaiResponseCount = getAllOpenAIResponses().count
        let searchQueryCount = getAllSearchQueryCache().count
        return (marketDataCount, openaiResponseCount, searchQueryCount)
    }
    
    // Debug function to print cache contents
    func debugCacheContents() {
        let stats = getCacheStats()
        print("🔍 Cache Debug:")
        print("  - Market Data (Song ID): \(stats.marketDataCount) entries")
        print("  - Search Query Cache: \(stats.searchQueryCount) entries") 
        print("  - OpenAI Responses: \(stats.openaiResponseCount) entries")
        
        let marketData = getAllMarketData()
        if !marketData.isEmpty {
            print("📋 Market Data Keys:")
            for key in marketData.keys.sorted() {
                print("  - \(key)")
            }
        }
        
        let searchQueryData = getAllSearchQueryCache()
        if !searchQueryData.isEmpty {
            print("📋 Search Query Keys:")
            for key in searchQueryData.keys.sorted() {
                print("  - \(key)")
            }
        }
    }
    
    // Debug function to clear cache for testing (optional)
    func clearCacheForTesting() {
        clearAllCache()
        print("🧪 Cache cleared for testing - next API calls will be fresh")
    }
    
    // MARK: - Private Helper Methods
    
    private func generateMarketDataCacheKey(songId: String, hasCustomImage: Bool) -> String {
        return "market_\(songId)_\(hasCustomImage)"
    }
    
    private func generateSearchQueryCacheKey(searchQuery: String, hasCustomImage: Bool) -> String {
        let normalizedQuery = searchQuery.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        return "query_\(normalizedQuery.hashValue)_\(hasCustomImage)"
    }
    
    private func generateOpenAICacheKey(tool: String, input: String) -> String {
        let normalizedTool = tool.lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedInput = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "openai_\(normalizedTool)_\(normalizedInput.hashValue)"
    }
    
    private func getAllMarketData() -> [String: Data] {
        return userDefaults.object(forKey: marketDataKey) as? [String: Data] ?? [:]
    }
    
    private func getAllSearchQueryCache() -> [String: Data] {
        return userDefaults.object(forKey: searchQueryCacheKey) as? [String: Data] ?? [:]
    }
    
    private func getAllOpenAIResponses() -> [String: Data] {
        return userDefaults.object(forKey: openaiResponseKey) as? [String: Data] ?? [:]
    }
    
    private func cleanupExpiredMarketData(_ cache: inout [String: Data]) {
        let keysToRemove = cache.compactMap { key, data -> String? in
            guard let cachedData = try? JSONDecoder().decode(CachedMarketData.self, from: data) else {
                return key // Remove invalid entries
            }
            return cachedData.isValid ? nil : key
        }
        
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            print("🧹 Cleaned up \(keysToRemove.count) expired market data entries")
        }
    }
    
    private func cleanupExpiredSearchQueryCache(_ cache: inout [String: Data]) {
        let keysToRemove = cache.compactMap { key, data -> String? in
            guard let cachedData = try? JSONDecoder().decode(CachedMarketData.self, from: data) else {
                return key // Remove invalid entries
            }
            return cachedData.isValid ? nil : key
        }
        
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            print("🧹 Cleaned up \(keysToRemove.count) expired search query cache entries")
        }
    }
    
    private func cleanupExpiredOpenAIResponses(_ cache: inout [String: Data]) {
        let keysToRemove = cache.compactMap { key, data -> String? in
            guard let cachedResponse = try? JSONDecoder().decode(CachedOpenAIResponse.self, from: data) else {
                return key // Remove invalid entries
            }
            return cachedResponse.isValid ? nil : key
        }
        
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            print("🧹 Cleaned up \(keysToRemove.count) expired OpenAI response entries")
        }
    }
}

// MARK: - SerpAPI Models
struct SerpSearchResult: Codable, Equatable {
    let searchMetadata: SearchMetadata?
    let searchParameters: SearchParameters?
    let searchInformation: SearchInformation?
    let shoppingResults: [ShoppingResult]?
    let organicResults: [OrganicResult]?
    let imageResults: [ImageResult]?
    let visualMatches: [VisualMatch]?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case searchMetadata = "search_metadata"
        case searchParameters = "search_parameters"
        case searchInformation = "search_information"
        case shoppingResults = "shopping_results"
        case organicResults = "organic_results"
        case imageResults = "image_results"
        case visualMatches = "visual_matches"
        case error
    }
}

struct SearchMetadata: Codable, Equatable {
    let status: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case createdAt = "created_at"
    }
}

struct SearchParameters: Codable, Equatable {
    let engine: String?
    let query: String?
    let condition: String?
}

struct SearchInformation: Codable, Equatable {
    let totalResults: String?
    let queryDisplayed: String?
    
    enum CodingKeys: String, CodingKey {
        case totalResults = "total_results"
        case queryDisplayed = "query_displayed"
    }
}

struct ShoppingResult: Codable, Equatable {
    let position: Int?
    let title: String?
    let price: String?
    let extractedPrice: Double?
    let link: String?
    let source: String?
    let rating: Double?
    let reviews: Int?
    let thumbnail: String?
    let condition: String?
    
    enum CodingKeys: String, CodingKey {
        case position, title, price, link, source, rating, reviews, thumbnail, condition
        case extractedPrice = "extracted_price"
    }
}

struct OrganicResult: Codable, Equatable {
    let position: Int?
    let title: String?
    let link: String?
    let snippet: String?
    let price: String?
    let extractedPrice: Double?
    let rating: Double?
    let reviews: Int?
    let thumbnail: String?
    
    enum CodingKeys: String, CodingKey {
        case position, title, link, snippet, price, rating, reviews, thumbnail
        case extractedPrice = "extracted_price"
    }
}

struct ImageResult: Codable, Equatable {
    let position: Int?
    let title: String?
    let link: String?
    let redirectLink: String?
    let displayedLink: String?
    let favicon: String?
    let thumbnail: String?
    let imageResolution: String?
    let snippet: String?
    let snippetHighlightedWords: [String]?
    let source: String?
    let date: String?
    
    enum CodingKeys: String, CodingKey {
        case position, title, link, favicon, thumbnail, snippet, source, date
        case redirectLink = "redirect_link"
        case displayedLink = "displayed_link"
        case imageResolution = "image_resolution"
        case snippetHighlightedWords = "snippet_highlighted_words"
    }
}

struct VisualMatch: Codable, Equatable {
    let position: Int?
    let title: String?
    let link: String?
    let source: String?
    let sourceIcon: String?
    let rating: Double?
    let reviews: Int?
    let price: PriceInfo?
    let inStock: Bool?
    let condition: String?
    let thumbnail: String?
    let thumbnailWidth: Int?
    let thumbnailHeight: Int?
    let image: String?
    let imageWidth: Int?
    let imageHeight: Int?
    
    enum CodingKeys: String, CodingKey {
        case position, title, link, source, rating, reviews, price, condition
        case thumbnail, image
        case sourceIcon = "source_icon"
        case inStock = "in_stock"
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
    }
}

struct PriceInfo: Codable, Equatable {
    let value: String?
    let extractedValue: Double?
    let currency: String?
    
    enum CodingKeys: String, CodingKey {
        case value, currency
        case extractedValue = "extracted_value"
    }
}

enum PlacesAPIError: Error {
    case invalidURL
    case invalidResponse
    case noResults
    case decodingError
}

// MARK: - Thrift Store Map Service
class ThriftStoreMapService: ObservableObject {
    private let apiKey = APIKeys.googleMaps
    private let baseURL = "https://places.googleapis.com/v1/places:searchNearby"
    
    @Published var thriftStores: [ThriftStore] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func searchNearbyThriftStores(latitude: Double, longitude: Double, radius: Int = 10) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        print("🔍 Searching for real thrift stores near (\(latitude), \(longitude))")
        
        do {
            // First try nearby search
            var stores = try await performThriftStoreSearch(latitude: latitude, longitude: longitude, radius: radius)
            
            // If we don't have enough thrift stores, try text search as fallback
            if stores.count < 3 {
                print("🔍 Not enough thrift stores found (\(stores.count)), trying text search fallback...")
                let textSearchStores = try await performTextSearchForThriftStores(latitude: latitude, longitude: longitude)
                
                // Combine results, avoiding duplicates
                let existingIds = Set(stores.map { $0.id })
                let newStores = textSearchStores.filter { !existingIds.contains($0.id) }
                stores.append(contentsOf: newStores)
                
                print("🔍 Combined search found \(stores.count) total thrift stores")
            }
            
            await MainActor.run {
                self.thriftStores = stores
                self.isLoading = false
            }
        } catch {
            print("❌ ThriftStoreMapService error: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // New method for text search fallback
    private func performTextSearchForThriftStores(latitude: Double, longitude: Double) async throws -> [ThriftStore] {
        let textSearchURL = "https://places.googleapis.com/v1/places:searchText"
        
        guard let url = URL(string: textSearchURL) else {
            throw PlacesAPIError.invalidURL
        }
        
        // Create request body for text search
        let requestBody: [String: Any] = [
            "textQuery": "thrift store near me",
            "maxResultCount": 10
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.primaryType", forHTTPHeaderField: "X-Goog-FieldMask")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw PlacesAPIError.invalidURL
        }
        
        print("🔍 Text search for thrift stores...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse
        }
        
        print("🗺️ Text search response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🗺️ Text search error response: \(errorString)")
            }
            return [] // Return empty array instead of throwing to allow nearby search results to still show
        }
        
        let result = try JSONDecoder().decode(NewGooglePlacesResult.self, from: data)
        
        let stores = result.places?.compactMap { place in
            ThriftStore(from: place)
        } ?? []
        
        print("🔍 Text search found \(stores.count) thrift stores")
        
        // Filter to only nearby stores (within reasonable distance)
        let nearbyStores = stores.filter { store in
            let distance = calculateDistance(lat1: latitude, lon1: longitude, lat2: store.latitude, lon2: store.longitude)
            return distance <= 25.0 // 25km max distance
        }
        
        print("🔍 \(nearbyStores.count) text search stores are within 25km")
        
        return nearbyStores
    }
    
    // Helper function to calculate distance between two coordinates
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6371.0 // Earth's radius in kilometers
        
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    private func performThriftStoreSearch(latitude: Double, longitude: Double, radius: Int) async throws -> [ThriftStore] {
        // Convert radius from km to meters (Google Places API uses meters)
        let radiusInMeters = radius * 1000
        
        guard let url = URL(string: baseURL) else {
            throw PlacesAPIError.invalidURL
        }
        
        // Create request body for new Places API with expanded types to catch thrift stores
        let requestBody: [String: Any] = [
            "includedTypes": ["store", "discount_store", "clothing_store"], // Expanded to include more thrift store types
            "maxResultCount": 20,
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": latitude,
                        "longitude": longitude
                    ],
                    "radius": min(radiusInMeters, 50000) // Max 50km
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.primaryType", forHTTPHeaderField: "X-Goog-FieldMask")
        
        // Print bundle ID for debugging
        if let bundleId = Bundle.main.bundleIdentifier {
            print("🗺️ App bundle ID: \(bundleId)")
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw PlacesAPIError.invalidURL
        }
        
        print("🗺️ Searching for thrift stores near: \(latitude), \(longitude)")
        print("🔍 New Google Places API request with expanded types")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse
        }
        
        print("🗺️ Places API response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🗺️ Places API error response: \(errorString)")
            }
            throw PlacesAPIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(NewGooglePlacesResult.self, from: data)
        
        let stores = result.places?.compactMap { place in
            ThriftStore(from: place)
        } ?? []
        
        print("🗺️ New Google Places API found \(stores.count) potential stores")
        
        // Debug: Print first few stores to see what we're getting
        for (index, store) in stores.prefix(5).enumerated() {
            print("🔍 Store \(index + 1): '\(store.title)' at \(store.address)")
        }
        
        // Enhanced filter for thrift stores with better keyword matching
        let thriftKeywords = [
            // Core thrift terms
            "thrift", "thrifting", "thrifted", "thrift store", "thrift shop",
            
            // Secondhand terms
            "secondhand", "second-hand", "second hand", "preloved", "pre-loved", "pre loved",
            
            // Resale terms
            "resale", "resell", "recycled", "reclaimed", "hand-me-down",
            
            // Store types and names
            "consignment", "donation", "donation center", "vintage", "used", 
            "antique", "flea market", "streetwear", "retro",
            
            // Popular chains and store names
            "goodwill", "salvation army", "savers", "value village", "platos closet", "plato's closet",
            "buffalo exchange", "crossroads trading", "crossroads", "wasteland", "beacon's closet",
            "out of the closet", "community thrift", "relove", "eye thrift", "born again",
            "2nd street", "second street",
            
            // Other terms
            "charity", "discount"
        ]
        
        let thriftStores = stores.filter { store in
            let searchText = "\(store.title) \(store.address)".lowercased()
            let isThriftStore = thriftKeywords.contains { keyword in
                searchText.contains(keyword)
            }
            
            if isThriftStore {
                print("✅ Found thrift store: '\(store.title)'")
            }
            
            return isThriftStore
        }
        
        print("🗺️ Filtered to \(thriftStores.count) thrift stores")
        
        // If we still have few thrift stores, let's be more inclusive for testing
        if thriftStores.count < 3 {
            print("⚠️ Only found \(thriftStores.count) thrift stores, showing additional discount/clothing stores for testing")
            // Include stores that might be thrift stores based on type
            let additionalStores = stores.filter { store in
                let searchText = "\(store.title) \(store.address)".lowercased()
                let isAlreadyIncluded = thriftKeywords.contains { keyword in
                    searchText.contains(keyword)
                }
                // Include discount stores and some clothing stores that might be thrift stores
                return !isAlreadyIncluded && (searchText.contains("discount") || searchText.contains("vintage") || searchText.contains("used"))
            }
            return thriftStores + additionalStores.prefix(5)
        }
        
        return thriftStores
    }
}

// MARK: - Thrift Store Data Models
struct ThriftStore: Identifiable, Codable {
    let id = UUID()
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let reviews: Int?
    let phoneNumber: String?
    let website: String?
    let hours: String?
    let thumbnail: String?
    
    init(from place: NewGooglePlace) {
        self.title = place.displayName?.text ?? "Store"
        self.address = place.formattedAddress ?? ""
        self.latitude = place.location.latitude
        self.longitude = place.location.longitude
        self.rating = place.rating
        self.reviews = place.userRatingCount
        self.phoneNumber = nil // Not available in basic search
        self.website = nil // Not available in basic search
        self.hours = nil // Not available in basic search
        self.thumbnail = nil // Not available in basic search
    }
    
    // Legacy initializer for backward compatibility
    init(from place: GooglePlace) {
        self.title = place.name
        self.address = place.vicinity ?? place.formatted_address ?? ""
        self.latitude = place.geometry.location.lat
        self.longitude = place.geometry.location.lng
        self.rating = place.rating
        self.reviews = place.user_ratings_total
        self.phoneNumber = nil // Not available in Nearby Search
        self.website = nil // Not available in Nearby Search
        self.hours = nil // Not available in Nearby Search
        self.thumbnail = place.photos?.first?.photo_reference
    }
    
    // Custom initializer for mock data
    init(title: String, address: String, latitude: Double, longitude: Double, rating: Double?, reviews: Int?, phoneNumber: String?, website: String?, hours: String?, thumbnail: String?) {
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.rating = rating
        self.reviews = reviews
        self.phoneNumber = phoneNumber
        self.website = website
        self.hours = hours
        self.thumbnail = thumbnail
    }
}

// MARK: - New Google Places API Models
struct NewGooglePlacesResult: Codable {
    let places: [NewGooglePlace]?
}

struct NewGooglePlace: Codable {
    let id: String
    let displayName: PlaceDisplayName?
    let formattedAddress: String?
    let location: NewPlaceLocation
    let rating: Double?
    let userRatingCount: Int?
    let primaryType: String?
}

struct PlaceDisplayName: Codable {
    let text: String
}

struct NewPlaceLocation: Codable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Legacy Google Places API Models (for backward compatibility)
struct GooglePlacesResult: Codable {
    let results: [GooglePlace]
    let status: String
    let error_message: String?
}

struct GooglePlace: Codable {
    let place_id: String
    let name: String
    let vicinity: String?
    let formatted_address: String?
    let geometry: PlaceGeometry
    let rating: Double?
    let user_ratings_total: Int?
    let photos: [PlacePhoto]?
    let types: [String]
    
    enum CodingKeys: String, CodingKey {
        case place_id, name, vicinity, formatted_address, geometry, rating, user_ratings_total, photos, types
    }
}

struct PlaceGeometry: Codable {
    let location: PlaceLocation
}

struct PlaceLocation: Codable {
    let lat: Double
    let lng: Double
}

struct PlacePhoto: Codable {
    let photo_reference: String
    let height: Int
    let width: Int
}

// MARK: - Enhanced Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationUpdateTimer: Timer?
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTrackingLocation = false
    
    // Singleton to ensure consistent location tracking across the app
    static let shared = LocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update when user moves 10 meters
        authorizationStatus = locationManager.authorizationStatus
        
        // Defer location tracking to avoid TCC violations during app startup
        DispatchQueue.main.async { [weak self] in
            self?.startLocationTracking()
        }
        
        // Track app lifecycle to maintain location services
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appDidBecomeActive), 
            name: UIApplication.didBecomeActiveNotification, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appWillResignActive), 
            name: UIApplication.willResignActiveNotification, 
            object: nil
        )
    }
    
    deinit {
        locationUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidBecomeActive() {
        print("📍 App became active - ensuring location tracking")
        startLocationTracking()
    }
    
    @objc private func appWillResignActive() {
        print("📍 App will resign active - maintaining background location if possible")
        // Keep location services running for when app returns
    }
    
    func startLocationTracking() {
        guard !isTrackingLocation else { return }
        
        print("📍 Starting enhanced location tracking...")
        isTrackingLocation = true
        
        switch authorizationStatus {
        case .notDetermined:
            print("📍 Requesting location authorization...")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginLocationUpdates()
        case .denied, .restricted:
            print("📍 Location access denied - using default NYC location")
            setDefaultLocation()
        @unknown default:
            print("📍 Unknown authorization status")
            locationManager.requestWhenInUseAuthorization()
        }
        
        // Set up periodic location refresh (every 60 seconds) - less aggressive
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshLocation()
        }
    }
    
    func stopLocationTracking() {
        print("📍 Stopping location tracking...")
        isTrackingLocation = false
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    private func beginLocationUpdates() {
        print("📍 Beginning continuous location updates...")
        locationManager.startUpdatingLocation()
        
        // Also do a one-time location request for immediate results
        locationManager.requestLocation()
    }
    
    private func refreshLocation() {
        guard isTrackingLocation else { return }
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 Refreshing location...")
            locationManager.requestLocation()
        default:
            break
        }
    }
    
    private func setDefaultLocation() {
        // Default to NYC coordinates
        location = CLLocation(latitude: 40.7589, longitude: -73.9851)
        print("📍 Set default location: NYC")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Only update if the new location is significantly different or more recent
        if let currentLocation = location {
            let distance = newLocation.distance(from: currentLocation)
            let timeInterval = newLocation.timestamp.timeIntervalSince(currentLocation.timestamp)
            
            // Update if moved more than 100 meters or if it's been more than 60 seconds - less aggressive
            if distance > 100 || timeInterval > 60 {
                location = newLocation
                print("📍 Location updated: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
            }
        } else {
            location = newLocation
            print("📍 Initial location set: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        // If we don't have a location yet, set default
        if location == nil {
            setDefaultLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 Authorization status changed to: \(status.rawValue)")
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            beginLocationUpdates()
        case .denied, .restricted:
            setDefaultLocation()
        case .notDetermined:
            // Will be handled by the next authorization request
            break
        @unknown default:
            print("📍 Unknown authorization status")
        }
    }
}

// MARK: - Thrift Store Annotation
class ThriftStoreAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let thriftStore: ThriftStore
    
    init(thriftStore: ThriftStore) {
        self.thriftStore = thriftStore
        self.coordinate = CLLocationCoordinate2D(latitude: thriftStore.latitude, longitude: thriftStore.longitude)
        self.title = thriftStore.title
        
        var subtitleText = thriftStore.address
        if let rating = thriftStore.rating {
            subtitleText += " • ⭐ \(String(format: "%.1f", rating))"
        }
        if let reviews = thriftStore.reviews {
            subtitleText += " (\(reviews) reviews)"
        }
        self.subtitle = subtitleText
        
        super.init()
    }
}

// MARK: - Custom Apple-Style Annotation View
class ThriftStoreAnnotationView: MKAnnotationView {
    
    private var nameLabel: UILabel!
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        canShowCallout = false
        isUserInteractionEnabled = true
        
        // Create the main container
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.isUserInteractionEnabled = true
        
        // Create store name label (lowercase, smaller, with ellipsis)
        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .black
        nameLabel.backgroundColor = .white
        nameLabel.layer.cornerRadius = 16  // Larger radius for new size
        nameLabel.layer.masksToBounds = false  // Allow shadow
        nameLabel.layer.borderWidth = 0.5
        nameLabel.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor  // Subtle blue hint
        
        // Add shadow using a separate shadow layer to avoid masksToBounds conflict
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 2)
        nameLabel.layer.shadowOpacity = 0.15
        nameLabel.layer.shadowRadius = 4
        nameLabel.layer.shadowPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 130, height: 32), cornerRadius: 16).cgPath
        nameLabel.isUserInteractionEnabled = false // Let map handle the touches
        
        // Create link emoji pin
        let pinView = UILabel()
        pinView.translatesAutoresizingMaskIntoConstraints = false
        pinView.text = "🔗"
        pinView.font = UIFont.systemFont(ofSize: 24)
        pinView.textAlignment = .center
        pinView.isUserInteractionEnabled = false  // Don't block map interactions
        
        // Add subviews
        containerView.addSubview(nameLabel)
        containerView.addSubview(pinView)
        addSubview(containerView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            
            // Name label - increased touch area
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            nameLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 130), // Wider
            nameLabel.heightAnchor.constraint(equalToConstant: 32), // Taller for better touch
            
            // Pin (link emoji) - larger touch target
            pinView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            pinView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            pinView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            pinView.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            pinView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    

    
    // Remove aggressive touch handling to allow map interactions
    
    func showCopyFeedback() {
        // Add visual feedback for tap
        UIView.animate(withDuration: 0.1, animations: {
            self.nameLabel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.nameLabel.alpha = 0.8
            self.nameLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.nameLabel.transform = CGAffineTransform.identity
                self.nameLabel.alpha = 1.0
                self.nameLabel.backgroundColor = .white
            }
        }
    }
    

    
    override func prepareForReuse() {
        super.prepareForReuse()
        updateContent()
    }
    
    override var annotation: MKAnnotation? {
        didSet {
            updateContent()
        }
    }
    
    private func updateContent() {
        guard let annotation = annotation as? ThriftStoreAnnotation else { return }
        nameLabel.text = "  \(annotation.thriftStore.title.lowercased())  "
    }
}

// MARK: - Map View Controller (Updated for Google Maps)
class MapViewController: ObservableObject {
    private var mapView: GMSMapView?
    
    func setMapView(_ mapView: GMSMapView) {
        self.mapView = mapView
    }
    
    func zoomIn() {
        guard let mapView = mapView else { return }
        let currentZoom = mapView.camera.zoom
        let newZoom = min(currentZoom + 1, 20) // Max zoom level 20
        
        let camera = GMSCameraUpdate.zoom(to: newZoom)
        mapView.animate(with: camera)
    }
    
    func zoomOut() {
        guard let mapView = mapView else { return }
        let currentZoom = mapView.camera.zoom
        let newZoom = max(currentZoom - 1, 1) // Min zoom level 1
        
        let camera = GMSCameraUpdate.zoom(to: newZoom)
        mapView.animate(with: camera)
    }
}

// MARK: - Legacy Apple Maps View (DEPRECATED - Use GoogleMapsView instead)
/*
struct ThriftStoreMapView: UIViewRepresentable {
    @StateObject private var mapService = ThriftStoreMapService()
    @ObservedObject private var locationManager = LocationManager.shared // Use singleton
    @ObservedObject var mapController: MapViewController
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        
        // Ultra-minimal map appearance - no streets or labels
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsBuildings = false
        mapView.showsPointsOfInterest = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        
        // Hide all text labels on map
        mapView.mapType = .mutedStandard
        
        // Set initial region based on current location or default to NYC
        let initialLocation = locationManager.location?.coordinate ?? CLLocationCoordinate2D(latitude: 40.7589, longitude: -73.9851)
        let defaultRegion = MKCoordinateRegion(
            center: initialLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        mapView.setRegion(defaultRegion, animated: false)
        
        // Register custom annotation view
        mapView.register(ThriftStoreAnnotationView.self, forAnnotationViewWithReuseIdentifier: "ThriftStorePin")
        
        // Set map reference in controller for zoom functionality
        mapController.setMapView(mapView)
        
        print("🗺️ Map view initialized with location: \(initialLocation)")
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        
        // Update annotations when thrift stores change (no state modification here)
        let currentAnnotations = mapView.annotations.compactMap { $0 as? ThriftStoreAnnotation }
        let newStores = mapService.thriftStores
        
        // Only update annotations if the stores have actually changed
        if currentAnnotations.count != newStores.count || 
           !currentAnnotations.allSatisfy({ annotation in
               newStores.contains { $0.id == annotation.thriftStore.id }
           }) {
            
            mapView.removeAnnotations(currentAnnotations)
            let newAnnotations = newStores.map { ThriftStoreAnnotation(thriftStore: $0) }
            mapView.addAnnotations(newAnnotations)
            print("🗺️ Updated map with \(newAnnotations.count) store annotations")
        }
        
        // Handle location updates (use coordinator state, not @State)
        if let location = locationManager.location {
            // Only update region if this is the first location or user has moved significantly
            let shouldUpdateRegion = !coordinator.hasInitializedLocation || 
                                   (coordinator.lastSearchLocation == nil || 
                                    location.distance(from: coordinator.lastSearchLocation!) > 1000) // 1km threshold
            
            if shouldUpdateRegion {
                let newRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                mapView.setRegion(newRegion, animated: coordinator.hasInitializedLocation)
                coordinator.hasInitializedLocation = true
                print("🗺️ Updated map region to: \(location.coordinate)")
            }
            
            // Search for thrift stores if location has changed significantly or no stores loaded
            let shouldSearchStores = coordinator.lastSearchLocation == nil || 
                                   location.distance(from: coordinator.lastSearchLocation!) > 2000 || // 2km threshold
                                   (mapService.thriftStores.isEmpty && !mapService.isLoading)
            
            if shouldSearchStores {
                coordinator.lastSearchLocation = location
                Task {
                    print("🗺️ Searching for stores near: \(location.coordinate)")
                    await mapService.searchNearbyThriftStores(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Use coordinator to track state instead of @State to avoid infinite loops
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ThriftStoreMapView
        var hasInitializedLocation = false
        var lastSearchLocation: CLLocation?
        
        init(_ parent: ThriftStoreMapView) {
            self.parent = parent
            super.init()
            
            // Start location tracking immediately
            parent.locationManager.startLocationTracking()
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Don't customize user location annotation
            if annotation is MKUserLocation {
                return nil
            }
            
            guard annotation is ThriftStoreAnnotation else {
                return nil
            }
            
            let identifier = "ThriftStorePin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? ThriftStoreAnnotationView
            
            if annotationView == nil {
                annotationView = ThriftStoreAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            print("🗺️ Map annotation selected")
            
            // Handle address copying when annotation is selected
            guard let annotation = view.annotation as? ThriftStoreAnnotation else { 
                return 
            }
            
            let store = annotation.thriftStore
            
            // Ensure we have a valid address
            guard !store.address.isEmpty else {
                print("❌ Store address is empty")
                return
            }
            
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Copy address to clipboard
            UIPasteboard.general.string = store.address
            print("✅ Address copied to clipboard: \(store.address)")
            
            // Add visual feedback to the annotation view
            if let annotationView = view as? ThriftStoreAnnotationView {
                annotationView.showCopyFeedback()
            }
            
            // Show feedback that address was copied
            let alert = UIAlertController(
                title: "✨ Address Copied!",
                message: "\n\(store.title)\n\(store.address)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Got it!", style: .default))
            
            // Find the top view controller to present the alert
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {
                    
                    var topController = rootViewController
                    while let presented = topController.presentedViewController {
                        topController = presented
                    }
                    
                    topController.present(alert, animated: true)
                } else {
                    print("❌ Could not find view controller to present alert")
                }
            }
            
            // Deselect the annotation to allow multiple taps
            mapView.deselectAnnotation(annotation, animated: false)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Optionally search for new stores when user pans the map significantly
            let currentCenter = mapView.region.center
            
            if let lastSearchLocation = self.lastSearchLocation {
                let distance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                    .distance(from: lastSearchLocation)
                
                // If user has panned more than 5km, search for new stores
                if distance > 5000 {
                    self.lastSearchLocation = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                    Task {
                        print("🗺️ Map panned significantly, searching for new stores")
                        await parent.mapService.searchNearbyThriftStores(
                            latitude: currentCenter.latitude,
                            longitude: currentCenter.longitude
                        )
                    }
                }
            }
        }
    }
}
*/



// MARK: - Clothing Details Models
struct ClothingDetails: Codable, Equatable {
    let category: String?
    let style: String?
    let season: String?
    let gender: String?
    let designerTier: String?
    let era: String?
    let colors: [String]?
    let fabricComposition: [FabricComponent]?
    let isAuthentic: Bool?
    
    enum CodingKeys: String, CodingKey {
        case category, style, season, gender, era, colors
        case designerTier = "designer_tier"
        case fabricComposition = "fabric_composition"
        case isAuthentic = "is_authentic"
    }
}

struct FabricComponent: Codable, Equatable {
    let material: String
    let percentage: Int
}

// Completely static Apple Sign In Button - no visual changes allowed
struct AppleSignInButton: View {
    @ObservedObject var authManager: AuthenticationManager
    
    var body: some View {
        ZStack {
            // Static black background - never changes
            Rectangle()
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: 56)
                .cornerRadius(28)
            
            // Static content - never changes
            HStack {
                Image(systemName: "applelogo")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                Text("Sign in with Apple")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .contentShape(Rectangle()) // Define tap area
        .onTapGesture {
            // Simple tap action - no button styling at all
            authManager.signInWithApple()
        }
        .allowsHitTesting(!authManager.isLoading) // Disable when loading but no visual change
    }
}

// Completely static Google Sign In Button - no visual changes allowed
struct GoogleSignInButton: View {
    @ObservedObject var authManager: AuthenticationManager
    
    var body: some View {
        ZStack {
            // Static white background with border - never changes
            Rectangle()
                .fill(Color.white)
                .frame(maxWidth: .infinity, maxHeight: 56)
                .cornerRadius(28)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            
            // Static content - never changes
            HStack {
                Image("google-logo")
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("Sign in with Google")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black)
            }
        }
        .contentShape(Rectangle()) // Define tap area
        .onTapGesture {
            // Simple tap action - no button styling at all
            authManager.signInWithGoogle()
        }
        .allowsHitTesting(!authManager.isLoading) // Disable when loading but no visual change
    }
}

// Completely static Continue with Email Button - no visual changes allowed
struct EmailSignInButton: View {
    @Binding var showingEmailSignIn: Bool
    @ObservedObject var authManager: AuthenticationManager
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            // Static white background with border - never changes
            Rectangle()
                .fill(Color.white)
                .frame(maxWidth: .infinity, maxHeight: 56)
                .cornerRadius(28)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            
            // Static content - never changes
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.black)
                Text("Continue with email")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black)
            }
        }
        .contentShape(Rectangle()) // Define tap area
        .onTapGesture {
            // Simple tap action - no button styling at all
            showingEmailSignIn = true
            onTap()
        }
        .allowsHitTesting(!authManager.isLoading) // Disable when loading but no visual change
    }
}

// Completely static Get Started Button - no visual changes allowed
struct GetStartedButton: View {
    @Binding var showingOnboarding: Bool
    
    var body: some View {
        ZStack {
            // Static black background - never changes
            Rectangle()
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: 56)
                .cornerRadius(28)
            
            // Static content - never changes
            Text("Get Started")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
        }
        .contentShape(Rectangle()) // Define tap area
        .onTapGesture {
            // Simple tap action - no button styling at all
            showingOnboarding = true
        }
    }
}

// Song Data Model with Codable support for persistence
struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var lyrics: String
    var imageName: String
    var customImageData: Data? // Store image as Data for persistence
    var additionalImagesData: [Data]? // Store additional images for multi-image analysis
    var useWaveformDesign: Bool = false
    var lastEdited: Date
    var associatedInstrumental: String? // Track which instrumental is loaded with this song
    
    // Custom initializer to ensure UUID is created only once
    init(title: String, lyrics: String, imageName: String, customImageData: Data? = nil, additionalImagesData: [Data]? = nil, useWaveformDesign: Bool = false, lastEdited: Date = Date(), associatedInstrumental: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.lyrics = lyrics
        self.imageName = imageName
        self.customImageData = customImageData
        self.additionalImagesData = additionalImagesData
        self.useWaveformDesign = useWaveformDesign
        self.lastEdited = lastEdited
        self.associatedInstrumental = associatedInstrumental
    }
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: lastEdited)
    }
    
    // Computed property for UIImage (not persisted directly)
    var customImage: UIImage? {
        get {
            guard let data = customImageData else { return nil }
            return UIImage(data: data)
        }
        set {
            customImageData = newValue?.jpegData(compressionQuality: 0.7)
        }
    }
    
    // Computed property for additional images (not persisted directly)
    var additionalImages: [UIImage]? {
        get {
            guard let dataArray = additionalImagesData else { return nil }
            return dataArray.compactMap { UIImage(data: $0) }
        }
        set {
            additionalImagesData = newValue?.compactMap { $0.jpegData(compressionQuality: 0.7) }
        }
    }
    
    // All images combined (main + additional + asset images)
    var allImages: [UIImage] {
        var images: [UIImage] = []
        
        // Add custom image if available
        if let mainImage = customImage {
            images.append(mainImage)
        }
        // Add asset image if available and no custom image
        else if !imageName.isEmpty, let assetImage = UIImage(named: imageName) {
            images.append(assetImage)
        }
        
        // Add additional images
        if let additionalImages = additionalImages {
            images.append(contentsOf: additionalImages)
        }
        
        return images
    }
    
    // Custom coding keys to exclude computed properties from Codable
    enum CodingKeys: String, CodingKey {
        case id, title, lyrics, imageName, customImageData, additionalImagesData, useWaveformDesign, lastEdited, associatedInstrumental
    }
}

// Song Manager to handle app-wide song data with persistence
@MainActor
class SongManager: ObservableObject {
    @Published var songs: [Song] = []
    
    private let userDefaultsKey = "SavedSongs"
    private let imageIndexKey = "CurrentImageIndex"
    private let migrationKey = "RealThriftDataMigrationCompleted"
    
    // Available images for new songs (includes new + default images)
    private let availableImages = [
        "travis",      // New artist image
        "ecko",        // New artist image
        "coach",       // New artist image
        "mansion",     // New image
        "skyline",     // New image  
        "couple",      // New image
        "lambo",       // Existing
        "boy",         // Existing
        "girl"         // Existing
    ]
    
    private var currentImageIndex: Int {
        get {
            UserDefaults.standard.integer(forKey: imageIndexKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: imageIndexKey)
        }
    }
    
    init() {
        // Defer heavy loading to avoid blocking the main thread
        DispatchQueue.main.async { [weak self] in
            self?.loadSongs()
        }
    }
    
    func updateSong(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            // Remove the song from its current position
            songs.remove(at: index)
            // Insert it at the beginning to make it most recently edited
            songs.insert(song, at: 0)
            saveSongs()
            print("📝 Moved song '\(song.title)' to front of recently added list")
        }
    }
    
    // Update song properties without changing its position in the list
    func updateSongInPlace(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index] = song
            saveSongs()
            print("📝 Updated song '\(song.title)' without moving position")
        }
    }
    
    func addSong(_ song: Song) {
        songs.insert(song, at: 0) // Add to beginning of list
        saveSongs()
    }
    
    func createNewSong() -> Song {
        // Get the next image in rotation
        let selectedImage = availableImages[currentImageIndex]
        
        // Move to next image for the next song
        currentImageIndex = (currentImageIndex + 1) % availableImages.count
        
        // Generate unique title
        let uniqueTitle = generateUniqueTitle()
        
        let newSong = Song(
            title: uniqueTitle,
            lyrics: "", // Start with empty lyrics - placeholder will show in UI
            imageName: selectedImage,
            useWaveformDesign: false, // Use actual images instead of waveform
            lastEdited: Date()
        )
        
        print("🎨 Created new song with title: '\(uniqueTitle)' and image: \(selectedImage)")
        addSong(newSong)
        return newSong
    }
    
    // Generate unique title with incrementing numbers
    private func generateUniqueTitle() -> String {
        let baseName = "Untitled Song"
        
        // Check if base name is available
        if !songs.contains(where: { $0.title == baseName }) {
            return baseName
        }
        
        // Find the highest number suffix in use
        var highestNumber = 0
        let basePattern = "\(baseName) ("
        
        for song in songs {
            if song.title.hasPrefix(basePattern) && song.title.hasSuffix(")") {
                let numberPart = song.title.dropFirst(basePattern.count).dropLast(1)
                if let number = Int(numberPart) {
                    highestNumber = max(highestNumber, number)
                }
            }
        }
        
        // Return the next available number
        let nextNumber = highestNumber + 1
        let uniqueTitle = "\(baseName) (\(nextNumber))"
        
        print("📝 Generated unique title: '\(uniqueTitle)' (highest existing: \(highestNumber))")
        return uniqueTitle
    }
    
    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        saveSongs()
    }
    
    func removeSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        saveSongs()
        print("🗑️ Removed song '\(song.title)' from song manager")
        
        // Also remove associated profit data from UserDefaults
        UserDefaults.standard.removeObject(forKey: "avgPrice_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "sellPrice_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "profitOverride_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "useCustomProfit_\(song.id)")
    }
    
    private func saveSongs() {
        if let encoded = try? JSONEncoder().encode(songs) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 Saved \(songs.count) songs to UserDefaults")
        } else {
            print("❌ Failed to encode songs for saving")
        }
    }
    
    private func loadSongs() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            songs = decoded
            print("📱 Loaded \(songs.count) songs from UserDefaults")
            
            // Debug: Print song IDs to verify UUID persistence
            for song in songs {
                print("🔍 Loaded song: '\(song.title)' with ID: \(song.id.uuidString)")
            }
            
            // Migrate sample songs to use new artist images
            migrateSampleSongsToNewImages()
        } else {
            // First time - create default sample songs
            let calendar = Calendar.current
            let now = Date()
            
            songs = [
                Song(
                    title: "Nike Air Jordan 1's - T-Scott", 
                    lyrics: "🔥 FIND: Authentic 80s leather jacket\n💰 PRICE: $45 (Retail: $300+)\n📍 SOURCE: Local thrift store\n⭐ CONDITION: Excellent, minimal wear\n\n📝 NOTES:\n• Genuine leather, buttery soft\n• Classic moto style with zippers\n• Perfect for fall/winter\n• Checked comps - selling for $150+ online\n• Could flip for 3x profit easily\n\n🎯 WHY I BOUGHT IT:\nTimeless piece, great ROI potential, fits current trends", 
                    imageName: "travis", 
                    lastEdited: calendar.date(byAdding: .day, value: -3, to: now) ?? now
                ),
                Song(
                    title: "Vintage Ecko Navy Blue Hoodie", 
                    lyrics: "🔥 FIND: Jordan 4 White Cement (2016)\n💰 PRICE: $65 (Retail: $190, Resale: $180-250)\n📍 SOURCE: Goodwill\n⭐ CONDITION: 8/10, light creasing\n\n📝 NOTES:\n• Size 10.5 - popular size\n• OG all with box (missing lid)\n• Slight yellowing on midsole (normal)\n• No major flaws or scuffs\n• StockX verified authentic look-alikes\n\n🎯 WHY I BOUGHT IT:\nInstant profit, always in demand, classic colorway", 
                    imageName: "ecko", 
                    lastEdited: calendar.date(byAdding: .day, value: -7, to: now) ?? now
                ),
                Song(
                    title: "Coach Vintage Handbag", 
                    lyrics: "🔥 FIND: Coach Legacy Shoulder Bag\n💰 PRICE: $12 (Retail: $298)\n📍 SOURCE: Estate sale\n⭐ CONDITION: 9/10, barely used\n\n📝 NOTES:\n• Authentic serial number verified\n• Black pebbled leather\n• Silver hardware, no tarnishing\n• Interior pristine, no stains\n• Dust bag included\n• Model 9966 - discontinued style\n\n🎯 WHY I BOUGHT IT:\nAuthentic Coach under $15 is always a buy. These sell for $80-120 online.", 
                    imageName: "coach", 
                    lastEdited: calendar.date(byAdding: .day, value: -12, to: now) ?? now
                )
            ]
            saveSongs() // Save the initial songs
            print("🎵 Created initial sample songs")
        }
    }
    
    // Migrate existing sample songs to use new artist images
    private func migrateSampleSongsToNewImages() {
        // Check if migration has already been completed
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }
        
        let imageMapping = [
            "lambo": "travis",
            "boy": "ecko", 
            "girl": "coach"
        ]
        
        // Also handle title mapping for old sample songs
        let titleMapping = [
            "My Turn (Sample Song)": "Nike Air Jordan 1's - T-Scott",
            "IDGAF (Sample Song)": "Vintage Ecko Navy Blue Hoodie",
            "Deep Thoughts (Sample Song)": "Coach Vintage Handbag"
        ]
        
        var updated = false
        
        for i in 0..<songs.count {
            let currentSong = songs[i]
            
            // Check if this is an old sample song that needs migration
            if currentSong.title.contains("(Sample Song)") || 
               imageMapping.keys.contains(currentSong.imageName) {
                
                // Update image if needed
                if let newImageName = imageMapping[currentSong.imageName] {
                    songs[i].imageName = newImageName
                    updated = true
                }
                
                // Update title and content if it's an old sample song
                if let newTitle = titleMapping[currentSong.title] {
                    songs[i].title = newTitle
                    
                    // Set realistic dates for migrated songs
                    let calendar = Calendar.current
                    let now = Date()
                    
                    // Add realistic content and dates based on the new title
                    switch newTitle {
                    case "Nike Air Jordan 1's - T-Scott":
                        songs[i].lyrics = "🔥 FIND: Authentic 80s leather jacket\n💰 PRICE: $45 (Retail: $300+)\n📍 SOURCE: Local thrift store\n⭐ CONDITION: Excellent, minimal wear\n\n📝 NOTES:\n• Genuine leather, buttery soft\n• Classic moto style with zippers\n• Perfect for fall/winter\n• Checked comps - selling for $150+ online\n• Could flip for 3x profit easily\n\n🎯 WHY I BOUGHT IT:\nTimeless piece, great ROI potential, fits current trends"
                        songs[i].lastEdited = calendar.date(byAdding: .day, value: -3, to: now) ?? now
                    case "Vintage Ecko Navy Blue Hoodie":
                        songs[i].lyrics = "🔥 FIND: Jordan 4 White Cement (2016)\n💰 PRICE: $65 (Retail: $190, Resale: $180-250)\n📍 SOURCE: Goodwill\n⭐ CONDITION: 8/10, light creasing\n\n📝 NOTES:\n• Size 10.5 - popular size\n• OG all with box (missing lid)\n• Slight yellowing on midsole (normal)\n• No major flaws or scuffs\n• StockX verified authentic look-alikes\n\n🎯 WHY I BOUGHT IT:\nInstant profit, always in demand, classic colorway"
                        songs[i].lastEdited = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                    case "Coach Vintage Handbag":
                        songs[i].lyrics = "🔥 FIND: Coach Legacy Shoulder Bag\n💰 PRICE: $12 (Retail: $298)\n📍 SOURCE: Estate sale\n⭐ CONDITION: 9/10, barely used\n\n📝 NOTES:\n• Authentic serial number verified\n• Black pebbled leather\n• Silver hardware, no tarnishing\n• Interior pristine, no stains\n• Dust bag included\n• Model 9966 - discontinued style\n\n🎯 WHY I BOUGHT IT:\nAuthentic Coach under $15 is always a buy. These sell for $80-120 online."
                        songs[i].lastEdited = calendar.date(byAdding: .day, value: -12, to: now) ?? now
                    default:
                        break
                    }
                    updated = true
                }
                
                print("🔄 Migrated sample: '\(currentSong.title)' to '\(songs[i].title)' with image '\(songs[i].imageName)'")
            }
        }
        
        if updated {
            saveSongs()
            print("✅ Sample songs migration completed with real thrift data")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var purchasedSubscriptions: [Product] = []
    @Published var isSubscribed = false
    
    private let productIds = [
        "com.thrifty.thrifty.unlimited.yearly79",         // $79.00 yearly subscription (NEW)
        "com.thrifty.thrifty.unlimited.yearly.winback39" // $39.00 winback offer (NEW)
    ]
    
    // Fallback product IDs (temporarily for testing while new products are pending approval)
    private let fallbackProductIds = [
        "com.thrifty.thrifty.unlimited.yearly",         // Old yearly subscription
        "com.thrifty.thrifty.unlimited.monthly.winback" // Old winback offer
    ]
    
    init() {
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    func loadProducts() async {
        do {
            subscriptions = try await Product.products(for: productIds)
            print("✅ Successfully loaded \(subscriptions.count) products")
            for product in subscriptions {
                print("   - \(product.id): \(product.displayPrice)")
            }
            
            // Check if we got the expected number of products
            if subscriptions.count < productIds.count {
                print("⚠️ Missing products detected!")
                let loadedIds = subscriptions.map { $0.id }
                for productId in productIds {
                    if !loadedIds.contains(productId) {
                        print("❌ Missing product: \(productId)")
                    }
                }
                print("💡 Trying fallback product IDs for testing...")
                
                // Try fallback products since new ones aren't available
                do {
                    let fallbackProducts = try await Product.products(for: fallbackProductIds)
                    print("✅ Fallback products loaded successfully: \(fallbackProducts.count) products")
                    for product in fallbackProducts {
                        print("   - \(product.id): \(product.displayPrice)")
                    }
                    // Use fallback products if we got more products than with new IDs
                    if fallbackProducts.count > subscriptions.count {
                        subscriptions = fallbackProducts
                        print("⚠️ Using old product IDs temporarily until new ones are approved")
                    }
                } catch {
                    print("❌ Fallback products also failed:", error)
                }
            }
            
        } catch {
            print("❌ Failed to load products:", error)
            print("🔍 Attempting to load products with these IDs:")
            for productId in productIds {
                print("   - \(productId)")
            }
            
            // Try fallback products immediately if main load failed
            print("💡 Trying fallback product IDs...")
            do {
                subscriptions = try await Product.products(for: fallbackProductIds)
                print("✅ Fallback products loaded successfully: \(subscriptions.count) products")
                for product in subscriptions {
                    print("   - \(product.id): \(product.displayPrice)")
                }
                print("⚠️ Using old product IDs temporarily until new ones are approved")
            } catch {
                print("❌ Even fallback products failed:", error)
                print("💡 This usually means:")
                print("   1. Products are not yet approved in App Store Connect")
                print("   2. Products are not available in this region")
                print("   3. There's a configuration issue")
            }
        }
    }
    
    func updateSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == productIds[0] {
                    isSubscribed = true
                    return
                }
            case .unverified:
                continue
            }
        }
        isSubscribed = false
    }
    
    func restorePurchases() async throws {
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }
}

enum StoreError: Error {
    case failedVerification
    case userCancelled
    case pending
    case unknown
}

struct SignInView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthenticationManager.shared
    @Binding var showingEmailSignIn: Bool
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            ZStack {
                Text("Sign In")
                    .font(.system(size: 24, weight: .bold))
                    .frame(maxWidth: .infinity)
                
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 24)
            
            Divider()
                .padding(.top, 16)
            
            // Sign in buttons
            VStack(spacing: 20) {
                // Sign in with Apple - Isolated button
                AppleSignInButton(authManager: authManager)
                
                // Google Sign In - RE-ENABLED with real CLIENT_ID
                GoogleSignInButton(authManager: authManager)
                
                // Continue with email - Static button
                EmailSignInButton(showingEmailSignIn: $showingEmailSignIn, authManager: authManager) {
                    dismiss()
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 24)
            
            // Terms text with original format and simplified tap detection
            TermsAndPrivacyText(showingPrivacyPolicy: $showingPrivacyPolicy)
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .background(Color.white)
        .cornerRadius(32, corners: [.topLeft, .topRight])
        .clipped() // Prevent any content from bleeding outside bounds
        .onChange(of: authManager.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                dismiss()
            }
        }
        .alert("Authentication Error", isPresented: .constant(authManager.errorMessage != nil)) {
            Button("OK") {
                authManager.errorMessage = nil
            }
        } message: {
            Text(authManager.errorMessage ?? "")
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.8)])
                .presentationDragIndicator(.visible)
        }
    }
}

// Terms and Privacy Text Component - Separated to avoid compilation issues
struct TermsAndPrivacyText: View {
    @Binding var showingPrivacyPolicy: Bool
    @State private var showingTermsOfService = false
    
    var body: some View {
        VStack(spacing: 0) {
            termsText
                .multilineTextAlignment(.center)
        }
    }
    
    private var termsText: some View {
        VStack(spacing: 2) {
            Text("By continuing you agree to Thrifty's")
                .font(.system(size: 12))
                .foregroundColor(.black)
            
            HStack(spacing: 0) {
                Text("Terms of Service")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .underline(color: .black)
                    .onTapGesture {
                        print("✅ Opening Thrifty Terms of Service")
                        showingTermsOfService = true
                    }
                
                Text(" and ")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                
                Text("Privacy Policy")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .underline(color: .black)
                    .onTapGesture {
                        print("✅ Privacy Policy tapped directly")
                        showingPrivacyPolicy = true
                    }
            }
        }
        .sheet(isPresented: $showingTermsOfService) {
            TermsOfServiceView()
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.8)])
                .presentationDragIndicator(.visible)
        }
    }

}

// Terms of Service View
struct TermsOfServiceView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    contentSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("Terms of Service")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
            
            Text("Last updated: July 23, 2025")
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            introductionText
            serviceTermsSection
            userObligationsSection
            intellectualPropertySection
            disclaimerSection
            contactSection
        }
    }
    
    private var introductionText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Thrifty. These Terms of Service govern your use of our application and services.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("By using our Service, you agree to be bound by these Terms. If you disagree with any part of these terms, then you may not access the Service.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var serviceTermsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Description")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Thrifty provides an AI-powered item scanning platform that helps users identify and evaluate thrift store items using artificial intelligence technology.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Our services include but are not limited to:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• AI-powered item identification and analysis")
                Text("• Price estimation and market value assessment")
                Text("• Brand and product recognition technology")
                Text("• Unlimited item scanning capabilities")
                Text("• Thrift store item evaluation tools")
            }
            .font(.system(size: 16))
            .foregroundColor(.black)
        }
    }
    
    private var userObligationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User Obligations")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("You agree to use our Service responsibly and in accordance with these terms:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Use the Service only for lawful purposes")
                Text("• Respect intellectual property rights")
                Text("• Provide accurate information when required")
                Text("• Maintain the security of your account")
                Text("• Report any bugs or security issues")
            }
            .font(.system(size: 16))
            .foregroundColor(.black)
        }
    }
    
    private var intellectualPropertySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intellectual Property")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("User-Generated Content")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
            
            Text("You retain ownership of any images and content you upload to our Service. However, you grant us a limited license to process and analyze your content to provide item identification, pricing analysis, and improve our services.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Our Technology")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("All technology, software, and AI models used in our Service remain the exclusive property of Thrifty and are protected by copyright and other intellectual property laws.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disclaimer")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Our Service is provided \"as is\" without warranties of any kind. We strive to provide accurate and helpful AI-generated item analysis, but cannot guarantee the absolute accuracy of price estimates, brand identification, or market value assessments.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Limitation of Liability")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("In no event shall Thrifty be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the Service.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contact Information")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("If you have any questions about these Terms of Service, please contact us:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("📧 By email: helpthrifty@gmail.com")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
        }
    }
}

// Privacy Policy View - Updated with exact content
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    contentSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("Privacy Policy")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
            
            Text("Last updated: July 23, 2025")
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            introductionText
            interpretationAndDefinitionsSection
            collectingAndUsingDataSection
            
            Group {
                retentionSection
                transferSection
                deleteDataSection
                disclosureSection
                securitySection
            }
            
            Group {
                childrenPrivacySection
                linksSection
                changesSection
            contactSection
            }
        }
    }
    
    private var introductionText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Privacy Policy describes Our policies and procedures on the collection, use and disclosure of Your information when You use the Service and tells You about Your privacy rights and how the law protects You.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("We use Your Personal data to provide and improve the Service. By using the Service, You agree to the collection and use of information in accordance with this Privacy Policy.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var interpretationAndDefinitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interpretation and Definitions")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Interpretation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
            
            Text("The words of which the initial letter is capitalized have meanings defined under the following conditions. The following definitions shall have the same meaning regardless of whether they appear in singular or in plural.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Definitions")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 8)
            
            Text("For the purposes of this Privacy Policy:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
            Group {
                Text("Account means a unique account created for You to access our Service or parts of our Service.")
                    Text("Affiliate means an entity that controls, is controlled by or is under common control with a party...")
                Text("Application refers to any application or software program provided by the Company, including but not limited to thrifty.ai, and any other applications or software programs provided by the Company.")
                Text("Company (referred to as either \"the Company\", \"We\", \"Us\" or \"Our\" in this Agreement) refers to Totally Science, 60 Heather Drive.")
                Text("Country refers to: New York, United States")
                }
                
                Group {
                    Text("Device means any device that can access the Service...")
                Text("Personal Data is any information that relates to an identified or identifiable individual.")
                Text("Service refers to the Application.")
                    Text("Service Provider means any natural or legal person who processes the data on behalf of the Company.")
                    Text("Usage Data refers to data collected automatically...")
                Text("You means the individual accessing or using the Service...")
                }
            }
            .font(.system(size: 16))
            .foregroundColor(.black)
        }
    }
    
    private var collectingAndUsingDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collecting and Using Your Personal Data")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .padding(.top, 20)
            
            Group {
                Text("Types of Data Collected")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("Personal Data")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("While using Our Service, We may ask You to provide Us with certain personally identifiable information...")
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                
                Text("Usage Data")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 8)
                
                Text("Usage Data is collected automatically when using the Service...")
                    .font(.system(size: 16))
                    .foregroundColor(.black)
            }
            
            Group {
                Text("Use of Your Personal Data")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 12)
                
                Text("The Company may use Personal Data for the following purposes:")
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("To provide and maintain our Service")
                    Text("To manage Your Account")
                    Text("For the performance of a contract")
                    Text("To contact You")
                    Text("To provide You with news, special offers...")
                    Text("To manage Your requests")
                    Text("For business transfers")
                    Text("For other purposes...")
                }
                .font(.system(size: 16))
                .foregroundColor(.black)
                .padding(.leading, 16)
            }
            
            Group {
            Text("Creative Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                    .padding(.top, 12)
            
            Text("We may process users' lyric drafts and generation history to improve user experience and help users refine their songwriting process more effectively.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("All creative data is processed on the device and is not stored on our servers. You may delete your lyric data at any time.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            }
        }
    }
    
    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retention of Your Personal Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("The Company will retain Your Personal Data only for as long as is necessary for the purposes set out in this Privacy Policy. We will retain and use Your Personal Data to the extent necessary to:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("comply with our legal obligations (for example, if we are required to retain your data to comply with applicable laws),")
                Text("resolve disputes, and")
                Text("enforce our legal agreements and policies.")
            }
            .font(.system(size: 16))
            .foregroundColor(.black)
            .padding(.leading, 16)
            
            Text("We also retain Usage Data for internal analysis purposes. Usage Data is generally retained for a shorter period, except when this data is used to strengthen the security or to improve the functionality of Our Service, or We are legally obligated to retain this data for longer periods.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transfer of Your Personal Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Your information, including Personal Data, may be transferred to — and maintained on — computers located outside of Your state, province, country or other governmental jurisdiction where the data protection laws may differ from those in Your jurisdiction.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Your consent to this Privacy Policy followed by Your submission of such information represents Your agreement to that transfer.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("The Company will take all steps reasonably necessary to ensure that Your data is treated securely and in accordance with this Privacy Policy, and no transfer of Your Personal Data will take place to an organization or a country unless there are adequate controls in place, including the security of Your data and other personal information.")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var deleteDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete Your Personal Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("You have the right to delete or request that We assist in deleting the Personal Data...")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var disclosureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disclosure of Your Personal Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Business Transactions")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
            
            Text("Law enforcement")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
            
            Text("Other legal requirements")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
        }
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security of Your Personal Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("The security of Your Personal Data is important to Us...")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var childrenPrivacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Children's Privacy")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Our Service does not address anyone under the age of 13...")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Links to Other Websites")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("Our Service may contain links to other websites that are not operated by Us...")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes to this Privacy Policy")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("We may update Our Privacy Policy from time to time...")
                .font(.system(size: 16))
                .foregroundColor(.black)
        }
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contact Us")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("If you have any questions about this Privacy Policy, You can contact us:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("📧 By email: helpthrifty@gmail.com")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
        }
    }
}

// Instrumental Card Component
struct InstrumentalCard: View {
    let title: String
    let imageName: String
    let genres: String
    let playCount: String
    let likeCount: String
    let commentCount: String
    
    // Get audio manager from shared manager
    @ObservedObject private var audioManager: AudioManager
    
    init(title: String, imageName: String, genres: String, playCount: String, likeCount: String, commentCount: String) {
        self.title = title
        self.imageName = imageName
        self.genres = genres
        self.playCount = playCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        
        // Get the audio manager from shared manager
        // title already includes .mp3 extension, so use it directly
        self.audioManager = SharedInstrumentalManager.shared.getAudioManager(for: title)
    }
    
    // Create audio data for this instrumental
    private var audioFileName: String {
        return title // title already includes .mp3 extension
    }
    
    // Display title without .mp3 extension
    private var displayTitle: String {
        return title.replacingOccurrences(of: ".mp3", with: "")
    }
    
    private var audioDuration: TimeInterval {
        return audioManager.duration
    }
    
    private var audioCurrentTime: TimeInterval {
        return audioManager.currentTime
    }
    
    private var progressPercentage: Double {
        return audioDuration > 0 ? audioCurrentTime / audioDuration : 0.0
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Container for artwork and gradient
            ZStack {
                // Square artwork as background
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 180) // Made image even larger
                    .clipped()
                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
            }
            
            // Compact Audio Player below the image
            instrumentalAudioPlayer
                .padding(.horizontal, 12)
        }
    }
    
    private var instrumentalAudioPlayer: some View {
        VStack(spacing: 8) {
            // Top row: File info and play button
            HStack(spacing: 8) {
                // Waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.1))
                    )
                
                // File name and time - smaller text
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(formatTime(audioCurrentTime)) / \(formatTime(audioDuration))")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Play button
                Button(action: {
                    if audioManager.isPlaying {
                        audioManager.pause()
                    } else {
                        // Try to load from bundle first (for default files)
                        let fileNameWithoutExtension = title.replacingOccurrences(of: ".mp3", with: "")
                        if let url = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3") {
                            audioManager.loadAudio(from: url)
                            audioManager.play()
                        } else {
                            // If not in bundle, the audio manager should already have the file loaded
                            // Just play it if it has a player
                            if audioManager.player != nil {
                        audioManager.play()
                            }
                        }
                    }
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                                    .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.1))
                        )
                }
            }
            
            // Simple progress line without markers
            GeometryReader { geometry in
                ZStack {
                    // Background line
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress line
                    HStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "#8B5CF6"),
                                        Color(hex: "#EC4899")
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressPercentage, height: 4)
                        
                        Spacer()
                    }
                }
            }
            .frame(height: 20)
        }
        .padding(8)
                    .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Instrumental List Item Component
struct InstrumentalListItem: View {
    let title: String
    @ObservedObject var audioManager: AudioManager
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var isDragging = false
    
    private var progressPercentage: Double {
        return audioManager.duration > 0 ? audioManager.currentTime / audioManager.duration : 0.0
    }
    
    var body: some View {
        ZStack {
            // Delete button background
            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black)
                        .cornerRadius(8)
                }
            }
            .padding(.trailing, 16)
            
            // Main content
            VStack(spacing: 12) {
                // Top row with track info and play button
                HStack(spacing: 12) {
                    // Waveform icon
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                    
                    // Track info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text("\(formatTime(audioManager.currentTime)) / \(formatTime(audioManager.duration))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Play button
                    Button(action: {
                        if audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            // Try to load from bundle first (for default files)
                            if let url = Bundle.main.url(forResource: title.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3") {
                                audioManager.loadAudio(from: url)
                                audioManager.play()
                            } else {
                                // If not in bundle, the audio manager should already have the file loaded
                                // Just play it if it has a player
                                if audioManager.player != nil {
                                    audioManager.play()
                                }
                            }
                        }
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
                
                // Scrubber line with drag gesture
                GeometryReader { geometry in
                    ZStack {
                        // Background line
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.2))
                            .frame(height: 4)
                        
                        // Progress line
                        HStack {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "#8B5CF6"),
                                            Color(hex: "#EC4899")
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progressPercentage, height: 4)
                            
                            Spacer()
                        }
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let percentage = min(max(value.location.x / geometry.size.width, 0), 1)
                                let time = audioManager.duration * percentage
                                audioManager.seek(to: time)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.black)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 && !isDragging {
                            offset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        if !isDragging {
                            withAnimation(.spring()) {
                                if value.translation.width < -50 {
                                    offset = -60
                                    isSwiped = true
                                } else {
                                    offset = 0
                                    isSwiped = false
                                }
                            }
                        }
                    }
            )
            .onTapGesture {
                if !isDragging {
                    withAnimation(.spring()) {
                        offset = 0
                        isSwiped = false
                    }
                }
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .offset(y: 60),
            alignment: .bottom
        )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Loop Controls View
struct LoopControlsView: View {
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
    @StateObject private var sharedManager = SharedInstrumentalManager.shared
    @StateObject private var globalLoopSettings = GlobalLoopSettings.shared
    @State private var startTimeText: String = "0:00"
    @State private var endTimeText: String = "0:00"
    @State private var isEditingStart: Bool = false
    @State private var isEditingEnd: Bool = false
    @State private var isLoopSaved: Bool = false
    @State private var currentManager: AudioManager?
    
    // Get the currently playing manager or apply settings to the song that's about to be played
    private func getCurrentManager() -> AudioManager {
        if let playingManager = globalAudioManager.currentPlayingManager {
            return playingManager
        } else {
            // If no song is playing, we'll apply the loop settings to whatever song gets played next
            // For now, return a temporary manager for UI purposes
            let tempManager = AudioManager()
            return tempManager
        }
    }
    
    // Apply loop settings to a specific manager
    private func applyLoopSettings(to manager: AudioManager) {
        if let startTime = parseTimeString(startTimeText),
           let endTime = parseTimeString(endTimeText),
           startTime < endTime {
            manager.hasCustomLoop = true
            manager.loopStart = startTime
            manager.loopEnd = min(endTime, manager.duration)
            print("✅ Applied loop settings to \(manager.audioFileName): \(formatTime(startTime)) to \(formatTime(endTime))")
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Start time
            VStack(alignment: .leading, spacing: 4) {
                Text("START")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                
                HStack {
                    TimePickerButton(text: $startTimeText) { newValue in
                        startTimeText = newValue
                        updateStartTime()
                    }
                    
                    Button(action: { 
                        let manager = getCurrentManager()
                        manager.loopStart = manager.currentTime
                        startTimeText = formatTime(manager.loopStart)
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
            }
            
            // End time
            VStack(alignment: .leading, spacing: 4) {
                Text("END")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                
                HStack {
                    TimePickerButton(text: $endTimeText) { newValue in
                        endTimeText = newValue
                        updateEndTime()
                    }
                    
                    Button(action: { 
                        let manager = getCurrentManager()
                        manager.loopEnd = manager.currentTime
                        manager.hasCustomLoop = true
                        endTimeText = formatTime(manager.loopEnd)
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
            }
            
            // Save/Stop Loop Button
            VStack(alignment: .leading, spacing: 4) {
                Text("LOOP")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                
                Button(action: {
                    if isLoopSaved {
                        // Just disable the loop without resetting timestamps
                        globalLoopSettings.clearPendingLoop()
                        if let playingManager = globalAudioManager.currentPlayingManager {
                            playingManager.hasCustomLoop = false
                        }
                        isLoopSaved = false
                    } else {
                        // Save loop
                        saveLoop()
                        isLoopSaved = globalLoopSettings.hasPendingLoop
                    }
                }) {
                    Text(isLoopSaved ? "STOP LOOP" : "SET LOOP")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Image("tool-bg1")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .padding(.bottom, 12) // Add extra bottom padding
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .onAppear {
            // Initialize with global loop settings if available
            if globalLoopSettings.hasPendingLoop {
                startTimeText = formatTime(globalLoopSettings.pendingLoopStart)
                endTimeText = formatTime(globalLoopSettings.pendingLoopEnd)
                isLoopSaved = true
            } else {
                startTimeText = "0:00"
                endTimeText = "0:00"
                isLoopSaved = false
            }
        }
        .onChange(of: globalLoopSettings.hasPendingLoop) { hasLoop in
            isLoopSaved = hasLoop
        }
    }
    
    private func updateStartTime() {
        let manager = getCurrentManager()
        if let time = parseTimeString(startTimeText) {
            // Ensure start time is less than end time
            if manager.loopEnd > 0 && time >= manager.loopEnd {
                // If start time is greater than or equal to end time, adjust end time
                manager.loopEnd = min(time + 10, manager.duration) // Set to 10 seconds after start
                endTimeText = formatTime(manager.loopEnd)
            }
            
            manager.loopStart = time
        } else {
            startTimeText = formatTime(manager.loopStart)
        }
    }
    
    private func updateEndTime() {
        let manager = getCurrentManager()
        if let time = parseTimeString(endTimeText) {
            // Check if end time is too close to start time (2 seconds or less)
            if time <= manager.loopStart + 2 {
                // If end time is too close to start time, set it to 10 seconds after start
                let newEndTime = min(manager.loopStart + 10, manager.duration)
                manager.loopEnd = newEndTime
                endTimeText = formatTime(newEndTime)
                print("🔄 Auto-adjusted END time to 10 seconds after START: \(formatTime(newEndTime))")
            } else {
                manager.loopEnd = time
            }
        } else {
            endTimeText = formatTime(manager.loopEnd)
        }
    }
    
    private func saveLoop() {
        print("🔍 Save loop called")
        print("🔍 Start text: \(startTimeText), End text: \(endTimeText)")
        
        // Enable custom loop if both times are valid
        if let startTime = parseTimeString(startTimeText),
           let endTime = parseTimeString(endTimeText) {
            
            // Check if end time is too close to start time (2 seconds or less)
            let finalEndTime: TimeInterval
            if endTime <= startTime + 2 {
                finalEndTime = startTime + 10
                print("🔄 Auto-adjusted END time to 10 seconds after START: \(formatTime(finalEndTime))")
            } else {
                finalEndTime = endTime
            }
            
            if startTime < finalEndTime {
                // Set global pending loop settings
                globalLoopSettings.setPendingLoop(start: startTime, end: finalEndTime)
                
                // Also apply to currently playing manager if any
                if let playingManager = globalAudioManager.currentPlayingManager {
                    playingManager.hasCustomLoop = true
                    playingManager.loopStart = startTime
                    playingManager.loopEnd = finalEndTime
                    print("✅ Loop saved to current manager: \(playingManager.audioFileName)")
                }
                
                print("✅ Global loop settings saved: \(formatTime(startTime)) to \(formatTime(finalEndTime))")
            } else {
                globalLoopSettings.clearPendingLoop()
                print("❌ Invalid loop times, loop disabled")
            }
        } else {
            globalLoopSettings.clearPendingLoop()
            print("❌ Invalid loop times, loop disabled")
        }
    }
    
    private func validateAndCorrectTime(_ timeString: String) -> String? {
        let components = timeString.split(separator: ":")
        
        // Must have exactly one colon
        guard components.count == 2 else { return nil }
        
        // Parse minutes and seconds
        guard let minutesStr = components.first,
              let secondsStr = components.last,
              let minutes = Int(minutesStr),
              let seconds = Int(secondsStr) else {
            return nil
        }
        
        // Validate ranges
        guard minutes >= 0 && seconds >= 0 else { return nil }
        
        var correctedMinutes = minutes
        var correctedSeconds = seconds
        
        // Handle seconds overflow (e.g., 0:60 becomes 1:00)
        if seconds >= 60 {
            correctedMinutes += seconds / 60
            correctedSeconds = seconds % 60
        }
        
        // Format the corrected time
        return String(format: "%d:%02d", correctedMinutes, correctedSeconds)
    }
    
    private func parseTimeString(_ timeString: String) -> TimeInterval? {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]),
              seconds >= 0 && seconds < 60 else {
            return nil
        }
        return TimeInterval(minutes * 60 + seconds)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimeInput(_ input: String) -> String {
        // Remove any non-numeric characters and limit to 3 digits
        let numbers = input.filter { $0.isNumber }.prefix(3)
        
        // If empty, return default
        if numbers.isEmpty {
            return "0:00"
        }
        
        // Convert to string and pad with leading zeros
        let paddedNumbers = String(repeating: "0", count: max(0, 3 - numbers.count)) + numbers
        
        // Format as M:SS
        return "\(paddedNumbers.prefix(1)):\(paddedNumbers.suffix(2))"
    }
}

// Lyric Tool Card Component
struct LyricToolCard: View {
    let title: String
    let icon: String
    let description: String
    let index: Int
    let isPro: Bool
    let backgroundImage: String
    @State private var showingToolDetail = false
    

    
    // Map tool titles to their corresponding image names (same as ToolCard)
    private var imageName: String {
        switch title {
        case "AI Bar Generator":
            return "ai-bar-generator"
        case "Alliterate It":
            return "alliterator"
        case "Chorus Creator":
            return "chorus-creator"
        case "Creative One-Liner":
            return "creative-one-liner"
        case "Diss Track Generator":
            return "disstrack-generator"
        case "Double Entendre":
            return "double-entendre"
        case "Finisher":
            return "song-finisher"
        case "Flex-on-'em":
            return "flex-on-em"
        case "Imperfect Rhyme":
            return "imperfect-rhyme"
        case "Industry Analyzer":
            return "industry-analyzer"
        case "Quadruple Entendre":
            return "quadruple-entendre"
        case "Rap Instagram Captions":
            return "song-ig-captions"
        case "Rap Name Generator":
            return "name-generator"
        case "Shapeshift":
            return "shapeshift"
        case "Triple Entendre":
            return "Triple-Entendre"
        case "Ultimate Come Up Song":
            return "ultimate-comeup-song"
        default:
            return "ai-bar-generator" // fallback
        }
    }
    
    var body: some View {
        Button(action: { showingToolDetail = true }) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail with background image and custom tool image overlay
                ZStack {
                    // Background image
                    Image(backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                    
                    // Dark overlay for better icon visibility
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 60, height: 60)
                    
                    // Custom tool image overlay
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Description only
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 0)
        }
        .fullScreenCover(isPresented: $showingToolDetail) {
            ToolDetailView(title: title, description: description, backgroundImage: backgroundImage)
        }
    }
}

// Helper to apply corner radius to specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    // Custom horizontal slide transition for onboarding
    func horizontalSlideTransition() -> some View {
        self
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct ConfettiPiece: View {
    let color: Color
    @State private var position = CGPoint(x: 0, y: 0)
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 8...16))
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(position)
            .onAppear {
                let startX = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                let endX = startX + CGFloat.random(in: -100...100)
                let endY = UIScreen.main.bounds.height + 100
                
                position = CGPoint(x: startX, y: -20)
                
                withAnimation(.easeOut(duration: Double.random(in: 2...4))) {
                    position = CGPoint(x: endX, y: endY)
                    rotation = Double.random(in: 0...360)
                    opacity = 0
                }
            }
    }
}

struct ConfettiView: View {
    @State private var confettiPieces: [Int] = []
    
    let colors: [Color] = [
        .red, .blue, .green, .yellow, .orange, .purple, .pink, .cyan, .mint, .indigo
    ]
    
    var body: some View {
        ZStack {
            ForEach(confettiPieces, id: \.self) { _ in
                ConfettiPiece(color: colors.randomElement() ?? .blue)
            }
        }
        .onAppear {
            startConfetti()
        }
    }
    
    private func startConfetti() {
        for i in 0..<50 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                confettiPieces.append(i)
            }
        }
        
        // Continue dropping confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for i in 50..<100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i - 50) * 0.15) {
                    confettiPieces.append(i)
                }
            }
        }
    }
}

struct RatingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var selectedRating: Int = 5 // Default to 5 stars selected
    @State private var navigateToNext = false
    @State private var showingRatingPopup = false
    @State private var ratingCompleted = false
    @State private var popupShown = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        // Ensure proper spacing for all device sizes, especially iPad
                        // Header with back button and progress
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "arrow.left")
                                    .foregroundColor(.black)
                                    .font(.system(size: 16))
                            )
                    }
                    
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                // Title
                Text("Give us rating")
                    .font(.system(size: 32, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                // Star rating container - enhanced design
                VStack {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { index in
                            Button(action: {
                                selectedRating = index
                                // Track question-specific answer
                                coordinator.trackQuestionAnswered(answer: "\(index) stars")
                            }) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 24)) // Reduced from 28
                                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                    .scaleEffect(selectedRating >= index ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedRating)
                            }
                        }
                    }
                    .padding(.vertical, 16) // Reduced from 20
                    .padding(.horizontal, 32)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color(.systemGray6), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.top, 24) // Reduced from 32
                
                // Social proof section
                VStack(spacing: 12) { // Reduced from 16
                    Text("Thrifty was made for\npeople like you")
                        .font(.system(size: 20, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.top, 24) // Reduced from 32
                    
                    // User avatars with real photos
                    HStack(spacing: -8) {
                        Image("onb1")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44) // Reduced from 48
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                        
                        Image("onb2")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44) // Reduced from 48
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                        
                        Image("onb3")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44) // Reduced from 48
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                    }
                    .padding(.top, 8)
                    
                    Text("+ 1000 Thrifty users")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                
                // Testimonials with enhanced styling
                VStack(spacing: 12) { // Reduced from 16
                    // Marley Bryle testimonial
                    HStack(alignment: .top, spacing: 12) {
                        Image("onb4")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40) // Reduced from 44
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("Marley Bryle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10)) // Reduced from 12
                                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                    }
                                }
                            }
                            
                            Text("\"I flip vintage clothes online, and this tool helps me spot undervalued gems faster. It's like having a pro thrifter in my pocket!\"")
                                .font(.system(size: 13)) // Reduced from 14
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                    
                    // Benny Marcs testimonial
                    HStack(alignment: .top, spacing: 12) {
                        Image("onb5")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40) // Reduced from 44
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("Benny Marcs")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10)) // Reduced from 12
                                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                    }
                                }
                            }
                            
                            Text("\"I used to get overwhelmed in big thrift stores. Now I know exactly what to look for—and what to skip. It makes thrifting fun again!\"")
                                .font(.system(size: 13)) // Reduced from 14
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray))
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 24) // Reduced from 32
                .padding(.bottom, 80) // Reduced bottom padding for floating button
                    }
                }
                
                // Floating Next button overlay
                VStack(spacing: 20) {
                    // Next button - Floating over scrollable content
                    Button(action: {
                        navigateToNext = true
                    }) {
                        Text("Next")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(selectedRating > 0 ? Color.black : Color.gray)
                                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                            )
                            .foregroundColor(.white)
                    }
                    .disabled(selectedRating == 0)
                    .padding(.horizontal, 24)
                    .padding(.top, 20) // Add equal top padding to match the spacing
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom + 16, 40)) // Ensure minimum 40pt bottom padding for iPad
                    .onChange(of: showingRatingPopup) { newValue in
                        if newValue && !popupShown {
                            popupShown = true
                            // Request review when showingRatingPopup becomes true
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                SKStoreReviewController.requestReview(in: scene)
                            }
                            // Set a timer to detect when the popup is dismissed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                showingRatingPopup = false
                                ratingCompleted = true
                            }
                        }
                    }
                    
                    // Force button visibility - safety measure for iPad
                    if selectedRating == 0 {
                        Text("Please select a rating to continue")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, 8)
                    }
                }
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                )
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(isActive: $navigateToNext) {
                    CustomPlanView()
                } label: {
                    EmptyView()
                }
            }
            // Add bottom background to ensure button area is visible on iPad
            .background(Color.white, alignment: .bottom)
            .background(Color.white)
            .navigationBarHidden(true)
            .preferredColorScheme(.light)
            .ignoresSafeArea(.keyboard, edges: .bottom) // Ensure content isn't cut off by keyboard
            .onAppear {
                coordinator.currentStep = 15
                MixpanelService.shared.trackQuestionViewed(questionTitle: "Give us rating", stepNumber: 15)
                // FacebookPixelService.shared.trackOnboardingStepViewed(questionTitle: "Give us rating", stepNumber: 15)
                
                // Ensure button is always visible by default
                ratingCompleted = true
                
                // Show rating popup automatically when view appears - only when hardPaywall is true
                if remoteConfig.hardPaywall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showingRatingPopup = true
                    }
                }
            }
        }
    }
}

// Update CompletionView to navigate to RatingView
struct CompletionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var navigateToRating = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            // Confetti overlay
            if showConfetti {
                ConfettiView()
            }
            
            VStack(spacing: 0) {
                // Header with back button and progress
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "arrow.left")
                                    .foregroundColor(.black)
                                    .font(.system(size: 18))
                            )
                    }
                    
                    // Progress bar
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: UIScreen.main.bounds.width * 0.714, height: 2) // 15/21 ≈ 0.714
                        
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                Spacer()
                
                // Success checkmark
                ZStack {
                    Circle()
                        .fill(Color(red: 0.83, green: 0.69, blue: 0.52))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.3), value: showContent)
                
                // "All done!" text
                Text("All done!")
                    .font(.system(size: 17, weight: .medium))
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
                
                // Main title
                Text("Thank you for\ntrusting us")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.8), value: showContent)
                
                // Description
                Text("We promise to always keep your personal information private and secure.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                
                Spacer()
                
                // Update Let's do this button to navigate to RatingView (disabled when hardPaywall is false)
                Group {
                    if remoteConfig.hardPaywall {
                NavigationLink(isActive: $navigateToRating) {
                    RatingView()
                } label: {
                    Text("Let's do this")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(28)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    coordinator.nextStep()
                    navigateToRating = true
                })
                    } else {
                        // Skip rating when hardPaywall is false - go directly to next step
                        NavigationLink(isActive: $navigateToRating) {
                            CustomPlanView()
                        } label: {
                            Text("Let's do this")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .cornerRadius(28)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            coordinator.nextStep()
                            navigateToRating = true
                        })
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 14
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Thank you for trusting us", stepNumber: 14)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showContent = true
                showConfetti = true
            }
        }
    }
}

// Update ProgressGraphView to navigate to CompletionView
struct ProgressGraphView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showGraph = false
    @State private var showTrophy = false
    @State private var navigateToNext = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.667, height: 2) // 14/21 ≈ 0.667
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("You have great\npotential to crush\nyour goal")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Graph container
            VStack(spacing: 16) {
                // Graph title
                Text("Your Money Savings")
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .opacity(showGraph ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.3), value: showGraph)
                
                // Graph
                ZStack {
                    // Background grid lines (horizontal)
                    VStack(spacing: 40) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    
                    GeometryReader { geometry in
                        let graphWidth = geometry.size.width - 48 // Account for padding
                        let graphHeight: CGFloat = 160
                        
                        // Define exact data points first
                        let point1 = CGPoint(x: 0, y: graphHeight * 0.8)           // 3 days
                        let point2 = CGPoint(x: graphWidth * 0.5, y: graphHeight * 0.5)  // 7 days  
                        let point3 = CGPoint(x: graphWidth, y: graphHeight * 0.2)   // 30 days
                        
                        // Area under curve
                        Path { path in
                            // Start from bottom
                            path.move(to: CGPoint(x: point1.x, y: graphHeight))
                            // Line to first point
                            path.addLine(to: point1)
                            // Curve through all points
                            path.addCurve(
                                to: point3,
                                control1: CGPoint(x: point1.x + graphWidth * 0.3, y: point1.y - 20),
                                control2: CGPoint(x: point3.x - graphWidth * 0.3, y: point3.y + 20)
                            )
                            // Close the area
                            path.addLine(to: CGPoint(x: point3.x, y: graphHeight))
                            path.addLine(to: CGPoint(x: point1.x, y: graphHeight))
                            path.closeSubpath()
                        }
                        .fill(Color(red: 0.83, green: 0.69, blue: 0.52).opacity(0.1))
                        .offset(x: 24) // Apply padding offset
                        .opacity(showGraph ? 1 : 0)
                        .animation(.easeOut(duration: 1.2).delay(0.6), value: showGraph)
                        
                        // Line graph
                        Path { path in
                            path.move(to: point1)
                            path.addCurve(
                                to: point3,
                                control1: CGPoint(x: point1.x + graphWidth * 0.3, y: point1.y - 20),
                                control2: CGPoint(x: point3.x - graphWidth * 0.3, y: point3.y + 20)
                            )
                        }
                        .trim(from: 0, to: showGraph ? 1 : 0)
                        .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 2)
                        .offset(x: 24) // Apply padding offset
                        .animation(.easeOut(duration: 1.2).delay(0.5), value: showGraph)
                        
                        // Data points - using the SAME coordinate system
                        Group {
                            // First point (3 days)
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 2)
                                )
                                .position(x: point1.x + 24, y: point1.y) // Apply padding offset
                                .opacity(showGraph ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.5), value: showGraph)
                            
                            // Second point (7 days)
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 2)
                                )
                                .position(x: point2.x + 24, y: point2.y) // Apply padding offset
                                .opacity(showGraph ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.8), value: showGraph)
                            
                            // Third point with trophy (30 days)
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 2)
                                    )
                                
                                Circle()
                                    .fill(Color(red: 0.83, green: 0.69, blue: 0.52))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "trophy.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16))
                                    )
                                    .offset(y: -24)
                            }
                            .position(x: point3.x + 24, y: point3.y) // Apply padding offset
                            .opacity(showGraph ? 1 : 0)
                            .animation(.easeOut(duration: 0.3).delay(1.1), value: showGraph)
                        }
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, 24)
                
                // Time labels
                HStack {
                    Text("1 Day")
                        .font(.system(size: 15))
                    Spacer()
                    Text("3 Days")
                        .font(.system(size: 15))
                    Spacer()
                    Text("7 Days")
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(showGraph ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showGraph)
                
                // Description text - full text without truncation
                Text("Based on Thrifty's historical data, finding valuable items is usually gradual at first, but after 7 days, you can spot great deals quickly!")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil) // Allow unlimited lines
                    .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .opacity(showGraph ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(1.3), value: showGraph)
            }
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToNext) {
                CompletionView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(showGraph ? Color.black : Color(.systemGray5))
                    .foregroundColor(showGraph ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(!showGraph)
            .simultaneousGesture(TapGesture().onEnded {
                if showGraph {
                    coordinator.nextStep()
                    navigateToNext = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 13
            MixpanelService.shared.trackQuestionViewed(questionTitle: "You have great potential to crush your goal", stepNumber: 13)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showGraph = true
            }
        }
    }
}

// Update UltimateGoalView to navigate to ProgressGraphView
struct UltimateGoalView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedGoal: String?
    @State private var navigateToNext = false
    
    let goals = [
        "I want to save more money",
        "I want to save more time",
        "Just enjoying the thrill of the hunt"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.619, height: 2) // 13/21 ≈ 0.619
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("What is your ultimate\ngoal?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom thrift profile.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Goals list
            VStack(spacing: 16) {
                ForEach(goals, id: \.self) { goal in
                    Button(action: { 
                        selectedGoal = goal
                        // Track question-specific answer
                        coordinator.trackQuestionAnswered(answer: goal)
                    }) {
                        Text(goal)
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedGoal == goal ? Color.black : Color(.systemGray6))
                            .foregroundColor(selectedGoal == goal ? .white : .black)
                            .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToNext) {
                ProgressGraphView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedGoal != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedGoal != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedGoal == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedGoal != nil {
                    coordinator.nextStep()
                    navigateToNext = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 12
        }
    }
}

// Update ObstaclesView to navigate to UltimateGoalView
struct ObstaclesView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedObstacle: String?
    @State private var navigateToNext = false
    
    let obstacles = [
        ("I go, but don't always score", "chart.bar"),
        ("Don't know what to look for", "brain"),
        ("Unsure what's actually valuable", "hand.raised"),
        ("Other thrifters are too fast", "calendar"),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.571, height: 2) // 12/21 ≈ 0.571
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("What's stopping you\nfrom reaching your\ngoals?")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Obstacles list
            VStack(spacing: 16) {
                ForEach(obstacles, id: \.0) { obstacle, icon in
                    Button(action: { 
                        selectedObstacle = obstacle
                        // Track question-specific answer
                        coordinator.trackQuestionAnswered(answer: obstacle)
                    }) {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .frame(width: 24)
                            Text(obstacle)
                                .font(.system(size: 17))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedObstacle == obstacle ? Color.black : Color(.systemGray6))
                        .foregroundColor(selectedObstacle == obstacle ? .white : .black)
                        .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToNext) {
                UltimateGoalView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedObstacle != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedObstacle != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedObstacle == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedObstacle != nil {
                    coordinator.nextStep()
                    navigateToNext = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 11
        }
    }
}

// Update ThriftingTransitionView to navigate to ObstaclesView
struct ThriftingTransitionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToNext = false
    @State private var showChart = false
    @State private var animationComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.524, height: 2) // 11/21 ≈ 0.524
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Find valuable items twice as fast with\nThrifty vs on your own")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Comparison chart
            VStack {
                HStack(alignment: .top, spacing: 16) {
                    // Without Thrifty column
                    VStack(spacing: 0) {
                        Text("Without\nThrifty")
                            .font(.system(size: 17))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .padding(.bottom, 12)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 160)
                            
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(width: 80, height: showChart ? 40 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: showChart)
                            
                            Text("20%")
                                .font(.system(size: 17))
                                .foregroundColor(.black)
                                .opacity(showChart ? 1 : 0)
                                .animation(.easeIn.delay(0.8), value: showChart)
                                .padding(.bottom, showChart ? 8 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // With Thrifty column
                    VStack(spacing: 0) {
                        Text("With\nThrifty")
                            .font(.system(size: 17))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .padding(.bottom, 12)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 160)
                            
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black,
                                        Color.black.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 80, height: showChart ? 120 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showChart)
                            
                            Text("2X")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .opacity(showChart ? 1 : 0)
                                .animation(.easeIn.delay(0.9), value: showChart)
                                .padding(.bottom, showChart ? 8 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.4, blue: 0.7), // Pink
                                    Color(red: 0.4, green: 0.9, blue: 0.5)  // Green
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .opacity(0.1) // Subtle gradient
                        )
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToNext) {
                ObstaclesView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(animationComplete ? Color.black : Color(.systemGray5))
                    .foregroundColor(animationComplete ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(!animationComplete)
            .simultaneousGesture(TapGesture().onEnded {
                if animationComplete {
                    coordinator.nextStep()
                    navigateToNext = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 10
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Thrifting Transition", stepNumber: 10)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showChart = true
                // Enable the button after all animations complete (0.3s initial delay + 0.9s for animations + 0.1s buffer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    animationComplete = true
                }
            }
        }
    }
}

// Update GoalSpeedView to navigate to ThriftingTransitionView
struct GoalSpeedView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToNext = false
    let selectedGoal: String
    
    init(selectedGoal: String) {
        self.selectedGoal = selectedGoal
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.476, height: 2) // 10/21 ≈ 0.476
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Powered Fake Detection")
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Thrifty analyzes stitching, logos, and materials. We flag possible fakes automatically.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // AI Fake Detection Image
            Image("ai-fake-detection")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 400)
                .padding(.horizontal, 16)
                .padding(.top, 0)
            
            Spacer()
            
            // Update Continue button to navigate to ThriftingTransitionView
            NavigationLink(isActive: $navigateToNext) {
                ThriftingTransitionView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(28)
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Track question-specific answer
                coordinator.trackQuestionAnswered(answer: "Viewed AI Powered Fake Detection")
                coordinator.nextStep()
                navigateToNext = true
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 9
        }
    }
}

// Update GoalConfirmationView to navigate to GoalSpeedView
struct GoalConfirmationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToSpeed = false
    let selectedGoal: String
    
    init(selectedGoal: String) {
        self.selectedGoal = selectedGoal
    }
    
    var formattedGoal: String {
        switch selectedGoal {
        case "I sometimes skip rare/valuable finds":
            return "Finding rare/valuable items"
        case "It's a hassle figuring out what things are really worth.":
            return "Valuing items correctly"
        case "I regret some of my purchases":
            return "Making smarter purchases"
        default:
            return selectedGoal
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.429, height: 2) // 9/21 ≈ 0.429
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            Spacer()
            
            // Goal confirmation text
            VStack(spacing: 16) {
                Text(formattedGoal)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(red: 0.83, green: 0.69, blue: 0.52)) // Gold color for the goal
                + Text(" is a realistic target. It's not hard at all!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            
            // Subtitle
            Text("90% of users say that the change is obvious after using Thrifty.")
                .font(.system(size: 17))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToSpeed) {
                GoalSpeedView(selectedGoal: selectedGoal)
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(28)
            }
            .simultaneousGesture(TapGesture().onEnded {
                coordinator.nextStep()
                navigateToSpeed = true
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 8
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Goal Confirmation", stepNumber: 8)
            // FacebookPixelService.shared.trackOnboardingStepViewed(questionTitle: "Goal Confirmation", stepNumber: 8)
        }
    }
}

// Update GoalSelectionView to navigate to GoalConfirmationView
struct GoalSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedGoal: String?
    @State private var navigateToConfirmation = false
    
    let goals = [
        "I sometimes skip rare/valuable finds",
        "It's a hassle figuring out what things are really worth.",
        "I regret some of my purchases"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.381, height: 2) // 8/21 ≈ 0.381
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("What are you struggling with?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom thrift settings.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Goal options
            VStack(spacing: 16) {
                ForEach(goals, id: \.self) { goal in
                    Button(action: { 
                        selectedGoal = goal
                        // Track question-specific answer
                        coordinator.trackQuestionAnswered(answer: goal)
                    }) {
                        Text(goal)
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedGoal == goal ? Color.black : Color(.systemGray6))
                            .foregroundColor(selectedGoal == goal ? .white : .black)
                            .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToConfirmation) {
                if let goal = selectedGoal {
                    GoalConfirmationView(selectedGoal: goal)
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedGoal != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedGoal != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedGoal == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedGoal != nil {
                    coordinator.nextStep()
                    navigateToConfirmation = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 7
        }
    }
}

// Update WritingStyleView to navigate to GoalSelectionView
struct WritingStyleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedStyle: String?
    @State private var navigateToGoal = false
    
    let styles = [
        ("Unique, story-rich items", "sparkles"),
        ("Deals & Discounts", "tag.fill"),
        ("Quick Flips", "arrow.clockwise"),
        ("No specific style", "xmark.circle")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.333, height: 2) // 7/21 ≈ 0.333
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("Do you have a specific\nthrifting style?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom thrift settings.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Style options
            VStack(spacing: 16) {
                ForEach(styles, id: \.0) { style, icon in
                    Button(action: { 
                        selectedStyle = style
                        // Track question-specific answer
                        coordinator.trackQuestionAnswered(answer: style)
                    }) {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 32)
                            Text(style)
                                .font(.system(size: 17))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedStyle == style ? Color.black : Color(.systemGray6))
                        .foregroundColor(selectedStyle == style ? .white : .black)
                        .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToGoal) {
                GoalSelectionView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedStyle != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedStyle != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedStyle == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedStyle != nil {
                    coordinator.nextStep()
                    navigateToGoal = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 6
        }
    }
}

// Update MusicGenreView to navigate to WritingStyleView
struct MusicGenreView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToStyle = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.286, height: 2) // 6/21 ≈ 0.286
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("Real-Time Marketplace Data")
                    .font(.system(size: 32, weight: .bold))
                Text("We use AI and real-time listings data from eBay, Etsy, Depop, & More!")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // AI Summary Image
            Image("ai-summary")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 400)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            
            Spacer()
            
            // Next button with navigation to WritingStyleView
            NavigationLink(isActive: $navigateToStyle) {
                WritingStyleView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .cornerRadius(28)
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Track question-specific answer
                coordinator.trackQuestionAnswered(answer: "Viewed Real-Time Marketplace Data")
                coordinator.nextStep()
                navigateToStyle = true
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 5
        }
    }
}

// Update AnimatedGraph to expose animation state
struct AnimatedGraph: View {
    @State private var showGraph = false
    @Binding var isAnimationComplete: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Graph container
            ZStack {
                // Graph background
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
                    .frame(height: 240)
                
                VStack(alignment: .leading, spacing: 0) {
                    // Your Creativity label
                    Text("Your Savings")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                        .padding(.leading, 24)
                        .padding(.top, 24)
                        .opacity(showGraph ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: showGraph)
                    
                    ZStack {
                        // Creativity line and fill
                        Path { path in
                            path.move(to: CGPoint(x: 24, y: 120))
                            path.addCurve(
                                to: CGPoint(x: 290, y: 60),
                                control1: CGPoint(x: 100, y: 160),
                                control2: CGPoint(x: 220, y: 60)
                            )
                            path.addLine(to: CGPoint(x: 290, y: 0))
                            path.addLine(to: CGPoint(x: 24, y: 0))
                            path.closeSubpath()
                        }
                        .trim(from: 0, to: showGraph ? 1 : 0)
                        .fill(Color.green.opacity(0.08))
                        .animation(.easeOut(duration: 1).delay(0.5), value: showGraph)
                        
                        // Normal writing line
                        Path { path in
                            path.move(to: CGPoint(x: 24, y: 120))
                            path.addCurve(
                                to: CGPoint(x: 290, y: 180),
                                control1: CGPoint(x: 100, y: 180),
                                control2: CGPoint(x: 220, y: 180)
                            )
                        }
                        .trim(from: 0, to: showGraph ? 1 : 0)
                        .stroke(Color.black, lineWidth: 1)
                        .animation(.easeOut(duration: 1), value: showGraph)
                        
                        // Creativity line
                        Path { path in
                            path.move(to: CGPoint(x: 24, y: 120))
                            path.addCurve(
                                to: CGPoint(x: 290, y: 60),
                                control1: CGPoint(x: 100, y: 160),
                                control2: CGPoint(x: 220, y: 60)
                            )
                        }
                        .trim(from: 0, to: showGraph ? 1 : 0)
                        .stroke(Color.green, lineWidth: 1)
                        .animation(.easeOut(duration: 1).delay(0.5), value: showGraph)
                        
                        // Normal writing text
                        Text("Normal thrifting")
                            .font(.system(size: 10))
                            .foregroundColor(Color.gray.opacity(0.95))
                            .offset(x: 40, y: 60)
                            .opacity(showGraph ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(0.6), value: showGraph)
                        
                        // Month labels
                        HStack {
                            Text("Month 1")
                                .font(.system(size: 15))
                                .padding(.leading, 24)
                            
                            Spacer()
                            
                            Text("Month 6")
                                .font(.system(size: 15))
                                .padding(.trailing, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .offset(y: 100)
                        .opacity(showGraph ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.6), value: showGraph)
                    }
                    .frame(height: 180)
                    .padding(.bottom, 60)
                }
            }
            
            // Bottom text
            Text("87% of users see an uptick\nin money and time saved")
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .opacity(showGraph ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showGraph)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: showGraph) { newValue in
                    // Set animation complete after all animations finish
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            isAnimationComplete = true
                        }
                    }
                }
            
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showGraph = true
            }
        }
    }
}

struct LongTermResultsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToGenre = false
    @State private var isGraphAnimationComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.125, height: 2) // 2/16 ≈ 0.125
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Thrifty creates\nlong-term savings")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Animated graph with binding
            AnimatedGraph(isAnimationComplete: $isGraphAnimationComplete)
                .padding(.top, 40)
                .padding(.horizontal, 24)
            
            Spacer()
            
            // Next button with navigation
            NavigationLink(isActive: $navigateToGenre) {
                MusicGenreView()
            } label: {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isGraphAnimationComplete ? Color.black : Color(.systemGray5))
                    .foregroundColor(isGraphAnimationComplete ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(!isGraphAnimationComplete)
            .simultaneousGesture(TapGesture().onEnded {
                if isGraphAnimationComplete {
                    coordinator.nextStep()
                    navigateToGenre = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 1
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Thrifty creates long-term savings", stepNumber: 1)
        }
    }
}





// Onboarding Coordinator to manage flow and progress
class OnboardingCoordinator: ObservableObject {
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 16 // Total number of onboarding steps (removed gender, source, and previous apps screens)
    
    // Track step timing for analytics
    private var stepStartTime: Date?
    private var onboardingStartTime: Date?
    
    let steps = [
        "How many items do you thrift per week?", 
        "Thrifty creates long-term savings",
        "Real-Time Marketplace Data",
        "Do you have a specific thrifting style?",
        "What are you struggling with?",
        "Goal Confirmation",
        "AI Powered Fake Detection",
        "Thrifting Transition",
        "What's stopping you from reaching your goals?",
        "What is your ultimate goal?",
        "You have great potential to crush your goal",
        "Thank you for trusting us",
        "Give us rating",
        "Your Custom Plan",
        "Setting up your profile...",
        "Final Congratulations",
        "Plan Summary",
        "Subscription"
    ]
    
    var progress: Double {
        return Double(currentStep + 1) / Double(totalSteps)
    }
    
    // Initialize tracking when onboarding starts
    func startOnboarding() {
        onboardingStartTime = Date()
        stepStartTime = Date()
        MixpanelService.shared.trackOnboardingStarted()
        // FacebookPixelService.shared.trackOnboardingStarted()
        trackStepViewed()
    }
    
    func nextStep() {
        // Track completion of current step
        trackStepCompleted()
        
        if currentStep < totalSteps - 1 {
            currentStep += 1
            stepStartTime = Date() // Start timing the new step
            trackStepViewed()
        } else {
            // Onboarding completed
            trackOnboardingCompleted()
        }
    }
    
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
            stepStartTime = Date() // Reset timing for the previous step
            trackStepViewed()
        }
    }
    
    func trackDropoff() {
        let timeSpent = stepStartTime?.timeIntervalSinceNow.magnitude
        MixpanelService.shared.trackOnboardingDropoff(
            step: currentStep,
            stepName: getCurrentStepName(),
            timeSpent: timeSpent
        )
    }
    
    // MARK: - Private Analytics Methods
    private func trackStepViewed() {
        let questionTitle = getCurrentStepName()
        
        // Only track question-specific event (no duplicates)
        MixpanelService.shared.trackQuestionViewed(
            questionTitle: questionTitle,
            stepNumber: currentStep
        )
    }
    
    private func trackStepCompleted() {
        // Don't track step completion separately since we track question answers
        // This reduces duplicate events
    }
    
    // Public method to track when a question is viewed
    func trackQuestionViewed(questionTitle: String, stepNumber: Int) {
        let timeSpent = stepStartTime?.timeIntervalSinceNow.magnitude
        MixpanelService.shared.trackQuestionViewed(
            questionTitle: questionTitle,
            stepNumber: stepNumber,
            timeSpent: timeSpent
        )
    }
    
    // New method to track when user answers a specific question
    func trackQuestionAnswered(answer: String) {
        let timeSpent = stepStartTime?.timeIntervalSinceNow.magnitude
        let questionTitle = getCurrentStepName()
        
        MixpanelService.shared.trackQuestionAnswered(
            questionTitle: questionTitle,
            answer: answer,
            stepNumber: currentStep,
            timeSpent: timeSpent
        )
    }
    
    private func trackOnboardingCompleted() {
        let totalTime = onboardingStartTime?.timeIntervalSinceNow.magnitude ?? 0
        MixpanelService.shared.trackOnboardingCompleted(totalTime: totalTime)
        // FacebookPixelService.shared.trackOnboardingCompleted(totalTime: totalTime, stepsCompleted: currentStep + 1)
    }
    
    private func getCurrentStepName() -> String {
        guard currentStep < steps.count else { return "Unknown" }
        return steps[currentStep]
    }
}

// Update SongFrequencyView to include navigation
struct SongFrequencyView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedFrequency: String?
    @State private var navigateToResults = false
    
    let frequencies = [
        ("0-2", "Thrifts now and then", "bag"),
        ("3-5", "A few items per week", "cart"),
        ("6+", "Dedicated Thrifter", "star.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                // Progress bar
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: UIScreen.main.bounds.width * 0.0625, height: 2) // 1/16 ≈ 0.0625
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("How many items do you thrift per week?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom thrift settings.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Frequency options
            VStack(spacing: 16) {
                ForEach(frequencies, id: \.0) { frequency, description, icon in
                    Button(action: { 
                        selectedFrequency = frequency
                        // Track question-specific answer
                        coordinator.trackQuestionAnswered(answer: frequency)
                    }) {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(frequency)
                                    .font(.system(size: 17))
                                Text(description)
                                    .font(.system(size: 15))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(selectedFrequency == frequency ? Color.black : Color(.systemGray6))
                        .foregroundColor(selectedFrequency == frequency ? .white : .black)
                        .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToResults) {
                LongTermResultsView()
                    .horizontalSlideTransition()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedFrequency != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedFrequency != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedFrequency == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedFrequency != nil {
                    coordinator.nextStep()
                    navigateToResults = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 0
        }
    }
}



// Central shopping cart emoji with wiggle animation
struct WiggleShoppingCartEmoji: View {
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    
    var body: some View {
        Text("🛒")
            .font(.system(size: 32))
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
            .onAppear {
                // Horizontal wiggle
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    offsetX = 8
                }
                
                // Vertical wiggle (different timing)
                withAnimation(
                    .easeInOut(duration: 3.2)
                    .repeatForever(autoreverses: true)
                ) {
                    offsetY = 6
                }
                
                // Gentle scale animation
                withAnimation(
                    .easeInOut(duration: 2.8)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.15
        }
                
                // Subtle rotation wiggle
            withAnimation(
                    .easeInOut(duration: 4.0)
                .repeatForever(autoreverses: true)
            ) {
                    rotation = 8
            }
        }
    }
}

struct CustomPlanView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showContent = false
    @State private var animationProgress: CGFloat = 0
    @State private var navigateToNext = false
    @State private var gradientRotation: Double = 0
    @State private var isAnimationComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 16))
                        )
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
            
            Spacer()
            
            // Animated Circle with Gradient and Emojis
            ZStack {
                // Animated gradient background circle
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.95, green: 0.9, blue: 1.0),
                                Color(red: 0.9, green: 0.95, blue: 1.0),
                                Color(red: 0.85, green: 0.9, blue: 0.95),
                                Color(red: 0.95, green: 0.9, blue: 1.0)
                            ]),
                            center: .center,
                            startAngle: .degrees(gradientRotation),
                            endAngle: .degrees(gradientRotation + 360)
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(showContent ? 1 : 0.5)
                    .opacity(showContent ? 1 : 0)
                
                // Dots around the circle
                ForEach(0..<12) { index in
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 4, height: 4)
                        .offset(y: -90)
                        .rotationEffect(.degrees(Double(index) * 30))
                        .opacity(showContent ? 1 : 0)
                }
                
                // Central wiggling shopping cart emoji
                WiggleShoppingCartEmoji()
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.8), value: showContent)
            }
            .padding(.bottom, 60)
            
            // "All done!" text
            Text("All done!")
                .font(.system(size: 17))
                .foregroundColor(Color(red: 0.83, green: 0.69, blue: 0.52))
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
            
            // Main title
            Text("Time to generate\nyour custom profile!")
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .padding(.horizontal, 24)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.9), value: showContent)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToNext) {
                LoadingView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isAnimationComplete ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color(.systemGray5))
                    .foregroundColor(isAnimationComplete ? .white : Color(.systemGray2))
                    .cornerRadius(26)
            }
            .disabled(!isAnimationComplete)
            .simultaneousGesture(TapGesture().onEnded {
                if isAnimationComplete {
                    navigateToNext = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 16
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Your Custom Plan", stepNumber: 16)
            // Start the animations sequence
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
            
            // Rotate gradient continuously
            withAnimation(
                .linear(duration: 10)
                .repeatForever(autoreverses: false)
            ) {
                gradientRotation = 360
            }
            
            // Enable continue button after animations complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                isAnimationComplete = true
            }
        }
    }
}

// Email Sign In View - Two Screen Flow
struct EmailSignInView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var currentScreen: EmailSignInScreen = .emailEntry
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var codeDigits = ["", "", "", ""]
    @FocusState private var focusedDigit: Int?
    
    enum EmailSignInScreen {
        case emailEntry
        case codeVerification
    }
    
    var body: some View {
        NavigationView {
        VStack(spacing: 0) {
                switch currentScreen {
                case .emailEntry:
                    emailEntryScreen
                case .codeVerification:
                    codeVerificationScreen
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .alert("Error", isPresented: .constant(authManager.errorMessage != nil)) {
                Button("OK") {
                    authManager.errorMessage = nil
                }
            } message: {
                Text(authManager.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Email Entry Screen
    private var emailEntryScreen: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Title
            Text("Sign In")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            // Email input field
            VStack(spacing: 20) {
                TextField("Email", text: $email)
                    .font(.system(size: 17))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                            )
                    )
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
                
                Spacer()
                
            // Continue button
            Button(action: {
                sendVerificationCode()
            }) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isEmailValid ? Color.black : Color(.systemGray4))
                    .foregroundColor(isEmailValid ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(!isEmailValid || authManager.isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
    }
    
    // MARK: - Code Verification Screen
    private var codeVerificationScreen: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { currentScreen = .emailEntry }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 18))
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Title
            Text("Confirm your email")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            // Description
                VStack(alignment: .leading, spacing: 8) {
                Text("Please enter the 4-digit code we've just sent to")
                    .font(.system(size: 17))
                        .foregroundColor(.gray)
                    
                Text(maskedEmail)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // 4-digit code input
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    CodeDigitField(
                        text: $codeDigits[index],
                        isActive: focusedDigit == index
                    )
                    .focused($focusedDigit, equals: index)
                    .onChange(of: codeDigits[index]) { newValue in
                        handleCodeInput(at: index, value: newValue)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            
            // Resend code
            HStack(spacing: 4) {
                Text("Didn't receive the code?")
                    .font(.system(size: 17))
                            .foregroundColor(.gray)
                        
                Button("Resend") {
                    resendCode()
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Properties
    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && !email.isEmpty
    }
    
    private var maskedEmail: String {
        let components = email.components(separatedBy: "@")
        guard components.count == 2 else { return email }
        
        let username = components[0]
        let domain = components[1]
        
        if username.count <= 2 {
            return "\(username)••••@\(domain)"
        } else {
            let prefix = String(username.prefix(2))
            return "\(prefix)••••@\(domain)"
        }
    }
    
    // MARK: - Helper Methods
    private func sendVerificationCode() {
        authManager.sendEmailVerificationCode(email: email) { success, message in
            DispatchQueue.main.async {
                if success {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.currentScreen = .codeVerification
                    }
                    self.focusedDigit = 0
                    
                    // Show success message if needed
                    if let message = message {
                        print("✅ \(message)")
                    }
                } else {
                    // Show error message
                    self.authManager.errorMessage = message ?? "Failed to send verification code"
                }
            }
        }
    }
    
    private func handleCodeInput(at index: Int, value: String) {
        // Only allow single digits
        if value.count > 1 {
            codeDigits[index] = String(value.last ?? Character(""))
        }
        
        // Move to next field if digit entered
        if !value.isEmpty && index < 3 {
            focusedDigit = index + 1
        }
        
        // Check if all digits are filled
        if codeDigits.allSatisfy({ !$0.isEmpty }) {
            verifyCode()
        }
    }
    
    private func resendCode() {
        // Reset code fields
        codeDigits = ["", "", "", ""]
        focusedDigit = 0
        
        // Use AuthenticationManager to resend code
        authManager.resendVerificationCode { success, message in
            DispatchQueue.main.async {
                if let message = message {
                    if success {
                        print("✅ \(message)")
        } else {
                        self.authManager.errorMessage = message
                    }
                }
            }
        }
    }
    
    private func verifyCode() {
        let enteredCode = codeDigits.joined()
        
        // Use AuthenticationManager to verify the real code
        authManager.verifyEmailCode(email: email, code: enteredCode) { success, message in
            DispatchQueue.main.async {
                if success {
                    // Successfully verified, AuthenticationManager handles sign in
                    self.dismiss()
                } else {
                    // Show error and reset code fields
                    self.authManager.errorMessage = message ?? "Invalid verification code"
                    self.codeDigits = ["", "", "", ""]
                    self.focusedDigit = 0
                }
            }
        }
    }
}

// MARK: - Code Digit Field Component
struct CodeDigitField: View {
    @Binding var text: String
    let isActive: Bool
    
    var body: some View {
        TextField("", text: $text)
            .font(.system(size: 24, weight: .medium))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.black : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                    )
            )
            .onChange(of: text) { newValue in
                // Limit to single digit
                if newValue.count > 1 {
                    text = String(newValue.last ?? Character(""))
            }
        }
    }
}

// MARK: - Google Maps View
struct GoogleMapsView: UIViewRepresentable {
    @ObservedObject var mapService: ThriftStoreMapService
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject var mapController: MapViewController
    
    func makeUIView(context: Context) -> GMSMapView {
        print("🗺️ Creating Google Maps view...")
        
        // Create map view with default frame - SwiftUI will handle sizing
        let mapView = GMSMapView()
        mapView.delegate = context.coordinator
        
        // Configure map settings
        mapView.settings.compassButton = false // We have custom zoom controls
        mapView.settings.myLocationButton = false // We have custom location tracking
        mapView.isMyLocationEnabled = true
        mapView.settings.scrollGestures = true
        mapView.settings.zoomGestures = true
        mapView.settings.tiltGestures = false
        mapView.settings.rotateGestures = false
        
        // Configure map appearance
        mapView.mapType = .normal
        mapView.isBuildingsEnabled = true
        mapView.isTrafficEnabled = false
        mapView.isIndoorEnabled = false
        
        // Add custom map style to hide street names and labels
        let styleJSON = """
        [
          {
            "featureType": "all",
            "elementType": "labels.text",
            "stylers": [
              {
                "visibility": "off"
              }
            ]
          },
          {
            "featureType": "road",
            "elementType": "labels",
            "stylers": [
              {
                "visibility": "off"
              }
            ]
          },
          {
            "featureType": "poi",
            "elementType": "labels",
            "stylers": [
              {
                "visibility": "off"
              }
            ]
          },
          {
            "featureType": "transit",
            "elementType": "labels",
            "stylers": [
              {
                "visibility": "off"
              }
            ]
          }
        ]
        """
        
        if let style = try? GMSMapStyle(jsonString: styleJSON) {
            mapView.mapStyle = style
            print("🗺️ Applied custom map style to hide labels")
        } else {
            print("⚠️ Failed to apply custom map style")
        }
        
        // Set initial camera position
        let defaultLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
        let initialLocation = locationManager.location?.coordinate ?? defaultLocation
        
            let camera = GMSCameraPosition.camera(
                withLatitude: initialLocation.latitude,
                longitude: initialLocation.longitude,
                zoom: 12.0
            )
            mapView.camera = camera
        
        print("📍 Initial map location set to: \(initialLocation)")
        
        // Setup coordinator with map view
        context.coordinator.setup(mapView: mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Update store markers
        context.coordinator.updateStores(stores: mapService.thriftStores)
        
        // Update user location if available and trigger search if needed
        if let location = locationManager.location {
            context.coordinator.updateUserLocation(location: location, mapView: mapView)
            
            // If we haven't searched for stores yet and now have location, search now
            if mapService.thriftStores.isEmpty && !context.coordinator.hasSearchedForStores {
                print("🔍 Location now available - searching for thrift stores...")
                context.coordinator.hasSearchedForStores = true
                Task {
                    await mapService.searchNearbyThriftStores(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapsView
        var mapView: GMSMapView?
        var markers: [GMSMarker] = []
        var hasInitializedLocation = false
        var hasSearchedForStores = false
        
        init(_ parent: GoogleMapsView) {
            self.parent = parent
            super.init()
        }
        
        func setup(mapView: GMSMapView) {
            self.mapView = mapView
            parent.mapController.setMapView(mapView)
            
            // Start location tracking
            parent.locationManager.startLocationTracking()
            
            // Load nearby stores if location is available immediately
            if let location = parent.locationManager.location {
                performInitialSearch(location: location)
            } else {
                print("📍 No location available yet, will search when location is found")
                // Set up a timer to retry getting location periodically
                setupLocationRetryTimer()
            }
        }
        
        private func performInitialSearch(location: CLLocation) {
            guard !hasSearchedForStores else { return }
            hasSearchedForStores = true
            
            Task {
                print("🔍 Performing initial search for thrift stores...")
                await parent.mapService.searchNearbyThriftStores(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
        }
        
        private func setupLocationRetryTimer() {
            // Check for location every 2 seconds for up to 10 seconds
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                attempts += 1
                
                if let location = self.parent.locationManager.location {
                    print("📍 Location found after \(attempts) attempts")
                    self.performInitialSearch(location: location)
                    timer.invalidate()
                } else if attempts >= 5 {
                    print("📍 Location not found after 10 seconds, stopping retry")
                    timer.invalidate()
                }
            }
        }
        
        func updateStores(stores: [ThriftStore]) {
            guard let mapView = mapView else { 
                print("❌ MapView not available for updating stores")
                return 
            }
            
            // Clear existing markers
            markers.forEach { $0.map = nil }
            markers.removeAll()
            
            // Add new markers
            for store in stores {
                let marker = GMSMarker()
                marker.position = CLLocationCoordinate2D(
                    latitude: store.latitude,
                    longitude: store.longitude
                )
                marker.title = store.title.lowercased() + " 🔗"
                marker.snippet = store.address
                marker.userData = store
                marker.map = mapView
                marker.icon = createCustomMarkerIcon(for: store)
                markers.append(marker)
            }
            
            print("🗺️ Updated Google Maps with \(stores.count) store markers")
            
            // If we have markers, adjust camera to show them
            if !markers.isEmpty && !hasInitializedLocation {
                var bounds = GMSCoordinateBounds()
                markers.forEach { marker in
                    bounds = bounds.includingCoordinate(marker.position)
                }
                
                let update = GMSCameraUpdate.fit(bounds, withPadding: 50.0)
                mapView.animate(with: update)
                print("📍 Adjusted camera to show all \(markers.count) store markers")
            }
        }
        
        func updateUserLocation(location: CLLocation, mapView: GMSMapView) {
            guard !hasInitializedLocation else { return }
            
            let camera = GMSCameraPosition.camera(
                withLatitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                zoom: 12.0
            )
            
            mapView.animate(to: camera)
            hasInitializedLocation = true
            print("📍 Google Maps centered on user location: \(location.coordinate)")
        }
        
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            handleMarkerTap(marker: marker)
            return true
        }
        
        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            handleCoordinateTap(coordinate: coordinate, mapView: mapView)
        }
        
        private func handleMarkerTap(marker: GMSMarker) {
            guard let store = marker.userData as? ThriftStore,
                  !store.address.isEmpty else {
                print("❌ No valid store data found")
                return
            }
            
            // Track map interaction for consumption data
            DispatchQueue.main.async {
                ConsumptionRequestService.shared.trackMapInteraction(interactionType: "map_viewed")
                ConsumptionRequestService.shared.trackFeatureUsed("map_interaction")
            }
            
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            UIPasteboard.general.string = store.address
            print("✅ Address copied to clipboard: \(store.address)")
            
            showCopyAlert(store: store)
        }
        
        private func handleCoordinateTap(coordinate: CLLocationCoordinate2D, mapView: GMSMapView) {
            let tapTolerance: Double = 0.001
            
            for marker in markers {
                let distance = abs(marker.position.latitude - coordinate.latitude) + 
                              abs(marker.position.longitude - coordinate.longitude)
                
                if distance < tapTolerance {
                    handleMarkerTap(marker: marker)
                    return
                }
            }
        }
        
        private func showCopyAlert(store: ThriftStore) {
            let alert = UIAlertController(
                title: "✨ Address Copied!",
                message: "\n\(store.title)\n\(store.address)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Got it!", style: .default))
            
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {
                    
                    var topController = rootViewController
                    while let presented = topController.presentedViewController {
                        topController = presented
                    }
                    
                    topController.present(alert, animated: true)
                }
            }
        }
        
        private func createCustomMarkerIcon(for store: ThriftStore) -> UIImage {
            // Prepare text with emoji and lowercase
            let baseText = store.title.lowercased()
            let linkEmoji = " 🔗"
            let maxWidth: CGFloat = 200 // Maximum width for text
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            
            // Check if text needs truncation
            let fullText = baseText + linkEmoji
            let fullTextSize = fullText.size(withAttributes: attributes)
            
            let finalText: String
            if fullTextSize.width > maxWidth {
                // Truncate and add ellipsis + emoji
                var truncatedText = baseText
                let ellipsisEmoji = "..." + linkEmoji
                let ellipsisSize = ellipsisEmoji.size(withAttributes: attributes)
                let availableWidth = maxWidth - ellipsisSize.width
                
                // Keep removing characters until it fits
                while truncatedText.size(withAttributes: attributes).width > availableWidth && !truncatedText.isEmpty {
                    truncatedText = String(truncatedText.dropLast())
                }
                finalText = truncatedText + ellipsisEmoji
            } else {
                finalText = fullText
            }
            
            // Calculate final text size and container dimensions
            let finalTextSize = finalText.size(withAttributes: attributes)
            let padding: CGFloat = 8 // Tighter padding on left/right
            let containerWidth = finalTextSize.width + (padding * 2)
            let containerHeight: CGFloat = 32
            let totalHeight: CGFloat = 48 // More space for pin to prevent cropping
            
            let size = CGSize(width: containerWidth, height: totalHeight)
            let renderer = UIGraphicsImageRenderer(size: size)
            
            return renderer.image { context in
                let cgContext = context.cgContext
                
                // Create rounded rectangle with less rounded corners
                let backgroundRect = CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
                let cornerRadius: CGFloat = 8.0 // Less rounded
                
                // Draw rounded rectangle background (no border)
                cgContext.setFillColor(UIColor.white.cgColor)
                let roundedPath = UIBezierPath(roundedRect: backgroundRect, cornerRadius: cornerRadius)
                cgContext.addPath(roundedPath.cgPath)
                cgContext.fillPath()
                
                // Draw text centered in container
                let textRect = CGRect(
                    x: padding,
                    y: (containerHeight - finalTextSize.height) / 2,
                    width: finalTextSize.width,
                    height: finalTextSize.height
                )
                
                finalText.draw(in: textRect, withAttributes: attributes)
                
                // Add iPhone pin emoji instead of gray rectangle
                let pinEmoji = "📍"
                let pinAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.black
                ]
                let pinSize = pinEmoji.size(withAttributes: pinAttributes)
                let pinRect = CGRect(
                    x: (containerWidth - pinSize.width) / 2,
                    y: containerHeight,
                    width: pinSize.width,
                    height: pinSize.height
                )
                
                pinEmoji.draw(in: pinRect, withAttributes: pinAttributes)
            }
        }
    }
}

// Modern Featured Post Card Component
struct FeaturedPostCard: View {
    let username: String
    let title: String
    let imageName: String
    let upvotes: Int
    let likes: Int
    
    var body: some View {
        VStack(spacing: 0) {
            // Post image as main content
            ZStack(alignment: .topLeading) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 240)
                    .clipped()
                
                // Gradient overlay for text readability - only at top
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.6),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .center
                )
                
                // Top content
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // User avatar
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(username.dropFirst().prefix(1).uppercased()))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        
                        Text(username)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                }
                .padding(16)
            }
            
            // Bottom content area
            VStack(alignment: .leading, spacing: 8) {
                // Post title
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                // Upvote and like section
                HStack(spacing: 12) {
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                            
                            Text("\(upvotes)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            
                            Text("\(likes)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
}

// Tinder-style Card Stack Component
struct TinderCardStack: View {
    @State private var cards: [CardData] = [
        CardData(id: 0, username: "u/sarah_thrifts", title: "Mid-century lamp for $8, sold for $120 on FB Marketplace 💡", imageName: "lamp-find", upvotes: 167),
        CardData(id: 1, username: "u/retro_mike", title: "Found this Pokémon Blue at Goodwill for $3, sold for $85! 🎮", imageName: "pokemon", upvotes: 342),
        CardData(id: 2, username: "u/luxe_hunter", title: "This Gucci bag from estate sale - paid $40, worth $850! 👜", imageName: "found-this-purse", upvotes: 289),
        CardData(id: 3, username: "u/deal_seeker22", title: "Goodwill bins haul - $12 investment, $340 profit this week! 🛍️", imageName: "goodwill-bins", upvotes: 198),
        CardData(id: 4, username: "u/vintage_finds", title: "Toy lot from garage sale - $25 in, $280 out! 🧸", imageName: "toy-lot", upvotes: 234)
    ]
    
    @State private var dragOffset = CGSize.zero
    @State private var dragRotation: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background cards (staggered)
            ForEach(0..<cards.count, id: \.self) { index in
                cardView(for: index)
            }
        }
    }
    
    private func cardView(for index: Int) -> some View {
        let card = cards[index]
        let isTopCard = index == cards.count - 1
        let cardIndex = cards.count - 1 - index
        
        // More visible staggering effects
        let scaleValue = isTopCard ? 1.0 : 1.0 - (Double(cardIndex) * 0.06)
        let xOffset = isTopCard ? dragOffset.width : CGFloat(cardIndex * -8) // More visible offset
        let yOffset = isTopCard ? dragOffset.height : CGFloat(cardIndex * 12)
        let rotation = isTopCard ? dragRotation : Double(cardIndex) * -2.0 // More visible rotation
        let opacityValue = cardIndex > 2 ? 0 : 1.0 - (Double(cardIndex) * 0.12) // Less opacity reduction for visibility
        
        return FeaturedPostCard(
            username: card.username,
            title: card.title,
            imageName: card.imageName,
            upvotes: card.upvotes,
            likes: card.likes
        )
        .scaleEffect(scaleValue)
        .offset(x: xOffset, y: yOffset)
        .rotationEffect(.degrees(rotation))
        .opacity(opacityValue)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: dragOffset)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cards.count) // Smoother card transitions
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isTopCard) // Smooth scale/opacity transitions
        .gesture(isTopCard ? createDragGesture() : nil)
        .zIndex(isTopCard ? 100 : Double(index))
    }
    
    private func createDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 20) // Increased minimum distance
            .onChanged { value in
                // Only respond to significantly horizontal drags (more than 2:1 ratio)
                if abs(value.translation.width) > abs(value.translation.height) * 2 {
                    dragOffset = value.translation
                    dragRotation = Double(value.translation.width / 10)
                }
            }
            .onEnded { value in
                // Only handle swipe if it's significantly horizontal
                if abs(value.translation.width) > abs(value.translation.height) * 2 {
                    handleDragEnd(value)
                } else {
                    // Reset if it was a vertical scroll
                    dragOffset = .zero
                    dragRotation = 0
                }
            }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        // Prevent multiple simultaneous swipes
        guard !isAnimating else { return }
        
        let swipeThreshold: CGFloat = 100
        
        if abs(value.translation.width) > swipeThreshold {
            // Mark as animating to prevent multiple swipes
            isAnimating = true
            
            // Swipe away animation
            let direction: CGFloat = value.translation.width > 0 ? 1 : -1
            
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: direction * 500, height: value.translation.height)
                dragRotation = Double(direction * 20)
            }
            
            // Remove card after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                removeTopCard()
            }
        } else {
            // Snap back with animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dragOffset = .zero
                dragRotation = 0
            }
        }
    }
    
    private func removeTopCard() {
        guard !cards.isEmpty else { return }
        
        let removedCard = cards.removeLast()
        
        // Reset drag state immediately to prevent double appearance
        dragOffset = .zero
        dragRotation = 0
        
        // Wait for the UI to settle before adding card back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.none) {
                cards.insert(removedCard, at: 0)
            }
            
            // Reset animation state to allow next swipe
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = false
            }
        }
    }
}

// Animated Info Bubble Component
struct InfoBubble: View {
    @Binding var showingInfo: Bool
    @State private var isPulsating = false
    
    var body: some View {
        Button(action: {
            showingInfo = true
        }) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .opacity(isPulsating ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isPulsating)
        }
        .onAppear {
            isPulsating = true
        }
    }
}

// Card Data Model
struct CardData: Identifiable {
    let id: Int
    let username: String
    let title: String
    let imageName: String
    let upvotes: Int
    let likes: Int
    
    init(id: Int, username: String, title: String, imageName: String, upvotes: Int) {
        self.id = id
        self.username = username
        self.title = title
        self.imageName = imageName
        self.upvotes = upvotes
        self.likes = Int.random(in: 15...89) // Random likes between 15-89
    }
}

// MARK: - Recent Finds Models
struct RecentFind: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: String
    let estimatedValue: Double
    let condition: String
    let brand: String?
    let location: String // Store location
    let dateFound: Date
    let notes: String?
    let imageData: Data? // Captured image data
    
}

class RecentFindsManager: ObservableObject {
    @Published var recentFinds: [RecentFind] = []
    
    func addRecentFind(_ find: RecentFind) {
        recentFinds.insert(find, at: 0) // Add to beginning for recency
        saveFinds()
    }
    
    func saveFinds() {
        do {
            let encoded = try JSONEncoder().encode(recentFinds)
            UserDefaults.standard.set(encoded, forKey: "RecentFinds")
            print("💾 Successfully saved \(recentFinds.count) recent finds")
        } catch {
            print("❌ Failed to save recent finds: \(error)")
        }
    }
    
    init() {
        loadFinds()
        // Add sample data if empty
        if recentFinds.isEmpty {
            addSampleData()
        }
    }
    
    private func loadFinds() {
        guard let data = UserDefaults.standard.data(forKey: "RecentFinds") else {
            print("📂 No saved recent finds data found")
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([RecentFind].self, from: data)
            recentFinds = decoded
            print("📂 Successfully loaded \(decoded.count) recent finds")
        } catch {
            print("❌ Failed to decode recent finds: \(error)")
            // Clear corrupted data and start fresh
            UserDefaults.standard.removeObject(forKey: "RecentFinds")
        }
    }
    
    private func addSampleData() {
        let sampleFinds = [
            RecentFind(
                id: UUID(),
                name: "Nike Air Jordan 1's - T-Scott",
                category: "Sneakers",
                estimatedValue: 215.00,
                condition: "8/10",
                brand: "Nike",
                location: "Goodwill",
                dateFound: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date(),
                notes: "Size 10.5 - popular size, light creasing, OG all with box (missing lid), slight yellowing on midsole",
                imageData: nil
            ),
            RecentFind(
                id: UUID(),
                name: "Vintage Ecko Navy Blue Hoodie",
                category: "Clothing",
                estimatedValue: 85.00,
                condition: "8/10",
                brand: "Ecko Unltd",
                location: "Thrift Store",
                dateFound: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                notes: "Vintage Y2K style, navy blue with rhino logo, size XL",
                imageData: nil
            ),
            RecentFind(
                id: UUID(),
                name: "Coach Legacy Shoulder Bag",
                category: "Accessories",
                estimatedValue: 100.00,
                condition: "9/10",
                brand: "Coach",
                location: "Estate Sale",
                dateFound: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
                notes: "Model 9966 - discontinued style, black pebbled leather, silver hardware, dust bag included",
                imageData: nil
            ),
            RecentFind(
                id: UUID(),
                name: "Jordan 4 White Cement",
                category: "Sneakers",
                estimatedValue: 215.00,
                condition: "8/10",
                brand: "Nike",
                location: "Goodwill",
                dateFound: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                notes: "2016 release, size 10.5, OG all with box, light creasing, no major flaws",
                imageData: nil
            ),
            RecentFind(
                id: UUID(),
                name: "Vintage Levi's Denim Jacket",
                category: "Clothing",
                estimatedValue: 45.00,
                condition: "7/10",
                brand: "Levi's",
                location: "Garage Sale",
                dateFound: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date(),
                notes: "Classic blue wash, size Large, some fading adds to vintage appeal",
                imageData: nil
            )
        ]
        
        recentFinds = sampleFinds
        saveFinds()
    }
}


struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingSignIn = false
    @State private var showingEmailSignIn = false
    @State private var showingOnboarding = false
    @State private var navigateToTryForFree = false

    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // Main Content
                VStack(spacing: 0) {
                    // Language Toggle
                    HStack {
                        Spacer()
                        
                        // Language Toggle (right side)
                        HStack(spacing: 4) {
                            Text("🇺🇸")
                                .font(.system(size: 14))
                            Text("EN")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    
                    // Main Video
                    MainVideoPlayer(videoName: "main")
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .padding(.bottom, 30)
                    
                    // Title Text
                    Text("Thrifting\nmade easy")
                        .font(.system(size: 42, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                    
                    // Bottom Buttons
                    VStack(spacing: 16) {
                        // Get Started - Static button
                        GetStartedButton(showingOnboarding: $showingOnboarding)
                        
                        // Only show sign in option if user is not logged in
                        if !authManager.isLoggedIn {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .font(.system(size: 15))
                            Button(action: { showingSignIn = true }) {
                                Text("Sign In")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.black)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.white)
            .preferredColorScheme(.light)

        }
        .navigationBarHidden(true)
        }
            .sheet(isPresented: Binding(
                get: { showingSignIn && !authManager.isLoggedIn },
                set: { showingSignIn = $0 }
            )) {
                SignInView(showingEmailSignIn: $showingEmailSignIn)
                    .presentationDetents([.height(UIScreen.main.bounds.height * 0.52)])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showingEmailSignIn) {
                EmailSignInView()
                    .presentationDetents([.height(UIScreen.main.bounds.height * 0.7)])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                NavigationView {
                    SongFrequencyView()
                        .horizontalSlideTransition()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .preferredColorScheme(.light)
            }

        
            .onChange(of: authManager.isLoggedIn) { isLoggedIn in
                if isLoggedIn {
                    // User became authenticated, dismiss any open sheets
                    showingSignIn = false
                    showingEmailSignIn = false
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// PaywallResumeView - Shows subscription screen directly when user returns to app
struct PaywallResumeView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        NavigationView {
            SubscriptionView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.light)
    }
}

// FirstTimeCongratsPopup - Shows congratulations popup for first-time users
struct FirstTimeCongratsPopup: View {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @State private var confettiTrigger = 0
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPopup()
                }
            
            // Popup content
            VStack(spacing: 20) {
                // Celebration emoji
                Text("🎉")
                    .font(.system(size: 60))
                    .scaleEffect(isPresented ? 1.2 : 1.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isPresented)
                
                // Title
                Text("Congrats on your 1-day streak!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                
                // Description
                Text("You've unlocked the Thrifty Map — your new shortcut to finding stores faster so you can profit with ease.")
                    .font(.system(size: 16))
                    .foregroundColor(.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                
                // Thanks button
                Button(action: {
                    dismissPopup()
                }) {
                    Text("Thanks!")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black)
                        .cornerRadius(25)
                }
                .padding(.top, 10)
            }
            .padding(30)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
            .scaleEffect(isPresented ? 1.0 : 0.8)
            .opacity(isPresented ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isPresented)
        }
        .confettiCannon(trigger: $confettiTrigger, num: 20, confettiSize: 6, fadesOut: true, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 80)
        .onAppear {
            // Start confetti animation shortly after popup appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiTrigger += 1
            }
        }
        .onChange(of: isPresented) { presented in
            if presented {
                // Start confetti when popup is presented
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    confettiTrigger += 1
                }
            }
        }
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

// Onboarding View for logged-in users who haven't completed onboarding
struct OnboardingView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showingOnboarding = false
    
    var body: some View {
        NavigationView {
            SongFrequencyView()
                .horizontalSlideTransition()
                .onAppear {
                    // Start tracking when onboarding begins
                    coordinator.startOnboarding()
                }
                .onDisappear {
                    // Track dropoff if user exits onboarding early
                    if !authManager.hasCompletedSubscription {
                        coordinator.trackDropoff()
                    }
                    // When onboarding is dismissed, mark it as completed
                    authManager.markOnboardingCompleted()
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.light)
    }
}

// Loading View with realistic progress animation
struct LoadingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var progress: CGFloat = 0.0
    @State private var progressText = "0%"
    @State private var statusText = "Initializing your profile..."
    @State private var showChecklist = false
    @State private var checkItems: [Bool] = [false, false, false, false, false]
    @State private var navigateToFinal = false
    
    let checklistItems = [
        "Thrifting style analysis",
        "Item valuation patterns", 
        "Shopping preferences",
        "Deal optimization",
        "Custom thrift profile"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 16))
                        )
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            Spacer()
            
            // Percentage
            Text(progressText)
                .font(.system(size: 72, weight: .bold))
                .padding(.bottom, 32)
            
            // Status text
            Text("We're setting everything up for you")
                .font(.system(size: 24, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            
            // Progress bar
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.4, blue: 0.7), // Pink
                                    Color(red: 0.4, green: 0.6, blue: 1.0)  // Blue
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
                
                Text(statusText)
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            
            // Recommendations checklist
            VStack(alignment: .leading, spacing: 0) {
                Text("Custom profile analysis:")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                
                ForEach(Array(checklistItems.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text("• \(item)")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if checkItems[index] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 20)
            }
            .background(Color.black)
            .cornerRadius(20)
            .padding(.horizontal, 24)
            .opacity(showChecklist ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: showChecklist)
            
            Spacer()
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 17
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Setting up your profile...", stepNumber: 17)
            startLoadingSequence()
        }
        .background(
            NavigationLink(isActive: $navigateToFinal) {
                FinalCongratulationsView()
            } label: {
                EmptyView()
            }
            .hidden()
        )
    }
    
    private func startLoadingSequence() {
        // Show checklist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showChecklist = true
        }
        
        // Start counting from 1% 
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            countUp()
        }
    }
    
    private func countUp() {
        var currentCount = 0
        let freezePoints: [Int: (String, Int)] = [
            18: ("Analyzing your thrifting style...", 0),
            34: ("Processing item valuation patterns...", 1), 
            56: ("Analyzing shopping preferences...", 2),
            78: ("Optimizing deal optimization...", 3),
            92: ("Finalizing your custom thrift profile...", 4)
        ]
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            currentCount += 1
            
            // Update progress and text
            DispatchQueue.main.async {
                self.progress = CGFloat(currentCount) / 100.0
                self.progressText = "\(currentCount)%"
            }
            
            // Check for freeze points
            if let (statusMessage, checkIndex) = freezePoints[currentCount] {
                timer.invalidate()
                
                DispatchQueue.main.async {
                    self.statusText = statusMessage
                    self.checkItems[checkIndex] = true
                }
                
                // Resume counting after freeze
                let freezeDuration: Double = currentCount == 92 ? 1.5 : 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + freezeDuration) {
                    self.resumeCountingFrom(currentCount + 1, freezePoints: freezePoints)
                }
                return
            }
            
            // Final completion
            if currentCount >= 100 {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.statusText = "Complete!"
                    if !self.checkItems[4] {
                        self.checkItems[4] = true
                    }
                }
                
                // Navigate to final screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.navigateToFinal = true
                }
            }
        }
    }
    
    private func resumeCountingFrom(_ startCount: Int, freezePoints: [Int: (String, Int)]) {
        var currentCount = startCount - 1
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            currentCount += 1
            
            // Update progress and text
            DispatchQueue.main.async {
                self.progress = CGFloat(currentCount) / 100.0
                self.progressText = "\(currentCount)%"
            }
            
            // Check for freeze points
            if let (statusMessage, checkIndex) = freezePoints[currentCount] {
                timer.invalidate()
                
                DispatchQueue.main.async {
                    self.statusText = statusMessage
                    self.checkItems[checkIndex] = true
                }
                
                // Resume counting after freeze
                let freezeDuration: Double = currentCount == 92 ? 1.5 : 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + freezeDuration) {
                    self.resumeCountingFrom(currentCount + 1, freezePoints: freezePoints)
                }
                return
            }
            
            // Final completion
            if currentCount >= 100 {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.statusText = "Complete!"
                    if !self.checkItems[4] {
                        self.checkItems[4] = true
                    }
                }
                
                // Navigate to final screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.navigateToFinal = true
                }
            }
        }
    }
}

// Final congratulations view with confetti
struct FinalCongratulationsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var navigateToSummary = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            // Confetti overlay
            if showConfetti {
                ConfettiView()
            }
            
            VStack(spacing: 0) {
                // Header with back button and progress
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "arrow.left")
                                    .foregroundColor(.black)
                                    .font(.system(size: 16))
                            )
                    }
                    
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Spacer()
                
                // Success checkmark circle
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.3), value: showContent)
                .padding(.bottom, 48)
                
                // Congratulations text
                Text("Congratulations")
                    .font(.system(size: 36, weight: .bold))
                    .padding(.bottom, 16)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
                
                // Subtitle
                Text("your custom profile is ready!")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.8), value: showContent)
                
                Spacer()
                
                // Let's get started button
                NavigationLink(isActive: $navigateToSummary) {
                    CustomPlanSummaryView()
                } label: {
                    HStack {
                        Text("Let's get started!")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .cornerRadius(28)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    navigateToSummary = true
                })
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            coordinator.currentStep = 18
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Final Congratulations", stepNumber: 18)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showContent = true
                showConfetti = true
            }
        }
    }
}

// Custom Plan Summary View
struct CustomPlanSummaryView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showContent = false
    @State private var navigateToSubscription = false
    
    // Calculate date 3 days from now
    private var targetDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return formatter.string(from: futureDate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "arrow.left")
                                .foregroundColor(.black)
                                .font(.system(size: 16))
                        )
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Success checkmark and title
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(showContent ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.3), value: showContent)
                        
                        VStack(spacing: 4) {
                            Text("Congratulations")
                                .font(.system(size: 24, weight: .bold))
                        }
                        .multilineTextAlignment(.center)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
                    }
                    .padding(.top, 12)
                    
                    Spacer(minLength: 4)
                    
                    // Stats rings
                    VStack(spacing: 12) {
                        // Stats circles grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            
                            // Boost in clarity
                            RecommendationCircle(
                                icon: "eye.fill",
                                title: "Boost in clarity",
                                value: "79%",
                                color: Color.purple,
                                delay: 1.2
                            )
                            
                            // Boost in savings
                            RecommendationCircle(
                                icon: "dollarsign.circle.fill",
                                title: "Boost in savings",
                                value: "71%",
                                color: Color.green,
                                delay: 1.4
                            )
                            
                            // Time saved per day
                            RecommendationCircle(
                                icon: "clock.fill",
                                title: "Time saved per day",
                                value: "2.5h",
                                color: Color.blue,
                                delay: 1.6
                            )
                            
                            // Boost in enjoyment
                            RecommendationCircle(
                                icon: "heart.fill",
                                title: "Boost in enjoyment",
                                value: "85%",
                                color: Color.orange,
                                delay: 1.8
                            )
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                    .padding(.horizontal, 24)
                    
                    // Your custom prediction (moved to bottom)
                    VStack(spacing: 12) {
                        Text("Your custom prediction")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Based on your profile, you'll see significant improvement in thrift success and value-finding within the next 3 days.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(2.0), value: showContent)
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    
                    Spacer(minLength: 60)
                }
            }
            
            // Let's get started button
            NavigationLink(isActive: $navigateToSubscription) {
                TryForFreeView()
            } label: {
                Text("Let's get started!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .cornerRadius(26)
            }
            .simultaneousGesture(TapGesture().onEnded {
                navigateToSubscription = true
            })
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(2.2), value: showContent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.currentStep = 19
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Plan Summary", stepNumber: 19)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showContent = true
            }
        }
    }
}

// Recommendation Circle Component
struct RecommendationCircle: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    let delay: Double
    
    @State private var showCircle = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Centered heading with icon
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: showCircle ? 0.75 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0).delay(delay), value: showCircle)
                
                // Value text
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .opacity(showCircle ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(delay + 0.5), value: showCircle)
            }
            

        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCircle = true
            }
        }
    }
}

// Simple and reliable video player for main.mp4
struct MainVideoPlayer: UIViewRepresentable {
    let videoName: String
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.white
        
        // Try to find video in main bundle
        var videoURL: URL?
        
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            print("✅ Found video in main bundle: \(url)")
            videoURL = url
        } else if let path = Bundle.main.path(forResource: videoName, ofType: "mp4") {
            videoURL = URL(fileURLWithPath: path)
            print("✅ Found video at path: \(path)")
        } else {
            print("❌ \(videoName).mp4 not found in project bundle")
            return containerView
        }
        
        guard let url = videoURL else { return containerView }
        
        // Create AVPlayer and AVPlayerLayer
        let player = AVPlayer(url: url)
        player.isMuted = true
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect // Maintain aspect ratio without cropping
        playerLayer.backgroundColor = UIColor.white.cgColor
        
        // Add player layer to container
        containerView.layer.addSublayer(playerLayer)
        
        // Set initial frame - important for immediate visibility
        playerLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100) // Temporary size
        
        // Store references for later access
        containerView.layer.setValue(player, forKey: "player")
        containerView.layer.setValue(playerLayer, forKey: "playerLayer")
        
        // Update frame after a short delay when container has proper bounds
        DispatchQueue.main.async {
            if containerView.bounds != .zero {
                playerLayer.frame = containerView.bounds
                print("🔧 Set initial player layer frame to: \(containerView.bounds)")
            }
        }
        
        // Start playing
                        player.play()
        print("🎬 MainVideoPlayer started playing: \(videoName)")
        
        // Set up looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
                            print("🔄 Video ended, looping...")
                            player.seek(to: .zero)
                            player.play()
                        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        print("🔄 updateUIView called with bounds: \(uiView.bounds)")
        
        if let playerLayer = uiView.layer.value(forKey: "playerLayer") as? AVPlayerLayer {
            // Always update the frame, even if bounds are the same
            playerLayer.frame = uiView.bounds
            print("🔧 Updated player layer frame to: \(uiView.bounds)")
            
            // Force a redraw
            playerLayer.setNeedsDisplay()
        } else {
            print("❌ Could not find playerLayer in updateUIView")
        }
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let videoName: String
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        // Get video URL from bundle
        guard let path = Bundle.main.path(forResource: "spin", ofType: "mp4") else {
            print("❌ Failed to find video file: spin.mp4")
            return view
        }
        
        print("✅ Found video at path:", path)
        let videoURL = URL(fileURLWithPath: path)
        
        // Create AVPlayer and layer
        let player = AVPlayer(url: videoURL)
        let playerLayer = AVPlayerLayer(player: player)
        
        // Calculate size based on screen width
        let width = UIScreen.main.bounds.width - 40
        playerLayer.frame = CGRect(x: 0, y: 0, width: width, height: width) // Make it square
        playerLayer.videoGravity = .resizeAspect
        
        // Add player layer to view
        view.layer.addSublayer(playerLayer)
        
        // Play video and loop
        player.play()
        
        // Remove any existing observers before adding new one
        NotificationCenter.default.removeObserver(self)
        
        // Add loop observer
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                            object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Handle any view updates if needed
    }
}

struct SpinnerView: View {
    @State private var rotation: Double = 0
    @State private var isSpinning = false
    
    // Segments arranged exactly like the Figma design - gift box positioned where the golden arrow points
    let segments = [
        ("50%", [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.6, green: 0.8, blue: 1.0)]),    // Light blue gradient 
        ("No LUCK", [Color.white, Color(red: 0.95, green: 0.95, blue: 0.95)]),                         // White gradient
        ("30%", [Color(red: 0.95, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.6, blue: 0.8)]),   // Pink gradient
        ("90%", [Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.8, green: 0.5, blue: 1.0)]),    // Purple gradient
        ("70%", [Color.white, Color(red: 0.95, green: 0.95, blue: 0.95)]),                              // White gradient
        ("🎁", [Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.8, green: 0.5, blue: 1.0)])      // Purple gradient - WINNER POSITION
    ]
    
    var body: some View {
        ZStack {
            // Main wheel container with shadow
            ZStack {
                // Segments
                ForEach(0..<6) { index in
                    SpinnerSegment(
                        text: segments[index].0,
                        gradientColors: segments[index].1,
                        index: index
                    )
                }
                .rotationEffect(.degrees(rotation))
                
                // Outer blue gradient border (thicker, more prominent)
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.8),
                                Color(red: 0.2, green: 0.5, blue: 1.0),
                                Color(red: 0.3, green: 0.6, blue: 1.0),
                                Color(red: 0.1, green: 0.3, blue: 0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 12
                    )
                    .frame(width: 320, height: 320)
                
                // Inner gold gradient ring
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.84, blue: 0.0),
                                Color(red: 1.0, green: 0.92, blue: 0.2),
                                Color(red: 0.9, green: 0.75, blue: 0.0),
                                Color(red: 1.0, green: 0.88, blue: 0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 296, height: 296)
                
                // Center circle with music emoji
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.4, blue: 0.9),
                                        Color(red: 0.3, green: 0.5, blue: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .overlay(
                        Text("🛒")
                            .font(.system(size: 32))
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            
            // Golden triangle pointer (positioned to point at gift segment)
            HStack {
                Spacer()
                ZStack {
                    // Shadow behind triangle
                    Triangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 28, height: 32)
                        .rotationEffect(.degrees(-90))
                        .offset(x: 11, y: 2)
                    
                    // Main golden triangle
                    Triangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.84, blue: 0.0),
                                    Color(red: 1.0, green: 0.92, blue: 0.2),
                                    Color(red: 0.9, green: 0.75, blue: 0.0),
                                    Color(red: 1.0, green: 0.88, blue: 0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 32)
                        .rotationEffect(.degrees(-90)) // Point toward center
                        .overlay(
                            Triangle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 1.0, green: 0.84, blue: 0.0),
                                            Color(red: 0.9, green: 0.75, blue: 0.0)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .frame(width: 28, height: 32)
                                .rotationEffect(.degrees(-90))
                        )
                        .offset(x: 10)
                }
            }
            .frame(width: 320, height: 320)
        }
        .frame(width: 320, height: 320)
        .onAppear {
            // Start spinning after a brief delay, land exactly on gift box
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 3.5)) {
                    // Multiple spins + precise landing on gift box center (240 degrees -> 0 degrees = 120 degree rotation)
                    rotation = 1800 + 120 // 5 full rotations + exact center landing on gift box
                }
            }
        }
    }
}

struct SpinnerSegment: View {
    let text: String
    let gradientColors: [Color]
    let index: Int
    
    var body: some View {
        ZStack {
            // Segment path with enhanced gradients
            Path { path in
                let center = CGPoint(x: 160, y: 160)
                path.move(to: center)
                path.addArc(center: center,
                          radius: 148,
                          startAngle: .degrees(Double(index) * 60 - 90),
                          endAngle: .degrees(Double(index + 1) * 60 - 90),
                          clockwise: false)
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Segment divider lines (more subtle)
            Path { path in
                let angle = Double(index) * 60 - 90
                let startRadius: CGFloat = 30
                let endRadius: CGFloat = 148
                let startX = 160 + startRadius * cos(angle * .pi / 180)
                let startY = 160 + startRadius * sin(angle * .pi / 180)
                let endX = 160 + endRadius * cos(angle * .pi / 180)
                let endY = 160 + endRadius * sin(angle * .pi / 180)
                
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
            
            // Text with better positioning and styling
            Text(text)
                .font(.system(size: text == "🎁" ? 36 : (text == "No LUCK" ? 16 : 22), weight: .bold))
                .foregroundColor(isWhiteSegment ? .black : .white)
                .shadow(color: isWhiteSegment ? Color.clear : Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                .rotationEffect(.degrees(Double(index) * 60 + 30)) // Rotate text to follow segment
                .position(textPosition(for: index))
        }
        .frame(width: 320, height: 320)
    }
    
    private var isWhiteSegment: Bool {
        return gradientColors.first == .white
    }
    
    private func textPosition(for index: Int) -> CGPoint {
        let angle = Double(index) * 60 + 30 - 90 // Center of segment
        let radius: CGFloat = 110 // Distance from center
        let x = 160 + radius * cos(angle * .pi / 180)
        let y = 160 + radius * sin(angle * .pi / 180)
        return CGPoint(x: x, y: y)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

struct WinbackView: View {
    @Binding var isPresented: Bool
    @State private var showOneTimeOffer = false
    @State private var spinnerCompleted = false
    let storeManager: StoreManager // Add this parameter
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    
    var body: some View {
        ZStack {
            if showOneTimeOffer {
                OneTimeOfferView(isPresented: $showOneTimeOffer, parentPresented: $isPresented, storeManager: storeManager) // Pass storeManager
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
                VStack(spacing: 32) {
                    // Win exclusive offers title
                    Text("Win exclusive offers")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.top, 40)
                    
                    // Title with proper line breaks and gradient
                    VStack(spacing: 8) {
                        Text("Grab your permanent")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("Discount")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.3, green: 0.5, blue: 1.0),  // Blue
                                        Color(red: 0.9, green: 0.4, blue: 0.7)   // Pink
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    Spacer()
                    
                    // Centered Spinner (only show in hard paywall mode)
                    if remoteConfig.hardPaywall {
                    SpinnerView()
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .onAppear {
                    if remoteConfig.hardPaywall {
                    // Show one time offer after spinner completes (0.8s delay + 3.5s animation = 4.3s total)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
                        if !spinnerCompleted {
                            spinnerCompleted = true
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showOneTimeOffer = true
                                }
                            }
                        }
                    } else {
                        // Soft paywall mode - show offer immediately without spinner
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !spinnerCompleted {
                                spinnerCompleted = true
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showOneTimeOffer = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

// TimelineItem component with separate elements
struct TimelineItem: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isLast: Bool
    let showContent: Bool
    let lineColor: Color
    let lineHeight: CGFloat // Individual line height control
    let iconTopPadding: CGFloat // Individual icon positioning
    let textTopPadding: CGFloat // Individual text positioning
    let showLine: Bool // Control whether to show the line
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: Spacer for layout
            VStack(spacing: 0) {
                // Spacer for text spacing - independent of line
                Spacer()
                    .frame(height: 20)
            }
            .frame(width: 24)
            
            // Right side: Text content - independently positioned
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.bottom, isLast ? 0 : 20)
            .padding(.top, textTopPadding)
        }
        .overlay(
            // Line segment centered with icon
            Group {
                if showLine {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 6, height: lineHeight)
                        .offset(y: 24 + iconTopPadding) // Position below icon
                        .offset(x: 9) // Center horizontally with icon (24/2 - 6/2 = 9)
                }
            }
            , alignment: .topLeading
        )
        .overlay(
            // Icon positioned at the top of the line segment
            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 24, height: 24)
                
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(y: iconTopPadding)
            , alignment: .topLeading
        )
        .opacity(showContent ? 1 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
    }
}

// Try For Free View - new page before bell notification
struct TryForFreeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showContent = false
    @State private var navigateToSubscription = false
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - removed restore button
            HStack {
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Main content
            VStack(spacing: 0) {
                // Title
                Text(remoteConfig.hardPaywall ? "We want you to try\nThrifty for free" : "We want you to try\nThrifty")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
                
                // Main Video
                MainVideoPlayer(videoName: "main")
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.bottom, 30)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
            }
            
            // Bottom section with button and payment text
            VStack(spacing: 16) {
                // Payment info (conditional based on paywall mode)
                if remoteConfig.hardPaywall {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    
                    Text("No Payment Due Now")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                }
                
                // Try button (conditional text based on paywall mode)
                NavigationLink(isActive: $navigateToSubscription) {
                    SubscriptionView()
                } label: {
                    Text(remoteConfig.hardPaywall ? "Try for $0.00" : "Try Thrifty")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                
                // Legal text (conditional based on paywall mode)
                if !remoteConfig.hardPaywall {
                Text("Just $6 per month (billed annually)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .background(Color.white)
        .navigationBarHidden(true)
        .onAppear {
            showContent = true
            // Track winback subscription view
            MixpanelService.shared.trackSubscriptionViewed(planType: "winback_offer")
            // FacebookPixelService.shared.trackSubscriptionViewed(planType: "winback_offer")
        }
    }
}

// Update SubscriptionView to use new WinbackView
struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @StateObject private var storeManager = StoreManager()
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var showContent = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showWinback = false
    @State private var navigateToCreateAccount = false
    @State private var currentStep = 1 // 1 = bell reminder, 2 = subscription details
    @State private var bellAnimating = false
    @State private var showingPrivacyPolicy = false
    @State private var isPurchasing = false // Loading state for purchase button
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with restore button - add safe area padding to prevent cropping
            HStack {
                Spacer()
                Button(action: {
                    Task {
                        do {
                            try await storeManager.restorePurchases()
                        } catch {
                            errorMessage = "Failed to restore purchases"
                            showError = true
                        }
                    }
                }) {
                    Text("Restore")
                        .font(.system(size: 17))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20) // Increased from 16 to 20 to prevent cropping
            
            // Main content
            VStack(spacing: 20) {
                if currentStep == 1 {
                    // Step 1: Bell reminder screen
                    VStack(spacing: 0) {
                        // Reminder text at the top
                        Text("We'll send you a reminder\nbefore your free trial ends")
                            .font(.system(size: 24, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black)
                            .padding(.top, 40)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
                        
                        Spacer()
                        
                        // Bell icon with notification badge in the middle
                        ZStack {
                            // Bell with advanced realistic shake animation
                            Image(systemName: "bell")
                                .font(.system(size: 200, weight: .light))
                                .foregroundColor(.black)
                                .rotationEffect(.degrees(bellAnimating ? -15 : 0))
                                .animation(
                                    Animation.easeInOut(duration: 0.25)
                                        .repeatForever(autoreverses: true),
                                    value: bellAnimating
                                )
                                .scaleEffect(bellAnimating ? 0.98 : 1.0)
                                .animation(
                                    Animation.easeInOut(duration: 0.1)
                                        .repeatForever(autoreverses: true),
                                    value: bellAnimating
                                )
                            
                            // Notification badge
                            Circle()
                                .fill(Color.black)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text("1")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 55, y: -60)
                                .rotationEffect(.degrees(bellAnimating ? -15 : 0))
                                .animation(
                                    Animation.easeInOut(duration: 0.25)
                                        .repeatForever(autoreverses: true),
                                    value: bellAnimating
                                )
                                .scaleEffect(bellAnimating ? 0.98 : 1.0)
                                .animation(
                                    Animation.easeInOut(duration: 0.1)
                                        .repeatForever(autoreverses: true),
                                    value: bellAnimating
                                )
                        }
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
                        .onAppear {
                            // Start bell animation after content appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                bellAnimating = true
                            }
                        }
                        
                        Spacer()
                    }
                } else {
                    // Step 2: Subscription details screen
                    VStack(spacing: 0) {
                                                // Title - positioned higher (conditional based on paywall mode)
                        Text(remoteConfig.hardPaywall ? "Start your 3-days FREE trial to continue." : "Subscribe to Thrifty Unlimited")
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black)
                            .lineLimit(nil) // Allow unlimited lines to prevent truncation
                            .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                            .padding(.horizontal, 24) // Add horizontal padding to ensure proper spacing
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
                        
                        // Add more space between title and timeline
                        Spacer()
                            .frame(height: 40)
                        
                                                // Proper timeline structure - each item is self-contained
                            VStack(spacing: 0) {
                            // Today item - top line (you can adjust lineHeight individually)
                            TimelineItem(
                                icon: "lock.fill",
                                iconColor: .green,
                                title: "Today",
                                description: "Unlock all the app's features and thrift faster, save more, and score hidden gems daily.",
                                isLast: false,
                                showContent: showContent,
                                lineColor: .green,
                                lineHeight: 100, // Adjust this for top line length
                                iconTopPadding: 15,
                                textTopPadding: 25,
                                showLine: true
                            )
                            
                            // In 2 days item - middle line (you can adjust lineHeight individually)
                            TimelineItem(
                                icon: "bell.fill",
                                iconColor: .green,
                                title: "In 2 days - Reminder",
                                description: "We'll send you a reminder that your trial is ending soon.",
                                isLast: false,
                                showContent: showContent,
                                lineColor: .green,
                                lineHeight: 80, // Adjust this for middle line length
                                iconTopPadding: 15,
                                textTopPadding: 25,
                                showLine: true
                            )
                                
                            // In 3 days item - bottom line (you can adjust lineHeight individually)
                            TimelineItem(
                                icon: "plus",
                                iconColor: .gray,
                                title: "In 3 days - Billing Starts",
                                description: "You'll be charged, unless you cancel anytime before.",
                                isLast: true,
                                showContent: showContent,
                                lineColor: .gray,
                                lineHeight: 80, // Adjust this for bottom line length
                                iconTopPadding: 15,
                                textTopPadding: 25,
                                showLine: true
                            )
                        }
                        .padding(.horizontal, 24)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
                        
                        Spacer()
                    }
                }
                
                // Bottom section with button and payment text
                VStack(spacing: 12) {
                    if currentStep == 1 {
                        // Step 1: No payment due now text
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                            
                            Text("No Payment Due Now")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                        }
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                        
                        // Step 1: Try button (conditional text based on paywall mode)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep = 2
                            }
                        }) {
                            Text(remoteConfig.hardPaywall ? "Try For $0.00" : "Try Thrifty")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.black)
                                .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                        }
                        .padding(.horizontal, 24)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                        
                        // Step 1: Legal text (conditional based on paywall mode)
                        if !remoteConfig.hardPaywall {
                            Text("Yearly subscription")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                        }
                        
                        // No commitment text for Step 1
                        Text("No commitment, cancel anytime.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.6), value: showContent)
                    } else {
                        // Step 2: Payment info (conditional based on paywall mode)
                        if remoteConfig.hardPaywall {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                                
                                Text("No Payment Due Now")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                        }
                            
                        // Step 2: Purchase button - same position as step 1 button
                            Button(action: {
                                // Prevent multiple taps
                                guard !isPurchasing else { return }
                                
                                Task {
                                    // Set loading state
                                    isPurchasing = true
                                    
                                    do {
                                        // Track subscription attempt
                                        MixpanelService.shared.trackSubscriptionViewed(planType: "yearly")
                                        // FacebookPixelService.shared.trackSubscriptionViewed(planType: "yearly")
                                        
                                        print("🔍 Attempting to purchase yearly subscription...")
                                        print("📦 Available products: \(storeManager.subscriptions.count)")
                                        for product in storeManager.subscriptions {
                                            print("   - \(product.id): \(product.displayPrice)")
                                        }
                                        print("🎯 Looking for yearly subscription product...")
                                        
                                        // Find the yearly subscription product (try new ID first, then fallback)
                                        guard let subscription = storeManager.subscriptions.first(where: { 
                                            $0.id == "com.thrifty.thrifty.unlimited.yearly79" || 
                                            $0.id == "com.thrifty.thrifty.unlimited.yearly" 
                                        }) else {
                                            print("❌ Yearly subscription product not found")
                                            errorMessage = "Yearly subscription product not available"
                                            showError = true
                                            isPurchasing = false // Reset loading state
                                            return
                                        }
                                        
                                        print("✅ Found yearly subscription: \(subscription.id) - \(subscription.displayPrice)")
                                        let result = try await subscription.purchase()
                                        
                                        switch result {
                                        case .success(let verification):
                                            switch verification {
                                            case .verified(let transaction):
                                                print("✅ Successfully purchased yearly subscription: \(transaction.productID)")
                                                
                                                // Track successful subscription purchase
                                                MixpanelService.shared.trackSubscriptionPurchased(planType: "yearly", price: Double(truncating: subscription.price as NSNumber))
                                                
                                                // Schedule delayed tracking (1 hour validation) - Facebook + SKAdNetwork
                                                DelayedTrackingService.shared.scheduleDelayedTrialEvent(
                                                    planType: "yearly", 
                                                    price: Double(truncating: subscription.price as NSNumber),
                                                    transactionId: String(transaction.originalID),
                                                    skAdNetworkValue: 32
                                                )
                                                
                                                // Successful purchase - mark subscription as completed
                                                await transaction.finish()
                                                await storeManager.updateSubscriptionStatus()
                                                authManager.markSubscriptionCompleted()
                                                isPurchasing = false // Reset loading state
                                                navigateToCreateAccount = true
                                            case .unverified:
                                                throw StoreError.failedVerification
                                            }
                                        case .pending:
                                            throw StoreError.pending
                                                                case .userCancelled:
                            // Show winback for both hard and soft paywall modes
                            // The difference is only in the wheel animation (handled in WinbackView)
                                showWinback = true
                                isPurchasing = false // Reset loading state
                                        @unknown default:
                                            isPurchasing = false // Reset loading state
                                            throw StoreError.unknown
                                        }
                                                        } catch StoreError.userCancelled {
                        // Show winback for both hard and soft paywall modes
                        // The difference is only in the wheel animation (handled in WinbackView)
                            showWinback = true
                            isPurchasing = false // Reset loading state
                                    } catch StoreError.pending {
                                        errorMessage = "Purchase is pending"
                                        showError = true
                                        isPurchasing = false // Reset loading state
                                    } catch {
                                        errorMessage = "Failed to make purchase"
                                        showError = true
                                        isPurchasing = false // Reset loading state
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(isPurchasing ? "Processing..." : "Start my 3-Day Free Trial")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                .background(isPurchasing ? Color.gray : Color.black)
                                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                            }
                            .disabled(isPurchasing)
                            .padding(.horizontal, 24)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                            
                            // Add pricing text under the button (always show)
                            Text("Just $6 per month (billed annually)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .opacity(showContent ? 1 : 0)
                                .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                    }
                    
                    if currentStep == 2 {
                        // Legal text for step 2 (conditional based on paywall mode)
                        if !remoteConfig.hardPaywall {
                            Text("Yearly subscription")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                        }
                        
                        // Terms & Privacy links for soft paywall compliance
                        if !remoteConfig.hardPaywall {
                            TermsAndPrivacyText(showingPrivacyPolicy: $showingPrivacyPolicy)
                                .padding(.top, 16)
                                .opacity(showContent ? 1 : 0)
                                .animation(.easeOut(duration: 0.6).delay(1.6), value: showContent)
                            
                            // Restore Purchases Button (required by Apple)
                            Button(action: {
                                Task {
                                    do {
                                        try await AppStore.sync()
                                        print("✅ Purchases restored successfully")
                                    } catch {
                                        print("❌ Failed to restore purchases: \(error)")
                                        errorMessage = "Failed to restore purchases"
                                        showError = true
                                    }
                                }
                            }) {
                                Text("Restore Purchases")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .padding(.top, 12)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.8), value: showContent)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .edgesIgnoringSafeArea(.bottom) // Only ignore bottom safe area, keep top safe area for proper restore button positioning
        .onAppear {
            coordinator.currentStep = 20
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Subscription", stepNumber: 20)
            // FacebookPixelService.shared.trackOnboardingStepViewed(questionTitle: "Subscription", stepNumber: 20)
            // Track subscription view appearance
            MixpanelService.shared.trackSubscriptionViewed(planType: "yearly_subscription_page")
            // FacebookPixelService.shared.trackSubscriptionViewed(planType: "yearly_subscription_page")
            
            // Set paywall screen state to true when user reaches subscription screen
            authManager.setPaywallScreenState(true)
            
            showContent = true
            // Load products when view appears
            Task {
                await storeManager.loadProducts()
            }
            
                    // Note: Both hard and soft paywall modes show winback when user cancels
        // The difference is only in the wheel animation and pricing transparency
        }
        .onDisappear {
            // Clear paywall state when user leaves subscription screen by going back
            if !authManager.hasCompletedSubscription {
                authManager.setPaywallScreenState(false)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showWinback) {
                WinbackView(isPresented: $showWinback, storeManager: storeManager)
        }
        .background(
            NavigationLink(isActive: $navigateToCreateAccount) {
                CreateAccountView()
            } label: {
                EmptyView()
            }
            .hidden()
        )
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.8)])
                .presentationDragIndicator(.visible)
        }

    }
}

struct OneTimeOfferView: View {
    @Binding var isPresented: Bool
    @Binding var parentPresented: Bool
    let storeManager: StoreManager // Accept StoreManager instance as a parameter
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToCreateAccount = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with X button
            HStack {
                Button(action: {
                    parentPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            VStack(spacing: 32) {
                // ONE TIME OFFER title
                Text("ONE TIME OFFER")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                
                // 80% OFF FOREVER box with sparkles (made bigger with shadow and white border)
                ZStack {
                    // Sparkle decorations around the box
                    VStack {
                        HStack {
                            Image(systemName: "sparkle")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .offset(x: -30, y: -15)
                            Spacer()
                            Image(systemName: "sparkle")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .offset(x: 30, y: -20)
                        }
                        Spacer()
                        HStack {
                            Image(systemName: "sparkle")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .offset(x: -35, y: 15)
                            Spacer()
                            Image(systemName: "sparkle")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .offset(x: 35, y: 20)
                        }
                    }
                    .frame(width: 320, height: 160)
                    
                    // Main offer box (with shadow and white border)
                    VStack(spacing: 12) {
                        Text("50% OFF")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                        Text("FOREVER")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(width: 280, height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white, lineWidth: 3)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
                    )
                }
                
                // Pricing
                HStack(spacing: 8) {
                    Text("$79.00")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .strikethrough()
                }
                
                // Warning text with black triangle and exclamation mark
                HStack {
                    ZStack {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black)
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .offset(y: 1)
                    }
                    Text("This offer won't be there once you close it!")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 24)
                
                // Combined LOWEST PRICE EVER with yearly plan box - only show when NOT hardPaywall
                if !remoteConfig.hardPaywall {
                VStack(spacing: 0) {
                    // LOWEST PRICE EVER header
                    Text("LOWEST PRICE EVER")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.black)
                        .cornerRadius(12, corners: [.topLeft, .topRight])
                    
                    // Yearly plan box (seamlessly connected to header with no top corners)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Monthly")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                            Text("Winback Offer • $39.00")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("$39.00 /year")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                    .overlay(
                        RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight])
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .offset(y: -1) // Slight overlap to create seamless connection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16) // Move closer to button
                }
                
                // CLAIM YOUR ONE TIME OFFER button
                Button(action: {
                    // Prevent multiple taps
                    guard !isPurchasing else { return }
                    
                    Task {
                        await purchaseSubscription()
                    }
                }) {
                    HStack(spacing: 8) {
                        if storeManager.subscriptions.isEmpty || isPurchasing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text(isPurchasing ? "Processing..." : 
                             storeManager.subscriptions.isEmpty ? "Loading..." : "CLAIM YOUR ONE TIME OFFER")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background((storeManager.subscriptions.isEmpty || isPurchasing) ? Color.gray : Color.black)
                    .cornerRadius(28)
                }
                .disabled(storeManager.subscriptions.isEmpty || isPurchasing)
                .padding(.horizontal, 24)
                .padding(.top, 24) // Reduced spacing from top elements
                
                // Retry button if products failed to load
                if storeManager.subscriptions.isEmpty {
                    Button(action: {
                        Task {
                            await storeManager.loadProducts()
                        }
                    }) {
                        Text("Retry Loading Products")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $navigateToCreateAccount) {
            CreateAccountView()
        }
    }
    
    private func purchaseSubscription() async {
        isPurchasing = true
        
        print("🔍 Attempting to purchase special subscription...")
        print("📦 Available products: \(storeManager.subscriptions.count)")
        for product in storeManager.subscriptions {
            print("   - \(product.id): \(product.displayPrice)")
        }
        
        do {
            // Find the winback product for one-time offer (try new ID first, then fallback)
            guard let specialSubscription = storeManager.subscriptions.first(where: { 
                $0.id == "com.thrifty.thrifty.unlimited.yearly.winback39" ||
                $0.id == "com.thrifty.thrifty.unlimited.monthly.winback" 
            }) else {
                print("❌ Winback offer product not found in available products")
                print("🔍 Looking for: com.thrifty.thrifty.unlimited.yearly.winback39 or com.thrifty.thrifty.unlimited.monthly.winback")
                print("📦 Available products:")
                for product in storeManager.subscriptions {
                    print("   - \(product.id)")
                }
                errorMessage = "Winback $39.00 offer not available. Please try again or contact support."
                showError = true
                isPurchasing = false
                return
            }
            
            let result = try await specialSubscription.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("✅ Successfully purchased $39.00 winback offer: \(transaction.productID)")
                    
                    // Track successful winback subscription purchase
                    MixpanelService.shared.trackSubscriptionPurchased(planType: "winback_39.00", price: 39.00)
                    
                    // Schedule delayed tracking (1 hour validation) - Facebook + SKAdNetwork
                    DelayedTrackingService.shared.scheduleDelayedPurchaseEvent(
                        planType: "winback_39.00", 
                        price: 39.00,
                        transactionId: String(transaction.originalID),
                        skAdNetworkValue: 63
                    )
                    
                    await transaction.finish()
                    await storeManager.updateSubscriptionStatus()
                    authManager.markSubscriptionCompleted()
                    isPurchasing = false // Reset loading state
                    navigateToCreateAccount = true
                case .unverified:
                    errorMessage = "Purchase verification failed"
                    showError = true
                }
            case .userCancelled:
                // User cancelled, no error needed
                break
            case .pending:
                errorMessage = "Purchase is pending approval"
                showError = true
            @unknown default:
                errorMessage = "Unknown purchase error"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isPurchasing = false
    }
}

// Create Account View - appears after successful purchase
struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and progress bar
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Title
            Text("Create an account")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            Spacer()
            
            // Static sign in buttons
            VStack(spacing: 20) {
                // Sign in with Apple - Static button
                AppleSignInButton(authManager: AuthenticationManager.shared)
                
                // Google Sign In - RE-ENABLED with real CLIENT_ID
                GoogleSignInButton(authManager: AuthenticationManager.shared)
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .onChange(of: authManager.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                // User successfully signed in, mark subscription as completed
                authManager.markSubscriptionCompleted()
            }
        }
    }
}

// Define custom colors for white theme design
extension Color {
    static let thriftyBackground = Color.white
    static let thriftyTopBanner = Color.white
    static let thriftySecondaryText = Color(hex: "6B6B6B")
    static let thriftyDeleteRed = Color(hex: "FF453A")
    static let thriftyAccent = Color.black // Black accent color for buttons
}

// Helper for hex color initialization
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Tool Response Manager for persisting generated responses
@MainActor
class ToolResponseManager: ObservableObject {
    static let shared = ToolResponseManager()
    
    private init() {
        loadAllResponses()
    }
    
    @Published var toolResponses: [String: ToolResponse] = [:]
    
    struct ToolResponse: Codable {
        var userInput: String
        var generatedText: String
        var timestamp: Date
        
        init(userInput: String = "", generatedText: String = "") {
            self.userInput = userInput
            self.generatedText = generatedText
            self.timestamp = Date()
        }
    }
    
    func getResponse(for toolTitle: String) -> ToolResponse {
        return toolResponses[toolTitle] ?? ToolResponse()
    }
    
    func saveResponse(for toolTitle: String, userInput: String, generatedText: String) {
        toolResponses[toolTitle] = ToolResponse(userInput: userInput, generatedText: generatedText)
        saveToUserDefaults()
    }
    
    func updateUserInput(for toolTitle: String, userInput: String) {
        var response = toolResponses[toolTitle] ?? ToolResponse()
        response.userInput = userInput
        toolResponses[toolTitle] = response
        saveToUserDefaults()
    }
    
    func clearResponse(for toolTitle: String) {
        toolResponses.removeValue(forKey: toolTitle)
        saveToUserDefaults()
    }
    
    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(toolResponses) {
            UserDefaults.standard.set(encoded, forKey: "ToolResponses")
        }
    }
    
    private func loadAllResponses() {
        if let data = UserDefaults.standard.data(forKey: "ToolResponses"),
           let decoded = try? JSONDecoder().decode([String: ToolResponse].self, from: data) {
            toolResponses = decoded
        }
    }
}

// User Data Model
struct UserData: Codable {
    let id: String
    let email: String?
    let name: String?
    let profileImageURL: String?
    let authProvider: AuthProvider
    
    enum AuthProvider: String, Codable {
        case apple = "apple"
        case google = "google"
        case email = "email"
    }
}

// Remote Config Manager for controlling app features using Firestore
@MainActor
class RemoteConfigManager: NSObject, ObservableObject {
    static let shared = RemoteConfigManager()
    
    @Published var hardPaywall: Bool = true // Default to true (hard paywall)
    
    private let hardPaywallKey = "hardpaywall"
    private let configCollection = "app_config"
    private var hasAttemptedLoad = false
    
    private override init() {
        super.init()
        // Don't load immediately - wait for Firebase to be configured
    }
    
    private func loadConfigFromFirestore() {
        // Ensure we only try to load once Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("⚠️ Firebase not configured yet, delaying config loag d...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.loadConfigFromFirestore()
            }
            return
        }
        
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        
        let db = Firestore.firestore()
        print("🔍 Attempting to read from Firestore: \(configCollection)/paywall_config")
        
        db.collection(configCollection).document("paywall_config").getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading config from Firestore: \(error.localizedDescription)")
                    print("🔍 Error details: \(error)")
                    print("🔍 Error code: \((error as NSError).code)")
                    
                    // Check for specific error types
                    if (error as NSError).code == -1009 { // Network offline
                        print("📱 Device appears to be offline")
                    } else if (error as NSError).code == 7 { // Permission denied
                        print("🔒 Permission denied - check Firestore rules")
                    }
                    
                    // Keep default value (true) and retry after delay
                    print("🔄 Will retry in 5 seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self?.hasAttemptedLoad = false
                        self?.loadConfigFromFirestore()
                    }
                    return
                }
                
                if let document = document, document.exists,
                   let data = document.data(),
                   let hardPaywall = data[self?.hardPaywallKey ?? ""] as? Bool {
                    self?.hardPaywall = hardPaywall
                    print("✅ Config loaded from Firestore - hardPaywall: \(hardPaywall)")
                } else {
                    print("ℹ️ No config found in Firestore, using default (hardPaywall: true)")
                    print("🔍 Document exists: \(document?.exists ?? false)")
                    print("🔍 Document path: \(self?.configCollection ?? "")/paywall_config")
                    print("🔍 Expected field: \(self?.hardPaywallKey ?? "")")
                    
                    if let data = document?.data() {
                        print("🔍 Document data: \(data)")
                        print("🔍 Available fields: \(Array(data.keys))")
                    } else {
                        print("❌ Document data is nil")
                    }
                    
                    // Provide setup instructions
                    print("📝 To fix this:")
                    print("   1. Go to Firebase Console → Firestore")
                    print("   2. Create collection: app_config")
                    print("   3. Create document: paywall_config")
                    print("   4. Add field: hardpaywall (boolean) = true")
                }
            }
        }
    }
    
    // Call this after Firebase is configured
    func initializeConfig() {
        loadConfigFromFirestore()
    }

    
    func refreshConfig() {
        hasAttemptedLoad = false
        loadConfigFromFirestore()
    }
    
    func togglePaywallMode() {
        hardPaywall.toggle()
        print("🎛️ Paywall mode changed to: \(hardPaywall ? "HARD" : "SOFT")")
    }
}

// Authentication Manager for handling real authentication
@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasCompletedOnboarding: Bool = false
    @Published var hasCompletedSubscription: Bool = false
    @Published var isOnPaywallScreen: Bool = false
    @Published var hasSeenFirstTimeCongratsPopup: Bool = false
    
    private let isLoggedInKey = "AuthenticationManager_IsLoggedIn"
    private let userDataKey = "AuthenticationManager_UserData"
    private let hasCompletedOnboardingKey = "AuthenticationManager_HasCompletedOnboarding"
    private let hasCompletedSubscriptionKey = "AuthenticationManager_HasCompletedSubscription"
    private let isOnPaywallScreenKey = "AuthenticationManager_IsOnPaywallScreen"
    private let hasSeenFirstTimeCongratsPopupKey = "AuthenticationManager_HasSeenFirstTimeCongratsPopup"
    private var currentNonce: String?
    
    private override init() {
        super.init()
        
        // Initialize with default values
        isLoggedIn = false
        currentUser = nil
        isLoading = false
        errorMessage = nil
        hasCompletedOnboarding = false
        hasCompletedSubscription = false
        isOnPaywallScreen = false
        hasSeenFirstTimeCongratsPopup = false
        
        // Load saved authentication state
        loadAuthenticationState()
        
        print("🔐 AuthenticationManager initialized - isLoggedIn: \(isLoggedIn), hasCompletedOnboarding: \(hasCompletedOnboarding), hasCompletedSubscription: \(hasCompletedSubscription), isOnPaywallScreen: \(isOnPaywallScreen)")
    }
    
    // Apple Sign In
    func signInWithApple() {
        isLoading = true
        errorMessage = nil
        
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // Google Sign In with Firebase - RE-ENABLED with real CLIENT_ID
    func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first?.rootViewController else {
            errorMessage = "Unable to find presenting view controller"
            isLoading = false
            return
        }
        
        GoogleSignIn.GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    // Check if user cancelled (this is normal behavior, not an error)
                    if error.localizedDescription.contains("cancelled") || error.localizedDescription.contains("canceled") {
                        print("🔐 Google Sign In cancelled by user")
                        self.isLoading = false
                        return // Don't show error message for cancellation
                    }
                    
                    self.errorMessage = "Google Sign In failed: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.errorMessage = "Failed to get Google ID token"
                    self.isLoading = false
                    return
                }
                
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
                
                Auth.auth().signIn(with: credential) { authResult, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.errorMessage = "Firebase authentication failed: \(error.localizedDescription)"
                            self.isLoading = false
                            return
                        }
                        
                        guard let firebaseUser = authResult?.user else {
                            self.errorMessage = "Failed to get Firebase user"
                            self.isLoading = false
                            return
                        }
                        
                        let userData = UserData(
                            id: firebaseUser.uid,
                            email: firebaseUser.email,
                            name: firebaseUser.displayName,
                            profileImageURL: firebaseUser.photoURL?.absoluteString,
                            authProvider: .google
                        )
                        
                        self.completeSignIn(with: userData)
                    }
                }
            }
        }
    }
    
    // Email Sign In (placeholder - requires Firebase setup)
    func signInWithEmail(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        // Basic validation
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            isLoading = false
            return
        }
        
        guard email.contains("@") && email.contains(".") else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            isLoading = false
            return
        }
        
        // TODO: Implement Email Sign In with Firebase
        // For now, show error that Firebase is needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.errorMessage = "Email Sign In requires Firebase setup. Please use Apple Sign In for now."
            self.isLoading = false
        }
    }
    
    // MARK: - Email Verification Methods
    
    // Store verification data temporarily
    @Published var pendingVerificationEmail: String?
    @Published var verificationCodeSent: Bool = false
    private var generatedVerificationCode: String?
    private var codeGenerationTime: Date?
    
    // Send verification code to email using Firebase Cloud Functions
    func sendEmailVerificationCode(email: String, completion: @escaping (Bool, String?) -> Void) {
        // Validate email format
        guard email.contains("@") && email.contains(".") && !email.isEmpty else {
            completion(false, "Please enter a valid email address")
            return
        }
        
        // Check for Apple employee - skip actual email sending
        if email.lowercased() == "apple@test.com" {
            isLoading = true
            errorMessage = nil
            
            // Set up verification data for Apple employee
            generatedVerificationCode = "1234" // Hardcoded code
            codeGenerationTime = Date()
            pendingVerificationEmail = email
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.verificationCodeSent = true
                completion(true, "Apple employee verification ready - use code: 1234")
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Generate 4-digit verification code
        let verificationCode = String(format: "%04d", Int.random(in: 1000...9999))
        generatedVerificationCode = verificationCode
        codeGenerationTime = Date()
        pendingVerificationEmail = email
        
        // Call Firebase Cloud Function to send email
        let functions = Functions.functions()
        let sendVerificationEmail = functions.httpsCallable("sendVerificationEmail")
        
        sendVerificationEmail.call([
            "email": email,
            "verificationCode": verificationCode,
            "appName": "Thrifty"
        ]) { (result: HTTPSCallableResult?, error: Error?) in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("❌ Failed to send verification email: \(error.localizedDescription)")
                    
                    // Fallback to development mode
                    print("🔐 FALLBACK MODE: Verification code for \(email): \(verificationCode)")
                    print("📧 Email would contain: Your verification code is \(verificationCode)")
                    
                    self.verificationCodeSent = true
                    completion(true, "Verification code sent (check console for development code: \(verificationCode))")
                } else {
                    print("✅ Verification email sent successfully to \(email)")
                    self.verificationCodeSent = true
                    completion(true, "Verification code sent to \(email)")
                }
            }
        }
    }
    
    // Verify the email code
    func verifyEmailCode(email: String, code: String, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true
        errorMessage = nil
        
        // Check for Apple employee hardcoded credentials
        if email.lowercased() == "apple@test.com" && code == "1234" {
            // Apple employee login - bypass normal verification
            let userData = UserData(
                id: "apple_employee_\(email.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: ".", with: "_"))",
                email: email,
                name: "Apple Employee",
                profileImageURL: nil,
                authProvider: .email
            )
            self.completeSignIn(with: userData)
            // Apple employees should go through onboarding
            self.hasCompletedOnboarding = false
            self.saveAuthenticationState()
            self.clearVerificationData()
            completion(true, "Welcome Apple Employee!")
            return
        }
        
        // Check if we have a pending verification for this email
        guard let pendingEmail = pendingVerificationEmail,
              pendingEmail.lowercased() == email.lowercased() else {
            isLoading = false
            completion(false, "No verification code sent for this email")
            return
        }
        
        // Check if code matches and is not expired (valid for 10 minutes)
        guard let generatedCode = generatedVerificationCode,
              let generationTime = codeGenerationTime else {
            isLoading = false
            completion(false, "No verification code generated")
            return
        }
        
        // Check if code is expired (10 minutes)
        let timeElapsed = Date().timeIntervalSince(generationTime)
        if timeElapsed > 600 { // 10 minutes
            isLoading = false
            completion(false, "Verification code has expired. Please request a new one.")
            return
        }
        
        // Verify the code
        if code == generatedCode {
            // Code is correct, create user account or sign in
            Auth.auth().createUser(withEmail: email, password: UUID().uuidString) { [weak self] authResult, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        // If user already exists, try to sign in instead
                        if error.localizedDescription.contains("already in use") {
                            // User exists, treat as sign in
                            let userData = UserData(
                                id: "email_\(email.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: ".", with: "_"))",
                                email: email,
                                name: email.components(separatedBy: "@").first?.capitalized,
                                profileImageURL: nil,
                                authProvider: .email
                            )
                            self.completeSignIn(with: userData)
                            self.clearVerificationData()
                            completion(true, "Successfully signed in!")
                        } else {
                            self.isLoading = false
                            completion(false, "Failed to create account: \(error.localizedDescription)")
                        }
                    } else {
                        // Successfully created account
                        guard let firebaseUser = authResult?.user else {
                            self.isLoading = false
                            completion(false, "Failed to get user data")
                            return
                        }
                        
                        let userData = UserData(
                            id: firebaseUser.uid,
                            email: firebaseUser.email,
                            name: firebaseUser.email?.components(separatedBy: "@").first?.capitalized,
                            profileImageURL: nil,
                            authProvider: .email
                        )
                        
                        self.completeSignIn(with: userData)
                        self.clearVerificationData()
                        completion(true, "Account created successfully!")
                    }
                }
            }
        } else {
            isLoading = false
            completion(false, "Invalid verification code. Please try again.")
        }
    }
    
    // Resend verification code
    func resendVerificationCode(completion: @escaping (Bool, String?) -> Void) {
        guard let email = pendingVerificationEmail else {
            completion(false, "No email address for resending code")
            return
        }
        
        sendEmailVerificationCode(email: email, completion: completion)
    }
    
    // Clear verification data
    private func clearVerificationData() {
        pendingVerificationEmail = nil
        generatedVerificationCode = nil
        codeGenerationTime = nil
        verificationCodeSent = false
    }
    
    func completeSignIn(with userData: UserData) {
        currentUser = userData
        isLoggedIn = true
        isLoading = false
        // Reset subscription status for new user - will be updated by Firebase call
        hasCompletedSubscription = false
        saveAuthenticationState()
        loadSubscriptionStatusFromFirebase()

        print("🔐 User signed in: \(userData.name ?? userData.email ?? "Unknown")")
    }
    
    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        saveAuthenticationState()
        print("✅ Onboarding marked as completed")
    }
    
    func markSubscriptionCompleted() {
        hasCompletedSubscription = true
        isOnPaywallScreen = false  // Clear paywall state when subscription is completed
        saveAuthenticationState()
        saveSubscriptionStatusToFirebase()
        print("✅ Subscription marked as completed")
    }
    
    func setPaywallScreenState(_ isOnPaywall: Bool) {
        isOnPaywallScreen = isOnPaywall
        saveAuthenticationState()
        print("💳 Paywall screen state set to: \(isOnPaywall)")
    }
    
    func markFirstTimeCongratsPopupSeen() {
        hasSeenFirstTimeCongratsPopup = true
        saveAuthenticationState()
        print("🎉 First time congrats popup marked as seen")
    }
    
    func setGuestMode() {
        isLoggedIn = true
        currentUser = UserData(
            id: "guest_\(UUID().uuidString)",
            email: nil,
            name: "Guest User",
            profileImageURL: nil,
            authProvider: .email
        )
        saveAuthenticationState()
        print("👤 Set guest mode - user is now logged in")
    }
    
    private func saveSubscriptionStatusToFirebase() {
        guard let email = currentUser?.email else {
            print("❌ No email available to save subscription status")
            return
        }
        
        let db = Firestore.firestore()
        let subscriptionData: [String: Any] = [
            "hasCompletedSubscription": true,
            "completedAt": FieldValue.serverTimestamp(),
            "email": email,
            "userID": currentUser?.id ?? "unknown"
        ]
        
        // Use email as the document ID for cross-auth provider compatibility
        let emailKey = email.lowercased().replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "@", with: "_")
        db.collection("user_subscriptions").document(emailKey).setData(subscriptionData) { error in
            if let error = error {
                print("❌ Error saving subscription status to Firebase: \(error.localizedDescription)")
            } else {
                print("✅ Successfully saved subscription completion to Firebase for email: \(email)")
            }
        }
    }
    
    private func loadSubscriptionStatusFromFirebase() {
        guard let email = currentUser?.email else {
            print("❌ No email available to load subscription status")
            return
        }
        
        let db = Firestore.firestore()
        // Use email as the document ID for cross-auth provider compatibility
        let emailKey = email.lowercased().replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "@", with: "_")
        db.collection("user_subscriptions").document(emailKey).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading subscription status from Firebase: \(error.localizedDescription)")
                    // On error, default to false (show onboarding)
                    self?.hasCompletedSubscription = false
                    self?.saveAuthenticationState()
                    return
                }
                
                if let document = document, document.exists,
                   let data = document.data(),
                   let hasCompleted = data["hasCompletedSubscription"] as? Bool {
                    self?.hasCompletedSubscription = hasCompleted
                    self?.saveAuthenticationState()
                    print("✅ Loaded subscription status from Firestore for email \(email): \(hasCompleted)")
                } else {
                    // No subscription record found - user hasn't completed subscription
                    print("📝 No subscription status found in Firestore for email: \(email) - defaulting to false")
                    self?.hasCompletedSubscription = false
                    self?.saveAuthenticationState()
                }
            }
        }
    }
    
    func logOut() {
        do {
            try Auth.auth().signOut()
            GoogleSignIn.GIDSignIn.sharedInstance.signOut() // Re-enabled with real CLIENT_ID
            
            currentUser = nil
            isLoggedIn = false
            isLoading = false
            errorMessage = nil
            hasCompletedOnboarding = false
            hasCompletedSubscription = false
            isOnPaywallScreen = false  // Clear paywall state on sign out
            hasSeenFirstTimeCongratsPopup = false  // Reset popup state on sign out
            saveAuthenticationState()
            print("🚪 User logged out - redirecting to sign in")
        } catch {
            errorMessage = "Failed to log out: \(error.localizedDescription)"
        }
    }
    
    private func saveAuthenticationState() {
        UserDefaults.standard.set(isLoggedIn, forKey: isLoggedInKey)
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.set(hasCompletedSubscription, forKey: hasCompletedSubscriptionKey)
        UserDefaults.standard.set(isOnPaywallScreen, forKey: isOnPaywallScreenKey)
        UserDefaults.standard.set(hasSeenFirstTimeCongratsPopup, forKey: hasSeenFirstTimeCongratsPopupKey)
        
        if let userData = currentUser,
           let encoded = try? JSONEncoder().encode(userData) {
            UserDefaults.standard.set(encoded, forKey: userDataKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDataKey)
        }
    }
    
    private func loadAuthenticationState() {
        // Default to false - users must sign in every time
        isLoggedIn = UserDefaults.standard.bool(forKey: isLoggedInKey)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        hasCompletedSubscription = UserDefaults.standard.bool(forKey: hasCompletedSubscriptionKey)
        isOnPaywallScreen = UserDefaults.standard.bool(forKey: isOnPaywallScreenKey)
        hasSeenFirstTimeCongratsPopup = UserDefaults.standard.bool(forKey: hasSeenFirstTimeCongratsPopupKey)
        
        if let data = UserDefaults.standard.data(forKey: userDataKey),
           let userData = try? JSONDecoder().decode(UserData.self, from: data) {
            currentUser = userData
        }
        
        // If we have user data but are not logged in, clear the user data
        if !isLoggedIn {
            currentUser = nil
        }
        

    }
    
    // Helper functions for Apple Sign In
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// Apple Sign In Delegate
extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                errorMessage = "Invalid state: A login callback was received, but no login request was sent."
                isLoading = false
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                errorMessage = "Unable to fetch Apple ID token"
                isLoading = false
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to serialize Apple ID token"
                isLoading = false
                return
            }
            
            // Create Firebase credential with Apple ID token
            let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce)
            
            // Sign in to Firebase with Apple credential
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.errorMessage = "Firebase authentication failed: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }
                    
                    guard let firebaseUser = authResult?.user else {
                        self.errorMessage = "Failed to get Firebase user"
                        self.isLoading = false
                        return
                    }
                    
                    // Create UserData with Firebase user info
                    let userData = UserData(
                        id: firebaseUser.uid,
                        email: firebaseUser.email ?? appleIDCredential.email,
                        name: firebaseUser.displayName ?? appleIDCredential.fullName?.formatted(),
                        profileImageURL: firebaseUser.photoURL?.absoluteString,
                        authProvider: .apple
                    )
                    
                    self.completeSignIn(with: userData)
                    print("✅ Apple Sign In successful - Firebase user created: \(firebaseUser.uid)")
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isLoading = false
        
        // Check if error is user cancellation (error code 1001)
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                // User cancelled - this is normal, don't show error
                print("🔐 Apple Sign In cancelled by user")
                return
            case .unknown:
                errorMessage = "Apple Sign In failed: Unknown error occurred"
            case .invalidResponse:
                errorMessage = "Apple Sign In failed: Invalid response received"
            case .notHandled:
                errorMessage = "Apple Sign In failed: Request not handled"
            case .failed:
                errorMessage = "Apple Sign In failed: Authentication failed"
            default:
                errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
        }
        
        print("❌ Apple Sign In error: \(error)")
    }
}

// Presentation Context Provider
extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

// Enhanced ProfileManager for user data tracking
@MainActor
class ProfileManager: ObservableObject {
    @Published var profilePicture: String = "tool-bg4"
    @Published var customProfileImage: UIImage?
    @Published var userName: String = "@thriftuser438"
    @Published var totalWordsWritten: Int = 0
    @Published var profitRefreshTrigger: Int = 0
    
    private let userNameKey = "ProfileManager_UserName"
    private let profilePictureKey = "ProfileManager_ProfilePicture"
    private let totalWordsKey = "ProfileManager_TotalWords"
    private let customImageKey = "ProfileManager_CustomImage"
    
    init() {
        // Defer heavy loading to avoid blocking the main thread
        DispatchQueue.main.async { [weak self] in
            self?.loadUserData()
        }
    }
    
    func updateUserName(_ name: String) {
        // Clean the input: lowercase, alphanumeric only
        let cleanedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        
        // Ensure username always starts with @
        if cleanedName.isEmpty {
            userName = "@thriftuser438"
        } else {
            userName = "@" + cleanedName
        }
        saveUserData()
    }
    
    func addWordsWritten(_ wordCount: Int) {
        totalWordsWritten += wordCount
        saveUserData()
    }
    
    func countWordsInText(_ text: String) -> Int {
        // Handle empty or whitespace-only text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return 0
        }
        
        // Split by whitespace and newlines, filter out empty strings
        let words = trimmedText.components(separatedBy: .whitespacesAndNewlines)
        let validWords = words.filter { !$0.isEmpty }
        
        return validWords.count
    }
    
    func calculateTotalProfit(from songManager: SongManager) -> Double {
        var totalProfit: Double = 0.0
        
        for song in songManager.songs {
            // Get saved values for this song
            let savedAvgPrice = UserDefaults.standard.double(forKey: "avgPrice_\(song.id)")
            let savedSellPrice = UserDefaults.standard.double(forKey: "sellPrice_\(song.id)")
            let savedProfitOverride = UserDefaults.standard.string(forKey: "profitOverride_\(song.id)") ?? ""
            let savedUseCustomProfit = UserDefaults.standard.bool(forKey: "useCustomProfit_\(song.id)")
            
            // Calculate profit for this song
            if savedUseCustomProfit && !savedProfitOverride.isEmpty {
                totalProfit += Double(savedProfitOverride) ?? 0
            } else if savedAvgPrice > 0 && savedSellPrice > 0 {
                totalProfit += savedSellPrice - savedAvgPrice
            }
        }
        
        return totalProfit
    }
    
    func triggerProfitRefresh() {
        profitRefreshTrigger += 1
    }
    
    func saveUserData() {
        UserDefaults.standard.set(userName, forKey: userNameKey)
        UserDefaults.standard.set(profilePicture, forKey: profilePictureKey)
        UserDefaults.standard.set(totalWordsWritten, forKey: totalWordsKey)
        
        // Save custom image data
        if let customImage = customProfileImage,
           let imageData = customImage.jpegData(compressionQuality: 0.7) {
            UserDefaults.standard.set(imageData, forKey: customImageKey)
        }
    }
    
    private func loadUserData() {
        let loadedName = UserDefaults.standard.string(forKey: userNameKey) ?? "@thriftuser438"
        // Clean and validate loaded username
        let nameWithoutAt = loadedName.hasPrefix("@") ? String(loadedName.dropFirst()) : loadedName
        let cleanedName = nameWithoutAt.lowercased().filter { $0.isLetter || $0.isNumber }
        
        if cleanedName.isEmpty {
            userName = "@thriftuser438"
        } else {
            userName = "@" + cleanedName
        }
        
        profilePicture = UserDefaults.standard.string(forKey: profilePictureKey) ?? "tool-bg4"
        totalWordsWritten = UserDefaults.standard.integer(forKey: totalWordsKey)
        
        // Load custom image
        if let imageData = UserDefaults.standard.data(forKey: customImageKey),
           let image = UIImage(data: imageData) {
            customProfileImage = image
        }
    }
}



// Update MainAppView to use ProfileManager
struct MainAppView: View {
    @State private var selectedTab = 0
    @StateObject private var audioManager = AudioManager()
    @StateObject private var songManager = SongManager()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var streakManager = StreakManager()
    @ObservedObject private var authManager = AuthenticationManager.shared
    private let usageTracker = AppUsageTracker.shared
    @StateObject private var recentFindsManager = RecentFindsManager()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showCameraFlow = true  // Start with camera open
    @State private var showThriftAnalysis = false
    @State private var currentAnalysisSong: Song?
    @State private var showFirstTimeCongratsPopup = false
    @State private var shouldTriggerMapUnlock = false
    @State private var triggerMapUnlockAnimation = false
    
    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            // Main content based on selected tab
                mainContent
                
                // Custom Tab Bar
                customTabBar
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            // Check if user should see first-time congrats popup
            checkAndPrepareFirstTimeFlow()
            
            // Start usage tracking session
            usageTracker.startSession()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // Auto-show camera when app becomes active (returns from background)
                if !showCameraFlow {
                    showCameraFlow = true
                }
                // Start new session
                usageTracker.startSession()
            case .inactive, .background:
                // End session when app goes to background
                usageTracker.endSession()
            @unknown default:
                break
            }
        }
        .onChange(of: showCameraFlow) { isShowing in
            // When camera is dismissed (without taking photos), check if we should trigger map unlock
            if !isShowing && shouldTriggerMapUnlock {
                triggerMapUnlockSequence()
            }
        }
        // Camera Flow Overlay (no fullScreenCover - direct ZStack)
        .overlay(
            Group {
                if showCameraFlow {
                    ThriftCameraView(
                        isPresented: $showCameraFlow,
                        onImagesCapture: { images in
                            print("📱 Captured \(images.count) images for thrift analysis")
                            
                            // Track scan for consumption data
                            usageTracker.trackScan()
                            usageTracker.trackFeatureUsage("item_scan")
                            
                            createNewAnalysisWithImages(images)
                            showCameraFlow = false
                            
                            // Check if we should trigger map unlock after camera closes
                            if shouldTriggerMapUnlock {
                                triggerMapUnlockSequence()
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(1000) // Ensure it's on top
                }
            }
        )
        // First Time Congrats Popup Overlay (only show when camera is not active)
        .overlay(
            Group {
                if showFirstTimeCongratsPopup && !showCameraFlow {
                    FirstTimeCongratsPopup(
                        isPresented: $showFirstTimeCongratsPopup,
                        onDismiss: {
                            authManager.markFirstTimeCongratsPopupSeen()
                        }
                    )
                    .zIndex(2000) // Higher than camera overlay
                }
            }
        )
        // Thrift Analysis Edit View
        .sheet(isPresented: $showThriftAnalysis) {
            if let song = currentAnalysisSong {
                SongEditView(
                    songManager: songManager,
                    song: song,
                    recentFindsManager: recentFindsManager,
                    onDismiss: {
                        showThriftAnalysis = false
                        currentAnalysisSong = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
            Group {
                if selectedTab == 0 {
                homeView
                } else if selectedTab == 1 {
                recentFindsView
                } else if selectedTab == 2 {
                profileView
            }
        }
    }
    
    // MARK: - Individual Tab Views
    private var homeView: some View {
        HomeView(
            audioManager: audioManager,
            songManager: songManager,
            streakManager: streakManager,
            profileManager: profileManager,
            selectedTab: $selectedTab,
            triggerMapUnlock: $triggerMapUnlockAnimation,
            onMapUnlockCompleted: {
                // Show popup after map unlock animation completes
                showFirstTimeCongratsPopupAfterMapUnlock()
            }
        )
    }
    
    
    private var recentFindsView: some View {
        RecentFindsPageView(
            songManager: songManager,
            audioManager: audioManager,
            profileManager: profileManager
        )
    }
    
    private var profileView: some View {
        ProfileView(
            profileManager: profileManager,
            songManager: songManager,
            streakManager: streakManager
        )
    }
    
    // MARK: - Custom Tab Bar
    private var customTabBar: some View {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                tabBarContent
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
            .background(tabBarBackground)
        }
    }
    
    // MARK: - Tab Bar Content
    private var tabBarContent: some View {
                    HStack(spacing: 0) {
                        // Left side - group the 3 main tabs with better spacing
                        HStack(spacing: 45) { // Spacing between tab items
                            // Home Tab
                            Button(action: { selectedTab = 0 }) {
                                VStack(spacing: 4) {
                                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(selectedTab == 0 ? .black : .gray)
                                    
                                    Text("Home")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(selectedTab == 0 ? .black : .gray)
                                }
                            }
                            
                            // Analytics Tab (Bar Chart Icon)
                            Button(action: { selectedTab = 1 }) {
                                VStack(spacing: 4) {
                                    Image(systemName: selectedTab == 1 ? "chart.bar.fill" : "chart.bar")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(selectedTab == 1 ? .black : .gray)
                                    
                                    Text("Analytics")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(selectedTab == 1 ? .black : .gray)
                                }
                            }
                            
                            // Settings Tab (changed from Profile to match your design)
                            Button(action: { selectedTab = 2 }) {
                                VStack(spacing: 4) {
                                    Image(systemName: selectedTab == 2 ? "gearshape.fill" : "gearshape")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(selectedTab == 2 ? .black : .gray)
                                    
                                    Text("Settings")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(selectedTab == 2 ? .black : .gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 32) // More padding from edge for home icon
                        
                        // Right side - Plus button moved more to the left
                        HStack {
                            Spacer()
                            plusButton
                                .offset(x: -20, y: -32) // Move left and up to sit on top of tab bar
                        }
                        .frame(width: 80) // Wider frame to accommodate left offset
        }
    }
    
    // MARK: - Plus Button
    private var plusButton: some View {
                        Button(action: {
                            showCameraFlow = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
    }
    
    
    // MARK: - Profile Image
    @ViewBuilder
    private var profileImage: some View {
                            if let customImage = profileManager.customProfileImage {
                                Image(uiImage: customImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 30, height: 30)
                                    .clipShape(Circle())
                .overlay(profileImageOverlay)
                            } else {
                                Image(profileManager.profilePicture)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 30, height: 30)
                                    .clipShape(Circle())
                .overlay(profileImageOverlay)
        }
    }
    
    // MARK: - Profile Image Overlay
    private var profileImageOverlay: some View {
                                        Circle()
                                            .stroke(selectedTab == 1 ? Color(red: 0.83, green: 0.69, blue: 0.52) : Color.clear, lineWidth: 2)
    }
    
    // MARK: - Tab Bar Background
    private var tabBarBackground: some View {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 0.5)
                            Rectangle()
                                .fill(Color.white)
        .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
                                .ignoresSafeArea(.all, edges: .bottom)
        }
    }
    
    // MARK: - Camera Integration
    private func createNewAnalysisWithImages(_ capturedImages: [UIImage]) {
        guard !capturedImages.isEmpty else { 
            print("⚠️ No images captured, skipping thrift analysis")
            return 
        }
        
        print("🔍 Creating new thrift analysis for \(capturedImages.count) images...")
        
        // Track analysis creation for consumption data
        usageTracker.trackFeatureUsage("price_analysis")
        
        // Track API calls that will be made for this analysis
        ConsumptionRequestService.shared.trackOpenAICall(successful: true, estimatedCostCents: 15) // 3 OpenAI calls
        ConsumptionRequestService.shared.trackSerpAPICall(successful: true, estimatedCostCents: 5)   // 1 SerpAPI call
        ConsumptionRequestService.shared.trackFirebaseCall(successful: true, estimatedCostCents: 1)  // Firebase storage
        
        // Track successful analysis once market data is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            usageTracker.trackSuccessfulAnalysis()
        }
        
        // Create a new song entry for the thrift analysis
        var newSong = Song(
            title: "Analyzing...",
            lyrics: "",
            imageName: "default",
            useWaveformDesign: false,
            lastEdited: Date()
        )
        
        // Set the first captured image as the main image (for SerpAPI)
        if let firstImage = capturedImages.first {
            newSong.customImage = firstImage
            
            // Check if we have pre-analyzed results from camera flow
            if let cachedTitle = AnalysisResultsCache.shared.getGeneratedTitle(for: firstImage) {
                newSong.title = cachedTitle
                print("📝 Using pre-generated title: \(cachedTitle)")
            }
        }
        
        // Clear any existing cache for this new song to prevent old results from showing
        MarketDataCache.shared.removeMarketData(for: newSong.id.uuidString, hasCustomImage: true)
        MarketDataCache.shared.removeMarketData(for: newSong.id.uuidString, hasCustomImage: false)
        
        // Also clear generic thrift search query cache to prevent cached results for new images
        let genericSearchQuery = "vintage fashion clothing accessories thrift"
        MarketDataCache.shared.removeMarketDataByQuery(searchQuery: genericSearchQuery, hasCustomImage: true)
        MarketDataCache.shared.removeMarketDataByQuery(searchQuery: genericSearchQuery, hasCustomImage: false)
        
        print("🗑️ Cleared cached data for new thrift analysis song and generic search queries")
        
        // Add the song to the manager (this will automatically add it to recents)
        songManager.addSong(newSong)
        
        print("✅ Thrift analysis entry created for '\(newSong.title)' (ID: \(newSong.id)) - ready for analysis")
        
        // Create a RecentFind entry for the Profit Tracker
        createRecentFindFromAnalysis(song: newSong, capturedImages: capturedImages)
        
        // Skip immediate analysis - let the background task from camera flow handle it
        // This avoids duplicate uploads and API calls
        
        // Show the thrift analysis edit view
        currentAnalysisSong = newSong
        showThriftAnalysis = true
    }
    
    // MARK: - Recent Find Creation
    private func createRecentFindFromAnalysis(song: Song, capturedImages: [UIImage]) {
        // Extract item details from the song title and analysis
        let itemName = song.title == "Analyzing..." ? "New Thrift Find" : song.title
        
        // Determine category based on item name
        let category = categorizeItem(name: itemName)
        
        // Generate estimated value based on category and item type
        let estimatedValue = generateEstimatedValue(for: itemName, category: category)
        
        // Determine condition (default to good for new finds)
        let condition = "8/10"
        
        // Extract brand if possible from the name
        let brand = extractBrand(from: itemName)
        
        // Default location
        let location = "Recent Scan"
        
        // Convert first captured image to Data for storage
        let imageData: Data? = capturedImages.first?.jpegData(compressionQuality: 0.8)
        
        // Debug logging for image data
        if let imageData = imageData {
            print("📷 Successfully converted image to data: \(imageData.count) bytes")
        } else {
            print("⚠️ Failed to convert captured image to data. Captured images count: \(capturedImages.count)")
        }
        
        // Create the RecentFind
        let recentFind = RecentFind(
            id: UUID(),
            name: itemName,
            category: category,
            estimatedValue: estimatedValue,
            condition: condition,
            brand: brand,
            location: location,
            dateFound: Date(),
            notes: "Scanned with camera analysis",
            imageData: imageData
        )
        
        // Add to recent finds manager
        recentFindsManager.addRecentFind(recentFind)
        
        print("📱 Added new recent find: \(itemName) - $\(estimatedValue)")
        print("🆔 Recent find ID: \(recentFind.id)")
        print("📊 Total recent finds: \(recentFindsManager.recentFinds.count)")
    }
    
    private func categorizeItem(name: String) -> String {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("jordan") || lowercaseName.contains("nike") || lowercaseName.contains("sneaker") || lowercaseName.contains("shoe") {
            return "Sneakers"
        } else if lowercaseName.contains("bag") || lowercaseName.contains("purse") || lowercaseName.contains("handbag") || lowercaseName.contains("coach") {
            return "Accessories"
        } else if lowercaseName.contains("hoodie") || lowercaseName.contains("shirt") || lowercaseName.contains("jacket") || lowercaseName.contains("clothing") || lowercaseName.contains("dress") {
            return "Clothing"
        } else if lowercaseName.contains("lamp") || lowercaseName.contains("vase") || lowercaseName.contains("decor") {
            return "Home Decor"
        } else {
            return "Clothing" // Default category
        }
    }
    
    private func generateEstimatedValue(for name: String, category: String) -> Double {
        let lowercaseName = name.lowercased()
        
        // High-value items
        if lowercaseName.contains("jordan") || lowercaseName.contains("nike") {
            return Double.random(in: 80...250)
        } else if lowercaseName.contains("coach") || lowercaseName.contains("designer") {
            return Double.random(in: 50...200)
        } else if lowercaseName.contains("vintage") {
            return Double.random(in: 25...100)
        } else {
            // Category-based defaults
            switch category {
            case "Sneakers":
                return Double.random(in: 30...120)
            case "Accessories":
                return Double.random(in: 20...80)
            case "Clothing":
                return Double.random(in: 15...60)
            case "Home Decor":
                return Double.random(in: 10...50)
            default:
                return Double.random(in: 10...40)
            }
        }
    }
    
    private func extractBrand(from name: String) -> String? {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("nike") {
            return "Nike"
        } else if lowercaseName.contains("jordan") {
            return "Nike"
        } else if lowercaseName.contains("coach") {
            return "Coach"
        } else if lowercaseName.contains("ecko") {
            return "Ecko Unltd"
        } else if lowercaseName.contains("levi") {
            return "Levi's"
        } else {
            return nil
        }
    }
    
    // MARK: - Update Recent Find
    private func updateRecentFindTitle(songId: UUID, newTitle: String) {
        // Find the recent find that corresponds to this song and update it
        if let findIndex = recentFindsManager.recentFinds.firstIndex(where: { find in
            // Match by approximate time (within 10 minutes) and if the current name is generic
            let timeDifference = abs(find.dateFound.timeIntervalSince(Date()))
            return timeDifference < 600 && (find.name == "New Thrift Find" || find.name == "Analyzing...")
        }) {
            // Create updated find with new information
            let oldFind = recentFindsManager.recentFinds[findIndex]
            let category = categorizeItem(name: newTitle)
            let estimatedValue = generateEstimatedValue(for: newTitle, category: category)
            let brand = extractBrand(from: newTitle)
            
            let updatedFind = RecentFind(
                id: oldFind.id,
                name: newTitle,
                category: category,
                estimatedValue: estimatedValue,
                condition: oldFind.condition,
                brand: brand,
                location: oldFind.location,
                dateFound: oldFind.dateFound,
                notes: oldFind.notes,
                imageData: oldFind.imageData
            )
            
            // Replace the old find with updated one
            recentFindsManager.recentFinds[findIndex] = updatedFind
            recentFindsManager.saveFinds()
            
            print("🔄 Updated recent find: \(oldFind.name) → \(newTitle)")
        }
    }
    
    // MARK: - Photo Upload Analysis
    private func performUploadAnalysis(for image: UIImage, songId: UUID) async {
        print("🔍 Starting parallel analysis for uploaded photo...")
        
        do {
            // Run clothing analysis and title generation in parallel
            async let clothingAnalysis = performUploadClothingAnalysis(for: image)
            async let titleGeneration = performUploadTitleGeneration(for: image)
            
            let (clothingDetails, generatedTitle) = try await (clothingAnalysis, titleGeneration)
            
            await MainActor.run {
                // Store results in cache for immediate use
                if let details = clothingDetails {
                    AnalysisResultsCache.shared.storeClothingDetails(details, for: image)
                }
                if let title = generatedTitle {
                    AnalysisResultsCache.shared.storeGeneratedTitle(title, for: image)
                    
                    // Update the song title if it's still "Analyzing..."
                    if let songIndex = songManager.songs.firstIndex(where: { $0.id == songId }),
                       songManager.songs[songIndex].title == "Analyzing..." {
                        songManager.songs[songIndex].title = title
                        // Also update the corresponding recent find
                        updateRecentFindFromAnalysis(recentFindsManager: recentFindsManager, songId: songId, newTitle: title)
                    }
                }
                print("✅ Upload analysis complete - results cached")
            }
        } catch {
            print("❌ Upload analysis failed: \(error)")
        }
    }
    
    private func performUploadClothingAnalysis(for image: UIImage) async throws -> ClothingDetails? {
        let prompt = """
        Analyze this clothing item and provide details in this exact JSON format:
        {
            "brand": "brand name or 'Unknown'",
            "category": "category like 'Shirt', 'Pants', 'Dress', etc.",
            "color": "primary color",
            "size": "size if visible or 'Unknown'",
            "material": "material type if visible or 'Unknown'",
            "style": "style description",
            "condition": "condition assessment",
            "estimatedValue": "estimated resale value or 'Unknown'",
            "isAuthentic": true/false or null if unknown
        }
        Be specific and accurate. If information isn't clearly visible, use 'Unknown' or null.
        """
        
        do {
            let response = try await OpenAIService.shared.generateVisionCompletion(
                prompt: prompt,
                images: [image],
                maxTokens: 500,
                temperature: 0.3
            )
            
            return parseUploadClothingDetailsResponse(response)
        } catch {
            print("🔍 Upload clothing analysis failed: \(error)")
            return nil
        }
    }
    
    private func performUploadTitleGeneration(for image: UIImage) async throws -> String? {
        let prompt = """
        Generate a concise, descriptive title for this thrift item for resale. 
        Format: [Brand/Style] [Type] [Key Features]
        Examples: "Vintage Levi's Denim Jacket", "Nike Air Force 1 Sneakers", "Floral Midi Dress"
        Keep it under 6 words and focus on the most sellable aspects.
        """
        
        do {
            let response = try await OpenAIService.shared.generateVisionCompletion(
                prompt: prompt,
                images: [image],
                maxTokens: 50,
                temperature: 0.7
            )
            
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("🏷️ Upload title generation failed: \(error)")
            return nil
        }
    }
    
    private func parseUploadClothingDetailsResponse(_ response: String) -> ClothingDetails? {
        // Extract JSON from response if it contains other text
        let jsonStart = response.firstIndex(of: "{") ?? response.startIndex
        let jsonEnd = response.lastIndex(of: "}") ?? response.endIndex
        let jsonString = String(response[jsonStart...jsonEnd])
        
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ClothingDetails.self, from: data)
        } catch {
            print("🔍 Failed to decode upload clothing details: \(error)")
            return nil
        }
    }
    
    // MARK: - First Time Congrats Popup Logic
    private func checkAndPrepareFirstTimeFlow() {
        // Only prepare if user hasn't seen it and has completed subscription (first time reaching main app)
        if !authManager.hasSeenFirstTimeCongratsPopup && authManager.hasCompletedSubscription {
            shouldTriggerMapUnlock = true
            print("🎉 First time user detected - will trigger map unlock after camera closes")
        }
    }
    
    private func triggerMapUnlockSequence() {
        shouldTriggerMapUnlock = false
        
        // Wait a moment for camera to fully close, then switch to home tab and trigger map unlock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            selectedTab = 0 // Ensure we're on home tab
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Trigger map unlock animation via binding
                triggerMapUnlockAnimation = true
            }
        }
    }
    
    private func showFirstTimeCongratsPopupAfterMapUnlock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showFirstTimeCongratsPopup = true
            }
        }
    }
}

// Streak Manager for tracking writing streaks
@MainActor
class StreakManager: ObservableObject {
    @Published var currentStreak: Int = 0
    @Published var writingDays: Set<Date> = []
    @Published var debugDayOffset: Int = 0 // For debug purposes
    @Published var isDebugSkipActive: Bool = false // Prevent auto-adding during debug skip
    
    private let calendar = Calendar.current
    private let writingDaysKey = "StreakManager_WritingDays"
    private let debugOffsetKey = "StreakManager_DebugOffset"
    private let lastAppOpenKey = "StreakManager_LastAppOpen"
    
    init() {
        // Defer heavy operations to avoid blocking the main thread
        DispatchQueue.main.async { [weak self] in
            self?.loadData()
            self?.trackAppOpening()
            self?.updateStreak()
        }
    }
    
    // Get the current effective date (real date + debug offset)
    var currentEffectiveDate: Date {
        let realDate = Date()
        return calendar.date(byAdding: .day, value: debugDayOffset, to: realDate) ?? realDate
    }
    
    func addWritingDay(_ date: Date? = nil) {
        let targetDate = date ?? currentEffectiveDate
        let startOfDay = calendar.startOfDay(for: targetDate)
        
        // Don't add days during debug skip simulation
        if isDebugSkipActive && calendar.isDate(startOfDay, inSameDayAs: currentEffectiveDate) {
            print("🐛 Prevented adding skipped day during debug simulation")
            return
        }
        
        writingDays.insert(startOfDay)
        updateStreak()
        saveData()
    }
    
    func hasWrittenOnDate(_ date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return writingDays.contains(startOfDay)
    }
    
    // Debug function to advance the day by 1
    func advanceDebugDay() {
        isDebugSkipActive = false // Clear skip flag for normal advance
        debugDayOffset += 1
        
        // Automatically add the new day as a writing day to maintain streak
        let newToday = calendar.startOfDay(for: currentEffectiveDate)
        writingDays.insert(newToday)
        
        updateStreak()
        saveData()
        print("🐛 Advanced debug day by 1. Current offset: \(debugDayOffset)")
        print("🐛 Effective current date: \(currentEffectiveDate)")
        print("🐛 Added new day to writing streak: \(newToday)")
    }
    
    // Debug function to skip a day (advance without adding to streak)
    func skipDebugDay() {
        isDebugSkipActive = true // Prevent auto-adding during skip
        debugDayOffset += 1
        
        // Explicitly remove the new "today" from writing days if it exists
        let skippedToday = calendar.startOfDay(for: currentEffectiveDate)
        writingDays.remove(skippedToday)
        
        updateStreak()
        saveData()
        print("🐛 Skipped a day. Current offset: \(debugDayOffset)")
        print("🐛 Effective current date: \(currentEffectiveDate)")
        print("🐛 SKIPPED day - removed from writing streak if it existed")
        print("🐛 Current streak after skip: \(currentStreak)")
    }
    
    // Reset debug offset back to real time
    func resetDebugDay() {
        debugDayOffset = 0
        isDebugSkipActive = false // Clear skip flag on reset
        updateStreak()
        saveData()
        print("🐛 Reset debug day offset")
        print("🐛 Cleared debug skip flag - normal app behavior resumed")
    }
    
    // Track when user opens the app
    func trackAppOpening() {
        // Don't auto-add days during debug skip simulation
        if isDebugSkipActive {
            print("📱 Skipping auto-add during debug skip simulation")
            return
        }
        
        let today = calendar.startOfDay(for: currentEffectiveDate)
        let lastOpenString = UserDefaults.standard.string(forKey: lastAppOpenKey) ?? ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let todayString = dateFormatter.string(from: today)
        
        // If this is the first time opening today, add it as a writing day
        if lastOpenString != todayString {
            addWritingDay(today)
            UserDefaults.standard.set(todayString, forKey: lastAppOpenKey)
            print("📱 App opened for first time today - added to streak!")
        }
    }
    
    private func updateStreak() {
        currentStreak = calculateCurrentStreak()
    }
    
    func calculateCurrentStreak() -> Int {
        let today = calendar.startOfDay(for: currentEffectiveDate)
        var streak = 0
        var currentDate = today
        
        // Only count streak if today is included (user opened app today)
        if !hasWrittenOnDate(today) {
            return 0
        }
        
        // Count consecutive days backwards from today
        while hasWrittenOnDate(currentDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = previousDay
        }
        
        return streak
    }
    
    func saveData() {
        // Save writing days
        let dateArray = Array(writingDays)
        if let encoded = try? JSONEncoder().encode(dateArray) {
            UserDefaults.standard.set(encoded, forKey: writingDaysKey)
        }
        
        // Save debug offset
        UserDefaults.standard.set(debugDayOffset, forKey: debugOffsetKey)
    }
    
    private func loadData() {
        // Load writing days
        if let data = UserDefaults.standard.data(forKey: writingDaysKey),
           let decoded = try? JSONDecoder().decode([Date].self, from: data) {
            writingDays = Set(decoded)
        }
        
        // Load debug offset
        debugDayOffset = UserDefaults.standard.integer(forKey: debugOffsetKey)
    }
}

// Streak Calendar View matching Figma design
struct StreakCalendarView: View {
    @ObservedObject var streakManager: StreakManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var songManager: SongManager
    @State private var giftAnimating = false
    @Binding var showGiftNotification: Bool
    @Binding var giftBoxPosition: CGPoint

    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    private var weekDays: [Date] {
        let effectiveToday = streakManager.currentEffectiveDate
        let startOfToday = calendar.startOfDay(for: effectiveToday)
        
        // Create 7 days centered around today, with today in the second position (index 1)
        return (-1..<6).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfToday)
        }
    }
    
    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: streakManager.currentEffectiveDate)
    }
    
    private func isFourthDayFromToday(_ date: Date) -> Bool {
        // Use account creation date, not current date, so gift has a fixed date
        let accountCreationDate = getAccountCreationDate()
        let giftDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 4, to: accountCreationDate) ?? accountCreationDate)
        let checkDate = calendar.startOfDay(for: date)
        return calendar.isDate(giftDate, inSameDayAs: checkDate)
    }
    
    private func getAccountCreationDate() -> Date {
        let userDefaults = UserDefaults.standard
        let accountCreationKey = "AccountCreationDate"
        
        if let savedDate = userDefaults.object(forKey: accountCreationKey) as? Date {
            return savedDate
        } else {
            // First time - set account creation date to today
            let today = calendar.startOfDay(for: Date())
            userDefaults.set(today, forKey: accountCreationKey)
            return today
        }
    }
    
    private func isPartOfCurrentStreak(_ date: Date) -> Bool {
        // Check if this date is part of the current streak
        let today = calendar.startOfDay(for: streakManager.currentEffectiveDate)
        let checkDate = calendar.startOfDay(for: date)
        
        // If it's a future date, it's not part of current streak
        if checkDate > today {
            return false
        }
        
        // If today doesn't have activity, there's no current streak
        if !streakManager.hasWrittenOnDate(today) {
            return false
        }
        
        // Check if there's an unbroken chain from today back to this date
        var currentDate = today
        while currentDate >= checkDate {
            if !streakManager.hasWrittenOnDate(currentDate) {
                return false
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = previousDay
        }
        
        return true
    }
    
    var body: some View {
        ZStack {
        VStack(spacing: 8) {
        // Calendar week view
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { date in
                    let isStreakDay = isPartOfCurrentStreak(date)
                    let isTodayDate = isToday(date)
                    let isGiftDay = isFourthDayFromToday(date)
                    
                VStack(spacing: 8) {
                    // Show gift emoji for 4th day, regular circle for others
                    if isGiftDay {
                        // Gift emoji with pulse and gentle movement animation
                        GeometryReader { geometry in
                            Text("🎁")
                                .font(.system(size: 32))
                                .scaleEffect(giftAnimating ? 1.3 : 1.0)
                                .rotationEffect(.degrees(giftAnimating ? 8 : -8))
                                .opacity(giftAnimating ? 1.0 : 0.9)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: giftAnimating)
                                .onAppear {
                                    giftAnimating = true
                                    // Capture the gift box position
                                    let frame = geometry.frame(in: .global)
                                    giftBoxPosition = CGPoint(
                                        x: frame.midX,
                                        y: frame.midY
                                    )
                                }
                                .onDisappear {
                                    giftAnimating = false
                                }
                                .onTapGesture {
                                    triggerGiftNotification()
                                }
                        }
                        .frame(width: 32, height: 32)
                    } else {
                    // Consistent dashed circle design for all days
                    ZStack {
                        Circle()
                            .stroke(
                                style: StrokeStyle(
                                    lineWidth: 1.5,
                                    lineCap: .round,
                                    dash: [4.5, 4.5] // Dashed design for all days
                                )
                            )
                            .foregroundStyle(
                                isStreakDay ? 
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.96, green: 0.87, blue: 0.70),  // Light beige
                                        Color(red: 0.83, green: 0.69, blue: 0.52),  // Medium beige
                                        Color(red: 0.76, green: 0.60, blue: 0.42),  // Darker beige
                                        Color(red: 0.96, green: 0.87, blue: 0.70)   // Back to light
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) : 
                                LinearGradient(
                                    gradient: Gradient(colors: [.black.opacity(0.3), .black.opacity(0.3)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .background(
                                // Fill background for streak days
                                isStreakDay ? 
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.96, green: 0.87, blue: 0.70),  // Light beige
                                                Color(red: 0.83, green: 0.69, blue: 0.52),  // Medium beige
                                                Color(red: 0.76, green: 0.60, blue: 0.42),  // Darker beige
                                                Color(red: 0.96, green: 0.87, blue: 0.70)   // Back to light
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .opacity(0.15)
                                    )
                                : nil
                            )
                            .frame(width: 32, height: 32) // Same size for all days
                            .scaleEffect(isTodayDate ? 1.1 : 1.0)
                            .shadow(
                                color: isTodayDate ? Color(red: 0.83, green: 0.69, blue: 0.52).opacity(0.6) : .clear,
                                radius: isTodayDate ? 8 : 0,
                                x: 0,
                                y: 0
                            )
                        
                        // Day letter inside circle
                        Text(dayLetter(for: date))
                                .font(.system(size: 14, weight: isTodayDate ? .bold : .medium))
                            .foregroundColor(
                                    isStreakDay ? .black : .black.opacity(0.6)
                            )
                            .shadow(
                                    color: isTodayDate ? Color.black.opacity(0.3) : .clear,
                                    radius: isTodayDate ? 2 : 0,
                                x: 0,
                                y: 0
                            )
                                            }
                    }
                    
                    // Day number below circle (show for all days including gift day)
                    Text(dateFormatter.string(from: date))
                            .font(.system(size: 14, weight: isTodayDate ? .bold : .medium))
                        .foregroundColor(
                                isStreakDay ? .black : .black.opacity(0.8)
                        )
                        .shadow(
                                color: isTodayDate ? Color.black.opacity(0.3) : .clear,
                                radius: isTodayDate ? 2 : 0,
                            x: 0,
                            y: 0
                        )
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Debug feature: long press to simulate streak on this date
                    debugAddStreakDay(date)
                }
                
                if date != weekDays.last {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 0)
        }
        

        }
    }
    
    private func dayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        let dayName = formatter.string(from: date)
        return String(dayName.prefix(1))
    }
    
    private func triggerGiftNotification() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Show notification with animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showGiftNotification = true
        }
    }
    
    // Debug function to add/remove streak days
    private func debugAddStreakDay(_ date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        if streakManager.hasWrittenOnDate(startOfDay) {
            // Remove the day if it exists
            streakManager.writingDays.remove(startOfDay)
            print("🐛 DEBUG: Removed streak day for \(dateFormatter.string(from: date))")
        } else {
            // Add the day if it doesn't exist
            streakManager.writingDays.insert(startOfDay)
            print("🐛 DEBUG: Added streak day for \(dateFormatter.string(from: date))")
        }
        
        // Update streak and save
        streakManager.objectWillChange.send()
        streakManager.saveData()
        
        // Recalculate the current streak
        DispatchQueue.main.async {
            streakManager.currentStreak = streakManager.calculateCurrentStreak()
            print("🐛 DEBUG: Current streak updated to \(streakManager.currentStreak)")
            
            // Show which days are currently in the streak
            let sortedDays = streakManager.writingDays.sorted(by: >)
            let dayStrings = sortedDays.prefix(7).map { dateFormatter.string(from: $0) }
            print("🐛 DEBUG: Recent writing days: \(dayStrings.joined(separator: ", "))")
        }
    }
}

// Home View - Main screen with empty state
struct HomeView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var songManager: SongManager
    @ObservedObject var streakManager: StreakManager
    @ObservedObject var profileManager: ProfileManager
    @State private var scrollOffset: CGFloat = 0
    @Binding var selectedTab: Int
    @Binding var triggerMapUnlock: Bool
    @StateObject private var mapController = MapViewController()
    @StateObject private var mapService = ThriftStoreMapService()
    @State private var showGiftNotification = false
    @State private var countdownTimer: Timer?
    @State private var timeRemaining = ""
    @State private var countdownDays = 0
    @State private var countdownHours = 0
    @State private var countdownMinutes = 0
    @State private var countdownSeconds = 0
    @State private var popupScale: CGFloat = 0.1
    @State private var popupOffset: CGSize = .zero
    @State private var showPopupContent = false
    @State private var giftBoxPosition: CGPoint = .zero
    @State private var actuallyShowPopup = false
    
    // Map unlock animation states
    @State private var mapUnlockScale: CGFloat = 0.8
    @State private var mapUnlockOpacity: Double = 0.3
    @State private var showUnlockOverlay = false
    @State private var unlockAnimationCompleted = false
    
    // Debug states
    @State private var showDebugButton = false
    
    // Featured posts carousel state
    @State private var featuredPostIndex = 0
    
    // Callback for when unlock animation completes
    var onMapUnlockCompleted: (() -> Void)?
    
    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // Combined Header and Streak Calendar section with extended background
            VStack(spacing: 0) {
                // Dynamic Header
                HStack {
                    if scrollOffset <= 0 {
                        // Expanded Header
                HStack {
                    // Brand logo
                    Image("thrifty")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Debug button (only visible when enabled)
                        if showDebugButton {
                            Button(action: {
                                // Trigger debug popup flow
                                triggerDebugMapUnlock()
                            }) {
                                Text("🐛")
                                    .font(.system(size: 16))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Streak counter and money bubble side by side
                        HStack(spacing: 8) {
                            // Streak bubble
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.orange)
                                
                                Text("\(streakManager.currentStreak)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            
                            // Money bubble (same style as streak bubble)
                            HStack(spacing: 6) {
                                let totalProfit = profileManager.calculateTotalProfit(from: songManager)
                                Text("$\(String(format: "%.0f", totalProfit))")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .id(profileManager.profitRefreshTrigger)
                        }
                        .onLongPressGesture(minimumDuration: 2.0) {
                            // Long press on streak counter to toggle debug button
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showDebugButton.toggle()
                            }
                            
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                            print("🐛 Debug button toggled: \(showDebugButton)")
                        }
                    }
                        }
                    } else {
                        // Collapsed Header
                        HStack {
                            Spacer()
                            Image("thrifty")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 32)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 32)
                .padding(.bottom, 16)
                
                // Streak Calendar with embedded money bubble
                StreakCalendarView(
                    streakManager: streakManager, 
                    profileManager: profileManager,
                    songManager: songManager,
                    showGiftNotification: $showGiftNotification, 
                    giftBoxPosition: $giftBoxPosition
                )
                .padding(.top, 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(
                GeometryReader { geometry in
                    ZStack {
                        // White background for header area
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: 180 + geometry.safeAreaInsets.top)
                        
                        // Soft gradient overlay for subtle depth
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: 0.4),
                                .init(color: Color.gray.opacity(0.03), location: 0.7),
                                .init(color: Color.gray.opacity(0.08), location: 0.9),
                                .init(color: Color.gray.opacity(0.05), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .cornerRadius(20, corners: [.topLeft, .topRight])
                }
            )
            
            // Content Area with Scroll Tracking
            ScrollView {
                GeometryReader { geometry in
                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)
                
                VStack(spacing: 16) {
                    // Content with standard padding
                    VStack(spacing: 16) {
                        // Recent Finds header
                        HStack {
                            Text("Recent Finds")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            Spacer()
                        }
                        .padding(.top, 0)
                        
                        // Horizontal Scrollable Songs
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(songManager.songs) { song in
                                    AlbumCard(songManager: songManager, song: song, showDeleteButton: false, audioManager: audioManager)
                                        .frame(width: 140)
                                }
                                
                                // Add some padding at the end to show partial third item
                                Spacer()
                                    .frame(width: 70)
                            }
                            .padding(.trailing, 24)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Divider line - extends to screen edges
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.top, 32)
                        .padding(.bottom, 16)
                    
                    // Thrifts Near Me section
                    VStack(spacing: 16) {
                        // Section header
                        HStack {
                            Text("Thrifts Near Me")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            Spacer()
                        }
                        
                        // Map View with Zoom Controls
                        ZStack(alignment: .topTrailing) {
                            GoogleMapsView(mapService: mapService, mapController: mapController)
                                .frame(height: 250)
                                .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                .preferredColorScheme(.light)
                                .scaleEffect(mapUnlockScale)
                                .opacity(mapUnlockOpacity)
                                .overlay(
                                    // Unlock animation overlay
                                    Group {
                                        if showUnlockOverlay {
                                            ZStack {
                                                // Semi-transparent background
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(Color.black.opacity(0.7))
                                                
                                                VStack(spacing: 12) {
                                                    // Lock icon that transforms to unlock
                                                    Image(systemName: unlockAnimationCompleted ? "lock.open.fill" : "lock.fill")
                                                        .font(.system(size: 40, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .scaleEffect(unlockAnimationCompleted ? 1.2 : 1.0)
                                                        .rotationEffect(.degrees(unlockAnimationCompleted ? 10 : 0))
                                                    
                                                    Text("Map Unlocked!")
                                                        .font(.system(size: 18, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .opacity(unlockAnimationCompleted ? 1.0 : 0.0)
                                                }
                                            }
                                            .transition(.opacity)
                                        }
                                    }
                                )
                                .onAppear {
                                    // Force refresh when view appears
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        // This helps with the navigation back issue
                                        print("🗺️ Map view appeared - checking for location and stores")
                                        
                                        // Ensure location tracking is active
                                        LocationManager.shared.startLocationTracking()
                                        
                                        // If we have location and no stores, trigger search
                                        if let location = LocationManager.shared.location,
                                           mapService.thriftStores.isEmpty {
                                            print("🔍 Map appeared with location but no stores - searching now...")
                                            Task {
                                                await mapService.searchNearbyThriftStores(
                                                    latitude: location.coordinate.latitude,
                                                    longitude: location.coordinate.longitude
                                                )
                                            }
                                        }
                                    }
                                }
                            
                            // Zoom Controls
                            VStack(spacing: 8) {
                                // Zoom In Button
                                Button(action: {
                                    mapController.zoomIn()
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(width: 32, height: 32)
                                        .background(.white)
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                
                                // Zoom Out Button
                                Button(action: {
                                    mapController.zoomOut()
                                }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(width: 32, height: 32)
                                        .background(.white)
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                            }
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    
                    // Divider line - extends to screen edges
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.top, 32)
                        .padding(.bottom, 16)
                    
                    // Featured Profit Users section
                    VStack(spacing: 16) {
                        // Section header - aligned with other sections
                        HStack {
                            Text("Users who profited this week 💰")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                            Spacer()
                        }
                        
                        // Tinder-style card stack
                        TinderCardStack()
                            .frame(height: 380)
                            .frame(maxWidth: .infinity) // Match map width
                            .padding(.horizontal, -12) // Compensate for parent padding to center cards
                        
                        // Facebook community button
                        Button(action: {
                            if let url = URL(string: "https://www.facebook.com/groups/954491966015035/") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image("facebook-logo-2019")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                
                                 Text("Join our Facebook group")
                                     .font(.system(size: 16, weight: .medium))
                                     .foregroundColor(.black)
                                 
                                 Spacer()
                                 
                                 Image(systemName: "arrow.right")
                                     .font(.system(size: 16, weight: .medium))
                                     .foregroundColor(.black)
                             }
                             .padding(.horizontal, 16)
                             .padding(.vertical, 16)
                             .background(
                                 RoundedRectangle(cornerRadius: 12)
                                     .fill(Color.white)
                             )
                             .overlay(
                                 RoundedRectangle(cornerRadius: 12)
                                     .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                             )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, -12) // Match the card width
                        .padding(.top, 16)
                        
                        // Reddit community button
                        Button(action: {
                            if let url = URL(string: "https://www.reddit.com/r/Flipping/") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 12) {
                                 Image("redditlogo")
                                     .resizable()
                                     .aspectRatio(contentMode: .fit)
                                     .frame(width: 24, height: 24)
                                
                                Text("Join r/flipping")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                         .frame(maxWidth: .infinity)
                         .padding(.horizontal, -12) // Match the card width
                         .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100) // Bottom padding to account for tab bar
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
        .background(Color.thriftyBackground)
        .navigationBarHidden(true)
        .onAppear {
            print("🏠 HomeView appeared - ensuring location tracking is active")
            // Ensure location tracking is started when home view appears
            LocationManager.shared.startLocationTracking()
        }
        .onChange(of: triggerMapUnlock) { shouldTrigger in
            if shouldTrigger {
                triggerMapUnlockAnimation()
                // Reset the trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    triggerMapUnlock = false
                }
            }
        }
        
        // Gift notification overlay - appears over entire screen
        if actuallyShowPopup {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showGiftNotification = false
                }
            
            VStack(spacing: 16) {
                if showPopupContent {
                    Text("🎁")
                        .font(.system(size: 48))
                        .opacity(showPopupContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.1), value: showPopupContent)
                    
                    Text("Unlock Secret Feature")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .opacity(showPopupContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.15), value: showPopupContent)
                    
                    // Countdown timer - formatted like the reference image
                    if !timeRemaining.isEmpty {
                        CountdownTimerView(
                            days: countdownDays,
                            hours: countdownHours,
                            minutes: countdownMinutes,
                            seconds: countdownSeconds
                        )
                        .padding(.vertical, 8)
                        .opacity(showPopupContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.2), value: showPopupContent)
                    }
                    
                    Text("You're days away from a hidden feature that most users never see.")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .opacity(showPopupContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.25), value: showPopupContent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(popupScale)
            .offset(popupOffset)
        }
        }
        .onChange(of: showGiftNotification) { isShowing in
            if isShowing {
                startCountdownTimer()
                startPopupAnimation()
            } else {
                stopCountdownTimer()
                resetPopupAnimation()
            }
        }
    }
    
    private func startCountdownTimer() {
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateCountdown()
        }
    }
    
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        timeRemaining = ""
    }
    
    private func startPopupAnimation() {
        // Calculate offset from gift box position to screen center
        let screenCenter = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
        let offsetFromGift = CGSize(
            width: giftBoxPosition.x - screenCenter.x,
            height: giftBoxPosition.y - screenCenter.y
        )
        
        // Show the popup overlay
        actuallyShowPopup = true
        
        // Start small and positioned at gift location
        popupScale = 0.1
        popupOffset = offsetFromGift
        showPopupContent = false
        
        // Animate to center position with full scale - faster and smoother
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            popupScale = 1.0
            popupOffset = .zero
        }
        
        // Show content after box animation completes - shorter delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showPopupContent = true
        }
    }
    
    private func resetPopupAnimation() {
        // Calculate offset back to gift position
        let screenCenter = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
        let offsetToGift = CGSize(
            width: giftBoxPosition.x - screenCenter.x,
            height: giftBoxPosition.y - screenCenter.y
        )
        
        // Hide content immediately
        showPopupContent = false
        
        // Animate back to gift position - faster and smoother
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            popupScale = 0.1
            popupOffset = offsetToGift
        }
        
        // Hide the popup overlay after animation completes - shorter delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            actuallyShowPopup = false
        }
    }
    
    private func getAccountCreationDate() -> Date {
        let userDefaults = UserDefaults.standard
        let accountCreationKey = "AccountCreationDate"
        let calendar = Calendar.current
        
        if let savedDate = userDefaults.object(forKey: accountCreationKey) as? Date {
            return savedDate
        } else {
            // First time - set account creation date to today
            let today = calendar.startOfDay(for: Date())
            userDefaults.set(today, forKey: accountCreationKey)
            return today
        }
    }
    
    private func updateCountdown() {
        let now = Date()
        let calendar = Calendar.current
        let accountCreationDate = getAccountCreationDate()
        
        // Calculate the 4th day from account creation date (fixed date)
        guard let targetDate = calendar.date(byAdding: .day, value: 4, to: accountCreationDate) else {
            timeRemaining = ""
            return
        }
        
        let timeInterval = targetDate.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            timeRemaining = "Available now!"
            stopCountdownTimer()
            return
        }
        
        let totalSeconds = Int(timeInterval)
        countdownDays = totalSeconds / 86400
        countdownHours = (totalSeconds % 86400) / 3600
        countdownMinutes = (totalSeconds % 3600) / 60
        countdownSeconds = totalSeconds % 60
        
        // Keep the old format for the timeRemaining check
        if countdownDays > 0 {
            timeRemaining = "\(countdownDays)d \(countdownHours)h \(countdownMinutes)m \(countdownSeconds)s"
        } else if countdownHours > 0 {
            timeRemaining = "\(countdownHours)h \(countdownMinutes)m \(countdownSeconds)s"
        } else if countdownMinutes > 0 {
            timeRemaining = "\(countdownMinutes)m \(countdownSeconds)s"
        } else {
            timeRemaining = "\(countdownSeconds)s"
        }
    }
    
    // MARK: - Map Unlock Animation
    func triggerMapUnlockAnimation() {
        print("🗺️ Starting map unlock animation")
        
        // Reset animation states first
        mapUnlockScale = 0.8
        mapUnlockOpacity = 0.3
        unlockAnimationCompleted = false
        
        // Show unlock overlay
        withAnimation(.easeInOut(duration: 0.5)) {
            showUnlockOverlay = true
        }
        
        // Animate map scale and opacity to full
        withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
            mapUnlockScale = 1.0
            mapUnlockOpacity = 1.0
        }
        
        // After 0.8 seconds, animate the lock to unlock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                unlockAnimationCompleted = true
            }
        }
        
        // After 2.5 seconds total, hide overlay and call completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showUnlockOverlay = false
            }
            
            // Call completion callback after overlay is hidden
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onMapUnlockCompleted?()
            }
        }
    }
    
    // MARK: - Debug Functions
    private func triggerDebugMapUnlock() {
        print("🐛 Debug: Triggering map unlock animation")
        triggerMapUnlockAnimation()
    }
    
}

// Countdown Timer View with individual boxes
struct CountdownTimerView: View {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    
    var body: some View {
        HStack(spacing: 12) {
            CountdownBox(value: days, label: "DAYS")
            CountdownBox(value: hours, label: "HOURS")
            CountdownBox(value: minutes, label: "MINUTES")
            CountdownBox(value: seconds, label: "SECONDS")
        }
    }
}

// Individual countdown box component
struct CountdownBox: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.black)
                .cornerRadius(8)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

// Preference key for tracking scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}





// Profile View - User profile with original styling
struct ProfileView: View {
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var songManager: SongManager
    @ObservedObject var streakManager: StreakManager
    @State private var showingPhotoPicker = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingSupportEmail = false
    @State private var showingCopiedFeedback = false
    @State private var showingDeleteAlert = false
    @State private var showingLogoutAlert = false
    @FocusState private var isNameFieldFocused: Bool
    
    private var totalWords: String {
        if profileManager.totalWordsWritten < 1000 {
            return "\(profileManager.totalWordsWritten)"
        } else {
            let formatted = Double(profileManager.totalWordsWritten) / 1000.0
            return String(format: "%.1fK", formatted)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Profile Header Section
        VStack(spacing: 24) {
                // Profile Picture
                Button(action: { showingPhotoPicker = true }) {
                    if let customImage = profileManager.customProfileImage {
                        Image(uiImage: customImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 3)
                            )
                    } else {
                        Image(profileManager.profilePicture)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 0.83, green: 0.69, blue: 0.52), lineWidth: 3)
                            )
                    }
                }
                .sheet(isPresented: $showingPhotoPicker) {
                    ImagePicker(image: $profileManager.customProfileImage)
                }

                // Editable Username
                VStack(spacing: 12) {
                    if isEditingName {
                        TextField("username (letters & numbers only)", text: $editedName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                profileManager.updateUserName(editedName)
                                isEditingName = false
                            }
                            .onChange(of: editedName) { newValue in
                                let filtered = newValue.lowercased().filter { $0.isLetter || $0.isNumber }
                                if filtered != newValue {
                                    editedName = filtered
                                }
                            }
                            .onAppear {
                                editedName = profileManager.userName.hasPrefix("@") ? 
                                    String(profileManager.userName.dropFirst()) : 
                                    profileManager.userName
                                isNameFieldFocused = true
                            }
                    } else {
                        Button(action: {
                            isEditingName = true
                        }) {
                            HStack(spacing: 8) {
                                Text(profileManager.userName)
                                    .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                    
                                Image(systemName: "pencil")
                        .font(.system(size: 16))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                    }
                }
                
                // Stats Section
                HStack(spacing: 0) {
                    // Songs
                    VStack(spacing: 6) {
                        Text("\(songManager.songs.count)")
                            .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            Text("Finds")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Profit
                    VStack(spacing: 6) {
                        let totalProfit = profileManager.calculateTotalProfit(from: songManager)
                        Text("$\(String(format: "%.0f", totalProfit))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                        Text("Total Profit")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .id(profileManager.profitRefreshTrigger) // Force refresh when trigger changes
                    
                    // Streak
                    VStack(spacing: 6) {
                        Text("\(streakManager.currentStreak)")
                            .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            Text("Thrift Streak")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    

                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 50)
            .padding(.bottom, 40)
            
            // Menu Section
            VStack(spacing: 24) {
                if showingSupportEmail {
                    // Show email address
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Contact Support")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                                
                                // Email contact
                                Button(action: {
                                    UIPasteboard.general.string = "helpthrifty@gmail.com"
                                    showingCopiedFeedback = true
                                    
                                    // Hide the feedback after 2 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        showingCopiedFeedback = false
                                    }
                                }) {
                                    Text(showingCopiedFeedback ? "Copied!" : "helpthrifty@gmail.com")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(showingCopiedFeedback ? .green : .blue)
                                        .animation(.easeInOut(duration: 0.2), value: showingCopiedFeedback)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showingSupportEmail = false
                                showingCopiedFeedback = false // Reset feedback when hiding
                            }) {
                                Text("Hide")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                    }
                } else {
                    // Menu Items Group
                    VStack(spacing: 0) {
                        // Support
                    ProfileMenuItem(
                        icon: "envelope",
                        title: "Support",
                        showChevron: false,
                        action: {
                            showingSupportEmail = true
                                showingCopiedFeedback = false
                            }
                        )
                        
                        // Divider
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 0.5)
                            .padding(.leading, 68)
                
                // Log Out
                ProfileMenuItem(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Log Out",
                    showChevron: false,
                    action: {
                        showingLogoutAlert = true
                    }
                )
                
                        // Divider
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 0.5)
                            .padding(.leading, 68)
                
                // Delete Account
                ProfileMenuItem(
                    icon: "xmark",
                    title: "Delete Account",
                    showChevron: false,
                            isDestructive: true,
                    action: {
                        showingDeleteAlert = true
                    }
                )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 4)
                }
            }
            
            Spacer(minLength: 40)
            
            // Footer
            Text("Thrifty • 2025 • v1.20.1")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.6))
                .padding(.bottom, 100)
            }
        .padding(.horizontal, 24)
        .background(Color.thriftyBackground)
        .navigationBarHidden(true)
        .onAppear {
            updateTotalWords()
        }
        .onChange(of: songManager.songs) { _ in
            updateTotalWords()
        }
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone. All your songs, progress, and data will be permanently deleted.")
        }
        .alert("Log Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                logOut()
            }
        } message: {
            Text("Are you sure you want to log out? Your data will be saved locally.")
        }
    }
    
    private func updateTotalWords() {
        let totalWords = songManager.songs.reduce(0) { total, song in
            let wordCount = profileManager.countWordsInText(song.lyrics)
            return total + wordCount
        }
        
        print("📊 Profile Stats Update:")
        print("   • Total Songs: \(songManager.songs.count)")
        print("   • Total Words: \(totalWords)")
        print("   • Songs breakdown:")
        for (_, song) in songManager.songs.enumerated() {
            let wordCount = profileManager.countWordsInText(song.lyrics)
            print("     - \(song.title): \(wordCount) words")
        }
        
        profileManager.totalWordsWritten = totalWords
    }
    
    private func deleteAccount() {
        // Clear all user data
                        profileManager.userName = "@thriftuser438"
        profileManager.customProfileImage = nil
        profileManager.totalWordsWritten = 0
        
        // Clear all songs
        songManager.songs.removeAll()
        
        // Clear streak data
        streakManager.writingDays.removeAll()
        streakManager.currentStreak = 0
        streakManager.debugDayOffset = 0
        streakManager.isDebugSkipActive = false
        
        // Clear UserDefaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "ProfileManager_UserName")
        defaults.removeObject(forKey: "ProfileManager_ProfilePicture")
        defaults.removeObject(forKey: "ProfileManager_TotalWords")
        defaults.removeObject(forKey: "ProfileManager_CustomImage")
        defaults.removeObject(forKey: "SavedSongs")
        defaults.removeObject(forKey: "StreakManager_WritingDays")
        defaults.removeObject(forKey: "StreakManager_DebugOffset")
        defaults.removeObject(forKey: "StreakManager_LastAppOpen")
        defaults.removeObject(forKey: "ToolResponses")
        
        // Save the reset profile state
        profileManager.saveUserData()
        streakManager.saveData()
        
        print("🗑️ Account deleted - all user data cleared")
        
        // Log out the user after account deletion
        AuthenticationManager.shared.logOut()
        
        print("🚪 User logged out after account deletion - redirecting to sign in")
    }
    
    private func logOut() {
        // Clear temporary states but keep user data
        showingSupportEmail = false
        isEditingName = false
        
        // Log out through authentication manager
        AuthenticationManager.shared.logOut()
        
        print("🚪 User logged out - redirecting to sign in")
    }
}

struct ProfileMenuItem: View {
    let icon: String
    let title: String
    let showChevron: Bool
    let isDestructive: Bool
    let action: () -> Void
    @State private var isPressed = false
    
    init(icon: String, title: String, showChevron: Bool, isDestructive: Bool = false, action: @escaping () -> Void = {}) {
        self.icon = icon
        self.title = title
        self.showChevron = showChevron
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon with circular background
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDestructive ? .red : .black)
                }
                
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(isDestructive ? .red : .black)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.clear)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// Global Loop Settings Manager
@MainActor
class GlobalLoopSettings: ObservableObject {
    static let shared = GlobalLoopSettings()
    
    @Published var hasPendingLoop: Bool = false
    @Published var pendingLoopStart: TimeInterval = 0
    @Published var pendingLoopEnd: TimeInterval = 0
    
    private init() {}
    
    func setPendingLoop(start: TimeInterval, end: TimeInterval) {
        hasPendingLoop = true
        pendingLoopStart = start
        pendingLoopEnd = end
        print("🔄 Set pending loop: \(formatTime(start)) to \(formatTime(end))")
    }
    
    func clearPendingLoop() {
        hasPendingLoop = false
        pendingLoopStart = 0
        pendingLoopEnd = 0
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Global Audio Manager for coordinating all audio playback
@MainActor
class GlobalAudioManager: ObservableObject {
    static let shared = GlobalAudioManager()
    
    @Published var currentPlayingManager: AudioManager?
    
    private init() {}
    
    func playAudio(_ manager: AudioManager) {
        // Stop any currently playing audio
        if let currentManager = currentPlayingManager, currentManager != manager {
            currentManager.pause()
        }
        
        // Set the new manager as current
        currentPlayingManager = manager
    }
}

// Audio Manager for handling audio playback and controls
@MainActor
class AudioManager: ObservableObject, Equatable {
    @Published var player: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLooping = false
    @Published var loopStart: TimeInterval = 0
    @Published var loopEnd: TimeInterval = 0
    @Published var hasCustomLoop = false
    @Published var audioFileName: String = ""
    
    private var timer: Timer?
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("🔊 Audio session configured successfully")
        } catch {
            print("❌ Failed to setup audio session: \(error.localizedDescription)")
        }
    }
    
    static func == (lhs: AudioManager, rhs: AudioManager) -> Bool {
        return lhs === rhs
    }
    
    func loadAudio(from url: URL) {
        do {
            // Preserve current loop settings before loading
            let wasCustomLoop = hasCustomLoop
            let savedLoopStart = loopStart
            let savedLoopEnd = loopEnd
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            audioFileName = url.lastPathComponent
            
            // Check if there are pending loop settings from the UI
            if GlobalLoopSettings.shared.hasPendingLoop {
                hasCustomLoop = true
                loopStart = GlobalLoopSettings.shared.pendingLoopStart
                loopEnd = min(GlobalLoopSettings.shared.pendingLoopEnd, duration)
                print("✅ Applied pending loop settings: \(formatTime(loopStart)) to \(formatTime(loopEnd))")
            } else {
                // Restore loop settings if they were set
                if wasCustomLoop {
                    hasCustomLoop = true
                    loopStart = savedLoopStart
                    loopEnd = min(savedLoopEnd, duration) // Ensure loop end doesn't exceed duration
                    print("🔄 Restored loop settings: \(formatTime(loopStart)) to \(formatTime(loopEnd))")
                } else {
            resetLoop()
                }
            }
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    func play() {
        guard let player = player else { return }
        
        print("🎵 Play called for: \(audioFileName)")
        print("🎵 hasCustomLoop: \(hasCustomLoop)")
        print("🎵 loopStart: \(formatTime(loopStart))")
        print("🎵 loopEnd: \(formatTime(loopEnd))")
        
        // Notify global manager to stop other audio
        GlobalAudioManager.shared.playAudio(self)
        
        // Handle custom loop settings when starting playback
        if hasCustomLoop {
            // Always start from loop start when custom loop is enabled
            player.currentTime = loopStart
            currentTime = loopStart
            print("✅ Starting playback at loop start: \(formatTime(loopStart))")
        } else {
            print("ℹ️ No custom loop, starting from current position")
        }
        
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }
    
    func toggleLoop() {
        isLooping.toggle()
        player?.numberOfLoops = isLooping ? -1 : 0
    }
    
    func setCustomLoop(start: TimeInterval, end: TimeInterval) {
        loopStart = start
        loopEnd = end
        hasCustomLoop = true
    }
    
    func resetLoop() {
        hasCustomLoop = false
        loopStart = 0
        loopEnd = duration
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let player = self.player else { return }
                self.currentTime = player.currentTime
                
                // Handle custom loop
                if self.hasCustomLoop && self.currentTime >= self.loopEnd {
                    player.currentTime = self.loopStart
                    self.currentTime = self.loopStart
                }
                
                // Check if song ended
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Shared Instrumental Manager with persistence
@MainActor
class SharedInstrumentalManager: ObservableObject {
    static let shared = SharedInstrumentalManager()
    
    @Published var instrumentals: [String] = []
    @Published var audioManagers: [String: AudioManager] = [:]
    
    private let userDefaultsKey = "SavedInstrumentals"
    private let defaultInstrumentals = [
        "10AM In The South.mp3",
        "Better Mornings.mp3", 
        "Pleasent Poetry.mp3",
        "Run It Up.mp3",
        "Yacht Parties.mp3"
    ]
    
    private init() {
        loadInstrumentals()
        initializeAudioManagers()
    }
    
    func addInstrumental(_ fileName: String, url: URL) {
        print("📥 Adding instrumental: \(fileName) from URL: \(url)")
        
        if !instrumentals.contains(fileName) {
            instrumentals.insert(fileName, at: 0)
            
            // Copy file to app's documents directory for permanent access
            if let permanentURL = copyToDocuments(file: url, fileName: fileName) {
            let newAudioManager = AudioManager()
                newAudioManager.loadAudio(from: permanentURL)
            audioManagers[fileName] = newAudioManager
                
                print("✅ Added instrumental to list and created audio manager")
                print("🎵 Audio manager has player: \(newAudioManager.player != nil)")
                print("⏱️ Duration: \(newAudioManager.duration)")
                print("📁 Copied to: \(permanentURL)")
            } else {
                print("❌ Failed to copy file to documents directory")
                // Remove from list if copy failed
                instrumentals.removeFirst()
                return
            }
            
            saveInstrumentals()
        } else {
            print("⚠️ Instrumental already exists: \(fileName)")
        }
    }
    
    // Copy file to app's documents directory for permanent access
    private func copyToDocuments(file sourceURL: URL, fileName: String) -> URL? {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            print("❌ Failed to access security scoped resource")
            return nil
        }
        
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }
        
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(fileName)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("✅ Copied \(fileName) to documents directory")
            return destinationURL
        } catch {
            print("❌ Failed to copy file: \(error)")
            return nil
        }
    }
    
    func removeInstrumental(_ fileName: String) {
        if let index = instrumentals.firstIndex(of: fileName) {
            instrumentals.remove(at: index)
            audioManagers.removeValue(forKey: fileName)
            
            // Also remove file from documents directory if it exists
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(fileName)
            
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("✅ Removed file from documents: \(fileName)")
                }
            } catch {
                print("⚠️ Failed to remove file from documents: \(error)")
            }
            
            saveInstrumentals()
        }
    }
    
    func getAudioManager(for instrumental: String) -> AudioManager {
        if let existingManager = audioManagers[instrumental] {
            // Check if existing manager has a player, if not, try to reload
            if existingManager.player == nil {
                print("🔄 Audio manager exists but no player, attempting to reload: \(instrumental)")
                loadAudioForManager(existingManager, instrumental: instrumental)
            }
            return existingManager
        } else {
            print("🔄 Creating new audio manager for missing instrumental: \(instrumental)")
            let newManager = AudioManager()
            loadAudioForManager(newManager, instrumental: instrumental)
            audioManagers[instrumental] = newManager
            return newManager
        }
    }
    
    // Helper function to load audio into a manager
    private func loadAudioForManager(_ manager: AudioManager, instrumental: String) {
        // Try to load from bundle first (for default instrumentals)
        let fileNameWithoutExtension = instrumental.replacingOccurrences(of: ".mp3", with: "").replacingOccurrences(of: ".wav", with: "").replacingOccurrences(of: ".m4a", with: "")
        if let url = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3") {
            manager.loadAudio(from: url)
            print("✅ Loaded default instrumental from bundle: \(instrumental)")
        } else {
            // Try to load from documents directory (for user-uploaded files)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(instrumental)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                manager.loadAudio(from: fileURL)
                print("✅ Loaded user instrumental from documents: \(instrumental)")
            } else {
                print("⚠️ Could not find instrumental file: \(instrumental)")
            }
        }
    }
    
    private func saveInstrumentals() {
        if let encoded = try? JSONEncoder().encode(instrumentals) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 Saved \(instrumentals.count) instrumentals to UserDefaults")
        } else {
            print("❌ Failed to encode instrumentals for saving")
        }
    }
    
    private func loadInstrumentals() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            instrumentals = decoded
            print("🎵 Loaded \(instrumentals.count) instrumentals from UserDefaults")
            print("🎵 Instrumentals list: \(instrumentals)")
            
            // Remove unwanted default instrumentals
            if let freestyleIndex = instrumentals.firstIndex(where: { $0.contains("3KFreestyle") }) {
                let freestyleFile = instrumentals[freestyleIndex]
                print("🗑️ Removing unwanted default instrumental: \(freestyleFile)")
                instrumentals.remove(at: freestyleIndex)
                saveInstrumentals()
            }
            
            // Debug: Check for problematic LoBo file
            if let loboIndex = instrumentals.firstIndex(where: { $0.contains("LoBo") }) {
                let loboFile = instrumentals[loboIndex]
                print("🚨 Found LoBo file in instrumentals: \(loboFile)")
                print("🚨 Removing it to fix persistent error...")
                instrumentals.remove(at: loboIndex)
                saveInstrumentals()
            }
        } else {
            // First time - use default instrumentals
            instrumentals = defaultInstrumentals
            saveInstrumentals()
            print("🎵 Created initial default instrumentals")
        }
    }
    
    private func initializeAudioManagers() {
        // Initialize audio managers for all instrumentals
        for instrumental in instrumentals {
            let newAudioManager = AudioManager()
            
            // Try to load from bundle first (for default instrumentals)
            if let url = Bundle.main.url(forResource: instrumental.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3") {
                newAudioManager.loadAudio(from: url)
            }
            // Note: User-added instrumentals will need to be re-added after app restart
            // This is a limitation of the file system access in iOS
            
            audioManagers[instrumental] = newAudioManager
        }
    }
}

// Instrumentals View - Audio upload and playback interface
struct SettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var showingFilePicker = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @StateObject private var sharedManager = SharedInstrumentalManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with background image like homepage and lyric tools
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Instrumentals")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Browse Files button
                    Button(action: { showingFilePicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Browse Files")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Image("tool-bg1")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 20)
            }
            .background(Color.black)  // Simple black background
            
            // Main content area with proper spacing
            VStack(spacing: 0) {
                // Instrumentals list with bottom padding to prevent cutoff
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sharedManager.instrumentals, id: \.self) { instrumental in
                            InstrumentalListItem(
                                title: instrumental,
                                audioManager: sharedManager.getAudioManager(for: instrumental),
                                onDelete: {
                                    sharedManager.removeInstrumental(instrumental)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 120)
                }
                .padding(.top, 20)
                
                Spacer()
            }
            
            // Fixed bottom section with loop controls
            VStack(spacing: 16) {
                // Loop controls - always visible
                LoopControlsView()
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 50)
            .padding(.top, 8)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.9),
                        Color.black
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingFilePicker) {
            AudioFilePicker { url in
                print("🎵 Loading audio from: \(url)")
                
                // Add the file to the shared manager
                let fileName = url.lastPathComponent
                sharedManager.addInstrumental(fileName, url: url)
            }
        }
    }
}

// Audio File Picker
struct AudioFilePicker: UIViewControllerRepresentable {
    let onFilePicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFilePicked: onFilePicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilePicked: (URL) -> Void
        
        init(onFilePicked: @escaping (URL) -> Void) {
            self.onFilePicked = onFilePicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                print("📁 File picked: \(url)")
                onFilePicked(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("❌ Document picker was cancelled")
        }
    }
}

struct AlbumCard: View {
    @ObservedObject var songManager: SongManager
    let song: Song
    let showDeleteButton: Bool
    @ObservedObject var audioManager: AudioManager
    @State private var showEditView = false

    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Button(action: { showEditView = true }) {
                    Group {
                        if let customImage = song.customImage {
                            Image(uiImage: customImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if song.useWaveformDesign {
                            // Waveform design - black background with white waveform
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black)
                                
                                Image(systemName: "waveform")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                            }
                        } else {
                            Image(song.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipped()
                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if showDeleteButton {
                    Button(action: {}) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.thriftyDeleteRed)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            }
            
            Button(action: { showEditView = true }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
            
                    Text(song.displayDate)
                .font(.system(size: 14))
                .foregroundColor(.thriftySecondaryText)
                .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showEditView) {
            SongEditView(
                songManager: songManager, 
                song: song,
                recentFindsManager: nil, // Not needed for regular song editing
                onDismiss: {
                    showEditView = false
                }
            )
        }

    }
}


// Instrumental Selector View - For choosing from uploaded instrumentals
struct InstrumentalSelectorView: View {
    @StateObject private var sharedManager = SharedInstrumentalManager.shared
    @Environment(\.dismiss) var dismiss
    let onInstrumentalSelected: (String) -> Void
    @State private var showingFilePicker = false
    
    // Available instrumental images for cycling through when new instrumentals are added
    let instrumentalImages = ["instrumental1", "instrumental2", "instrumental3", "instrumental4", "instrumental5", "instrumental6"]
    
    // Function to get the image name for each instrumental based on its index
    private func getInstrumentalImage(for index: Int) -> String {
        return instrumentalImages[index % instrumentalImages.count]
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 0) {
                    HStack {
                        // Close button
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                        
                        Spacer()
                        
                        Text("Choose Instrumental")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        // Browse Files button to add new instrumentals
                        Button(action: { showingFilePicker = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("Browse Files")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                .background(Color.black)
                
                // Instrumentals grid
                if sharedManager.instrumentals.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text("No Instrumentals Available")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Add some instrumentals to get started")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Button(action: { showingFilePicker = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("Browse Files")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                        }
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                } else {
                    // Instrumentals list
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(sharedManager.instrumentals.enumerated()), id: \.offset) { index, instrumental in
                                InstrumentalSelectorCard(
                                    title: instrumental,
                                    imageName: getInstrumentalImage(for: index),
                                    audioManager: sharedManager.getAudioManager(for: instrumental),
                                    onSelect: {
                                        onInstrumentalSelected(instrumental)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingFilePicker) {
                AudioFilePicker { url in
                    print("🎵 Loading audio from: \(url)")
                    
                    // Add the file to the shared manager
                    let fileName = url.lastPathComponent
                    sharedManager.addInstrumental(fileName, url: url)
                }
            }
        }
    }
}

// Instrumental Selector Card - For selecting instrumentals in the song editor
struct InstrumentalSelectorCard: View {
    let title: String
    let imageName: String
    @ObservedObject var audioManager: AudioManager
    let onSelect: () -> Void
    @State private var isPlaying = false
    
    private var displayTitle: String {
        return title.replacingOccurrences(of: ".mp3", with: "")
    }
    
    private var progressPercentage: Double {
        return audioManager.duration > 0 ? audioManager.currentTime / audioManager.duration : 0.0
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Top row with track info and play button - same as InstrumentalListItem
            HStack(spacing: 12) {
                // Waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(formatTime(audioManager.currentTime)) / \(formatTime(audioManager.duration))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Play button
                Button(action: {
                    if audioManager.isPlaying {
                        audioManager.pause()
                    } else {
                        // Try to load from bundle first (for default files)
                        let fileNameWithoutExtension = title.replacingOccurrences(of: ".mp3", with: "")
                        if let url = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3") {
                            audioManager.loadAudio(from: url)
                            audioManager.play()
                        } else {
                            // If not in bundle, the audio manager should already have the file loaded
                            // Just play it if it has a player
                            if audioManager.player != nil {
                                audioManager.play()
                            }
                        }
                    }
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(4)
                }
            }
            
            // Scrubber line with drag gesture - same as InstrumentalListItem
            GeometryReader { geometry in
                ZStack {
                    // Background line
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress line
                    HStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "#8B5CF6"),
                                        Color(hex: "#EC4899")
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(progressPercentage), height: 4)
                        
                        Spacer()
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = min(max(value.location.x / geometry.size.width, 0), 1)
                            let time = audioManager.duration * percentage
                            audioManager.seek(to: time)
                        }
                )
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Song Edit View - For editing lyrics
struct SongEditView: View {
    @ObservedObject var songManager: SongManager
    @State private var song: Song
    var recentFindsManager: RecentFindsManager?
    @StateObject private var serpAPIService = SerpAPIService()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var isEditingTitle = false
    @State private var showingDeleteAlert = false
    @FocusState private var isTitleFocused: Bool
    @State private var marketData: SerpSearchResult?
    @State private var isLoadingMarketData = false
    @State private var marketAnalysisError: String?
    let onDismiss: () -> Void
    // ADDED:
    @State private var hasInstrumentalLoaded: Bool = false
    @StateObject private var audioManager = AudioManager()
    @State private var displayedVisualMatches: [VisualMatch] = []
    @State private var displayedShoppingResults: [ShoppingResult] = []
    
    // Persistent deletion tracking
    @State private var deletedVisualMatchIds: Set<String> = []
    @State private var deletedShoppingResultIds: Set<String> = []
    
    // Info popup state
    @State private var showingAveragePriceInfo = false
    
    // Swipe hint animation states
    @State private var showSwipeHint = false
    @State private var swipeHintOffset: CGFloat = 0
    @State private var hasShownSwipeHint = false
    
    // Confetti animation states
    @State private var trigger = 0
    @State private var isViewFullyLoaded = false
    @State private var shouldTriggerConfettiWhenLoaded = false
    @State private var expandedImageURL: String?
    @State private var showingExpandedImage = false
    @State private var clothingDetails: ClothingDetails?
    @State private var isAnalyzingClothing = false
    @State private var isScrolling = false
    @State private var hasDeletedItems = false
    
    init(songManager: SongManager, song: Song, recentFindsManager: RecentFindsManager?, onDismiss: @escaping () -> Void) {
        self.songManager = songManager
        self.recentFindsManager = recentFindsManager
        self.onDismiss = onDismiss
        self._song = State(initialValue: song)
        
        print("🔧 SongEditView initialized for song: '\(song.title)' (ID: \(song.id))")
        
        // Check for potential duplicate initialization
        if song.title == "Analyzing..." {
            print("📊 Thrift Analysis song initialized - ID: \(song.id)")
        }
    }
    
    // MARK: - Price Helper Functions
    private func formatPriceToUSD(_ price: String?) -> String? {
        guard let priceString = price else { return nil }
        
        // Remove currency symbols but preserve commas and periods
        let cleanPrice = priceString.replacingOccurrences(of: "*", with: "")
                                   .replacingOccurrences(of: "CHF", with: "")
                                   .replacingOccurrences(of: "€", with: "")
                                   .replacingOccurrences(of: "£", with: "")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use regex to find the first price pattern (handles commas properly)
        let pattern = #"(\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\d+(?:\.\d{2})?)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: cleanPrice, options: [], range: NSRange(location: 0, length: cleanPrice.count)) {
            
            let matchString = (cleanPrice as NSString).substring(with: match.range)
            
            // Remove commas for Double conversion
            let numberString = matchString.replacingOccurrences(of: ",", with: "")
            
            if let value = Double(numberString) {
                // Apply currency conversion
            var usdValue = value
            
            if priceString.contains("CHF") {
                usdValue = value * 1.1 // CHF to USD
            } else if priceString.contains("€") {
                usdValue = value * 1.08 // EUR to USD
            } else if priceString.contains("£") {
                usdValue = value * 1.25 // GBP to USD
            }
            
                return "$\(String(format: "%.0f", usdValue))" // No decimals for cleaner display
            }
        }
        
        return cleanPrice.isEmpty ? nil : "$\(cleanPrice)"
    }
    
    // MARK: - Price Calculation Functions
    
    private func calculateOverallAveragePrice() -> Double? {
        guard let marketData = marketData else { return nil }
        
        var allPrices: [Double] = []
        
        // Collect prices from visual matches (both available and sold)
        if let visualMatches = marketData.visualMatches {
            let notDeletedMatches = getFilteredVisualMatches(visualMatches)
            let pricesFromVisual = notDeletedMatches.compactMap { match -> Double? in
                if let extractedValue = match.price?.extractedValue, extractedValue > 0 {
                    return extractedValue
                } else if let priceString = match.price?.value {
                    return extractNumericPrice(priceString)
                }
                return nil
            }
            allPrices.append(contentsOf: pricesFromVisual)
        }
        
        // Collect prices from shopping results (both available and sold)
        if let shoppingResults = marketData.shoppingResults {
            let notDeletedResults = getFilteredShoppingResults(shoppingResults)
            let pricesFromShopping = notDeletedResults.compactMap { result -> Double? in
                if let extractedPrice = result.extractedPrice, extractedPrice > 0 {
                    return extractedPrice
                } else if let priceString = result.price {
                    return extractNumericPrice(priceString)
                }
                return nil
            }
            allPrices.append(contentsOf: pricesFromShopping)
        }
        
        // Calculate average
        guard !allPrices.isEmpty else { return nil }
        return allPrices.reduce(0, +) / Double(allPrices.count)
    }
    
    // MARK: - Confetti Animation Functions
    
    private func triggerConfetti() {
        if isViewFullyLoaded {
            // View is fully loaded, trigger confetti immediately
            trigger += 1
        } else {
            // View is still loading, set flag to trigger when loaded
            shouldTriggerConfettiWhenLoaded = true
        }
    }
    
    // MARK: - Swipe Hint Animation Functions
    
    private func showSwipeHintAnimation() {
        // Only show hint once per session and if there are items
        guard !hasShownSwipeHint else { return }
        
        // Delay the hint so user can see the items first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.8)) {
                self.swipeHintOffset = -80 // Slide left to reveal delete button
                self.showSwipeHint = true
            }
            
            // Hold the position for a moment to show the delete button
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.swipeHintOffset = 0 // Slide back to original position
                }
                
                // Hide hint after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.showSwipeHint = false
                    self.hasShownSwipeHint = true
                }
            }
        }
    }
    
    // MARK: - Deletion Management Functions
    
    private func generateVisualMatchId(_ match: VisualMatch) -> String {
        return "\(match.position ?? 0)_\(match.title ?? "unknown")_\(match.source ?? "")"
    }
    
    private func generateShoppingResultId(_ result: ShoppingResult) -> String {
        return "\(result.position ?? 0)_\(result.title ?? "unknown")_\(result.source ?? "")"
    }
    
    private func loadDeletions() {
        let songId = song.id.uuidString
        
        if let deletedVisual = UserDefaults.standard.array(forKey: "deletedVisualMatches_\(songId)") as? [String] {
            deletedVisualMatchIds = Set(deletedVisual)
        }
        
        if let deletedShopping = UserDefaults.standard.array(forKey: "deletedShoppingResults_\(songId)") as? [String] {
            deletedShoppingResultIds = Set(deletedShopping)
        }
        
        print("🗑️ Loaded \(deletedVisualMatchIds.count) deleted visual matches and \(deletedShoppingResultIds.count) deleted shopping results for song: \(song.title)")
    }
    
    private func saveDeletions() {
        let songId = song.id.uuidString
        
        UserDefaults.standard.set(Array(deletedVisualMatchIds), forKey: "deletedVisualMatches_\(songId)")
        UserDefaults.standard.set(Array(deletedShoppingResultIds), forKey: "deletedShoppingResults_\(songId)")
        
        print("🗑️ Saved \(deletedVisualMatchIds.count) deleted visual matches and \(deletedShoppingResultIds.count) deleted shopping results for song: \(song.title)")
    }
    
    private func deleteVisualMatch(_ match: VisualMatch, at index: Int) {
        let matchId = generateVisualMatchId(match)
        deletedVisualMatchIds.insert(matchId)
        saveDeletions()
        
        // Set flag to prevent auto-loading more results
        hasDeletedItems = true
        
        // Remove from displayed array with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            if index < displayedVisualMatches.count {
                displayedVisualMatches.remove(at: index)
            }
        }
        
        print("🗑️ Deleted visual match: \(match.title ?? "Unknown") from \(match.source ?? "Unknown source")")
    }
    
    private func deleteShoppingResult(_ result: ShoppingResult, at index: Int) {
        let resultId = generateShoppingResultId(result)
        deletedShoppingResultIds.insert(resultId)
        saveDeletions()
        
        // Set flag to prevent auto-loading more results
        hasDeletedItems = true
        
        // Remove from displayed array with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            if index < displayedShoppingResults.count {
                displayedShoppingResults.remove(at: index)
            }
        }
        
        print("🗑️ Deleted shopping result: \(result.title ?? "Unknown") from \(result.source ?? "Unknown source")")
    }
    
    private func getFilteredVisualMatches(_ matches: [VisualMatch]) -> [VisualMatch] {
        return matches.filter { match in
            let matchId = generateVisualMatchId(match)
            return !deletedVisualMatchIds.contains(matchId)
        }
    }
    
    private func getFilteredShoppingResults(_ results: [ShoppingResult]) -> [ShoppingResult] {
        return results.filter { result in
            let resultId = generateShoppingResultId(result)
            return !deletedShoppingResultIds.contains(resultId)
        }
    }
    
    private func extractNumericPrice(_ price: String?) -> Double? {
        guard let priceString = price else { return nil }
        
        // Remove currency symbols but preserve commas and periods
        let cleanPrice = priceString.replacingOccurrences(of: "*", with: "")
                                   .replacingOccurrences(of: "CHF", with: "")
                                   .replacingOccurrences(of: "€", with: "")
                                   .replacingOccurrences(of: "£", with: "")
                                   .replacingOccurrences(of: "$", with: "")
        
        // Use regex to find the first price pattern (handles commas properly)
        let pattern = #"(\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\d+(?:\.\d{2})?)"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: cleanPrice, options: [], range: NSRange(location: 0, length: cleanPrice.count)) {
            
            let matchString = (cleanPrice as NSString).substring(with: match.range)
            
            // Remove commas for Double conversion
            let numberString = matchString.replacingOccurrences(of: ",", with: "")
        
        if let value = Double(numberString) {
            // Apply currency conversion
            var usdValue = value
            
            if priceString.contains("CHF") {
                usdValue = value * 1.1 // CHF to USD
            } else if priceString.contains("€") {
                usdValue = value * 1.08 // EUR to USD
            } else if priceString.contains("£") {
                usdValue = value * 1.25 // GBP to USD
            }
            
            return usdValue
            }
        }
        
        return nil
    }

    // MARK: - Clothing Details Analysis
    private func analyzeClothingDetails() {
        let allImages = song.allImages
        guard !isAnalyzingClothing, !allImages.isEmpty else { 
            print("🔍 Clothing Details Analysis guard failed - analyzing: \(isAnalyzingClothing), images: \(allImages.count)")
            return 
        }
        
        print("🔍 Starting Clothing Details Analysis with \(allImages.count) images...")
        
        // Check both caches first to avoid duplicate API calls
        let cacheKey = "clothing_details_\(song.id.uuidString)_\(allImages.count)"
        
        // First check the image-based cache from background analysis
        if let firstImage = allImages.first,
           let cachedDetails = AnalysisResultsCache.shared.getClothingDetails(for: firstImage) {
            print("📦 Loading Clothing Details from background analysis cache")
            self.clothingDetails = cachedDetails
            return
        }
        
        // Then check traditional cache
        if let cachedResponse = MarketDataCache.shared.getOpenAIResponse(for: "clothing_details", input: cacheKey) {
            print("📦 Loading Clothing Details from traditional cache")
            let details = parseClothingDetailsResponse(cachedResponse)
            self.clothingDetails = details
            return
        }
        
        isAnalyzingClothing = true
        clothingDetails = nil
        
        Task {
            do {
                let prompt = createClothingAnalysisPrompt()
                print("🔍 Clothing Details Analysis prompt: \(prompt.prefix(100))...")
                
                // For now, we'll use the single image. In a real implementation,
                // you would pass multiple images to GPT-4o Vision
                // Use GPT-4 Vision if we have images
                let allImages = song.allImages
                let response: String
                
                if !allImages.isEmpty {
                    response = try await OpenAIService.shared.generateVisionCompletion(
                        prompt: prompt,
                        images: allImages,
                        maxTokens: 500,
                        temperature: 0.3
                    )
                } else {
                    response = try await OpenAIService.shared.generateCompletion(
                        prompt: prompt,
                        model: Config.defaultModel,
                        maxTokens: 500,
                        temperature: 0.3
                    )
                }
                
                // Save to cache
                MarketDataCache.shared.saveOpenAIResponse(response, for: "clothing_details", input: cacheKey, prompt: prompt)
                
                let details = parseClothingDetailsResponse(response)
                
                // Also save to image-based cache for cross-referencing
                if let firstImage = allImages.first {
                    AnalysisResultsCache.shared.storeClothingDetails(details, for: firstImage)
                }
                
                await MainActor.run {
                    print("🔍 Clothing Details Analysis completed: \(details)")
                    self.clothingDetails = details
                    self.isAnalyzingClothing = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Clothing Details Analysis error: \(error)")
                    
                    // Create fallback details on error with network-specific info
                    let errorCategory: String
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .networkConnectionLost, .timedOut:
                            errorCategory = "Network Error"
                        case .notConnectedToInternet:
                            errorCategory = "No Internet"
                        default:
                            errorCategory = "Network Issue"
                        }
                    } else {
                        errorCategory = "Analysis Error"
                    }
                    
                    self.clothingDetails = ClothingDetails(
                        category: errorCategory,
                        style: "Retry Required",
                        season: "N/A",
                        gender: "N/A",
                        designerTier: "N/A",
                        era: "N/A",
                        colors: ["Network Error"],
                        fabricComposition: [FabricComponent(material: "Check Connection", percentage: 100)],
                        isAuthentic: nil
                    )
                    self.isAnalyzingClothing = false
                }
            }
        }
    }
    
    private func createClothingAnalysisPrompt() -> String {
        let imageCount = song.allImages.count
        let imageContext = imageCount > 1 ? 
            "Analyze these \(imageCount) clothing images (full item, brand tag, fabric detail) and provide" : 
            "Analyze this clothing item and provide"
            
        return """
        \(imageContext) structured information in the following JSON format:
        
        {
            "category": "Tops/Bottoms/Dresses/Outerwear/Accessories/Shoes",
            "style": "Modern/Vintage/Minimalist/Streetwear/Bohemian/Classic",
            "season": "Spring/Summer/Fall/Winter/All Season",
            "gender": "Mens/Womens/Unisex",
            "designer_tier": "Luxury/Premium/Mid-Range/Fast Fashion/Unknown",
            "era": "Contemporary/Vintage/Y2K/90s/80s/70s/60s",
            "colors": ["Primary color", "Secondary color"],
            "fabric_composition": [
                {"material": "Cotton", "percentage": 80},
                {"material": "Polyester", "percentage": 20}
            ],
            "is_authentic": true
        }
        
        Be specific and accurate. If unsure about fabric composition, provide best estimate based on visual appearance and typical materials for this type of garment.
        
        For authenticity assessment, look for signs of authenticity such as:
        - Quality of stitching, materials, and construction
        - Brand labels, tags, and hardware that match authentic standards
        - Overall craftsmanship and attention to detail
        - Any obvious signs of counterfeiting or poor quality reproduction
        Set "is_authentic" to true if the item appears genuine, false if it appears to be a counterfeit or poor quality reproduction.
        """
    }
    
    private func parseClothingDetailsResponse(_ response: String) -> ClothingDetails {
        // Try to extract JSON from the response
        let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Safety check for empty response
        guard !cleanResponse.isEmpty else {
            print("⚠️ Empty response received, using fallback")
            return createFallbackClothingDetails()
        }
        
        // Look for JSON content between { and }
        if let startIndex = cleanResponse.firstIndex(of: "{"),
           let endIndex = cleanResponse.lastIndex(of: "}"),
           startIndex <= endIndex {
            
            // Safe string slicing with bounds check
            let jsonString = String(cleanResponse[startIndex...endIndex])
            
            if let data = jsonString.data(using: .utf8),
               let details = try? JSONDecoder().decode(ClothingDetails.self, from: data) {
                return details
            } else {
                print("⚠️ Failed to parse JSON: \(jsonString.prefix(100))")
            }
        } else {
            print("⚠️ No valid JSON brackets found in response: \(cleanResponse.prefix(100))")
        }
        
        // Fallback if JSON parsing fails
        return createFallbackClothingDetails()
    }
    
    private func createFallbackClothingDetails() -> ClothingDetails {
        return ClothingDetails(
            category: "Unknown",
            style: "Modern",
            season: "All Season",
            gender: "Unisex",
            designerTier: "Unknown",
            era: "Contemporary",
            colors: ["Unknown"],
            fabricComposition: [FabricComponent(material: "Unknown", percentage: 100)],
            isAuthentic: nil
        )
    }
    
    // MARK: - Title Generation
    private func generateItemTitle() {
        let allImages = song.allImages
        guard !allImages.isEmpty else { 
            print("🏷️ No images available for title generation")
            return 
        }
        
        print("🏷️ Generating title with \(allImages.count) images...")
        
        // Check cache first
        let cacheKey = "title_generation_\(song.id.uuidString)_\(allImages.count)"
        if let cachedResponse = MarketDataCache.shared.getOpenAIResponse(for: "title_generation", input: cacheKey) {
            print("📦 Loading title from cache")
            updateSongTitle(with: cachedResponse.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        
        Task {
            do {
                let prompt = createTitleGenerationPrompt()
                print("🏷️ Title generation prompt: \(prompt.prefix(100))...")
                
                let response = try await OpenAIService.shared.generateVisionCompletion(
                    prompt: prompt,
                    images: allImages,
                    maxTokens: 50,
                    temperature: 0.7
                )
                
                print("🏷️ Title generation response: \(response)")
                
                // Cache the response
                MarketDataCache.shared.saveOpenAIResponse(response, for: "title_generation", input: cacheKey, prompt: prompt)
                
                // Clean up the response and update title
                let cleanTitle = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "Title:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                await MainActor.run {
                    updateSongTitle(with: cleanTitle)
                }
                
            } catch {
                print("❌ Title generation error: \(error)")
                await MainActor.run {
                    // Use a more descriptive fallback based on the item type
                    let fallbackTitle = generateFallbackTitle()
                    updateSongTitle(with: fallbackTitle)
                }
            }
        }
    }
    
    private func createTitleGenerationPrompt() -> String {
        let imageCount = song.allImages.count
        let imageContext = imageCount > 1 ? 
            "these \(imageCount) images of an item" : 
            "this image of an item"
            
        return """
        Based on \(imageContext), generate a short, catchy title (2-4 words max) that describes what this item is.
        
        Examples of good titles:
        - "Vintage Leather Jacket"
        - "Designer Handbag"
        - "Retro Denim Jeans"
        - "Silk Floral Dress"
        - "Golden Watch"
        - "Sneaker Collection"
        - "Vintage Find"
        - "Fashion Item"
        - "Thrift Treasure"
        
        Focus on:
        - Type of item (jacket, bag, shoes, etc.)
        - Notable style or era if visible (vintage, retro, modern)
        - Key material if obvious (leather, denim, silk)
        - If unclear, use descriptive terms like "Vintage Find", "Fashion Item", or "Unique Piece"
        
        IMPORTANT: Always return a title. Never return empty text.
        Return ONLY the title, no extra text or quotes.
        """
    }
    
    private func updateSongTitle(with newTitle: String) {
        let finalTitle = newTitle.isEmpty ? generateFallbackTitle() : newTitle
        song.title = finalTitle
        songManager.updateSong(song)
        print("🏷️ Updated song title to: '\(finalTitle)'")
    }
    
    private func generateFallbackTitle() -> String {
        // Generate a more descriptive fallback title based on available data
        let fallbackTitles = [
            "Vintage Find",
            "Designer Item",
            "Thrift Treasure",
            "Unique Piece",
            "Retro Item",
            "Fashion Find",
            "Collectible Item",
            "Antique Piece",
            "Stylish Find",
            "Quality Item"
        ]
        
        // Use a semi-random selection based on the song ID to ensure consistency
        let index = abs(song.id.hashValue) % fallbackTitles.count
        return fallbackTitles[index]
    }

    // MARK: - Display Items Management
    private func updateDisplayedItems() {
        guard let marketData = marketData else { return }
        
        // Update visual matches
        if let visualMatches = marketData.visualMatches, !visualMatches.isEmpty {
            // First filter out deleted items, then filter for prices
            let notDeletedMatches = getFilteredVisualMatches(visualMatches)
            let visualMatchesWithPrices = notDeletedMatches.filter { result in
                result.price?.extractedValue != nil && (result.price?.extractedValue ?? 0) > 0
            }
            
            // Always update with filtered results - remove isEmpty condition
            displayedVisualMatches = Array(visualMatchesWithPrices.prefix(10))
        }
        
        // Update shopping results
        if let shoppingResults = marketData.shoppingResults, !shoppingResults.isEmpty {
            // First filter out deleted items, then filter for prices
            let notDeletedResults = getFilteredShoppingResults(shoppingResults)
            let shoppingResultsWithPrices = notDeletedResults.filter { result in
                (result.extractedPrice != nil && (result.extractedPrice ?? 0) > 0) || 
                (result.price != nil && result.price != "N/A" && !result.price!.isEmpty)
            }
            
            // Always update with filtered results - remove isEmpty condition
            displayedShoppingResults = Array(shoppingResultsWithPrices.prefix(10))
        }
    }
    
    // MARK: - Sample Market Data for Default Songs
    private func createSampleMarketData(for songTitle: String) -> SerpSearchResult? {
        switch songTitle {
        case "Nike Air Jordan 1's - T-Scott":
            return SerpSearchResult(
                searchMetadata: SearchMetadata(status: "Success", createdAt: "2024-01-20T10:30:00Z"),
                searchParameters: SearchParameters(engine: "google_shopping", query: "vintage leather jacket", condition: "used"),
                searchInformation: SearchInformation(totalResults: "1,234", queryDisplayed: "vintage leather jacket"),
                shoppingResults: [
                    ShoppingResult(
                        position: 1,
                        title: "Vintage 80s Black Leather Moto Jacket",
                        price: "$145",
                        extractedPrice: 145.0,
                        link: "https://www.etsy.com/listing/vintage-leather-jacket",
                        source: "Etsy",
                        rating: 4.8,
                        reviews: 24,
                        thumbnail: "https://example.com/vintage-leather.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 2,
                        title: "Authentic Vintage Brown Leather Jacket",
                        price: "$180",
                        extractedPrice: 180.0,
                        link: "https://www.depop.com/products/vintage-leather",
                        source: "Depop",
                        rating: 4.9,
                        reviews: 16,
                        thumbnail: "https://example.com/brown-leather.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 3,
                        title: "Vintage Leather Bomber Jacket 90s",
                        price: "$120",
                        extractedPrice: 120.0,
                        link: "https://www.vinted.com/items/vintage-bomber",
                        source: "Vinted",
                        rating: 4.6,
                        reviews: 31,
                        thumbnail: "https://example.com/bomber-leather.jpg",
                        condition: "used"
                    )
                ],
                organicResults: nil,
                imageResults: nil,
                visualMatches: [
                    // IN STOCK ITEMS
                    VisualMatch(
                        position: 1,
                        title: "Nike Air Jordan 1 Retro High Dark",
                        link: "",
                        source: "Thrift Finds",
                        sourceIcon: nil,
                        rating: 4.7,
                        reviews: 42,
                        price: PriceInfo(value: "$225", extractedValue: 225.0, currency: "USD"),
                        inStock: true,
                        condition: "excellent",
                        thumbnail: "t1",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t1",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 2,
                        title: "Nike Air Jordan 1 Retro High OG \"Dark\"",
                        link: "",
                        source: "Poshmark",
                        sourceIcon: nil,
                        rating: 4.5,
                        reviews: 28,
                        price: PriceInfo(value: "$234", extractedValue: 234.0, currency: "USD"),
                        inStock: true,
                        condition: "good",
                        thumbnail: "t2",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t2",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 3,
                        title: "Nike Air Jordan 1 Retro OG High Dark Brown",
                        link: "",
                        source: "Mercari",
                        sourceIcon: nil,
                        rating: 4.8,
                        reviews: 15,
                        price: PriceInfo(value: "$280", extractedValue: 280.0, currency: "USD"),
                        inStock: true,
                        condition: "very good",
                        thumbnail: "t3",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t3",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    // SOLD OUT ITEMS
                    VisualMatch(
                        position: 4,
                        title: "Nike Air Jordan 1 Retro OG High Top",
                        link: "",
                        source: "eBay",
                        sourceIcon: nil,
                        rating: 4.9,
                        reviews: 67,
                        price: PriceInfo(value: "$225", extractedValue: 225.0, currency: "USD"),
                        inStock: false,
                        condition: "excellent",
                        thumbnail: "t4",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t4",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 5,
                        title: "Nike Air Jordan 1 High",
                        link: "",
                        source: "Grailed",
                        sourceIcon: nil,
                        rating: 5.0,
                        reviews: 34,
                        price: PriceInfo(value: "$195", extractedValue: 195.0, currency: "USD"),
                        inStock: false,
                        condition: "mint",
                        thumbnail: "t5",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t5",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 6,
                        title: "Size 11 - Air Jordan 1 Retro OG High Dark Brown",
                        link: "",
                        source: "Vestiaire",
                        sourceIcon: nil,
                        rating: 4.6,
                        reviews: 23,
                        price: PriceInfo(value: "$175", extractedValue: 175.0, currency: "USD"),
                        inStock: false,
                        condition: "good",
                        thumbnail: "t6",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "t6",
                        imageWidth: 800,
                        imageHeight: 800
                    )
                ],
                error: nil
            )
            
        case "Vintage Ecko Navy Blue Hoodie":
            return SerpSearchResult(
                searchMetadata: SearchMetadata(status: "Success", createdAt: "2024-01-20T10:30:00Z"),
                searchParameters: SearchParameters(engine: "google_shopping", query: "Vintage Ecko Navy Blue Hoodie", condition: "used"),
                searchInformation: SearchInformation(totalResults: "2,567", queryDisplayed: "Vintage Ecko Navy Blue Hoodie"),
                shoppingResults: [
                    ShoppingResult(
                        position: 1,
                        title: "Vintage Ecko Unltd. Hoodie Men's XXL",
                        price: "$30",
                        extractedPrice: 220.0,
                        link: "",
                        source: "StockX",
                        rating: 4.9,
                        reviews: 156,
                        thumbnail: "https://example.com/jordan4-white.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 2,
                        title: "Ecko Unltd. Hoodie Men's XL",
                        price: "$45",
                        extractedPrice: 280.0,
                        link: "",
                        source: "GOAT",
                        rating: 4.8,
                        reviews: 203,
                        thumbnail: "https://example.com/jordan4-bred.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 3,
                        title: "VTG Ecko Unltd Hoodie Men Medium",
                        price: "$40",
                        extractedPrice: 195.0,
                        link: "",
                        source: "eBay",
                        rating: 4.6,
                        reviews: 89,
                        thumbnail: "https://example.com/jordan4-blue.jpg",
                        condition: "used"
                    )
                ],
                organicResults: nil,
                imageResults: nil,
                visualMatches: [
                    // IN STOCK ITEMS
                    VisualMatch(
                        position: 1,
                        title: "Ecko Unltd Vintage Hoodie Men",
                        link: "",
                        source: "Grailed",
                        sourceIcon: nil,
                        rating: 4.8,
                        reviews: 67,
                        price: PriceInfo(value: "$30", extractedValue: 30.0, currency: "USD"),
                        inStock: true,
                        condition: "good",
                        thumbnail: "e1",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e1",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 2,
                        title: "Vintage Ecko Unltd Spellout Rhino Navy Blue",
                        link: "",
                        source: "eBay",
                        sourceIcon: nil,
                        rating: 4.7,
                        reviews: 124,
                        price: PriceInfo(value: "$29", extractedValue: 29.0, currency: "USD"),
                        inStock: true,
                        condition: "very good",
                        thumbnail: "e2",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e2",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 3,
                        title: "Ecko Unltd Rhino Navy Blue",
                        link: "",
                        source: "GOAT",
                        sourceIcon: nil,
                        rating: 4.9,
                        reviews: 89,
                        price: PriceInfo(value: "$34", extractedValue: 34.0, currency: "USD"),
                        inStock: true,
                        condition: "excellent",
                        thumbnail: "e3",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e3",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    // SOLD OUT ITEMS
                    VisualMatch(
                        position: 4,
                        title: "Vintage Y2K Ecko Hoodie Sweatshirt Mens",
                        link: "",
                        source: "StockX",
                        sourceIcon: nil,
                        rating: 5.0,
                        reviews: 156,
                        price: PriceInfo(value: "$45", extractedValue: 45.0, currency: "USD"),
                        inStock: false,
                        condition: "deadstock",
                        thumbnail: "e4",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e4",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 5,
                        title: "Ecko Hoodie Hoodie Mens L",
                        link: "",
                        source: "Flight Club",
                        sourceIcon: nil,
                        rating: 4.8,
                        reviews: 203,
                        price: PriceInfo(value: "$40", extractedValue: 40.0, currency: "USD"),
                        inStock: false,
                        condition: "mint",
                        thumbnail: "e5",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e5",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 6,
                        title: "2000's Ecko Hoodie XL Mens",
                        link: "",
                        source: "Kixify",
                        sourceIcon: nil,
                        rating: 4.6,
                        reviews: 78,
                        price: PriceInfo(value: "$30", extractedValue: 30.0, currency: "USD"),
                        inStock: false,
                        condition: "good",
                        thumbnail: "e6",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "e6",
                        imageWidth: 800,
                        imageHeight: 800
                    )
                ],
                error: nil
            )
            
        case "Coach Vintage Handbag":
            return SerpSearchResult(
                searchMetadata: SearchMetadata(status: "Success", createdAt: "2024-01-20T10:30:00Z"),
                searchParameters: SearchParameters(engine: "google_shopping", query: "coach vintage handbag", condition: "used"),
                searchInformation: SearchInformation(totalResults: "3,456", queryDisplayed: "coach vintage handbag"),
                shoppingResults: [
                    ShoppingResult(
                        position: 1,
                        title: "Coach Legacy Shoulder Brown Leather",
                        price: "$95",
                        extractedPrice: 95.0,
                        link: "",
                        source: "Fashionphile",
                        rating: 4.9,
                        reviews: 78,
                        thumbnail: "https://example.com/coach-legacy.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 2,
                        title: "Vintage Coach Station Bag Brown",
                        price: "$125",
                        extractedPrice: 125.0,
                        link: "",
                        source: "Vestiaire Collective",
                        rating: 4.7,
                        reviews: 54,
                        thumbnail: "https://example.com/coach-station.jpg",
                        condition: "used"
                    ),
                    ShoppingResult(
                        position: 3,
                        title: "Coach Vintage Crossbody Bag",
                        price: "$80",
                        extractedPrice: 80.0,
                        link: "",
                        source: "The RealReal",
                        rating: 4.8,
                        reviews: 92,
                        thumbnail: "https://example.com/coach-crossbody.jpg",
                        condition: "used"
                    )
                ],
                organicResults: nil,
                imageResults: nil,
                visualMatches: [
                    // IN STOCK ITEMS
                    VisualMatch(
                        position: 1,
                        title: "Coach Legacy 9966 Shoulder Bag",
                        link: "",
                        source: "Rebag",
                        sourceIcon: nil,
                        rating: 4.9,
                        reviews: 23,
                        price: PriceInfo(value: "$110", extractedValue: 110.0, currency: "USD"),
                        inStock: true,
                        condition: "excellent",
                        thumbnail: "c1",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c1",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 2,
                        title: "Coach Vintage Station Bag Brown",
                        link: "",
                        source: "Fashionphile",
                        sourceIcon: nil,
                        rating: 4.7,
                        reviews: 41,
                        price: PriceInfo(value: "$125", extractedValue: 125.0, currency: "USD"),
                        inStock: true,
                        condition: "very good",
                        thumbnail: "c2",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c2",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 3,
                        title: "Coach Crossbody Bag - Brown",
                        link: "",
                        source: "Vestiaire",
                        sourceIcon: nil,
                        rating: 4.8,
                        reviews: 67,
                        price: PriceInfo(value: "$95", extractedValue: 95.0, currency: "USD"),
                        inStock: true,
                        condition: "good",
                        thumbnail: "c3",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c3",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    // SOLD OUT ITEMS
                    VisualMatch(
                        position: 4,
                        title: "Coach Vintage Court Bag",
                        link: "",
                        source: "The RealReal",
                        sourceIcon: nil,
                        rating: 5.0,
                        reviews: 89,
                        price: PriceInfo(value: "$185", extractedValue: 185.0, currency: "USD"),
                        inStock: false,
                        condition: "pristine",
                        thumbnail: "c4",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c4",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 5,
                        title: "Coach Madison Tote",
                        link: "",
                        source: "Luxury Consignment",
                        sourceIcon: nil,
                        rating: 4.6,
                        reviews: 34,
                        price: PriceInfo(value: "$155", extractedValue: 155.0, currency: "USD"),
                        inStock: false,
                        condition: "excellent",
                        thumbnail: "c5",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c5",
                        imageWidth: 800,
                        imageHeight: 800
                    ),
                    VisualMatch(
                        position: 6,
                        title: "Coach Signature Handbag",
                        link: "",
                        source: "YOOX",
                        sourceIcon: nil,
                        rating: 4.4,
                        reviews: 52,
                        price: PriceInfo(value: "$135", extractedValue: 135.0, currency: "USD"),
                        inStock: false,
                        condition: "good",
                        thumbnail: "c6",
                        thumbnailWidth: 300,
                        thumbnailHeight: 300,
                        image: "c6",
                        imageWidth: 800,
                        imageHeight: 800
                    )
                ],
                error: nil
            )
            
        default:
            return nil
        }
    }

// MARK: - Sample Clothing Details for Default Songs
    private func createSampleClothingDetails(for songTitle: String) -> ClothingDetails? {
        switch songTitle {
        case "Nike Air Jordan 1's - T-Scott":
            return ClothingDetails(
                category: "Shoes",
                style: "Streetwear",
                season: "N/A",
                gender: "Male", 
                designerTier: "Mid-Range",
                era: "2020s",
                colors: ["Black", "Brown"],
                fabricComposition: [
                    FabricComponent(material: "Genuine Leather", percentage: 100)
                ],
                isAuthentic: true
            )
            
        case "Vintage Ecko Navy Blue Hoodie":
            return ClothingDetails(
                category: "Hoodies",
                style: "Streetwear",
                season: "Fall/Winter",
                gender: "Unisex",
                designerTier: "Standard",
                era: "Contemporary",
                colors: ["Navy Blue", "White"],
                fabricComposition: [
                    FabricComponent(material: "Cotton", percentage: 70),
                    FabricComponent(material: "Polyester", percentage: 30)
                ],
                isAuthentic: true
            )
            
        case "Coach Vintage Handbag":
            return ClothingDetails(
                category: "Accessories",
                style: "Classic",
                season: "All Season",
                gender: "Womens",
                designerTier: "Luxury",
                era: "Vintage",
                colors: ["Black", "Brown"],
                fabricComposition: [
                    FabricComponent(material: "Pebbled Leather", percentage: 100)
                ],
                isAuthentic: true
            )
            
        default:
            return nil
        }
    }
    
    // MARK: - Market Data Loading
    private func loadMarketData() {
        guard marketData == nil && !isLoadingMarketData else { return }
        
        // Check if this is a default sample song - use hardcoded sample data
        if let sampleData = createSampleMarketData(for: song.title) {
            print("📦 Loading sample market data for default song: \(song.title)")
            self.marketData = sampleData
            self.updateDisplayedItems()
            // Trigger confetti for sample data
            self.triggerConfetti()
            return
        }
        
        // Check cache first - try song ID cache first, then fallback to search query cache
        let hasCustomImage = song.customImage != nil
        if let cachedData = MarketDataCache.shared.getMarketData(for: song.id.uuidString, hasCustomImage: hasCustomImage) {
            print("📦 Loading market data from song ID cache for: \(song.title)")
            self.marketData = cachedData
            self.updateDisplayedItems()
            // Trigger confetti for cached data
            self.triggerConfetti()
            return
        }
        
        // Fallback: Check if we have cached data for the same search query
        let searchQuery = generateSearchQuery()
        if let cachedData = MarketDataCache.shared.getMarketDataByQuery(searchQuery: searchQuery, hasCustomImage: hasCustomImage) {
            print("📦 Loading market data from search query cache for: \(song.title) (query: \(searchQuery))")
            self.marketData = cachedData
            self.updateDisplayedItems()
            return
        }
        
        isLoadingMarketData = true
        displayedVisualMatches = []
        displayedShoppingResults = []
        
        Task {
            do {
                // Generate search query based on song title
                let searchQuery = generateSearchQuery()
                
                // Check if we have an image to use for visual search
                if let customImage = song.customImage,
                   let imageData = customImage.jpegData(compressionQuality: 0.8) {
                    print("🔍 Using pure image-based search (no text query)")
                    
                    // Try image-based search first (purely visual, no text)
                    let results = try await serpAPIService.searchWithImage(imageData: imageData)
                    
                    // Cache the results
                    MarketDataCache.shared.saveMarketData(results, for: song.id.uuidString, searchQuery: searchQuery, hasCustomImage: true)
                    
                    await MainActor.run {
                        // Debug the results we're about to set
                        let visualCount = results.visualMatches?.count ?? 0
                        let shoppingCount = results.shoppingResults?.count ?? 0
                        let organicCount = results.organicResults?.count ?? 0
                        let imageCount = results.imageResults?.count ?? 0
                        let totalCount = visualCount + shoppingCount + organicCount + imageCount
                        
                        print("🔍 Setting Market Data with:")
                        print("   📸 Visual Matches: \(visualCount)")
                        print("   🛒 Shopping Results: \(shoppingCount)")
                        print("   🔗 Organic Results: \(organicCount)")
                        print("   🖼️ Image Results: \(imageCount)")
                        print("   📊 Total Results: \(totalCount)")
                        
                        self.marketData = results
                        self.isLoadingMarketData = false
                        self.updateDisplayedItems()
                        
                        // Trigger confetti for successful data load
                        if totalCount > 0 {
                            self.triggerConfetti()
                        }
                    }
                } else {
                    print("🔍 Using text-based search for: \(searchQuery)")
                    
                    // Fallback to text-based search
                let results = try await serpAPIService.searchEBayItems(query: searchQuery, condition: "used")
                
                // Cache the results
                MarketDataCache.shared.saveMarketData(results, for: song.id.uuidString, searchQuery: searchQuery, hasCustomImage: false)
                
                await MainActor.run {
                    self.marketData = results
                    self.isLoadingMarketData = false
                        self.updateDisplayedItems()
                        
                        // Trigger confetti for successful fallback data load
                        if let shoppingResults = results.shoppingResults, !shoppingResults.isEmpty {
                            self.triggerConfetti()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.marketAnalysisError = error.localizedDescription
                    self.isLoadingMarketData = false
                }
            }
        }
    }
    
    private func generateSearchQuery() -> String {
        // Generate a search query based on the song title and image presence
        let title = song.title.lowercased()
        
        // If there's a custom image, enhance search for fashion/clothing items
        if song.customImage != nil {
            if title.isEmpty || title == "untitled song" || title == "analyzing..." {
                return "vintage fashion clothing accessories thrift"
        } else {
                return "\(title) vintage fashion clothing"
            }
        } else {
            // Text-only search, use title or generic term
            if title.isEmpty || title == "untitled song" || title == "analyzing..." {
                return "vintage items collectibles"
            } else {
                return title
            }
        }
    }
    

    
    // MARK: - Computed Properties for View Sections
    
    private var headerView: some View {
                VStack(spacing: 0) {
                    // Navigation header
                    HStack {
                        // Back button
                        Button(action: {
                            print("🔙 Back button tapped - calling onDismiss()")
                            onDismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        // Centered Thrifty logo
                        Image("thrifty")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 40)
                        
                        Spacer()
                        
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    // Scan result header section
                    HStack(spacing: 16) {
                        // Scanned item image - no longer tappable
                            Group {
                                if let customImage = song.customImage {
                                    Image(uiImage: customImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else if !song.imageName.isEmpty {
                                    // Show the asset image if no custom image
                                    Image(song.imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                        .overlay(
                                            VStack(spacing: 8) {
                                            Image(systemName: "photo")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.gray)
                                            Text("No photo")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.gray)
                                            }
                                        )
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipped()
                            .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .allowsHitTesting(false)
                        
                        // Item details
                        VStack(alignment: .leading, spacing: 8) {
                            if isEditingTitle {
                                // Expandable TextEditor when editing
                                TextEditor(text: $song.title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 50, maxHeight: 120)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .tint(.black) // Black cursor
                                    .focused($isTitleFocused)
                                    .onAppear {
                                        isTitleFocused = true
                                    }
                                    .onChange(of: isTitleFocused) { focused in
                                        if !focused {
                                            isEditingTitle = false
                                            // Save changes when editing is complete
                                            song.lastEdited = Date()
                                            songManager.updateSong(song)
                                        }
                                    }
                            } else {
                                // Single line display when not editing
                                Text(song.title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        isEditingTitle = true
                                    }
                                    .overlay(
                                        // Edit indicator
                                        HStack {
                                            Spacer()
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray.opacity(0.7))
                                                .padding(.trailing, 8)
                                        }
                                    )
                            }
                            
                            Text(song.displayDate)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .background(Color.white)
    }
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Thrifty: AI Profit Identifier Card
                averagePriceCard
                
                // In Stock Analysis Card
                inStockAnalysisCard
                
                // Sold Analysis Card
                soldAnalysisCard
                
                // Clothing Details Card
                if song.customImage != nil || !song.imageName.isEmpty {
                    clothingDetailsCard
                        .onAppear {
                            print("🔍 Clothing Details Card appeared - analyzing: \(isAnalyzingClothing), hasDetails: \(clothingDetails != nil)")
                        }
                } else {
                    Text("DEBUG: No custom image for clothing details")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .onAppear {
                updateDisplayedItems()
            }
                                 .background(Color.gray.opacity(0.05))
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Only detect vertical scrolling, completely ignore horizontal swipes for swipeActions
                        let verticalMovement = abs(value.translation.height)
                        let horizontalMovement = abs(value.translation.width)
                        
                        // Only trigger scroll detection if it's primarily vertical movement with more significant distance
                        if verticalMovement > horizontalMovement * 2 && verticalMovement > 40 && horizontalMovement < 20 {
                            if !isScrolling {
                                isScrolling = true
                            }
                        }
                    }
                    .onEnded { _ in
                        // Shorter delay to prevent blocking legitimate taps
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isScrolling = false
                        }
                    }
            )
    }
    
    private var averagePriceCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Average Price")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                    .tracking(1)
                
                // Animated info bubble
                InfoBubble(showingInfo: $showingAveragePriceInfo)
            }
            
            if let averagePrice = calculateOverallAveragePrice() {
                Text("$\(String(format: "%.0f", averagePrice))")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.black)
            } else if isLoadingMarketData {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(height: 56)
            } else {
                Text("N/A")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .preferredColorScheme(.light)
        .confettiCannon(trigger: $trigger, num: 20, confettiSize: 6, fadesOut: true, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 80)
        .zIndex(1000)
    }
    
    private var inStockAnalysisCard: some View {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
                                    
                Text("In Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                                    
                                    Spacer()
            }
                
            VStack(alignment: .leading, spacing: 8) {
                if isLoadingMarketData {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading in stock items...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let marketData = marketData {
                    // Prioritize imageResults from Google Reverse Image API, then fall back to visual matches
                    if let imageResults = marketData.imageResults, !imageResults.isEmpty {
                        // Convert imageResults to visual matches format for compatibility
                        let imageBasedMatches = imageResults.compactMap { imageResult -> VisualMatch? in
                            return VisualMatch(
                                position: imageResult.position,
                                title: imageResult.title,
                                link: imageResult.redirectLink ?? imageResult.link,
                                source: imageResult.source,
                                sourceIcon: imageResult.favicon,
                                rating: nil,
                                reviews: nil,
                                price: nil, // Image results typically don't have prices initially
                                inStock: nil,
                                condition: nil,
                                thumbnail: imageResult.thumbnail,
                                thumbnailWidth: nil,
                                thumbnailHeight: nil,
                                image: imageResult.thumbnail,
                                imageWidth: nil,
                                imageHeight: nil
                            )
                        }
                        
                        // Filter for available image results
                        let availableMatches = filterAvailableVisualMatches(imageBasedMatches)
                        
                        let currentMatches = Array(availableMatches.prefix(10))
                        
                        if !currentMatches.isEmpty {
                            Text("In Stock Image Results:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.bottom, 4)
                            
                            List {
                                ForEach(Array(currentMatches.enumerated()), id: \.offset) { index, result in
                                    visualMatchRowWithDelete(result: result, index: index)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: CGFloat(currentMatches.count * 95)) // Approximate height per row
                            .scrollDisabled(true)
                            .onAppear {
                                showSwipeHintAnimation()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                    // Fall back to visual matches if no image results
                    else if let visualMatches = marketData.visualMatches, !visualMatches.isEmpty {
                        // Filter for available visual matches
                        let availableMatches = filterAvailableVisualMatches(visualMatches)
                        
                        let currentMatches = Array(availableMatches.prefix(10))
                        
                        if !currentMatches.isEmpty {
                            Text("In Stock Visual Matches:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.bottom, 4)
                            
                            List {
                                ForEach(Array(currentMatches.enumerated()), id: \.offset) { index, result in
                                    visualMatchRowWithDelete(result: result, index: index)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: CGFloat(currentMatches.count * 95)) // Approximate height per row
                            .scrollDisabled(true)
                            .onAppear {
                                showSwipeHintAnimation()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Calculate average price from in-stock items
                            let prices = currentMatches.compactMap { result -> Double? in
                                if let extractedValue = result.price?.extractedValue, extractedValue > 0 {
                                    return extractedValue
                                } else if let priceString = result.price?.value {
                                    return extractNumericPrice(priceString)
                                }
                                return nil
                            }
                            
                            let averagePrice = prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count)
                            
                            HStack {
                                Text("In-Stock Average (\(currentMatches.count) items):")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Text(averagePrice > 0 ? "$\(String(format: "%.2f", averagePrice))" : "N/A")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("No in stock items found")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .padding(.vertical, 8)
                        }
                    }
                    // Show available shopping results
                    else if let shoppingResults = marketData.shoppingResults, !shoppingResults.isEmpty {
                        // Filter for available shopping results
                        let availableResults = filterAvailableShoppingResults(shoppingResults)
                        
                        let currentResults = Array(availableResults.prefix(10))
                        
                        if !currentResults.isEmpty {
                            Text("In Stock Shopping Results:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.bottom, 4)
                            
                            List {
                                ForEach(Array(currentResults.enumerated()), id: \.offset) { index, result in
                                    shoppingResultRowWithDelete(result: result, index: index)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: CGFloat(currentResults.count * 95)) // Approximate height per row
                            .scrollDisabled(true)
                            .onAppear {
                                showSwipeHintAnimation()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Calculate average price from in-stock results
                            let prices = currentResults.compactMap { result -> Double? in
                                if let extractedPrice = result.extractedPrice, extractedPrice > 0 {
                                    return extractedPrice
                                } else if let priceString = result.price {
                                    return extractNumericPrice(priceString)
                                }
                                return nil
                            }
                            
                            let averagePrice = prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count)
                            
                    HStack {
                                Text("In-Stock Average (\(currentResults.count) items):")
                                    .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Spacer()
                                
                                Text(averagePrice > 0 ? "$\(String(format: "%.2f", averagePrice))" : "N/A")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("No in stock items found")
                                .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                .padding(.vertical, 8)
                        }
                    }
                    // Show image results if available
                    else if let imageResults = marketData.imageResults, !imageResults.isEmpty {
                        Text("Similar Items Found:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.bottom, 4)
                        
                        ForEach(Array(imageResults.prefix(3).enumerated()), id: \.offset) { index, result in
                            imageResultRow(result: result)
                        }
                    } else {
                        Text("No in-stock data available")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    }
                } else if let error = marketAnalysisError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    Button(action: {
                        loadMarketData()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                            Text("Retry")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(15)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text("No in-stock data available")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                .padding(.vertical, 8)
            }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .preferredColorScheme(.light)
    }
    
    private var soldAnalysisCard: some View {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
                
                Text("Sold")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if isLoadingMarketData {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                        Text("Loading sold data...")
                                                .font(.system(size: 14))
                            .foregroundColor(.secondary)
                                            Spacer()
                                        }
                            } else if let marketData = marketData {
                    // Show sold visual matches
                                if let visualMatches = marketData.visualMatches, !visualMatches.isEmpty {
                        // Filter for sold visual matches using smart inference
                        let soldMatches = filterSoldVisualMatches(visualMatches)
                        
                        let currentMatches = Array(soldMatches.prefix(10))
                                    
                                    if !currentMatches.isEmpty {
                            Text("Sold Visual Matches:")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                            .padding(.bottom, 4)
                                        
                            List {
                                ForEach(Array(currentMatches.enumerated()), id: \.offset) { index, result in
                                                visualMatchRowWithDelete(result: result, index: index)
                                                    .listRowSeparator(.hidden)
                                                    .listRowBackground(Color.clear)
                                                    .listRowInsets(EdgeInsets())
                                            }
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: CGFloat(currentMatches.count * 95)) // Approximate height per row
                            .scrollDisabled(true)
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                            // Calculate average price from sold items
                                        let prices = currentMatches.compactMap { result -> Double? in
                                            if let extractedValue = result.price?.extractedValue, extractedValue > 0 {
                                                return extractedValue
                                            } else if let priceString = result.price?.value {
                                                return extractNumericPrice(priceString)
                                            }
                                            return nil
                                        }
                                        
                                        let averagePrice = prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count)
                                        
                                        HStack {
                                Text("Sold Average (\(currentMatches.count) items):")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.gray)
                                            
                                            Spacer()
                                            
                                            Text(averagePrice > 0 ? "$\(String(format: "%.2f", averagePrice))" : "N/A")
                                                .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                                        }
                        } else {
                            Text("No sold items found")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .padding(.vertical, 8)
                                    }
                                }
                    // Show sold shopping results
                                else if let shoppingResults = marketData.shoppingResults, !shoppingResults.isEmpty {
                        // Filter for sold shopping results using smart inference
                        let soldResults = filterSoldShoppingResults(shoppingResults)
                                    
                        let currentResults = Array(soldResults.prefix(10))
                                    
                        if !currentResults.isEmpty {
                            Text("Sold Shopping Results:")
                                            .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.gray)
                                            .padding(.bottom, 4)
                                        
                            List {
                                ForEach(Array(currentResults.enumerated()), id: \.offset) { index, result in
                                                shoppingResultRowWithDelete(result: result, index: index)
                                                    .listRowSeparator(.hidden)
                                                    .listRowBackground(Color.clear)
                                                    .listRowInsets(EdgeInsets())
                                            }
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: CGFloat(currentResults.count * 95)) // Approximate height per row
                            .scrollDisabled(true)
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                    
                            // Calculate average price from sold results
                            let prices = currentResults.compactMap { result -> Double? in
                                            if let extractedPrice = result.extractedPrice, extractedPrice > 0 {
                                                return extractedPrice
                                            } else if let priceString = result.price {
                                                return extractNumericPrice(priceString)
                                            }
                                            return nil
                                        }
                                        
                                        let averagePrice = prices.isEmpty ? 0 : prices.reduce(0, +) / Double(prices.count)
                                        
                                        HStack {
                                Text("Sold Average (\(currentResults.count) items):")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.gray)
                                            
                                            Spacer()
                                            
                                            Text(averagePrice > 0 ? "$\(String(format: "%.2f", averagePrice))" : "N/A")
                                                .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("No sold items found")
                                .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                .padding(.vertical, 8)
                        }
                    } else {
                        Text("No sold data available")
                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                                }
                        } else if let error = marketAnalysisError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                        Text(error)
                                        .font(.system(size: 14))
                            .foregroundColor(.orange)
                                    Spacer()
                                }
                    .padding(.vertical, 4)
                        } else {
                    Text("No sold data available")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                        .padding(.vertical, 8)
                                    }
                                }
                            }
                            .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .preferredColorScheme(.light)
    }
                            
    private var clothingDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
                        HStack {
                Image(systemName: "tshirt.fill")
                                .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                                    
                Text("Details")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                                    
                                    Spacer()
                
                // Authenticity indicator on the right
                if let details = clothingDetails, let isAuthentic = details.isAuthentic {
                    Text(isAuthentic ? "Authentic" : "Counterfeit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isAuthentic ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isAuthentic ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(8)
                }
                
                if isAnalyzingClothing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let details = clothingDetails {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    // Category
                    DetailCard(
                        icon: "tag.fill",
                        title: "CATEGORY",
                        value: details.category ?? "Unknown",
                        color: .green
                    )
                    
                    // Style
                    DetailCard(
                        icon: "sparkles",
                        title: "STYLE",
                        value: details.style ?? "Unknown",
                        color: .blue
                    )
                    
                    // Season
                    DetailCard(
                        icon: "leaf.fill",
                        title: "SEASON",
                        value: details.season ?? "Unknown",
                        color: .orange
                    )
                    
                    // Gender
                    DetailCard(
                        icon: "person.fill",
                        title: "GENDER",
                        value: details.gender ?? "Unknown",
                        color: .purple
                    )
                    
                    // Designer Tier
                    DetailCard(
                        icon: "diamond.fill",
                        title: "DESIGNER TIER",
                        value: details.designerTier ?? "Unknown",
                        color: .indigo
                    )
                    
                    // Era
                    DetailCard(
                        icon: "clock.fill",
                        title: "ERA",
                        value: details.era ?? "Unknown",
                        color: .brown
                    )
                }
                
                // Colors Section
                if let colors = details.colors, !colors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                            Image(systemName: "paintpalette.fill")
                                            .font(.system(size: 14))
                                .foregroundColor(.green)
                            Text("COLORS")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(colors, id: \.self) { color in
                                Text(color)
                                            .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                            }
                                        Spacer()
                                    }
                                }
                    .padding(.top, 8)
                            }
                            
                // Fabric Composition Section
                if let fabrics = details.fabricComposition, !fabrics.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                            Image(systemName: "fiberchannel")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("FABRIC COMPOSITION")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(fabrics, id: \.material) { fabric in
                                HStack {
                                    Text(fabric.material)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(fabric.percentage)%")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } else if isAnalyzingClothing {
                HStack {
                    Text("Analyzing clothing details...")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let details = clothingDetails, details.category?.contains("Error") == true {
                VStack(spacing: 12) {
                    Text("Analysis failed due to network issues.")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        analyzeClothingDetails()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                            Text("Retry Analysis")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(15)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 20)
            } else {
                // Analysis should be running automatically
                VStack(spacing: 12) {
                    Text("Analyzing clothing details...")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .italic()
                    
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .padding(.vertical, 20)
                                }
                            }
                            .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .preferredColorScheme(.light)
    }
    
    // MARK: - Main Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                headerView
                    .zIndex(1)
                contentScrollView
            }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .overlay(
                // Average Price Info Popup
                Group {
                    if showingAveragePriceInfo {
                        ZStack {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showingAveragePriceInfo = false
                                }
                            
                            VStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Text("How Average Price is Calculated")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            showingAveragePriceInfo = false
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("We calculate the average price by:")
                                            .font(.system(size: 14))
                                            .foregroundColor(.black)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.blue)
                                                Text("Adding up all listing prices from current resale platforms")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.black)
                                            }
                                            
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.blue)
                                                Text("Adding up all sold prices from recently completed sales")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.black)
                                            }
                                            
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.blue)
                                                Text("Dividing the total sum by the number of data points")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("💡 Pro Tip:")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.orange)
                                            
                                            Text("Sometimes we pick up bad data points. You can swipe left on any result to delete it, and the average price will update automatically!")
                                                .font(.system(size: 14))
                                                .foregroundColor(.black)
                                        }
                                    }
                                }
                                .padding(20)
                                .background(Color.white)
                                .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            )
            .onAppear {
                // Debug cache contents on app startup
                print("📱 SongEditView appeared for song: '\(song.title)' (ID: \(song.id.uuidString))")
                MarketDataCache.shared.debugCacheContents()
                
                // Load persistent deletions for this song
                loadDeletions()
                
                // Only auto-load market data if user hasn't deleted items
                if !hasDeletedItems {
                    loadMarketData()
                }
            
            // Check if this is a default sample song - use hardcoded sample clothing details
            if let sampleClothingDetails = createSampleClothingDetails(for: song.title) {
                print("📦 Loading sample clothing details for default song: \(song.title)")
                self.clothingDetails = sampleClothingDetails
            } else {
                // Start analysis if image already exists
                if song.customImage != nil {
                    let imageCount = song.allImages.count
                    print("🔍 Image exists on appear (\(imageCount) total images), starting clothing analysis...")
                    
                    // Check for pre-analyzed results from parallel analysis first
                    if let firstImage = song.allImages.first,
                       let cachedDetails = AnalysisResultsCache.shared.getClothingDetails(for: firstImage) {
                        print("📦 Loading Clothing Details from parallel analysis cache")
                        self.clothingDetails = cachedDetails
                    } else {
                        // Fallback to old cache mechanism
                    let clothingCacheKey = "clothing_details_\(song.id.uuidString)_\(song.allImages.count)"
                    if let cachedClothingResponse = MarketDataCache.shared.getOpenAIResponse(for: "clothing_details", input: clothingCacheKey) {
                            print("📦 Loading Clothing Details from traditional cache on appear")
                        let details = parseClothingDetailsResponse(cachedClothingResponse)
                        self.clothingDetails = details
                    } else if clothingDetails == nil && !isAnalyzingClothing {
                        // Check if analysis is already in progress from camera/upload flow
                        // If not found in any cache, then start analysis
                        print("🔍 No cached clothing details found, starting automatic analysis...")
                        analyzeClothingDetails()
                        }
                    }
                    
                    // Check for pre-generated title from parallel analysis
                    if song.title == "Analyzing...",
                       let firstImage = song.allImages.first,
                       let cachedTitle = AnalysisResultsCache.shared.getGeneratedTitle(for: firstImage) {
                        print("📦 Loading title from parallel analysis cache")
                        // Update the song title in the song manager
                        if let songIndex = songManager.songs.firstIndex(where: { $0.id == song.id }) {
                            songManager.songs[songIndex].title = cachedTitle
                            self.song.title = cachedTitle
                            // Also update the corresponding recent find
                            if let recentFindsManager = recentFindsManager {
                                updateRecentFindFromAnalysis(recentFindsManager: recentFindsManager, songId: song.id, newTitle: cachedTitle)
                            }
                        }
                    } else if song.title == "Analyzing..." {
                        generateItemTitle()
                    }
                }
            }
            
            // Mark view as fully loaded and trigger confetti if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isViewFullyLoaded = true
                if shouldTriggerConfettiWhenLoaded {
                    shouldTriggerConfettiWhenLoaded = false
                    trigger += 1
                }
            }
        }
        .onDisappear {
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .any(of: [.images]))
            .onChange(of: selectedPhoto) { newValue in
                Task {
                    if let newValue = newValue,
                       let data = try? await newValue.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        song.customImage = uiImage
                        song.lastEdited = Date()
                        songManager.updateSongInPlace(song)
                        
                    // Reload market data with the new image
                    await MainActor.run {
                        // Clear cache for this specific song/card
                        MarketDataCache.shared.removeMarketData(for: song.id.uuidString, hasCustomImage: true)
                        MarketDataCache.shared.removeMarketData(for: song.id.uuidString, hasCustomImage: false)
                        
                        // Also clear search query cache to ensure fresh data with new image
                        let searchQuery = generateSearchQuery()
                        MarketDataCache.shared.removeMarketDataByQuery(searchQuery: searchQuery, hasCustomImage: true)
                        MarketDataCache.shared.removeMarketDataByQuery(searchQuery: searchQuery, hasCustomImage: false)
                        
                        let clothingCacheKey = "clothing_details_\(song.id.uuidString)_\(song.allImages.count)"
                        MarketDataCache.shared.removeOpenAIResponse(for: "clothing_details", input: clothingCacheKey)
                        
                        marketData = nil // Clear existing data
                        marketAnalysisError = nil // Clear any previous errors
                        
                        // Reset analysis when new photo is selected
                        
                        // Clear displayed items
                        displayedVisualMatches = []
                        displayedShoppingResults = []
                        
                        // Reset clothing details
                        clothingDetails = nil
                        isAnalyzingClothing = false
                        
                        // Auto-start clothing details analysis for uploaded image
                        analyzeClothingDetails()
                    }
                    loadMarketData()
                }
            }
                }
            .onTapGesture {
                // Dismiss title editing when tapping outside
                if isEditingTitle {
                    isEditingTitle = false
                    isTitleFocused = false
            }
            }
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteSongWithCacheCleanup()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
            Text("Are you sure you want to delete this item? This action cannot be undone.")
            }
        .sheet(isPresented: $showingExpandedImage) {
            ImageExpansionView(imageURL: expandedImageURL ?? "")
        }
    }
    
    // MARK: - Delete Item Function
    private func deleteSongWithCacheCleanup() {
        print("🗑️ Deleting song: '\(song.title)' (ID: \(song.id))")
        
        // Clear all cached data for this song
        MarketDataCache.shared.removeMarketData(for: song.id.uuidString, hasCustomImage: true)
        MarketDataCache.shared.removeMarketData(for: song.id.uuidString, hasCustomImage: false)
        
        // Clear OpenAI cached responses for this song
        let songIdString = song.id.uuidString
        MarketDataCache.shared.removeOpenAIResponse(for: "clothing_details", input: "clothing_details_\(songIdString)_\(song.allImages.count)")
        MarketDataCache.shared.removeOpenAIResponse(for: "title_generation", input: "title_generation_\(songIdString)_\(song.allImages.count)")
        
        print("✅ Cleared all cached data for song: \(song.id)")
        
        // Remove the song from the song manager
        songManager.deleteSong(song)
        
        // Close the edit view
        onDismiss()
    }
    
    // MARK: - Helper Views for Market Data
    @ViewBuilder
    private func marketRow(platform: String, range: String, note: String) -> some View {
        HStack {
            Text(platform)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                .frame(minWidth: 60, alignment: .leading)
            
            Text(range)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
            
            Spacer()
            
            Text(note)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.trailing)
        }
    }
    
    @ViewBuilder
    private func imageResultRow(result: ImageResult) -> some View {
        HStack(spacing: 12) {
            // Thumbnail if available (non-clickable, bigger)
            if let thumbnail = result.thumbnail {
                // Check if it's a local asset or remote URL
                if thumbnail.hasPrefix("http") {
                    // Remote URL - use AsyncImage
                    AsyncImage(url: URL(string: thumbnail)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                            )
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                } else {
                    // Local asset - use Image
                    Image(thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                }
            } else {
                // Placeholder when no image available
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title ?? "Unknown Item")
                    .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                    .lineLimit(2)
                
                if let source = result.source {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func organicResultRow(result: OrganicResult) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title ?? "Unknown Item")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(2)
                
                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func shoppingResultRowWithDelete(result: ShoppingResult, index: Int) -> some View {
            // Product content
            Button(action: {
                guard !isScrolling else { return }
                if let urlString = result.link, let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 8) {
                    // Product thumbnail (non-clickable, bigger)
                    if let thumbnail = result.thumbnail {
                            AsyncImage(url: URL(string: thumbnail)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                        .font(.system(size: 20))
                                )
                        }
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                    } else {
                        // Placeholder when no image
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 24))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title ?? "Unknown Item")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            if let source = result.source {
                                Text(source)
                                    .font(.system(size: 12))
                .foregroundColor(.blue)
                            }
                            
                            // Display smart availability status instead of raw condition
                            let availabilityStatus = inferShoppingAvailabilityStatus(title: result.title, condition: result.condition, source: result.source)
                            Text(availabilityStatus == "available" ? "• In Stock" : "• Sold")
                                .font(.system(size: 12))
                                .foregroundColor(availabilityStatus == "available" ? .green : .red)
                        }
                        

                    }
            
            Spacer()
            
                    VStack(alignment: .trailing, spacing: 2) {
                        // Display USD converted price
                        if let price = result.price {
                            if let usdPrice = formatPriceToUSD(price) {
                                Text(usdPrice)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        
                        if let extractedPrice = result.extractedPrice, extractedPrice > 0 {
                            Text("$\(String(format: "%.2f", extractedPrice))")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                        }
                    }
                    .padding(.trailing, 16) // Add space for delete button
                }
            }
            .buttonStyle(PlainButtonStyle())
            .background(Color.clear)
            .contentShape(Rectangle())
        .padding(.vertical, 6)
        .offset(x: index == 0 && showSwipeHint ? swipeHintOffset : 0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteShoppingResult(result, at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder 
    private func shoppingResultRow(result: ShoppingResult) -> some View {
        Button(action: {
            guard !isScrolling else { return }
            if let urlString = result.link, let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
            // Product thumbnail (non-clickable, bigger)
            if let thumbnail = result.thumbnail {
                AsyncImage(url: URL(string: thumbnail)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                        )
                }
                .frame(width: 80, height: 80)
                .cornerRadius(8)
            } else {
                // Placeholder when no image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Unknown Item")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let source = result.source {
                        Text(source)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    
                    if let condition = result.condition {
                        Text("• \(condition)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                

            }
            
            Spacer()
            
                                VStack(alignment: .trailing, spacing: 2) {
                        if let price = result.price {
                            Text(price)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                        }
                        
                        if let extractedPrice = result.extractedPrice, extractedPrice > 0 {
                            Text("$\(String(format: "%.2f", extractedPrice))")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                        }
                    }
                    .padding(.trailing, 16) // Add space for delete button
            }
        }
        .buttonStyle(PlainButtonStyle()) // Prevent default button styling
        .background(Color.clear)
        .contentShape(Rectangle()) // Make entire row tappable
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func visualMatchRowWithDelete(result: VisualMatch, index: Int) -> some View {
            // Product content
            Button(action: {
                guard !isScrolling else { return }
                if let urlString = result.link, let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 8) {
                    // Thumbnail if available (non-clickable, bigger)
                    if let thumbnail = result.thumbnail {
                            // Check if it's a local asset or remote URL
                            if thumbnail.hasPrefix("http") {
                                // Remote URL - use AsyncImage
                                AsyncImage(url: URL(string: thumbnail)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                                .font(.system(size: 20))
                                        )
                                }
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                            } else {
                                // Local asset - use Image
                                Image(thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                            }
                    } else {
                        // Placeholder when no image available
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 24))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title ?? "Unknown Item")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            if let source = result.source {
                                Text(source)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            
                            // Display smart availability status instead of raw condition
                            let availabilityStatus = inferAvailabilityStatus(title: result.title, condition: result.condition, source: result.source, inStock: result.inStock)
                            Text(availabilityStatus == "available" ? "• In Stock" : "• Sold")
                                .font(.system(size: 12))
                                .foregroundColor(availabilityStatus == "available" ? .green : .red)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        // Display USD converted price
                        if let price = result.price?.value {
                            if let usdPrice = formatPriceToUSD(price) {
                                Text(usdPrice)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        

                    }
                    .padding(.trailing, 16) // Add space for delete button
                }
            }
            .buttonStyle(PlainButtonStyle())
            .background(Color.clear)
            .contentShape(Rectangle())
        .padding(.vertical, 6)
        .offset(x: index == 0 && showSwipeHint ? swipeHintOffset : 0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteVisualMatch(result, at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private func visualMatchRow(result: VisualMatch) -> some View {
        Button(action: {
            guard !isScrolling else { return }
            if let urlString = result.link, let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
            // Thumbnail if available
            if let thumbnail = result.thumbnail {
                // Check if it's a local asset or remote URL
                if thumbnail.hasPrefix("http") {
                    // Remote URL - use AsyncImage
                    AsyncImage(url: URL(string: thumbnail)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                    .font(.system(size: 14))
                            )
                    }
                    .frame(width: 55, height: 55)
                    .cornerRadius(6)
                } else {
                    // Local asset - use Image
                    Image(thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 55, height: 55)
                        .cornerRadius(6)
                }
            } else {
                // Placeholder when no image available
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 55, height: 55)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: 18))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title ?? "Unknown Item")
                    .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let source = result.source {
                        Text(source)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    if let condition = result.condition {
                        Text("• \(condition)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    if let inStock = result.inStock {
                        Text(inStock ? "• In Stock" : "• Sold")
                            .font(.system(size: 12))
                            .foregroundColor(inStock ? .green : .red)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let price = result.price?.value {
                    Text(price)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                }
                

            }
            }
        }
        .buttonStyle(PlainButtonStyle()) // Prevent default button styling
        .background(Color.clear)
        .contentShape(Rectangle()) // Make entire row tappable
        .padding(.vertical, 6)
    }
    

    
    // Function to load selected instrumental
    private func loadInstrumental(_ instrumentalTitle: String, saveAssociation: Bool = true) {
        print("🎵 Loading instrumental: \(instrumentalTitle) (saveAssociation: \(saveAssociation))")
        print("🔍 Current song: \(song.title)")
        print("🔍 Current song.associatedInstrumental before: \(song.associatedInstrumental ?? "nil")")
        
        let sharedManager = SharedInstrumentalManager.shared
        
        // Get the audio manager (this will auto-reload if needed)
        let instrumentalAudioManager = sharedManager.getAudioManager(for: instrumentalTitle)
        
        if let sourcePlayer = instrumentalAudioManager.player {
            print("🎶 Found player in audio manager")
            // Create a new player with the same URL to avoid sharing player instances
            do {
                // First stop any current audio and reset states
                audioManager.stop()
                
                // Reset all audio states before loading new instrumental
                audioManager.isPlaying = false
                audioManager.currentTime = 0
                audioManager.isLooping = false
                audioManager.loopStart = 0
                audioManager.loopEnd = 0
                audioManager.hasCustomLoop = false
                
                // Load the new instrumental
                audioManager.player = try AVAudioPlayer(contentsOf: sourcePlayer.url!)
                audioManager.player?.prepareToPlay()
                audioManager.duration = sourcePlayer.duration
                audioManager.audioFileName = instrumentalTitle
                
                // Ensure proper global audio manager state
                GlobalAudioManager.shared.currentPlayingManager = audioManager
                print("🌐 Set audioManager as current in GlobalAudioManager")
                
                // Force comprehensive UI update with aggressive state synchronization
                DispatchQueue.main.async {
                    hasInstrumentalLoaded = true // Immediately update UI state
                    audioManager.objectWillChange.send()
                }
                
                // Multi-phase refresh with extended timing for view recreation scenarios
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    hasInstrumentalLoaded = true
                    audioManager.objectWillChange.send()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    hasInstrumentalLoaded = true
                    audioManager.objectWillChange.send()
                }
                
                // Extended refresh for view recreation scenarios (300ms)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if audioManager.player != nil {
                        hasInstrumentalLoaded = true
                        audioManager.objectWillChange.send()
                        print("🔄 Extended refresh: Ensuring UI shows instrumental after view recreation")
                    }
                }
                
                // Only save the instrumental association if explicitly requested (to prevent overwriting during auto-load)
                if saveAssociation {
                    song.associatedInstrumental = instrumentalTitle
                    song.lastEdited = Date()
                    songManager.updateSong(song)
                    print("💾 Saved instrumental association with song: \(instrumentalTitle)")
                } else {
                    print("ℹ️ Loaded instrumental without updating association (auto-load)")
                }
                
                print("✅ Loaded instrumental with fresh state: \(instrumentalTitle)")
                print("🔍 Current song.associatedInstrumental after: \(song.associatedInstrumental ?? "nil")")
                print("🔍 hasInstrumentalLoaded set to: \(hasInstrumentalLoaded)")
                print("🔍 audioManager.player exists: \(audioManager.player != nil)")
            } catch {
                print("❌ Failed to create new player for instrumental: \(error)")
            }
        } else {
            print("❌ No player available for instrumental: \(instrumentalTitle)")
            print("⚠️ The instrumental file may be missing or corrupted. Try re-adding it.")
            print("🔍 Current song.associatedInstrumental unchanged: \(song.associatedInstrumental ?? "nil")")
        }
    }
    
    // Function to load associated instrumental when view appears
    private func loadAssociatedInstrumental() {
        print("🔍 Checking associated instrumental for song: \(song.title)")
        print("🔍 Current song.associatedInstrumental: \(song.associatedInstrumental ?? "nil")")
        print("🔍 Current audioManager.player: \(audioManager.player != nil ? "exists" : "nil")")
        print("🔍 Current hasInstrumentalLoaded: \(hasInstrumentalLoaded)")
        
        guard let associatedInstrumental = song.associatedInstrumental else {
            print("📝 No associated instrumental for song: \(song.title)")
            // Ensure UI state is correct when no instrumental should be loaded
            hasInstrumentalLoaded = false
            return
        }
        
        // Debug: Check if this is the problematic LoBo file
        if associatedInstrumental.contains("LoBo") {
            print("🚨 Found LoBo reference in song '\(song.title)' - this might be the source of the persistent error")
            print("🚨 Clearing this association to fix the error...")
            song.associatedInstrumental = nil
            songManager.updateSong(song)
            return
        }
        
        print("🔄 Loading associated instrumental: \(associatedInstrumental) for song: \(song.title)")
        loadInstrumental(associatedInstrumental, saveAssociation: false)
        
        // Additional state synchronization after loading associated instrumental
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if audioManager.player != nil && !hasInstrumentalLoaded {
                print("🔧 UI state sync: Correcting hasInstrumentalLoaded to true after associated instrumental load")
                hasInstrumentalLoaded = true
                audioManager.objectWillChange.send()
            }
        }
    }
    
    // Function to clear the instrumental from the song
    private func clearInstrumental() {
        print("🗑️ Clearing instrumental from song: \(song.title)")
        
        // Stop any playing audio first
        audioManager.stop()
        
        // Clear from global audio manager to prevent stale references
        if GlobalAudioManager.shared.currentPlayingManager === audioManager {
            GlobalAudioManager.shared.currentPlayingManager = nil
            print("🌐 Cleared audioManager from GlobalAudioManager")
        }
        
        // Clear ALL audio manager states
        audioManager.player = nil
        audioManager.duration = 0
        audioManager.audioFileName = ""
        audioManager.isPlaying = false
        audioManager.currentTime = 0
        audioManager.isLooping = false
        audioManager.loopStart = 0
        audioManager.loopEnd = 0
        audioManager.hasCustomLoop = false
        
        // Force complete UI state reset with extended clearing
        DispatchQueue.main.async {
            hasInstrumentalLoaded = false // Immediately update UI state
            audioManager.objectWillChange.send()
        }
        
        // Multiple-phase clearing to ensure state is fully reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            hasInstrumentalLoaded = false
            audioManager.objectWillChange.send()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hasInstrumentalLoaded = false
            audioManager.objectWillChange.send()
        }
        
        // Extended clearing for persistent state reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            hasInstrumentalLoaded = false
            audioManager.objectWillChange.send()
            print("🗑️ Extended clear: Ensured hasInstrumentalLoaded = false")
        }
        
        // Remove the association from the song
        song.associatedInstrumental = nil
        song.lastEdited = Date()
        songManager.updateSong(song)
        
        print("✅ Instrumental completely cleared - all states and global references reset")
    }
    
    // Function to delete the current song
    private func deleteSong() {
        print("🗑️ Deleting song: \(song.title)")
        
        // Delete the song from the manager
        songManager.deleteSong(song)
        
        print("✅ Song deleted successfully")
        
        // Dismiss the view after deletion
        onDismiss()
    }
    

    
    // Legacy Compact Audio Player View (kept for reference but not used)
    private var compactAudioPlayer: some View {
        VStack(spacing: 12) {
            // Main player interface - simplified design
            VStack(spacing: 12) {
                // Top row: File info and play button
                HStack(spacing: 12) {
                    // Waveform icon
                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.1))
                        )
                    
                    // File name and time - smaller text
                    VStack(alignment: .leading, spacing: 1) {
                        Text(audioManager.audioFileName.isEmpty ? "file name here" : audioManager.audioFileName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text("\(formatTime(audioManager.currentTime)) / \(formatTime(audioManager.duration))")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Play button
                    Button(action: {
                        if audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            audioManager.play()
                        }
                    }) {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.1))
                            )
                    }
                }
                
                // Simple progress line with draggable markers
                GeometryReader { geometry in
                    ZStack {
                        // Background line - taller but thinner
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.2))
                            .frame(height: 6)
                        
                        // Progress line - taller but thinner
                        HStack {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "#8B5CF6"),
                                            Color(hex: "#EC4899")
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(audioManager.currentTime / max(audioManager.duration, 1)), height: 6)
                            
                            Spacer()
                        }
                        
                        // Draggable Start marker - thinner and taller (WHITE/YELLOW for debugging)
                        Rectangle()
                            .fill(.yellow)
                            .frame(width: 2, height: 35)
                            .position(
                                x: geometry.size.width * CGFloat(audioManager.loopStart / max(audioManager.duration, 1)),
                                y: 17.5
                            )
                            .contentShape(Rectangle().size(width: 30, height: 35))
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Use proper coordinate system
                                        let newX = value.startLocation.x + value.translation.width
                                        let clampedX = max(0, min(newX, geometry.size.width))
                                        let newStart = audioManager.duration * Double(clampedX / geometry.size.width)
                                        let clampedStart = max(0, min(newStart, audioManager.duration - 1))
                                        audioManager.loopStart = clampedStart
                                        audioManager.hasCustomLoop = true
                                    }
                            )
                        
                        // Draggable End marker - thinner and taller (WHITE/BLUE for debugging)
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 2, height: 35)
                            .position(
                                x: geometry.size.width * CGFloat(audioManager.loopEnd / max(audioManager.duration, 1)),
                                y: 17.5
                            )
                            .contentShape(Rectangle().size(width: 30, height: 35))
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Use proper coordinate system
                                        let newX = value.startLocation.x + value.translation.width
                                        let clampedX = max(0, min(newX, geometry.size.width))
                                        let newEnd = audioManager.duration * Double(clampedX / geometry.size.width)
                                        let clampedEnd = max(1, min(newEnd, audioManager.duration))
                                        audioManager.loopEnd = clampedEnd
                                        audioManager.hasCustomLoop = true
                                    }
                            )
                        
                        // Current position indicator - ONLY this should control audio scrubbing
                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)
                            .position(
                                x: geometry.size.width * CGFloat(audioManager.currentTime / max(audioManager.duration, 1)),
                                y: 17.5
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newX = value.startLocation.x + value.translation.width
                                        let clampedX = max(0, min(newX, geometry.size.width))
                                        let newTime = audioManager.duration * Double(clampedX / geometry.size.width)
                                        audioManager.seek(to: newTime)
                                    }
                            )
                    }
                }
                .frame(height: 35)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            
            // Loop controls - simplified for clean line interface
            HStack(spacing: 12) {
                if audioManager.hasCustomLoop {
                    Button(action: {
                        audioManager.seek(to: audioManager.loopStart)
                        audioManager.play()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                            Text("Play Loop Section")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black)
                        )
                    }
                    
                    Button(action: { audioManager.resetLoop() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                            Text("Clear Loop")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.1))
                        )
                    }
                } else {
                    Text("Drag the white markers on the line to set loop points")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .italic()
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Debug Helper Functions
    
    private func debugAndFilterVisualMatches(_ visualMatches: [VisualMatch]) -> [VisualMatch] {
        print("🔍 Visual Filter Debug: Starting with \(visualMatches.count) visual matches")
        
        // Debug each item before filtering
        for (index, match) in visualMatches.enumerated() {
            let hasPrice = match.price?.extractedValue != nil && (match.price?.extractedValue ?? 0) > 0
            let inferredStatus = inferAvailabilityStatus(title: match.title, condition: match.condition, source: match.source, inStock: match.inStock)
            print("   Item \(index + 1): Price=\(match.price?.extractedValue ?? -1) HasPrice=\(hasPrice) Status=\(inferredStatus) Title=\(match.title ?? "N/A")")
        }
        
        // First try filtering for items with prices (removed inStock requirement)
        let pricedMatches = visualMatches.filter { result in
            let hasPrice = result.price?.extractedValue != nil && (result.price?.extractedValue ?? 0) > 0
            return hasPrice
        }
        
        if !pricedMatches.isEmpty {
            print("🔍 Visual Filter Result: \(pricedMatches.count) items with prices found")
            return pricedMatches
        }
        
        // If no items with prices, show relevant content that appears to be product-related
        let relevantMatches = visualMatches.filter { result in
            guard let title = result.title?.lowercased() else { return false }
            
            // Exclude obvious non-product content
            let isRelevant = !title.contains("youtube") && 
                           !title.contains("tiktok") && 
                           !title.contains("instagram") && 
                           !title.contains("new york times") && 
                           !title.contains("vogue") && 
                           !title.contains("best 10") &&
                           !title.contains("top 10") &&
                           !title.contains("guide to") &&
                           !title.contains("how to") &&
                           title.count < 150 // Exclude very long titles (likely articles)
            
            // Prefer content that mentions actual products or stores
            let hasProductKeywords = title.contains("bag") || 
                                   title.contains("handbag") || 
                                   title.contains("purse") || 
                                   title.contains("louis vuitton") || 
                                   title.contains("vintage") ||
                                   title.contains("speedy") ||
                                   title.contains("monogram")
            
            return isRelevant && hasProductKeywords
        }
        
        print("🔍 Visual Filter Result: \(relevantMatches.count) relevant items found (no prices available)")
        return relevantMatches
    }
    
    // Smart availability inference based on text patterns and inStock boolean
    private func inferAvailabilityStatus(title: String?, condition: String?, source: String?, inStock: Bool? = nil) -> String {
        // First check if we have explicit inStock data (for hardcoded items)
        if let inStock = inStock {
            return inStock ? "available" : "sold"
        }
        
        let allText = "\(title ?? "") \(condition ?? "") \(source ?? "")".lowercased()
        
        // Strong indicators of SOLD status
        if allText.contains("sold") ||
           allText.contains("no longer available") ||
           allText.contains("out of stock") ||
           allText.contains("discontinued") ||
           allText.contains("auction ended") ||
           allText.contains("listing ended") ||
           allText.contains("item removed") {
            return "sold"
        }
        
        // Strong indicators of AVAILABLE status
        if allText.contains("buy now") ||
           allText.contains("add to cart") ||
           allText.contains("in stock") ||
           allText.contains("available") ||
           allText.contains("ships") ||
           allText.contains("delivery") ||
           allText.contains("free shipping") ||
           allText.contains("buy it now") ||
           allText.contains("purchase") {
            return "available"
        }
        
        // If no clear indicators, assume available (better to show too many than too few)
        return "available"
    }
    
    // Filter specifically for available items
    private func filterAvailableVisualMatches(_ visualMatches: [VisualMatch]) -> [VisualMatch] {
        // First apply deletion filtering, then availability filtering
        let notDeletedMatches = getFilteredVisualMatches(visualMatches)
        return notDeletedMatches.filter { match in
            let hasPrice = match.price?.extractedValue != nil && (match.price?.extractedValue ?? 0) > 0
            let status = inferAvailabilityStatus(title: match.title, condition: match.condition, source: match.source, inStock: match.inStock)
            return hasPrice && status == "available"
        }
    }
    
    // Filter specifically for sold items
    private func filterSoldVisualMatches(_ visualMatches: [VisualMatch]) -> [VisualMatch] {
        // First apply deletion filtering, then availability filtering
        let notDeletedMatches = getFilteredVisualMatches(visualMatches)
        return notDeletedMatches.filter { match in
            let hasPrice = match.price?.extractedValue != nil && (match.price?.extractedValue ?? 0) > 0
            let status = inferAvailabilityStatus(title: match.title, condition: match.condition, source: match.source, inStock: match.inStock)
            return hasPrice && status == "sold"
        }
    }
    
    private func debugAndFilterShoppingResults(_ shoppingResults: [ShoppingResult]) -> [ShoppingResult] {
        print("🔍 Shopping Filter Debug: Starting with \(shoppingResults.count) shopping results")
        
        // Debug each item before filtering
        for (index, result) in shoppingResults.enumerated() {
            let hasPrice = (result.extractedPrice != nil && result.extractedPrice ?? 0 > 0) || 
                         (result.price != nil && result.price != "N/A" && !result.price!.isEmpty)
            let inferredStatus = inferShoppingAvailabilityStatus(title: result.title, condition: result.condition, source: result.source)
            print("   Item \(index + 1): ExtractedPrice=\(result.extractedPrice ?? -1) Price=\(result.price ?? "N/A") HasPrice=\(hasPrice) Status=\(inferredStatus) Title=\(result.title ?? "N/A")")
        }
        
        // Filter for items with prices (removed sold/instock filtering)
        let pricedResults = shoppingResults.filter { result in
            let hasPrice = (result.extractedPrice != nil && result.extractedPrice ?? 0 > 0) || 
                         (result.price != nil && result.price != "N/A" && !result.price!.isEmpty)
            return hasPrice
        }
        
        print("🔍 Shopping Filter Result: \(pricedResults.count) items with prices found")
        return pricedResults
    }
    
    // Smart availability inference for shopping results
    private func inferShoppingAvailabilityStatus(title: String?, condition: String?, source: String?) -> String {
        let allText = "\(title ?? "") \(condition ?? "") \(source ?? "")".lowercased()
        
        // Strong indicators of SOLD status
        if allText.contains("sold") ||
           allText.contains("out of stock") ||
           allText.contains("unavailable") ||
           allText.contains("no longer available") ||
           allText.contains("discontinued") ||
           allText.contains("sold out") ||
           allText.contains("temporarily out of stock") {
            return "sold"
        }
        
        // Strong indicators of AVAILABLE status
        if allText.contains("in stock") ||
           allText.contains("available") ||
           allText.contains("buy now") ||
           allText.contains("add to cart") ||
           allText.contains("ships") ||
           allText.contains("delivery") ||
           allText.contains("free shipping") ||
           allText.contains("quick delivery") ||
           allText.contains("express shipping") ||
           allText.contains("same day") ||
           allText.contains("next day") {
            return "available"
        }
        
        // If no clear indicators, assume available
        return "available"
    }
    
    // Filter specifically for available shopping results
    private func filterAvailableShoppingResults(_ shoppingResults: [ShoppingResult]) -> [ShoppingResult] {
        // First apply deletion filtering, then availability filtering
        let notDeletedResults = getFilteredShoppingResults(shoppingResults)
        return notDeletedResults.filter { result in
            let hasPrice = (result.extractedPrice != nil && result.extractedPrice ?? 0 > 0) || 
                         (result.price != nil && result.price != "N/A" && !result.price!.isEmpty)
            let status = inferShoppingAvailabilityStatus(title: result.title, condition: result.condition, source: result.source)
            return hasPrice && status == "available"
        }
    }
    
    // Filter specifically for sold shopping results
    private func filterSoldShoppingResults(_ shoppingResults: [ShoppingResult]) -> [ShoppingResult] {
        // First apply deletion filtering, then availability filtering
        let notDeletedResults = getFilteredShoppingResults(shoppingResults)
        return notDeletedResults.filter { result in
            let hasPrice = (result.extractedPrice != nil && result.extractedPrice ?? 0 > 0) || 
                         (result.price != nil && result.price != "N/A" && !result.price!.isEmpty)
            let status = inferShoppingAvailabilityStatus(title: result.title, condition: result.condition, source: result.source)
            return hasPrice && status == "sold"
        }
    }
}

// MARK: - Thrift Image Picker
struct ThriftImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.mediaTypes = ["public.image"]
        
        // Customize the picker appearance
        picker.navigationBar.tintColor = UIColor.systemBlue
        picker.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ThriftImagePicker
        
        init(_ parent: ThriftImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Compress image if needed for better performance
                let compressedImage = compressImage(image)
                parent.onImagePicked(compressedImage)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        private func compressImage(_ image: UIImage) -> UIImage {
            // Resize large images for better performance
            let maxSize: CGFloat = 1920
            let ratio = min(maxSize / image.size.width, maxSize / image.size.height)
            
            if ratio < 1.0 {
                let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let newImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return newImage ?? image
            }
            
            return image
        }
    }
}

// MARK: - Missing Components

struct TimePickerButton: View {
    @Binding var text: String
    let onUpdate: (String) -> Void
    @State private var showingPicker = false
    
    var body: some View {
        Button(action: {
            showingPicker = true
        }) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 45)
                .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingPicker) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: {
                        showingPicker = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                }
                .frame(height: 44)
                
                TimePicker(text: $text, onUpdate: onUpdate)
                    .frame(height: 160)
                
                Spacer(minLength: 0)
            }
            .background(Color.black)
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct TimePicker: UIViewRepresentable {
    @Binding var text: String
    let onUpdate: (String) -> Void
    
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        
        if let time = parseTimeComponents(text) {
            let minuteRow = max(0, min(time.minutes, 9))
            let secondRow = max(0, min(time.seconds, 59))
            picker.selectRow(minuteRow, inComponent: 0, animated: false)
            picker.selectRow(secondRow, inComponent: 1, animated: false)
        }
        
        return picker
    }
    
    func updateUIView(_ uiView: UIPickerView, context: Context) {
        if let time = parseTimeComponents(text) {
            let minuteRow = max(0, min(time.minutes, 9))
            let secondRow = max(0, min(time.seconds, 59))
            uiView.selectRow(minuteRow, inComponent: 0, animated: false)
            uiView.selectRow(secondRow, inComponent: 1, animated: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    private func parseTimeComponents(_ timeString: String) -> (minutes: Int, seconds: Int)? {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]),
              minutes >= 0, minutes <= 9,
              seconds >= 0, seconds <= 59
        else {
            return nil
        }
        return (minutes, seconds)
    }
    
    class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        let parent: TimePicker
        
        init(parent: TimePicker) {
            self.parent = parent
        }
        
        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            return 2
        }
        
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            return component == 0 ? 10 : 60
        }
        
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            if component == 0 {
                label.text = "\(row)"
            } else {
                label.text = String(format: "%02d", row)
            }
            label.textColor = .white
            label.font = .systemFont(ofSize: 20, weight: .medium)
            label.textAlignment = .center
            return label
        }
        
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let minutes = pickerView.selectedRow(inComponent: 0)
            let seconds = pickerView.selectedRow(inComponent: 1)
            let timeString = "\(minutes):\(String(format: "%02d", seconds))"
            parent.text = timeString
            parent.onUpdate(timeString)
        }
    }
}

struct ToolDetailView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let description: String
    let backgroundImage: String
    @State private var userInput = ""
    @State private var generatedText = ""
    @State private var isGenerating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text(title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, geometry.safeAreaInsets.top + 1)
                        
                        Text(description)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    }
                    .background(
                        ZStack {
                            Image(backgroundImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                            
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.clear, location: 0.0),
                                    .init(color: Color.black.opacity(0.4), location: 0.5),
                                    .init(color: Color.black.opacity(0.95), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .ignoresSafeArea(.all, edges: .top)
                    )
                    
                    Spacer()
                }
            }
        }
    }
}

struct DetailCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct ImageExpansionView: View {
    let imageURL: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                if imageURL.hasPrefix("http") {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        case .failure(_):
                            VStack(spacing: 16) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("Image not available")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .empty:
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Loading...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct ThriftCameraView: View {
    @Binding var isPresented: Bool
    let onImagesCapture: ([UIImage]) -> Void
    @StateObject private var serpAPIService = SerpAPIService()
    @StateObject private var cameraManager = CameraManager()
    @State private var currentStep: ScanStep = .capture
    @State private var capturedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var showingImagePicker = false
    @State private var marketData: SerpSearchResult?
    @State private var analysisError: String?
    
    enum ScanStep: CaseIterable {
        case capture
        case analysis
        
        var title: String {
            switch self {
            case .capture: return "Full Item"
            case .analysis: return "Analysis"
            }
        }
        
        var instruction: String {
            switch self {
            case .capture: return "Capture the entire item"
            case .analysis: return "Analyzing your image"
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            switch currentStep {
            case .capture:
                cameraView
            case .analysis:
                analysisView
            }
        }

    }
    
    private var cameraView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { 
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    // Stop camera immediately for faster dismissal
                    cameraManager.stopSession()
                    
                    isPresented = false 
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(currentStep.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(currentStep.instruction)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            ZStack {
                // Camera Preview
                CameraPreviewView(cameraManager: cameraManager)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 300, height: 300)
                
                VStack {
                    HStack {
                        CornerGuide(position: .topLeft)
                        Spacer()
                        CornerGuide(position: .topRight)
                    }
                    Spacer()
                    HStack {
                        CornerGuide(position: .bottomLeft)
                        Spacer()
                        CornerGuide(position: .bottomRight)
                    }
                }
                .frame(width: 300, height: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack(spacing: 20) {
                HStack(spacing: 60) {
                    // Gallery Button
                    Button(action: { showingImagePicker = true }) {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Main Capture Button
                    Button(action: captureCurrentStep) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 68, height: 68)
                                
                            Image(systemName: "camera")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                    
                    // Empty spacer to balance the layout
                    Spacer()
                        .frame(width: 50, height: 50)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 50)
        }
        .sheet(isPresented: $showingImagePicker) {
            ThriftImagePicker { image in
                capturedImage = image
                print("📷 Successfully selected photo from library - size: \(image.size)")
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                // Start API calls immediately after photo selection (same as camera capture)
                Task {
                    await performMarketAnalysis()
                }
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    goToNextStep()
                }
            }
        }
    }
    
    private var analysisView: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.89)
                .ignoresSafeArea()
            
            ZStack(alignment: .topLeading) {
                // Main content
                VStack(spacing: 40) {
                    Spacer()
                    
                    if let image = capturedImage {
                        VStack(spacing: 16) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 200, height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        }
                    }
                
                    VStack(spacing: 16) {
                        if let error = analysisError {
                            Text("Analysis Complete!")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        } else if let marketData = marketData {
                            Text("Analysis Complete!")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.black)
                        } else if isAnalyzing {
                            Text("Analyzing...")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.black)
                        } else {
                            Text("Ready")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.black)
                        }
                        
                        if let error = analysisError {
                            Text("Analysis completed with results")
                                .font(.system(size: 16))
                                .foregroundColor(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        } else if let marketData = marketData {
                            Text("Found \(marketData.shoppingResults?.count ?? 0) market listings")
                                .font(.system(size: 16))
                                .foregroundColor(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        } else if isAnalyzing {
                            Text("Running market analysis...")
                                .font(.system(size: 16))
                                .foregroundColor(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Tap to capture and analyze")
                                .font(.system(size: 16))
                                .foregroundColor(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        if isAnalyzing {
                            Text("AI is analyzing your image and searching market data")
                            .font(.system(size: 15))
                            .foregroundColor(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        } else if marketData != nil || analysisError != nil {
                            Text("Analysis complete - tap anywhere to continue")
                                .font(.system(size: 15))
                                .foregroundColor(.black.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        } else {
                            Text("Ready to capture and analyze your thrift find")
                                .font(.system(size: 15))
                                .foregroundColor(.black.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle(tint: .black.opacity(0.7)))
                            .frame(height: 4)
                            .padding(.horizontal, 40)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    private func performMarketAnalysis() async {
        isAnalyzing = true
        
        do {
            let searchQuery = generateSearchQuery()
            
            // Run market data searches in parallel first (faster APIs)
            async let ebayResults = serpAPIService.searchEBayItems(query: searchQuery, condition: "used")
            async let googleResults = serpAPIService.searchGoogleShopping(query: searchQuery)
            
            // Wait for market data first
            let (eBayData, googleData) = try await (ebayResults, googleResults)
            
            // Proceed with image immediately with market data
            await MainActor.run {
                self.marketData = eBayData
                
                if let image = self.capturedImage {
                    // Create song with market data ready
                    var capturedImages = [image]
                    self.onImagesCapture(capturedImages)
                }
                self.isPresented = false
                self.isAnalyzing = false
            }
            
            // Run vision analyses in background (slower APIs) after navigation - only if not cached
            Task.detached {
                do {
                    // Capture the image reference before the async calls
                    guard let capturedImage = self.capturedImage else { return }
                    
                    // Check if already cached to avoid unnecessary API calls
                    let hasClothingDetails = AnalysisResultsCache.shared.getClothingDetails(for: capturedImage) != nil
                    let hasTitle = AnalysisResultsCache.shared.getGeneratedTitle(for: capturedImage) != nil
                    
                    if hasClothingDetails && hasTitle {
                        print("📦 Background analysis skipped - already cached")
                        return
                    }
                    
                    print("🔍 Running background analysis for missing data - clothing: \(!hasClothingDetails), title: \(!hasTitle)")
                    
                    // Only run missing analyses
                    async let clothingAnalysis = hasClothingDetails ? nil : self.performClothingAnalysis()
                    async let titleGeneration = hasTitle ? nil : self.performTitleGeneration()
                    
                    let (clothingDetails, generatedTitle) = try await (clothingAnalysis, titleGeneration)
                    
                    // Store results in cache for when user views the analysis
                    if let details = clothingDetails {
                        AnalysisResultsCache.shared.storeClothingDetails(details, for: capturedImage)
                    }
                    if let title = generatedTitle {
                        AnalysisResultsCache.shared.storeGeneratedTitle(title, for: capturedImage)
                    }
                } catch {
                    print("⚠️ Background analysis failed: \(error)")
                }
            }
            
        } catch {
            await MainActor.run {
                self.analysisError = error.localizedDescription
                self.isAnalyzing = false
                
                // Immediately proceed without artificial delay
                    if let image = self.capturedImage {
                        self.onImagesCapture([image])
                    }
                    self.isPresented = false
                }
            }
        }
    
    // MARK: - Parallel Analysis Functions
    private func performClothingAnalysis() async throws -> ClothingDetails? {
        guard let image = capturedImage else { return nil }
        
        let prompt = """
        Analyze this clothing item and provide details in this exact JSON format:
        {
            "brand": "brand name or 'Unknown'",
            "category": "category like 'Shirt', 'Pants', 'Dress', etc.",
            "color": "primary color",
            "size": "size if visible or 'Unknown'",
            "material": "material type if visible or 'Unknown'",
            "style": "style description",
            "condition": "condition assessment",
            "estimatedValue": "estimated resale value or 'Unknown'",
            "isAuthentic": true/false or null if unknown
        }
        Be specific and accurate. If information isn't clearly visible, use 'Unknown' or null.
        """
        
        do {
            let response = try await OpenAIService.shared.generateVisionCompletion(
                prompt: prompt,
                images: [image],
                maxTokens: 500,
                temperature: 0.3
            )
            
            return parseClothingDetailsResponse(response)
        } catch {
            print("🔍 Clothing analysis failed: \(error)")
            return nil
        }
    }
    
    private func performTitleGeneration() async throws -> String? {
        guard let image = capturedImage else { return nil }
        
        let prompt = """
        Generate a concise, descriptive title for this thrift item for resale. 
        Format: [Brand/Style] [Type] [Key Features]
        Examples: "Vintage Levi's Denim Jacket", "Nike Air Force 1 Sneakers", "Floral Midi Dress"
        Keep it under 6 words and focus on the most sellable aspects.
        """
        
        do {
            let response = try await OpenAIService.shared.generateVisionCompletion(
                prompt: prompt,
                images: [image],
                maxTokens: 50,
                temperature: 0.7
            )
            
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("🏷️ Title generation failed: \(error)")
            return nil
        }
    }
    
    private func parseClothingDetailsResponse(_ response: String) -> ClothingDetails? {
        // Extract JSON from response if it contains other text
        let jsonStart = response.firstIndex(of: "{") ?? response.startIndex
        let jsonEnd = response.lastIndex(of: "}") ?? response.endIndex
        let jsonString = String(response[jsonStart...jsonEnd])
        
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ClothingDetails.self, from: data)
        } catch {
            print("🔍 Failed to decode clothing details: \(error)")
            return nil
        }
    }
    
    private func generateSearchQuery() -> String {
        let brandKeywords = ["vintage", "retro", "thrift", "secondhand"]
        let randomBrand = brandKeywords.randomElement() ?? "vintage"
        
        return "\(randomBrand) item thrift"
    }
    
    private func captureCurrentStep() {
        print("📷 Capture button pressed!")
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        print("📷 Camera ready status: \(cameraManager.isCameraReady)")
        
        cameraManager.capturePhoto { [self] image in
            DispatchQueue.main.async {
                if let capturedPhoto = image {
                    self.capturedImage = capturedPhoto
                    print("📷 Successfully captured photo - size: \(capturedPhoto.size)")
                    
                    // Start API calls immediately after photo capture
                    Task {
                        await self.performMarketAnalysis()
                    }
                } else {
                    print("📷 Failed to capture photo, using fallback")
                    // Fallback to a system image if capture fails
                    self.capturedImage = UIImage(systemName: "photo")
                }
                
                print("📷 About to transition to analysis step")
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.goToNextStep()
                }
            }
        }
    }
    
    private func goToNextStep() {
        print("📷 goToNextStep called - current step: \(currentStep)")
        switch currentStep {
        case .capture:
            currentStep = .analysis
            print("📷 Switched to analysis step")
        case .analysis:
            print("📷 Analysis complete - dismissing camera")
            isPresented = false
        }
    }
}

struct CornerGuide: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let position: Position
    
    var body: some View {
        VStack(spacing: 0) {
            if position == .topLeft || position == .topRight {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
            }
            
            HStack(spacing: 0) {
                if position == .topLeft || position == .bottomLeft {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 20, height: 2)
                }
                
                if position == .topRight || position == .bottomRight {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 20, height: 2)
                }
            }
            
            if position == .bottomLeft || position == .bottomRight {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
            }
        }
    }
}

// MARK: - Camera Preview Implementation
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        cameraManager.setupCamera(in: view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update camera preview frame when view bounds change
        DispatchQueue.main.async {
            cameraManager.updatePreviewFrame(to: uiView.bounds)
        }
        
        // Setup camera when it becomes ready (will be smart about not re-setting up)
        if cameraManager.isCameraReady {
            cameraManager.setupCamera(in: uiView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    @Published var isCameraReady = false
    @Published var isUsingFrontCamera = false
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var currentPhotoDelegate: PhotoCaptureDelegate?
    private var isCapturingPhoto = false
    private var hasSetupPreview = false
    
    override init() {
        super.init()
        // Defer camera permission check to avoid TCC violations during app startup
        DispatchQueue.main.async { [weak self] in
            self?.checkCameraPermission()
        }
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("📷 Camera permission already authorized")
            setupCaptureSession()
        case .notDetermined:
            print("📷 Requesting camera permission")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    print("📷 Camera permission granted")
                    DispatchQueue.main.async {
                        self.setupCaptureSession()
                    }
                } else {
                    print("📷 Camera permission denied by user")
                }
            }
        case .denied, .restricted:
            print("📷 Camera access denied or restricted")
        @unknown default:
            print("📷 Unknown camera permission status")
            break
        }
    }
    
    func setupCaptureSession() {
        print("📷 Starting camera session setup on background thread")
        
        DispatchQueue.global(qos: .userInteractive).async {
            // Create session on background thread
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            
            // Add video input (start with back camera)
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
                print("📷 Failed to setup camera input")
                return
            }
            
            session.addInput(videoInput)
            
            // Add photo output
            let photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            
            // Start running before updating UI
            session.startRunning()
            print("📷 Camera session started running")
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.captureSession = session
                self.currentCameraInput = videoInput
                self.photoOutput = photoOutput
                self.isUsingFrontCamera = false
                self.isCameraReady = true
                print("📷 Camera ready - UI updated")
            }
        }
    }
    
    func setupCamera(in view: UIView) {
        // Don't setup camera while capturing photo AND we already have a preview layer
        if isCapturingPhoto && hasSetupPreview {
            print("📷 Skipping camera setup - photo capture in progress")
            return
        }
        
        // Don't setup again if we already have a preview layer in this view
        if hasSetupPreview && videoPreviewLayer?.superlayer != nil {
            print("📷 Camera already set up, just updating frame")
            updatePreviewFrame(to: view.bounds)
            return
        }
        
        // Remove any existing preview layer
        videoPreviewLayer?.removeFromSuperlayer()
        
        guard let captureSession = captureSession else { 
            print("📷 Capture session not ready yet - will setup when ready")
            return 
        }
        
        print("📷 Setting up camera preview layer")
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        videoPreviewLayer?.frame = view.bounds
        
        if let videoPreviewLayer = videoPreviewLayer {
            view.layer.addSublayer(videoPreviewLayer)
            hasSetupPreview = true
            print("📷 Camera preview layer added to view with bounds: \(view.bounds)")
        }
    }
    
    func updatePreviewFrame(to bounds: CGRect) {
        videoPreviewLayer?.frame = bounds
    }
    
    func flipCamera() {
        guard let captureSession = captureSession,
              let currentInput = currentCameraInput else {
            print("📷 Cannot flip camera - session not ready")
            return
        }
        
        // Determine the new camera position
        let newPosition: AVCaptureDevice.Position = isUsingFrontCamera ? .back : .front
        
        // Find the new camera device
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
            print("📷 Failed to create new camera input for position: \(newPosition)")
            return
        }
        
        // Check if we can add the new input
        guard captureSession.canAddInput(newInput) else {
            print("📷 Cannot add new camera input")
            return
        }
        
        // Start configuration
        captureSession.beginConfiguration()
        
        // Remove current input and add new input
        captureSession.removeInput(currentInput)
        captureSession.addInput(newInput)
        
        // Update tracking variables
        currentCameraInput = newInput
        isUsingFrontCamera = (newPosition == .front)
        
        // Commit configuration
        captureSession.commitConfiguration()
        
        print("📷 Camera flipped to \(newPosition == .front ? "front" : "back") camera")
    }
    
    func stopSession() {
        print("📷 Stopping camera session...")
        
        DispatchQueue.global(qos: .userInteractive).async {
            self.captureSession?.stopRunning()
            
            DispatchQueue.main.async {
                self.isCameraReady = false
                self.videoPreviewLayer?.removeFromSuperlayer()
                self.videoPreviewLayer = nil
                print("📷 Camera session stopped and cleaned up")
            }
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        print("📷 CapturePhoto called")
        
        guard let photoOutput = photoOutput else {
            print("📷 ERROR: PhotoOutput is nil!")
            completion(nil)
            return
        }
        
        guard let captureSession = captureSession, captureSession.isRunning else {
            print("📷 ERROR: Capture session is not running!")
            completion(nil)
            return
        }
        
        print("📷 Starting photo capture...")
        isCapturingPhoto = true
        
        // Store delegate to prevent deallocation during async photo capture
        currentPhotoDelegate = PhotoCaptureDelegate { [weak self] image in
            self?.isCapturingPhoto = false
            completion(image)
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: currentPhotoDelegate!)
        print("📷 Photo capture delegate stored and capture initiated")
    }
}

// MARK: - Photo Capture Delegate
class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("📷 PhotoCaptureDelegate callback received!")
        
        if let error = error {
            print("📷 Photo capture error: \(error)")
            completion(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("📷 Failed to convert photo to UIImage")
            completion(nil)
            return
        }
        
        print("📷 Photo successfully captured and converted to UIImage")
        completion(image)
    }
}

// MARK: - Recent Find Update Helper
private func updateRecentFindFromAnalysis(recentFindsManager: RecentFindsManager, songId: UUID, newTitle: String) {
    // Find the recent find that corresponds to this song and update it
    if let findIndex = recentFindsManager.recentFinds.firstIndex(where: { find in
        // Match by approximate time (within 10 minutes) and if the current name is generic
        let timeDifference = abs(find.dateFound.timeIntervalSince(Date()))
        return timeDifference < 600 && (find.name == "New Thrift Find" || find.name == "Analyzing...")
    }) {
        // Create updated find with new information
        let oldFind = recentFindsManager.recentFinds[findIndex]
        let category = categorizeItemHelper(name: newTitle)
        let estimatedValue = generateEstimatedValueHelper(for: newTitle, category: category)
        let brand = extractBrandHelper(from: newTitle)
        
        let updatedFind = RecentFind(
            id: oldFind.id,
            name: newTitle,
            category: category,
            estimatedValue: estimatedValue,
            condition: oldFind.condition,
            brand: brand,
            location: oldFind.location,
            dateFound: oldFind.dateFound,
            notes: oldFind.notes,
            imageData: oldFind.imageData
        )
        
        // Replace the old find with updated one
        recentFindsManager.recentFinds[findIndex] = updatedFind
        recentFindsManager.saveFinds()
        
        print("🔄 Updated recent find: \(oldFind.name) → \(newTitle)")
    }
}

private func categorizeItemHelper(name: String) -> String {
    let lowercaseName = name.lowercased()
    
    if lowercaseName.contains("jordan") || lowercaseName.contains("nike") || lowercaseName.contains("sneaker") || lowercaseName.contains("shoe") {
        return "Sneakers"
    } else if lowercaseName.contains("bag") || lowercaseName.contains("purse") || lowercaseName.contains("handbag") || lowercaseName.contains("coach") {
        return "Accessories"
    } else if lowercaseName.contains("hoodie") || lowercaseName.contains("shirt") || lowercaseName.contains("jacket") || lowercaseName.contains("clothing") || lowercaseName.contains("dress") {
        return "Clothing"
    } else if lowercaseName.contains("lamp") || lowercaseName.contains("vase") || lowercaseName.contains("decor") {
        return "Home Decor"
    } else {
        return "Clothing" // Default category
    }
}

private func generateEstimatedValueHelper(for name: String, category: String) -> Double {
    let lowercaseName = name.lowercased()
    
    // High-value items
    if lowercaseName.contains("jordan") || lowercaseName.contains("nike") {
        return Double.random(in: 80...250)
    } else if lowercaseName.contains("coach") || lowercaseName.contains("designer") {
        return Double.random(in: 50...200)
    } else if lowercaseName.contains("vintage") {
        return Double.random(in: 25...100)
    } else {
        // Category-based defaults
        switch category {
        case "Sneakers":
            return Double.random(in: 30...120)
        case "Accessories":
            return Double.random(in: 20...80)
        case "Clothing":
            return Double.random(in: 15...60)
        case "Home Decor":
            return Double.random(in: 10...50)
        default:
            return Double.random(in: 10...40)
        }
    }
}

private func extractBrandHelper(from name: String) -> String? {
    let lowercaseName = name.lowercased()
    
    if lowercaseName.contains("nike") {
        return "Nike"
    } else if lowercaseName.contains("jordan") {
        return "Nike"
    } else if lowercaseName.contains("coach") {
        return "Coach"
    } else if lowercaseName.contains("ecko") {
        return "Ecko Unltd"
    } else if lowercaseName.contains("levi") {
        return "Levi's"
    } else {
        return nil
    }
}



// MARK: - Recent Finds Selection View
struct RecentFindsSelectionView: View {
    @ObservedObject var recentFindsManager: RecentFindsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Select Recent Find")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                    
                    Text("Choose from your recent thrift finds")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
                
                if recentFindsManager.recentFinds.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            Text("No recent finds yet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                            
                            Text("Your thrift store finds will appear here automatically")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Open Camera")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Items list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(recentFindsManager.recentFinds) { find in
                                RecentFindRow(
                                    find: find,
                                    onSelect: {
                                        // Recent find selected - no action needed
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
                
                // Manual entry option
                VStack {
                    Divider()
                        .padding(.horizontal, 24)
                    
                    Button(action: {
                        // No action needed - profit tracker removed
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                            
                            Text("Add item manually")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
                .background(Color(.systemGray6))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.black)
                }
            }
        }
    }
}


// MARK: - Recent Find Row
struct RecentFindRow: View {
    let find: RecentFind
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Category icon
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: categoryIcon)
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(find.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let brand = find.brand {
                            Text(brand)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                        }
                        
                        Text(find.condition)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                    
                    Text("Est. Value: $\(String(format: "%.2f", find.estimatedValue))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                    
                    Text("Found at \(find.location)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categoryIcon: String {
        switch find.category.lowercased() {
        case "sneakers":
            return "shoe.2"
        case "clothing":
            return "tshirt"
        case "accessories":
            return "handbag"
        case "home decor":
            return "house"
        default:
            return "tag"
        }
    }
}

// MARK: - Recent Find Inline Row (for Profit Tracker page)
struct RecentFindInlineRow: View {
    let find: RecentFind
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Item image from assets
                Image(imageNameForFind(find))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(find.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let brand = find.brand {
                            Text(brand)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                        }
                        
                        Text(find.condition)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                    
                    Text("Est. Value: $\(String(format: "%.2f", find.estimatedValue))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                    
                    Text("Found at \(find.location)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    
                    Text("Track")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func imageNameForFind(_ find: RecentFind) -> String {
        // Map specific items to their actual images
        switch find.name {
        case "Nike Air Jordan 1's - T-Scott":
            return "pokemon" // Best sneaker representation available
        case "Vintage Ecko Navy Blue Hoodie":
            return "ecko" // Perfect match - actual Ecko image
        case "Coach Legacy Shoulder Bag":
            return "coach" // Perfect match - actual Coach image
        case "Jordan 4 White Cement":
            return "pokemon" // Sneaker representation
        case "Vintage Levi's Denim Jacket":
            return "goodwill-bins" // General thrift find image
        case let name where name.lowercased().contains("jordan") || name.lowercased().contains("nike") || name.lowercased().contains("sneaker"):
            return "pokemon"
        case let name where name.lowercased().contains("ecko"):
            return "ecko"
        case let name where name.lowercased().contains("coach") || name.lowercased().contains("bag") || name.lowercased().contains("purse"):
            return "coach"
        case let name where name.lowercased().contains("levi") || name.lowercased().contains("denim") || name.lowercased().contains("jacket"):
            return "goodwill-bins"
        case let name where name.lowercased().contains("hoodie") || name.lowercased().contains("shirt") || name.lowercased().contains("clothing"):
            return "ecko" // Use ecko for general clothing
        default:
            return "toy-lot" // Default fallback for miscellaneous items
        }
    }
}

// MARK: - Recent Finds Page View  
struct RecentFindsPageView: View {
    @ObservedObject var songManager: SongManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var profileManager: ProfileManager
    @State private var previousTotalProfits: Double = 0.0
    @State private var showConfetti: Bool = false
    @State private var showFirstTimeNotification: Bool = false
    @State private var showWelcomeConfetti: Bool = false
    @State private var profitIncreaseFromSelling: Bool = false
    
    var totalProfits: Double {
        return profileManager.calculateTotalProfit(from: songManager)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Profit Calculator")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Text("$\(totalProfits, specifier: "%.2f")")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.opacity(0.8)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.6), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                    }
                    .background(Color.white)
                    
                    if songManager.songs.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No Items Yet")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.black)
                            Text("Start scanning items to calculate your potential profit")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(songManager.songs) { song in
                                    VerticalAlbumCard(
                                        songManager: songManager, 
                                        song: song, 
                                        audioManager: audioManager,
                                        profileManager: profileManager
                                    )
                                    .frame(maxWidth: 350)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.top, 48)
                            .padding(.bottom, 120)
                        }
                        .background(Color.white)
                    }
                }
                
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                }
                
                // First-time notification overlay
                if showFirstTimeNotification {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showFirstTimeNotification = false
                                showWelcomeConfetti = false
                            }
                        }
                    
                    // Welcome confetti overlay
                    if showWelcomeConfetti {
                        ConfettiView()
                            .allowsHitTesting(false)
                    }
                    
                    VStack(spacing: 20) {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                            
                            Text("Welcome to Profit Calculator!")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            
                            Text("This is where your recently scanned items will appear. Manually adjust the purchase amount and potential selling amount to keep track of your profits!")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button("Got it!") {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showFirstTimeNotification = false
                                    showWelcomeConfetti = false
                                }
                                // Mark as seen so it won't show again
                                UserDefaults.standard.set(true, forKey: "hasSeenProfitCalculatorIntro")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        )
                        .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onChange(of: totalProfits) { newValue in
                // Only trigger confetti if profit actually increased and both values are positive
                // AND it's from a selling price update (not purchase price adjustment)
                if newValue > previousTotalProfits && previousTotalProfits > 0 && newValue > 0 && profitIncreaseFromSelling {
                    showConfetti = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showConfetti = false
                    }
                }
                previousTotalProfits = newValue
                // Reset the flag after checking
                profitIncreaseFromSelling = false
            }
            .onChange(of: profileManager.profitRefreshTrigger) { _ in
                // Check if this update is from a selling price change
                // We'll set a flag when selling price is updated
                checkIfProfitIncreaseFromSelling()
            }
            .onAppear {
                previousTotalProfits = totalProfits
                
                // Check if this is the first time visiting profit calculator
                let hasSeenIntro = UserDefaults.standard.bool(forKey: "hasSeenProfitCalculatorIntro")
                if !hasSeenIntro {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showFirstTimeNotification = true
                        }
                        // Start confetti shortly after notification appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            showWelcomeConfetti = true
                            // Stop confetti after 4 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                showWelcomeConfetti = false
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func checkIfProfitIncreaseFromSelling() {
        // Check if any selling price was recently updated (within last 2 seconds)
        let lastUpdateTime = UserDefaults.standard.double(forKey: "lastSellPriceUpdate")
        let now = Date().timeIntervalSince1970
        let timeSinceLastUpdate = now - lastUpdateTime
        
        if timeSinceLastUpdate <= 2.0 && lastUpdateTime > 0 {
            profitIncreaseFromSelling = true
            // Clear the flag so it doesn't trigger again
            UserDefaults.standard.removeObject(forKey: "lastSellPriceUpdate")
        }
    }
}

// MARK: - Vertical Album Card
struct VerticalAlbumCard: View {
    @ObservedObject var songManager: SongManager
    let song: Song
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var profileManager: ProfileManager
    @State private var averagePrice: String = "0"
    @State private var sellPrice: String = "0"
    @State private var profitOverride: String = ""
    @State private var isEditingAveragePrice = false
    @State private var isEditingSellPrice = false
    @State private var isEditingProfit = false
    @State private var useCustomProfit = false
    @State private var showingDeleteAlert = false
    
    var calculatedProfit: Double {
        if useCustomProfit && !profitOverride.isEmpty {
            return Double(profitOverride) ?? 0
        }
        let avg = Double(averagePrice) ?? 0
        let sell = Double(sellPrice) ?? 0
        return sell - avg
    }
    
    var imageWithOverlays: some View {
        ZStack {
            imageView
            
            // Title overlay (top-left)
            VStack {
                HStack {
                    titleOverlay
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .onTapGesture {
            // Format and dismiss any active text editing when tapping on image
            if isEditingAveragePrice {
                averagePrice = formatPriceValue(averagePrice)
                isEditingAveragePrice = false
            }
            if isEditingSellPrice {
                sellPrice = formatPriceValue(sellPrice)
                isEditingSellPrice = false
            }
            if isEditingProfit {
                profitOverride = formatProfitValue(profitOverride)
                isEditingProfit = false
                useCustomProfit = !profitOverride.isEmpty
            }
        }
    }
    
    var imageWithTitleOverlay: some View {
        ZStack(alignment: .topLeading) {
            imageView
            titleOverlay
        }
    }
    
    var imageView: some View {
        Group {
            if let customImage = song.customImage {
                Image(uiImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
            } else if let firstAdditionalImage = song.additionalImages?.first {
                Image(uiImage: firstAdditionalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
            } else if !song.imageName.isEmpty {
                Image(song.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(
                        RoundedCorner(radius: 16, corners: [.topLeft, .topRight, .bottomLeft, .bottomRight])
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 240)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }
        }
            }
            
    var titleOverlay: some View {
                Text(song.title.isEmpty ? "Untitled Find" : song.title)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
            )
                    .lineLimit(2)
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
    }
    
    var titleOverlayBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.black.opacity(0.7), Color.clear]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var deleteButtonOverlay: some View {
        Button(action: {
            songManager.removeSong(song)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .blur(radius: 0.5)
                )
        }
    }
    
    var deleteButton: some View {
        HStack {
            Spacer()
            Button(action: {
                songManager.removeSong(song)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .zIndex(1)
    }
    
    var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            pricingSection
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
    
    var pricingSection: some View {
                VStack(spacing: 12) {
            combinedPriceRow
            
            Divider()
                .background(Color.gray.opacity(0.2))
                .padding(.vertical, 1)
            
            profitRow
        }
        .padding(.vertical, 4)
    }
    
    var combinedPriceRow: some View {
        HStack(spacing: 16) {
            purchasePriceField
            Spacer()
            sellingPriceField
        }
    }
    
    private var purchasePriceField: some View {
        HStack(spacing: 8) {
            Text("Purchase:")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            if isEditingAveragePrice {
                purchasePriceTextField
            } else {
                purchasePriceButton
            }
        }
    }
    
    private var purchasePriceTextField: some View {
        TextField("$0", text: $averagePrice)
            .keyboardType(.decimalPad)
            .font(.system(size: 14, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(width: 60, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.4), lineWidth: 2))
            .onSubmit {
                averagePrice = formatPriceValue(averagePrice)
                isEditingAveragePrice = false
            }
            .onChange(of: averagePrice) { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                if filtered != newValue {
                    averagePrice = filtered
                }
                let components = filtered.components(separatedBy: ".")
                if components.count > 2 {
                    averagePrice = components[0] + "." + components[1]
                }
            }
    }
    
    private var purchasePriceButton: some View {
        Button(action: {
            if isEditingSellPrice {
                sellPrice = formatPriceValue(sellPrice)
                isEditingSellPrice = false
            }
            if isEditingProfit {
                profitOverride = formatProfitValue(profitOverride)
                isEditingProfit = false
                useCustomProfit = !profitOverride.isEmpty
            }
            isEditingAveragePrice = true
        }) {
            Text("$\(averagePrice)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }
    
    private var sellingPriceField: some View {
        HStack(spacing: 8) {
            Text("Selling:")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            if isEditingSellPrice {
                sellingPriceTextField
            } else {
                sellingPriceButton
            }
        }
    }
    
    private var sellingPriceTextField: some View {
        TextField("$0", text: $sellPrice)
            .keyboardType(.decimalPad)
            .font(.system(size: 14, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(width: 60, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.4), lineWidth: 2))
            .onSubmit {
                sellPrice = formatPriceValue(sellPrice)
                isEditingSellPrice = false
            }
            .onChange(of: sellPrice) { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                if filtered != newValue {
                    sellPrice = filtered
                }
                let components = filtered.components(separatedBy: ".")
                if components.count > 2 {
                    sellPrice = components[0] + "." + components[1]
                }
            }
    }
    
    private var sellingPriceButton: some View {
        Button(action: {
            if isEditingAveragePrice {
                averagePrice = formatPriceValue(averagePrice)
                isEditingAveragePrice = false
            }
            if isEditingProfit {
                profitOverride = formatProfitValue(profitOverride)
                isEditingProfit = false
                useCustomProfit = !profitOverride.isEmpty
            }
            isEditingSellPrice = true
        }) {
            Text("$\(sellPrice)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }
    
    var purchasedForRow: some View {
                    HStack {
            Text("Purchase Price:")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                            
                            if isEditingAveragePrice {
                                TextField("0", text: $averagePrice)
                                    .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: 80, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                        )
                                    .onSubmit {
                                        averagePrice = formatPriceValue(averagePrice)
                                        isEditingAveragePrice = false
                                    }
                                    .onChange(of: averagePrice) { newValue in
                                        // Filter to only allow numbers and decimal point
                                        let filtered = newValue.filter { "0123456789.".contains($0) }
                                        if filtered != newValue {
                                            averagePrice = filtered
                                        }
                                        // Ensure only one decimal point
                                        let components = filtered.components(separatedBy: ".")
                                        if components.count > 2 {
                                            averagePrice = components[0] + "." + components[1]
                                        }
                                    }
                            } else {
                                Button(action: {
                                    // Format and dismiss other fields first
                                    if isEditingSellPrice {
                                        sellPrice = formatPriceValue(sellPrice)
                                        isEditingSellPrice = false
                                    }
                                    if isEditingProfit {
                                        profitOverride = formatProfitValue(profitOverride)
                                        isEditingProfit = false
                                        useCustomProfit = !profitOverride.isEmpty
                                    }
                                    isEditingAveragePrice = true
                                }) {
                                    Text(averagePrice)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 80, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    var sellingForRow: some View {
                    HStack {
            Text("Selling Price:")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                            
                            if isEditingSellPrice {
                                TextField("0", text: $sellPrice)
                                    .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: 80, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                        )
                                    .onSubmit {
                                        sellPrice = formatPriceValue(sellPrice)
                                        isEditingSellPrice = false
                                    }
                                    .onChange(of: sellPrice) { newValue in
                                        // Filter to only allow numbers and decimal point
                                        let filtered = newValue.filter { "0123456789.".contains($0) }
                                        if filtered != newValue {
                                            sellPrice = filtered
                                        }
                                        // Ensure only one decimal point
                                        let components = filtered.components(separatedBy: ".")
                                        if components.count > 2 {
                                            sellPrice = components[0] + "." + components[1]
                                        }
                                    }
                            } else {
                                Button(action: {
                                    // Format and dismiss other fields first
                                    if isEditingAveragePrice {
                                        averagePrice = formatPriceValue(averagePrice)
                                        isEditingAveragePrice = false
                                    }
                                    if isEditingProfit {
                                        profitOverride = formatProfitValue(profitOverride)
                                        isEditingProfit = false
                                        useCustomProfit = !profitOverride.isEmpty
                                    }
                                    isEditingSellPrice = true
                                }) {
                                    Text(sellPrice)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 80, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    var profitRow: some View {
                    HStack {
                        Text("Profit:")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                        
                        Spacer()
                        
            if isEditingProfit {
                TextField("$0.00", text: $profitOverride)
                    .keyboardType(.decimalPad)
                            .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 90, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                    )
                    .onSubmit {
                        profitOverride = formatProfitValue(profitOverride)
                        isEditingProfit = false
                        useCustomProfit = !profitOverride.isEmpty
                    }
                    .onChange(of: profitOverride) { newValue in
                        // Filter to only allow numbers, decimal point, and minus sign
                        let filtered = newValue.filter { "0123456789.-".contains($0) }
                        if filtered != newValue {
                            profitOverride = filtered
                        }
                        // Ensure only one decimal point and minus sign only at the beginning
                        var result = filtered
                        let components = result.components(separatedBy: ".")
                        if components.count > 2 {
                            result = components[0] + "." + components[1]
                        }
                        // Handle minus sign - only allow at the beginning
                        if result.contains("-") {
                            let minusCount = result.filter { $0 == "-" }.count
                            if minusCount > 1 || (result.contains("-") && !result.hasPrefix("-")) {
                                result = result.replacingOccurrences(of: "-", with: "")
                                if newValue.hasPrefix("-") {
                                    result = "-" + result
                                }
                            }
                        }
                        if result != filtered {
                            profitOverride = result
                        }
                    }
            } else {
                Button(action: {
                    // Format and dismiss other fields first
                    if isEditingAveragePrice {
                        averagePrice = formatPriceValue(averagePrice)
                        isEditingAveragePrice = false
                    }
                    if isEditingSellPrice {
                        sellPrice = formatPriceValue(sellPrice)
                        isEditingSellPrice = false
                    }
                    
                    if useCustomProfit {
                        isEditingProfit = true
                    } else {
                        profitOverride = String(calculatedProfit)
                        useCustomProfit = true
                        isEditingProfit = true
                    }
                }) {
                    Text("$\(String(format: "%.2f", calculatedProfit))")
                        .font(.system(size: 18, weight: .bold))
                            .foregroundColor(calculatedProfit >= 0 ? .green : .red)
                }
            }
        }
    }
    
    
    func loadSavedValues() {
        let savedAvgPrice = UserDefaults.standard.double(forKey: "avgPrice_\(song.id)")
        let savedSellPrice = UserDefaults.standard.double(forKey: "sellPrice_\(song.id)")
        let savedProfitOverride = UserDefaults.standard.string(forKey: "profitOverride_\(song.id)") ?? ""
        let savedUseCustomProfit = UserDefaults.standard.bool(forKey: "useCustomProfit_\(song.id)")
        
        if savedAvgPrice > 0 {
            averagePrice = String(savedAvgPrice)
        }
        if savedSellPrice > 0 {
            sellPrice = String(savedSellPrice)
        }
        profitOverride = savedProfitOverride
        useCustomProfit = savedUseCustomProfit
    }
    
    private func saveAveragePrice(_ value: String) {
        UserDefaults.standard.set(Double(value) ?? 0, forKey: "avgPrice_\(song.id)")
        // Reset custom profit when purchase price changes so it recalculates
        if useCustomProfit {
            useCustomProfit = false
            profitOverride = ""
            UserDefaults.standard.removeObject(forKey: "profitOverride_\(song.id)")
            UserDefaults.standard.set(false, forKey: "useCustomProfit_\(song.id)")
        }
        // Trigger profile refresh for real-time updates
        profileManager.triggerProfitRefresh()
    }
    
    private func saveSellPrice(_ value: String) {
        UserDefaults.standard.set(Double(value) ?? 0, forKey: "sellPrice_\(song.id)")
        // Reset custom profit when selling price changes so it recalculates
        if useCustomProfit {
            useCustomProfit = false
            profitOverride = ""
            UserDefaults.standard.removeObject(forKey: "profitOverride_\(song.id)")
            UserDefaults.standard.set(false, forKey: "useCustomProfit_\(song.id)")
        }
        
        // Mark that a selling price was just updated (for confetti logic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSellPriceUpdate")
        
        // Trigger profile refresh for real-time updates
        profileManager.triggerProfitRefresh()
    }
    
    private func saveProfitOverride(_ value: String) {
        UserDefaults.standard.set(value, forKey: "profitOverride_\(song.id)")
        // Trigger profile refresh for real-time updates
        profileManager.triggerProfitRefresh()
    }
    
    private func saveUseCustomProfit(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "useCustomProfit_\(song.id)")
    }
    
    private func formatPriceValue(_ value: String) -> String {
        // Auto-format to show .0 if it's a whole number and doesn't already have decimal
        if !value.isEmpty && !value.contains(".") {
            if let doubleValue = Double(value), doubleValue == floor(doubleValue) {
                return String(format: "%.1f", doubleValue)
            }
        }
        return value
    }
    
    private func formatProfitValue(_ value: String) -> String {
        // Auto-format to show .0 if it's a whole number and doesn't already have decimal
        if !value.isEmpty && !value.contains(".") {
            if value.hasPrefix("-") {
                let cleanValue = value.replacingOccurrences(of: "-", with: "")
                if let doubleValue = Double(cleanValue), doubleValue == floor(doubleValue) {
                    return String(format: "-%.1f", doubleValue)
                }
            } else {
                if let doubleValue = Double(value), doubleValue == floor(doubleValue) {
                    return String(format: "%.1f", doubleValue)
                }
            }
        }
        return value
    }
    
    private func deleteProfitData() {
        // Clear all profit tracking data
        averagePrice = "0"
        sellPrice = "0"
        profitOverride = ""
        useCustomProfit = false
        
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: "avgPrice_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "sellPrice_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "profitOverride_\(song.id)")
        UserDefaults.standard.removeObject(forKey: "useCustomProfit_\(song.id)")
        
        // Remove the item from the song manager
        songManager.removeSong(song)
        
        // Trigger profile refresh for real-time updates
        profileManager.triggerProfitRefresh()
        
        print("🗑️ Deleted profit tracking item: \(song.title)")
    }
    
    var body: some View {
        mainCard
    }
    
    var mainCard: some View {
        cardWithStyling
            .onAppear(perform: loadSavedValues)
            .onChange(of: averagePrice, perform: saveAveragePrice)
            .onChange(of: sellPrice, perform: saveSellPrice)
            .onChange(of: profitOverride, perform: saveProfitOverride)
            .onChange(of: useCustomProfit, perform: saveUseCustomProfit)
            .alert("Delete Profit Tracking", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteProfitData()
                }
            } message: {
                Text("Are you sure you want to delete the profit tracking data for this item? This action cannot be undone.")
            }
    }
    
    var cardWithStyling: some View {
        ZStack {
            cardLayout
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture {
                    // Format and dismiss any active text editing when tapping outside TextFields
                    if isEditingAveragePrice {
                        averagePrice = formatPriceValue(averagePrice)
                        isEditingAveragePrice = false
                    }
                    if isEditingSellPrice {
                        sellPrice = formatPriceValue(sellPrice)
                        isEditingSellPrice = false
                    }
                    if isEditingProfit {
                        profitOverride = formatProfitValue(profitOverride)
                        isEditingProfit = false
                        useCustomProfit = !profitOverride.isEmpty
                    }
                }
            
            // Delete button positioned over top right curve
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.9))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .offset(x: 8, y: -8) // Position it over the curve
                }
                Spacer()
            }
        }
    }
    
    var cardLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageWithOverlays
            contentSection
                .padding(.top, 12)
        }
    }
}

// MARK: - End of ContentView
