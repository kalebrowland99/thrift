//
//  ConsumptionRequestService.swift
//  Thrifty
//
//  Created by Eliana Silva on 9/13/25.
//

import Foundation

class ConsumptionRequestService {
    static let shared = ConsumptionRequestService()
    
    private init() {
        print("📊 ConsumptionRequestService: User account initialized")
    }
    
    // MARK: - API Call Tracking
    
    func trackOpenAICall(successful: Bool, estimatedCostCents: Int) {
        let event = [
            "type": "openai_call",
            "successful": successful,
            "cost_cents": estimatedCostCents,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(event)
        print("📊 OpenAI call tracked: \(successful ? "successful" : "failed"), cost: \(estimatedCostCents) cents")
    }
    
    func trackSerpAPICall(successful: Bool, estimatedCostCents: Int) {
        let event = [
            "type": "serpapi_call",
            "successful": successful,
            "cost_cents": estimatedCostCents,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(event)
        print("📊 SerpAPI call tracked: \(successful ? "successful" : "failed"), cost: \(estimatedCostCents) cents")
    }
    
    func trackFirebaseCall(successful: Bool, estimatedCostCents: Int) {
        let event = [
            "type": "firebase_call",
            "successful": successful,
            "cost_cents": estimatedCostCents,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(event)
        print("📊 Firebase call tracked: \(successful ? "successful" : "failed"), cost: \(estimatedCostCents) cents")
    }
    
    // MARK: - Session Management
    
    func startSession() {
        print("📊 ConsumptionRequestService: Session started")
        // Track session start
        let sessionEvent = [
            "type": "session_start",
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(sessionEvent)
    }
    
    func trackMapInteraction(interactionType: String) {
        let event = [
            "type": "map_interaction",
            "interaction_type": interactionType,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(event)
        print("📊 Map interaction tracked: \(interactionType)")
    }
    
    func trackFeatureUsed(_ feature: String) {
        let event = [
            "type": "feature_used",
            "feature": feature,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        logConsumptionEvent(event)
        print("📊 Feature usage tracked: \(feature)")
    }
    
    // MARK: - Private Methods
    
    private func logConsumptionEvent(_ event: [String: Any]) {
        // Store consumption events for later analysis
        var events = UserDefaults.standard.array(forKey: "consumption_events") as? [[String: Any]] ?? []
        events.append(event)
        
        // Keep only last 1000 events to prevent storage bloat
        if events.count > 1000 {
            events = Array(events.suffix(1000))
        }
        
        UserDefaults.standard.set(events, forKey: "consumption_events")
    }
}
