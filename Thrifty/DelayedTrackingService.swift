//
//  DelayedTrackingService.swift
//  Thrifty
//
//  Created by Eliana Silva on 9/13/25.
//

import Foundation

class DelayedTrackingService {
    static let shared = DelayedTrackingService()
    
    private init() {
        print("📊 DelayedTrackingService initialized")
    }
    
    // MARK: - Delayed Tracking Methods
    
    func scheduleDelayedTrialEvent(planType: String, price: Double, transactionId: String, skAdNetworkValue: Int) {
        let eventId = UUID().uuidString
        let event = [
            "id": eventId,
            "eventType": "trial_started",
            "planType": planType,
            "price": price,
            "transactionId": transactionId,
            "skAdNetworkValue": skAdNetworkValue,
            "scheduledTime": Date().addingTimeInterval(3600).timeIntervalSince1970
        ] as [String : Any]
        
        saveDelayedEvent(event)
        print("📊 Scheduled delayed trial event for plan: \(planType), price: $\(price)")
    }
    
    func scheduleDelayedPurchaseEvent(planType: String, price: Double, transactionId: String, skAdNetworkValue: Int) {
        let eventId = UUID().uuidString
        let event = [
            "id": eventId,
            "eventType": "purchase_completed",
            "planType": planType,
            "price": price,
            "transactionId": transactionId,
            "skAdNetworkValue": skAdNetworkValue,
            "scheduledTime": Date().addingTimeInterval(3600).timeIntervalSince1970
        ] as [String : Any]
        
        saveDelayedEvent(event)
        print("📊 Scheduled delayed purchase event for plan: \(planType), price: $\(price)")
    }
    
    // MARK: - Event Processing
    
    func processDelayedEvents() {
        let events = getDelayedEvents()
        let now = Date().timeIntervalSince1970
        
        for event in events {
            if let scheduledTime = event["scheduledTime"] as? TimeInterval,
               scheduledTime <= now {
                executeDelayedEvent(event)
                removeDelayedEvent(event)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func saveDelayedEvent(_ event: [String: Any]) {
        var events = getDelayedEvents()
        events.append(event)
        
        UserDefaults.standard.set(events, forKey: "delayed_tracking_events")
    }
    
    private func getDelayedEvents() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: "delayed_tracking_events") as? [[String: Any]] ?? []
    }
    
    private func removeDelayedEvent(_ event: [String: Any]) {
        guard let eventId = event["id"] as? String else { return }
        
        var events = getDelayedEvents()
        events.removeAll { eventDict in
            (eventDict["id"] as? String) == eventId
        }
        
        UserDefaults.standard.set(events, forKey: "delayed_tracking_events")
    }
    
    private func executeDelayedEvent(_ event: [String: Any]) {
        guard let eventType = event["eventType"] as? String,
              let planType = event["planType"] as? String else { return }
        
        switch eventType {
        case "trial_started":
            MixpanelService.shared.trackSubscriptionViewed(planType: planType)
        case "purchase_completed":
            MixpanelService.shared.trackSubscriptionPurchased(planType: planType)
        default:
            break
        }
        
        print("📊 Executed delayed event: \(eventType) for \(planType)")
    }
}
