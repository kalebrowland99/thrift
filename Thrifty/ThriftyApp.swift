//
//  ThriftyApp.swift
//  Thrifty
//
//  Created by Eliana Silva on 8/19/24.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import GoogleMaps

@main
struct ThriftyApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    
    init() {
        configureFirebase()
        configureGoogleServices()
        configureAnalyticsServices()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoggedIn {
                    if authManager.hasCompletedSubscription {
                        MainAppView()
                            .transition(.opacity)
                    } else {
                        OnboardingView()
                            .transition(.opacity)
                    }
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authManager.isLoggedIn)
            .animation(.easeInOut(duration: 0.3), value: authManager.hasCompletedSubscription)
            .onOpenURL { url in
                GoogleSignIn.GIDSignIn.sharedInstance.handle(url)
            }
            .onAppear {
                print("🚀 App launched - showing \(authManager.isLoggedIn ? (authManager.hasCompletedSubscription ? "MainAppView" : "OnboardingView") : "ContentView")")
                print("🎛️ Current paywall config - hardPaywall: \(remoteConfig.hardPaywall)")
            }
        }
    }
}

// MARK: - Configuration Methods
private extension ThriftyApp {
    
    func configureFirebase() {
        FirebaseApp.configure()
        print("✅ Firebase configured successfully")
        
        // Initialize remote config after Firebase is ready
        DispatchQueue.main.async {
            RemoteConfigManager.shared.initializeConfig()
        }
    }
    
    func configureGoogleServices() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("⚠️ GoogleService-Info.plist not found or CLIENT_ID missing - Google services will not work")
            return
        }
        
        // Configure Google Sign In
        GoogleSignIn.GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        print("✅ Google Sign In configured successfully")
        
        // Configure Google Maps with existing API key
        GMSServices.provideAPIKey(APIKeys.googleMaps)
        print("🗺️ Google Maps configured successfully")
    }
    
    func configureAnalyticsServices() {
        // Initialize Mixpanel service first (this ensures it's ready before other services use it)
        _ = MixpanelService.shared
        print("📊 Analytics services configured successfully")
        
        // Initialize tracking services after Mixpanel is ready
        _ = ConsumptionRequestService.shared
        _ = DelayedTrackingService.shared
        _ = AppUsageTracker.shared  // Initialize the singleton
        
        print("📊 All analytics services initialized successfully")
    }
}
