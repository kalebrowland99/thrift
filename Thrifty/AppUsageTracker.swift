import SwiftUI
import Foundation

class AppUsageTracker: ObservableObject {
    @Published var sessionStartTime: Date?
    @Published var totalUsageTime: TimeInterval = 0
    @Published var dailyUsageTime: TimeInterval = 0
    
    private let usageKey = "AppUsageTracker_TotalUsage"
    private let dailyUsageKey = "AppUsageTracker_DailyUsage"
    private let lastResetDateKey = "AppUsageTracker_LastResetDate"
    
    init() {
        loadUsageData()
        startSession()
        checkDailyReset()
    }
    
    func startSession() {
        sessionStartTime = Date()
    }
    
    func endSession() {
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        totalUsageTime += sessionDuration
        dailyUsageTime += sessionDuration
        
        saveUsageData()
        sessionStartTime = nil
    }
    
    func getCurrentSessionDuration() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func getTotalUsageToday() -> TimeInterval {
        return dailyUsageTime + getCurrentSessionDuration()
    }
    
    func resetDailyUsage() {
        dailyUsageTime = 0
        UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
        saveUsageData()
    }
    
    private func checkDailyReset() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let lastResetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date ?? Date.distantPast
        let lastResetDay = calendar.startOfDay(for: lastResetDate)
        
        if !calendar.isDate(today, inSameDayAs: lastResetDay) {
            resetDailyUsage()
        }
    }
    
    private func loadUsageData() {
        totalUsageTime = UserDefaults.standard.double(forKey: usageKey)
        dailyUsageTime = UserDefaults.standard.double(forKey: dailyUsageKey)
    }
    
    private func saveUsageData() {
        UserDefaults.standard.set(totalUsageTime, forKey: usageKey)
        UserDefaults.standard.set(dailyUsageTime, forKey: dailyUsageKey)
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
