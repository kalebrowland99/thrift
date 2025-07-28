//
//  ContentView.swift
//  Lyric Generator
//
//  Created by Kaleb Rowland on 7/16/25.
//

import SwiftUI
import StoreKit
import AVKit
import AVFoundation
import PhotosUI
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore
import GoogleSignIn

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
    let id = UUID()
    var title: String
    var lyrics: String
    var imageName: String
    var customImageData: Data? // Store image as Data for persistence
    var useWaveformDesign: Bool = false
    var lastEdited: Date
    var associatedInstrumental: String? // Track which instrumental is loaded with this song
    
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
    
    // Custom coding keys to exclude customImage from Codable
    enum CodingKeys: String, CodingKey {
        case id, title, lyrics, imageName, customImageData, useWaveformDesign, lastEdited, associatedInstrumental
    }
}

// Song Manager to handle app-wide song data with persistence
@MainActor
class SongManager: ObservableObject {
    @Published var songs: [Song] = []
    
    private let userDefaultsKey = "SavedSongs"
    private let imageIndexKey = "CurrentImageIndex"
    
    // Available images for new songs (includes new + default images)
    private let availableImages = [
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
        loadSongs()
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
        } else {
            // First time - create default sample songs
            songs = [
                Song(title: "My Turn (Sample Song)", lyrics: "", imageName: "lambo", lastEdited: Date()),
                Song(title: "IDGAF (Sample Song)", lyrics: "", imageName: "boy", lastEdited: Date()),
                Song(title: "Deep Thoughts (Sample Song)", lyrics: "", imageName: "girl", lastEdited: Date())
            ]
            saveSongs() // Save the initial songs
            print("🎵 Created initial sample songs")
        }
    }
}

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var purchasedSubscriptions: [Product] = []
    @Published var isSubscribed = false
    
    private let productIds = [
        "com.TrvzrWViGDUN.LyricsGenerator.unlimited.yearly",        // $29.99 regular subscription
        "com.TrvzrWViGDUN.LyricsGenerator.unlimited.yearly.special" // $19.99 special offer
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
        } catch {
            print("❌ Failed to load products:", error)
            // Retry once after a short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            do {
                subscriptions = try await Product.products(for: productIds)
                print("✅ Retry successful - loaded \(subscriptions.count) products")
            } catch {
                print("❌ Retry also failed:", error)
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
    
    var body: some View {
        VStack(spacing: 0) {
            termsText
                .multilineTextAlignment(.center)
        }
    }
    
    private var termsText: some View {
        VStack(spacing: 2) {
            Text("By continuing you agree to Fye AI's")
                .font(.system(size: 12))
                .foregroundColor(.black)
            
            HStack(spacing: 0) {
                Text("Terms of Service")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .underline(color: .black)
                    .onTapGesture {
                        print("✅ Opening Apple Terms of Service")
                        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                            UIApplication.shared.open(url)
                        }
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
            Text("Welcome to Fye AI's Lyric Generator. These Terms of Service govern your use of our application and services.")
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
            
            Text("Fye AI provides an AI-powered lyric generation platform that helps users create, edit, and refine song lyrics using artificial intelligence technology.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Our services include but are not limited to:")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• AI-powered lyric generation tools")
                Text("• Rhyme and wordplay assistance")
                Text("• Song structure and composition guidance")
                Text("• Creative writing enhancement features")
                Text("• Instrumental library access")
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
            
            Text("You retain ownership of lyrics and creative content you create using our Service. However, you grant us a limited license to process and analyze your content to provide and improve our services.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Our Technology")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("All technology, software, and AI models used in our Service remain the exclusive property of Fye AI and are protected by copyright and other intellectual property laws.")
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
            
            Text("Our Service is provided \"as is\" without warranties of any kind. We strive to provide accurate and helpful AI-generated content, but cannot guarantee the quality, originality, or commercial viability of generated lyrics.")
                .font(.system(size: 16))
                .foregroundColor(.black)
            
            Text("Limitation of Liability")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .padding(.top, 10)
            
            Text("In no event shall Fye AI be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the Service.")
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
            
            Text("📧 By email: support@fye.ai")
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
                Text("Application refers to any application or software program provided by the Company, including but not limited to fye.ai, Locked In, Fit AI, and any other applications or software programs provided by the Company.")
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
            
            Text("📧 By email: support@fye.ai")
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
                    .cornerRadius(12)
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
                        .background(Color.red)
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
    @State private var selectedRating: Int = 5 // Default to 5 stars selected
    @State private var navigateToNext = false
    @State private var showingRatingPopup = false
    @State private var ratingCompleted = false
    @State private var popupShown = false
    
    var body: some View {
        GeometryReader { geometry in
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
                    Text("Fye AI was made for\npeople like you")
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
                    
                    Text("+ 1000 Fye AI users")
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
                            
                            Text("\"I finally finished the songs that had been sitting in my notebook for months! Thought I'd never see the light of day lol\"")
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
                            
                            Text("\"The creativity this tool unlocks is incredible! The lyrics it generates feel natural, meaningful, and NOT cheesy like some other tools. It's made my songwriting process exciting again.\"")
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
                .padding(.bottom, 24) // Reduced from 32
                
                Spacer()
                
                // Next button
                Button(action: {
                    navigateToNext = true
                }) {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(ratingCompleted ? Color.black : Color.gray)
                                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                        )
                        .foregroundColor(.white)
                }
                .disabled(!ratingCompleted)
                .padding(.horizontal, 24)
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom + 8 : 24)
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
                
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(isActive: $navigateToNext) {
                    CustomPlanView()
                } label: {
                    EmptyView()
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .preferredColorScheme(.light)
            .onAppear {
                // Show rating popup automatically when view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showingRatingPopup = true
                }
            }
        }
    }
}

// Update CompletionView to navigate to RatingView
struct CompletionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var navigateToRating = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 14
    }
    
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
                
                // Update Let's do this button to navigate to RatingView
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
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
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
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 13
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
                Text("Your creativity transition")
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
                    Text("3 Days")
                        .font(.system(size: 15))
                    Spacer()
                    Text("7 Days")
                        .font(.system(size: 15))
                    Spacer()
                    Text("30 Days")
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(showGraph ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showGraph)
                
                // Description text - full text without truncation
                Text("Based on Fye AI's historical data, creativity growth is usually gradual at first, but after 7 days, you can reach your goal quickly!")
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
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 12
    }
    
    let goals = [
        "Building a loyal fanbase",
        "Releasing chart-topping music",
        "Financial independence through music"
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
                Text("This will be used to calibrate your custom lyrics.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Goals list
            VStack(spacing: 16) {
                ForEach(goals, id: \.self) { goal in
                    Button(action: { selectedGoal = goal }) {
                        Text(goal)
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedGoal == goal ? Color.black : Color(.systemGray6))
                            .foregroundColor(selectedGoal == goal ? .white : .black)
                            .cornerRadius(16)
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
    }
}

// Update ObstaclesView to navigate to UltimateGoalView
struct ObstaclesView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedObstacle: String?
    @State private var navigateToNext = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 11
    }
    
    let obstacles = [
        ("Lack of consistency", "chart.bar"),
        ("Writer's block", "brain"),
        ("Lack of support", "hand.raised"),
        ("Busy schedule", "calendar"),
        ("Lack of inspiration", "lightbulb")
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
                    Button(action: { selectedObstacle = obstacle }) {
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
                        .cornerRadius(16)
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
    }
}

// Update CreativityComparisonView to navigate to ObstaclesView
struct CreativityComparisonView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var navigateToNext = false
    @State private var showChart = false
    @State private var animationComplete = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 10
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
                        .frame(width: UIScreen.main.bounds.width * 0.524, height: 2) // 11/21 ≈ 0.524
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Boost creativity twice as fast with\nFye AI vs on your own")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Comparison chart
            VStack {
                HStack(alignment: .top, spacing: 16) {
                    // Without Fye AI column
                    VStack(spacing: 0) {
                        Text("Without\nFye AI")
                            .font(.system(size: 17))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .padding(.bottom, 12)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 160) // Made skinnier
                            
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(width: 80, height: showChart ? 40 : 0) // Made skinnier
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
                    
                    // With Fye AI column
                    VStack(spacing: 0) {
                        Text("With\nFye AI")
                            .font(.system(size: 17))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .padding(.bottom, 12)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 160) // Made skinnier
                            
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black,
                                        Color.black.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 80, height: showChart ? 120 : 0) // Made skinnier
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

// Update GoalSpeedView to navigate to CreativityComparisonView
struct GoalSpeedView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedSpeed: Double = 3.0 // Default to 3 days
    @State private var navigateToNext = false
    let selectedGoal: String
    
    init(selectedGoal: String) {
        self.selectedGoal = selectedGoal
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 9
    }
    
    var formattedGoal: String {
        switch selectedGoal {
        case "Overcoming writer's block":
            return "Overcoming writer's block in"
        case "My wordplay and creativity":
            return "My wordplay and creativity in"
        case "Delivering a clear and powerful message":
            return "Delivering a clear message in"
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
                        .frame(width: UIScreen.main.bounds.width * 0.476, height: 2) // 10/21 ≈ 0.476
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("How fast do you want\nto reach your goal?")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Goal text and value
            VStack(spacing: 8) {
                Text(formattedGoal)
                    .font(.system(size: 17))
                    .foregroundColor(.black)
                
                Text("\(Int(selectedSpeed)) days")
                    .font(.system(size: 42, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
            
            // Slider with emojis
            VStack(spacing: 24) {
                HStack(spacing: 0) {
                    Text("🦥")
                        .font(.system(size: 32))
                    Spacer()
                    Text("🐕")
                        .font(.system(size: 32))
                    Spacer()
                    Text("🐆")
                        .font(.system(size: 32))
                }
                .padding(.horizontal, 24)
                
                // Slider
                Slider(value: $selectedSpeed, in: 1...5, step: 1)
                    .accentColor(.black)
                
                // Speed labels
                HStack {
                    Text("1 day")
                        .font(.system(size: 15))
                    Spacer()
                    Text("5 days")
                        .font(.system(size: 15))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            // Recommended button (with black text)
            Button(action: {
                withAnimation {
                    selectedSpeed = 3
                }
            }) {
                Text("Recommended")
                    .font(.system(size: 17))
                    .foregroundColor(.black) // Explicitly set to black
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Update Continue button to navigate to CreativityComparisonView
            NavigationLink(isActive: $navigateToNext) {
                CreativityComparisonView()
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
                navigateToNext = true
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
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
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 8
    }
    
    var formattedGoal: String {
        switch selectedGoal {
        case "Overcomeing writer's block":
            return "Overcoming writer's block"
        case "Enhancing wordplay and creativity":
            return "Enhancing wordplay and creativity"
        case "Delivering a clear and powerful message":
            return "Delivering a clear and powerful message"
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
            Text("90% of users say that the change is obvious after using Fye AI.")
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
    }
}

// Update GoalSelectionView to navigate to GoalConfirmationView
struct GoalSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedGoal: String?
    @State private var navigateToConfirmation = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 7
    }
    
    let goals = [
        "Overcome writer's block",
        "Enhance wordplay and creativity",
        "Deliver a clear and powerful message"
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
                Text("This will be used to calibrate your custom lyrics.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Goal options
            VStack(spacing: 16) {
                ForEach(goals, id: \.self) { goal in
                    Button(action: { selectedGoal = goal }) {
                        Text(goal)
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedGoal == goal ? Color.black : Color(.systemGray6))
                            .foregroundColor(selectedGoal == goal ? .white : .black)
                            .cornerRadius(16)
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
    }
}

// Update WritingStyleView to navigate to GoalSelectionView
struct WritingStyleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedStyle: String?
    @State private var navigateToGoal = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 6
    }
    
    let styles = [
        ("Storytelling", "text.alignleft"),
        ("Wordplay & Punchlines", "arrow.up.and.down.and.arrow.left.and.right"),
        ("Adlibs & Vibes", "face.smiling"),
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
                Text("Do you have a specific\nwriting style?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom lyrics.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Style options
            VStack(spacing: 16) {
                ForEach(styles, id: \.0) { style, icon in
                    Button(action: { selectedStyle = style }) {
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
                        .cornerRadius(16)
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
    }
}

// Update MusicGenreView to navigate to WritingStyleView
struct MusicGenreView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var genre = ""
    @State private var navigateToStyle = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 5
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
                Text("What's your music\ngenre?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom lyrics")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Text input field
            TextField("Type here...", text: $genre)
                .font(.system(size: 17))
                .padding(20)
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            Spacer()
            
            // Next button with navigation to WritingStyleView
            NavigationLink(isActive: $navigateToStyle) {
                WritingStyleView()
            } label: {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(!genre.isEmpty ? Color.black : Color(.systemGray5))
                    .cornerRadius(28)
            }
            .disabled(genre.isEmpty)
            .simultaneousGesture(TapGesture().onEnded {
                if !genre.isEmpty {
                    coordinator.nextStep()
                    navigateToStyle = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
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
                    .frame(height: 280)
                
                VStack(alignment: .leading, spacing: 0) {
                    // Your Creativity label
                    Text("Your Creativity")
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
                        Text("Normal writing")
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
            Text("87% of users see an uptick\nin song releases even 6 month later")
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
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 4
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
                        .frame(width: UIScreen.main.bounds.width * 0.238, height: 2) // 5/21 ≈ 0.238
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Lyric Generator creates\nlong-term results")
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
    }
}

// Update PreviousAppsView to include navigation
struct PreviousAppsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedAnswer: String?
    @State private var navigateToResults = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 3
    }
    
    let answers = [
        ("No", "hand.thumbsdown"),
        ("Yes", "hand.thumbsup")
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
                        .frame(width: UIScreen.main.bounds.width * 0.190, height: 2) // 4/21 ≈ 0.190
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Have you tried other lyric writing apps?")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Answer options
            VStack(spacing: 16) {
                ForEach(answers, id: \.0) { answer, icon in
                    Button(action: { selectedAnswer = answer }) {
                        HStack {
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 32)
                            Text(answer)
                                .font(.system(size: 17))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedAnswer == answer ? Color.black : Color(.systemGray6))
                        .foregroundColor(selectedAnswer == answer ? .white : .black)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToResults) {
                LongTermResultsView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedAnswer != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedAnswer != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedAnswer == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedAnswer != nil {
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
    }
}

// Update SourceSelectionView to include navigation
struct SourceSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedSource: String?
    @State private var navigateToPreviousApps = false
    @State private var isSavingToFirebase = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 2
    }
    
    let sources = [
        "Instagram",
        "Facebook",
        "TikTok",
        "Youtube",
        "Google",
        "TV"
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
                        .frame(width: UIScreen.main.bounds.width * 0.143, height: 2) // 3/21 ≈ 0.143
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title
            Text("Where did you hear\nabout us?")
                .font(.system(size: 32, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            
            // Source options
            VStack(spacing: 16) {
                ForEach(sources, id: \.self) { source in
                    Button(action: { selectedSource = source }) {
                        HStack {
                            Image(source.lowercased())
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text(source)
                                .font(.system(size: 17))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedSource == source ? Color.black : Color(.systemGray6))
                        .foregroundColor(selectedSource == source ? .white : .black)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToPreviousApps) {
                PreviousAppsView()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedSource != nil ? Color.black : Color(.systemGray5))
                    .foregroundColor(selectedSource != nil ? .white : Color(.systemGray2))
                    .cornerRadius(28)
            }
            .disabled(selectedSource == nil)
            .simultaneousGesture(TapGesture().onEnded {
                if selectedSource != nil {
                    saveSourceToFirebase()
                    coordinator.nextStep()
                    navigateToPreviousApps = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
    
    private func saveSourceToFirebase() {
        guard let selectedSource = selectedSource else { return }
        
        let db = Firestore.firestore()
        let userID = Auth.auth().currentUser?.uid ?? "anonymous"
        
        let sourceData: [String: Any] = [
            "source": selectedSource,
            "timestamp": FieldValue.serverTimestamp(),
            "userID": userID
        ]
        
        db.collection("user_sources").addDocument(data: sourceData) { error in
            if let error = error {
                print("❌ Error saving source to Firebase: \(error.localizedDescription)")
            } else {
                print("✅ Successfully saved source '\(selectedSource)' to Firebase for user: \(userID)")
            }
        }
    }
}

// Onboarding Coordinator to manage flow and progress
class OnboardingCoordinator: ObservableObject {
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 21 // Total number of onboarding steps
    
    let steps = [
        "OnboardingGenderView",
        "SongFrequencyView", 
        "SourceSelectionView",
        "PreviousAppsView",
        "LongTermResultsView",
        "MusicGenreView",
        "WritingStyleView",
        "GoalSelectionView",
        "GoalConfirmationView",
        "GoalSpeedView",
        "CreativityComparisonView",
        "ObstaclesView",
        "UltimateGoalView",
        "ProgressGraphView",
        "CompletionView",
        "RatingView",
        "CustomPlanView",
        "LoadingView",
        "FinalCongratulationsView",
        "CustomPlanSummaryView",
        "SubscriptionView"
    ]
    
    var progress: Double {
        return Double(currentStep + 1) / Double(totalSteps)
    }
    
    func nextStep() {
        if currentStep < totalSteps - 1 {
            currentStep += 1
        }
    }
    
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }
}

// Update SongFrequencyView to include navigation
struct SongFrequencyView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedFrequency: String?
    @State private var navigateToSource = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 1
    }
    
    let frequencies = [
        ("0-2", "Writes now and then", "music.note"),
        ("3-5", "A few songs per week", "music.note.list"),
        ("6+", "Dedicated Artist", "music.quarternote.3")
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
                        .frame(width: UIScreen.main.bounds.width * 0.095, height: 2) // 2/21 ≈ 0.095
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("How many songs do you write per week?")
                    .font(.system(size: 32, weight: .bold))
                Text("This will be used to calibrate your custom lyrics.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            
            // Frequency options
            VStack(spacing: 16) {
                ForEach(frequencies, id: \.0) { frequency, description, icon in
                    Button(action: { selectedFrequency = frequency }) {
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
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            
            Spacer()
            
            // Continue button
            NavigationLink(isActive: $navigateToSource) {
                SourceSelectionView()
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
                    navigateToSource = true
                }
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

struct OnboardingGenderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var coordinator = OnboardingCoordinator()
    @State private var selectedGender: String?
    @State private var navigateToFrequency = false
    
    init() {
        // Set the current step for this view
        let coordinator = OnboardingCoordinator()
        coordinator.currentStep = 0
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
                        .frame(width: UIScreen.main.bounds.width * 0.048, height: 2) // 1/21 ≈ 0.048
                    
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
                
                // Title and subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your Gender")
                        .font(.system(size: 32, weight: .bold))
                    Text("This will be used to calibrate your custom lyrics.")
                        .font(.system(size: 17))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                
                // Gender options
                VStack(spacing: 16) {
                    ForEach(["Male", "Female"], id: \.self) { gender in
                        Button(action: { selectedGender = gender }) {
                            Text(gender)
                                .font(.system(size: 17))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(selectedGender == gender ? Color.black : Color(.systemGray6))
                                .foregroundColor(selectedGender == gender ? .white : .black)
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                
                Spacer()
                
                // Continue button
                NavigationLink(isActive: $navigateToFrequency) {
                    SongFrequencyView()
                        .horizontalSlideTransition()
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selectedGender != nil ? Color.black : Color(.systemGray5))
                        .foregroundColor(selectedGender != nil ? .white : Color(.systemGray2))
                        .cornerRadius(28)
                }
                .disabled(selectedGender == nil)
                .simultaneousGesture(TapGesture().onEnded {
                    if selectedGender != nil {
                        coordinator.nextStep()
                        navigateToFrequency = true
                    }
                })
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
    }
}

// Central music emoji with wiggle animation
struct WiggleMusicEmoji: View {
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    
    var body: some View {
        Text("🎵")
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
                
                // Central wiggling music emoji
                WiggleMusicEmoji()
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
            Text("Time to generate\nyour custom plan!")
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

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingSignIn = false
    @State private var showingEmailSignIn = false
    @State private var showingOnboarding = false

    
    var body: some View {
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
                    
                    // Main Image
                    Image("main")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .padding(.bottom, 30)
                        .padding(.horizontal, -20)
                    
                    // Title Text
                    Text("Lyric writing\nmade easy")
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
                    OnboardingGenderView()
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

// Onboarding View for logged-in users who haven't completed onboarding
struct OnboardingView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingOnboarding = false
    
    var body: some View {
        NavigationView {
            OnboardingGenderView()
                .horizontalSlideTransition()
                .onDisappear {
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
    @State private var progress: CGFloat = 0.0
    @State private var progressText = "0%"
    @State private var statusText = "Initializing your profile..."
    @State private var showChecklist = false
    @State private var checkItems: [Bool] = [false, false, false, false, false]
    @State private var navigateToFinal = false
    
    let checklistItems = [
        "Writing style analysis",
        "Rhyme schemes", 
        "Verse structure",
        "Creative themes",
        "Custom plan generation"
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
            18: ("Analyzing your writing style...", 0),
            34: ("Processing rhyme schemes...", 1), 
            56: ("Analyzing verse structure...", 2),
            78: ("Optimizing creative themes...", 3),
            92: ("Finalizing your custom plan...", 4)
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
                    
                    Spacer(minLength: 8)
                    
                    // Goal section
                    VStack(spacing: 12) {
                        Text("You should achieve:")
                            .font(.system(size: 16, weight: .medium))
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(0.8), value: showContent)
                        
                        Text("12 complete songs by \(targetDate)")
                            .font(.system(size: 20, weight: .bold))
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.0), value: showContent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    
                    // Stats rings
                    VStack(spacing: 12) {
                        // Stats circles grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            
                            // Boost in creativity
                            RecommendationCircle(
                                icon: "brain.head.profile",
                                title: "Boost In Creativity",
                                value: "79%",
                                color: Color.purple,
                                delay: 1.2
                            )
                            
                            // Writer's block destroyed
                            RecommendationCircle(
                                icon: "shield.fill",
                                title: "Writer's Block Destroyed",
                                value: "98%",
                                color: Color.green,
                                delay: 1.4
                            )
                            
                            // Words Written
                            RecommendationCircle(
                                icon: "doc.text.fill",
                                title: "Words Written",
                                value: "744",
                                color: Color.blue,
                                delay: 1.6
                            )
                            
                            // Hours saved
                            RecommendationCircle(
                                icon: "clock.fill",
                                title: "Hours Saved",
                                value: "8",
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
                        
                        Text("Based on your profile, you'll see significant improvement in lyric quality and writing speed within the next 3 days.")
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
                        Text("🎵")
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
                    
                    // Centered Spinner
                    SpinnerView()
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .onAppear {
                    // Show one time offer after spinner completes (0.8s delay + 3.5s animation = 4.3s total)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
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
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(nil)
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
                Text("We want you to try\nFye AI for free")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
                
                // Main Image
                Image("main")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(.bottom, 30)
                    .padding(.horizontal, -24)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: showContent)
            }
            
            // Bottom section with button and payment text
            VStack(spacing: 16) {
                // No payment due now
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
                
                // Try for $0.00 button
                NavigationLink(isActive: $navigateToSubscription) {
                    SubscriptionView()
                } label: {
                    Text("Try for $0.00")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .cornerRadius(12)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                
                // Legal text
                Text("Just $29.99 per year ($2.50/mo)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .background(Color.white)
        .navigationBarHidden(true)
        .onAppear {
            showContent = true
        }
    }
}

// Update SubscriptionView to use new WinbackView
struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with restore button
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
            .padding(.top, 16)
            
            // Main content
            VStack(spacing: 40) {
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
                                .fill(Color.red)
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
                                                // Title - positioned higher
                        Text("Start your 3-days FREE trial to continue.")
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black)
                            .padding(.top, 20)
                            .padding(.bottom, 30)
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
                                description: "Unlock all the app's features and speed up your Career, Lyrics, and Visibility.",
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
                VStack(spacing: 16) {
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
                        
                        // Step 1: Try For $0.00 button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep = 2
                            }
                        }) {
                            Text("Try For $0.00")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.black)
                                .cornerRadius(12)
                        }
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                        
                        // Step 1: Legal text
                        Text("3 days free, then $29.99 per year ($2.50/mo)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                    } else {
                        // Step 2: No payment due now text
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
                            
                        // Step 2: Purchase button - same position as step 1 button
                            Button(action: {
                                Task {
                                    do {
                                        print("🔍 Attempting to purchase regular $29.99 subscription...")
                                        print("📦 Available products: \(storeManager.subscriptions.count)")
                                        for product in storeManager.subscriptions {
                                            print("   - \(product.id): \(product.displayPrice)")
                                        }
                                        
                                        // Find the $29.99 regular subscription product
                                        guard let subscription = storeManager.subscriptions.first(where: { 
                                            $0.id == "com.TrvzrWViGDUN.LyricsGenerator.unlimited.yearly" 
                                        }) else {
                                            print("❌ Regular subscription product not found")
                                            errorMessage = "Regular subscription product not available"
                                            showError = true
                                            return
                                        }
                                        
                                        let result = try await subscription.purchase()
                                        
                                        switch result {
                                        case .success(let verification):
                                            switch verification {
                                            case .verified(let transaction):
                                                print("✅ Successfully purchased $29.99 subscription: \(transaction.productID)")
                                                // Successful purchase - mark subscription as completed
                                                await transaction.finish()
                                                await storeManager.updateSubscriptionStatus()
                                                authManager.markSubscriptionCompleted()
                                                navigateToCreateAccount = true
                                            case .unverified:
                                                throw StoreError.failedVerification
                                            }
                                        case .pending:
                                            throw StoreError.pending
                                                                case .userCancelled:
                            if remoteConfig.hardPaywall {
                                showWinback = true
                            } else {
                                // Soft paywall - automatically redirect to main app
                                authManager.markSubscriptionCompleted()
                                authManager.setGuestMode() // Auto-login for soft paywall
                            }
                                        @unknown default:
                                            throw StoreError.unknown
                                        }
                                                        } catch StoreError.userCancelled {
                        if remoteConfig.hardPaywall {
                            showWinback = true
                        } else {
                            // Soft paywall - automatically redirect to main app
                            authManager.markSubscriptionCompleted()
                            authManager.setGuestMode() // Auto-login for soft paywall
                        }
                                    } catch StoreError.pending {
                                        errorMessage = "Purchase is pending"
                                        showError = true
                                    } catch {
                                        errorMessage = "Failed to make purchase"
                                        showError = true
                                    }
                                }
                            }) {
                                Text("Start my 3-Day Free Trial")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color.black)
                                    .cornerRadius(12)
                            }
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.2), value: showContent)
                    }
                    
                    if currentStep == 2 {
                        // Legal text for step 2
                        Text("3 days free, then $29.99 per year ($2.50/mo)")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.6).delay(1.4), value: showContent)
                    }
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear {
            showContent = true
            // Load products when view appears
            Task {
                await storeManager.loadProducts()
            }
            
            // Note: When hardpaywall is false, still show the paywall normally
            // Only redirect to main app if user cancels the $29.99 purchase
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showWinback) {
            if remoteConfig.hardPaywall {
                WinbackView(isPresented: $showWinback, storeManager: storeManager)
            } else {
                // Soft paywall - show empty view since we auto-redirect
                EmptyView()
            }
        }
        .background(
            NavigationLink(isActive: $navigateToCreateAccount) {
                CreateAccountView()
            } label: {
                EmptyView()
            }
            .hidden()
        )

    }
}

struct OneTimeOfferView: View {
    @Binding var isPresented: Bool
    @Binding var parentPresented: Bool
    let storeManager: StoreManager // Accept StoreManager instance as a parameter
    @StateObject private var authManager = AuthenticationManager.shared
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
                        Text("80% OFF")
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
                    Text("$29.99")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .strikethrough()
                    Text("$1.66 /month")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
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
                
                // Combined LOWEST PRICE EVER with yearly plan box
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
                            Text("Yearly")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                            Text("12mo • $19.99")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("$1.66 /mo")
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
                
                // CLAIM YOUR ONE TIME OFFER button
                Button(action: {
                    Task {
                        await purchaseSubscription()
                    }
                }) {
                    HStack {
                        if storeManager.subscriptions.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(storeManager.subscriptions.isEmpty ? "Loading..." : "CLAIM YOUR ONE TIME OFFER")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(storeManager.subscriptions.isEmpty ? Color.gray : Color.black)
                    .cornerRadius(28)
                }
                .disabled(storeManager.subscriptions.isEmpty)
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
            // Find the special $19.99 product for one-time offer
            guard let specialSubscription = storeManager.subscriptions.first(where: { 
                $0.id == "com.TrvzrWViGDUN.LyricsGenerator.unlimited.yearly.special" 
            }) else {
                print("❌ Special $19.99 offer product not found in available products")
                print("🔍 Looking for: com.TrvzrWViGDUN.LyricsGenerator.unlimited.yearly.special")
                print("📦 Available products:")
                for product in storeManager.subscriptions {
                    print("   - \(product.id)")
                }
                errorMessage = "Special $19.99 offer not available. Please try again or contact support."
                showError = true
                isPurchasing = false
                return
            }
            
            let result = try await specialSubscription.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("✅ Successfully purchased $19.99 special offer: \(transaction.productID)")
                    await transaction.finish()
                    await storeManager.updateSubscriptionStatus()
                    authManager.markSubscriptionCompleted()
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

// Define custom colors to match Figma design
extension Color {
    static let fyeBackground = Color.black
    static let fyeTopBanner = Color(hex: "1C1C1E")
    static let fyeSecondaryText = Color(hex: "8E8E93")
    static let fyeDeleteRed = Color(hex: "FF453A")
    static let fyeAccent = Color(hex: "FF6B00") // Reddish-orange accent color
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
    
    private let isLoggedInKey = "AuthenticationManager_IsLoggedIn"
    private let userDataKey = "AuthenticationManager_UserData"
    private let hasCompletedOnboardingKey = "AuthenticationManager_HasCompletedOnboarding"
    private let hasCompletedSubscriptionKey = "AuthenticationManager_HasCompletedSubscription"
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
        
        // Load saved authentication state
        loadAuthenticationState()
        
        print("🔐 AuthenticationManager initialized - isLoggedIn: \(isLoggedIn), hasCompletedOnboarding: \(hasCompletedOnboarding), hasCompletedSubscription: \(hasCompletedSubscription)")
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
            "appName": "Fye AI"
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
        saveAuthenticationState()
        saveSubscriptionStatusToFirebase()
        print("✅ Subscription marked as completed")
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
                    print("✅ Loaded subscription status from Firebase for email \(email): \(hasCompleted)")
                } else {
                    // No subscription record found - user hasn't completed subscription
                    print("📝 No subscription status found in Firebase for email: \(email) - defaulting to false")
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
    @Published var userName: String = "@takeflight395"
    @Published var totalWordsWritten: Int = 0
    
    private let userNameKey = "ProfileManager_UserName"
    private let profilePictureKey = "ProfileManager_ProfilePicture"
    private let totalWordsKey = "ProfileManager_TotalWords"
    private let customImageKey = "ProfileManager_CustomImage"
    
    init() {
        loadUserData()
    }
    
    func updateUserName(_ name: String) {
        // Clean the input: lowercase, alphanumeric only
        let cleanedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        
        // Ensure username always starts with @
        if cleanedName.isEmpty {
            userName = "@takeflight395"
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
        let loadedName = UserDefaults.standard.string(forKey: userNameKey) ?? "@takeflight395"
        // Clean and validate loaded username
        let nameWithoutAt = loadedName.hasPrefix("@") ? String(loadedName.dropFirst()) : loadedName
        let cleanedName = nameWithoutAt.lowercased().filter { $0.isLetter || $0.isNumber }
        
        if cleanedName.isEmpty {
            userName = "@takeflight395"
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
    @State private var showingNewSongEditor = false
    @State private var editingSong: Song?
    @State private var songAudioManager: AudioManager?
    
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
        .fullScreenCover(isPresented: $showingNewSongEditor) {
            if let song = editingSong {
                SongEditView(
                    songManager: songManager, 
                    song: song, 
                    audioManager: songAudioManager ?? audioManager,
                    onDismiss: {
                        showingNewSongEditor = false
                        editingSong = nil
                        songAudioManager = nil
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
                progressView
                } else if selectedTab == 2 {
                settingsView
                } else if selectedTab == 3 {
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
            selectedTab: $selectedTab
        )
    }
    
    private var progressView: some View {
        ProgressView()
    }
    
    private var settingsView: some View {
        SettingsView(audioManager: audioManager)
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
                    .padding(.horizontal, 30)
                    .padding(.top, 16)
            }
            .background(tabBarBackground)
        }
    }
    
    // MARK: - Tab Bar Content
    private var tabBarContent: some View {
                    HStack {
                        // Home Tab
                        Button(action: { selectedTab = 0 }) {
                            Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(selectedTab == 0 ? Color(hex: "#e83a51") : .fyeSecondaryText)
                        }
                        
                        Spacer()
                        
                        // Tools Tab
                        Button(action: { selectedTab = 1 }) {
                Image(systemName: "wand.and.stars")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(selectedTab == 1 ? Color(hex: "#e83a51") : .fyeSecondaryText)
                        }
                        
                        Spacer()
                        
            // Plus Button
            plusButton
            
            Spacer()
            
            // Instrumentals Tab
            Button(action: { selectedTab = 2 }) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(selectedTab == 2 ? Color(hex: "#e83a51") : .fyeSecondaryText)
            }
            
            Spacer()
            
            // Profile Tab
            profileTabButton
        }
    }
    
    // MARK: - Plus Button
    private var plusButton: some View {
                        Button(action: {
                            let newSong = songManager.createNewSong()
                            editingSong = newSong
            songAudioManager = AudioManager()
                            showingNewSongEditor = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color(hex: "#e83a51"))
                                .clipShape(Circle())
                        }
    }
    
    // MARK: - Profile Tab Button
    private var profileTabButton: some View {
                        Button(action: { selectedTab = 3 }) {
            profileImage
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
                                            .stroke(selectedTab == 3 ? Color(hex: "#e83a51") : Color.clear, lineWidth: 2)
    }
    
    // MARK: - Tab Bar Background
    private var tabBarBackground: some View {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 0.5)
                            Rectangle()
                                .fill(Color.black)
        .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
                                .ignoresSafeArea(.all, edges: .bottom)
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
        loadData()
        trackAppOpening()
        updateStreak()
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
    
    private func calculateCurrentStreak() -> Int {
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

    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    private var weekDays: [Date] {
        let effectiveToday = streakManager.currentEffectiveDate
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: effectiveToday)?.start else {
            return []
        }
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
        }
    }
    
    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: streakManager.currentEffectiveDate)
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
        VStack(spacing: 8) {
        // Calendar week view
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { date in
                    let isStreakDay = isPartOfCurrentStreak(date)
                    let isTodayDate = isToday(date)
                    
                VStack(spacing: 8) {
                    // Dashed circle with day letter inside
                    ZStack {
                            
                        Circle()
                            .stroke(
                                style: StrokeStyle(
                                        lineWidth: isStreakDay ? 2.5 : 1.5,
                                    lineCap: .round,
                                        dash: isStreakDay ? [] : [4.5, 4.5] // Solid line for streak days, dashed for others
                                )
                            )
                            .foregroundStyle(
                                    isStreakDay ? 
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 1.0, green: 0.4, blue: 0.8),  // Pink
                                        Color(red: 0.3, green: 0.6, blue: 1.0),  // Blue
                                        Color(red: 0.8, green: 0.3, blue: 1.0)   // Purple
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) : 
                                LinearGradient(
                                    gradient: Gradient(colors: [.white.opacity(0.3), .white.opacity(0.3)]),
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
                                                    Color(red: 1.0, green: 0.4, blue: 0.8),  // Pink
                                                    Color(red: 0.3, green: 0.6, blue: 1.0),  // Blue
                                                    Color(red: 0.8, green: 0.3, blue: 1.0)   // Purple
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                            .opacity(0.15)
                                        )
                                    : nil
                                )
                            .frame(width: 32, height: 32)
                                .scaleEffect(isTodayDate ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isTodayDate)
                            .shadow(
                                    color: isTodayDate ? Color(red: 0.6, green: 0.3, blue: 1.0).opacity(0.6) : .clear,
                                    radius: isTodayDate ? 8 : 0,
                                x: 0,
                                y: 0
                            )
                        
                        // Day letter inside circle
                        Text(dayLetter(for: date))
                                .font(.system(size: 14, weight: isTodayDate ? .bold : .medium))
                            .foregroundColor(
                                    isStreakDay ? .white : .white.opacity(0.6)
                            )
                            .shadow(
                                    color: isTodayDate ? Color.white.opacity(0.3) : .clear,
                                    radius: isTodayDate ? 2 : 0,
                                x: 0,
                                y: 0
                            )
                    }
                    
                    // Day number below circle
                    Text(dateFormatter.string(from: date))
                            .font(.system(size: 14, weight: isTodayDate ? .bold : .medium))
                        .foregroundColor(
                                isStreakDay ? .white : .white.opacity(0.8)
                        )
                        .shadow(
                                color: isTodayDate ? Color.white.opacity(0.3) : .clear,
                                radius: isTodayDate ? 2 : 0,
                            x: 0,
                            y: 0
                        )
                }
                
                if date != weekDays.last {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 0)
        }
    }
    
    private func dayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        let dayName = formatter.string(from: date)
        return String(dayName.prefix(1))
    }
}

// Home View - Main screen with empty state
struct HomeView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var songManager: SongManager
    @ObservedObject var streakManager: StreakManager
    @StateObject private var sharedManager = SharedInstrumentalManager.shared
    @State private var scrollOffset: CGFloat = 0
    @Binding var selectedTab: Int
    
    let toolBackgrounds = ["tool-bg1", "tool-bg2", "tool-bg3", "tool-bg4", "tool-bg5", "tool-bg6"]
    
    let lyricTools = [
        ("AI Bar Generator", "wand.and.stars", "Generate relatable bars that rhyme to your inputted lyrics.", false),
        ("Alliterate It", "a.circle", "Before: I hid my gun\nAfter: Silently Snuck Steel", false),
        ("Chorus Creator", "music.note", "A song's repeated, memorable section that conveys the theme.", false),
        ("Creative One-Liner", "lightbulb.circle", "Generate a creative metaphors or simile related to your subject.", true),
        ("Diss Track Generator", "flame.circle", "Generate diss tracks according to your opponent's vulnerabilities.", true),
        ("Double Entendre", "2.circle", "A double entendre is a phrase designed to have two meanings.", true),
        ("Finisher", "checkmark.circle", "Analyze themes/rhyme schemes to finish your incomplete song.", true),
        ("Flex-on-'em", "star.circle", "Create a song relating to your personal accomplishments.", true),
        ("Imperfect Rhyme", "rhombus.circle", "An imperfect rhyme is when two words almost rhyme, but not quite.", true),
        ("Industry Analyzer", "chart.bar.circle", "Analyze the commerciality of a song for radio & record labels.", true),
        ("Quadruple Entendre", "4.circle", "A quadruple entendre is a phrase designed to have four meanings.", true),
        ("Rap Instagram Captions", "camera.circle", "Generate clever Instagram captions for your fans to see.", true),
        ("Rap Name Generator", "person.badge.plus", "Generate modern rap names inspired by your name.", true),
        ("Shapeshift", "arrow.2.squarepath", "Manipulate one word to sound like another word.", true),
        ("Triple Entendre", "3.circle", "A triple entendre is a phrase designed to have three meanings.", true),
        ("Ultimate Come Up Song", "star.circle", "Similar to an artist's style, but unique to your life story.", false)
    ]
    
    // Available instrumental images for cycling through when new instrumentals are added
    let instrumentalImages = ["instrumental1", "instrumental2", "instrumental3", "instrumental4", "instrumental5", "instrumental6"]
    
    let bestInstrumentals = [
        ("10AM In The South", "instrumental1", "Southern Hip Hop, Trap...", "71K", "2K", "132"),
        ("Better Mornings", "instrumental2", "Lo-fi, Chill, Morning...", "66K", "2.1K", "193"),
        ("Pleasent Poetry", "instrumental3", "Poetic, Melodic, Soul...", "89K", "3.4K", "247"),
        ("Run It Up", "instrumental4", "Trap, Drill, Energy...", "45K", "1.8K", "156"),
        ("Yacht Parties", "instrumental5", "Luxury, Party, Upbeat...", "92K", "4.2K", "301")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Combined Header and Streak Calendar section with extended background
            VStack(spacing: 0) {
                // Dynamic Header
                HStack {
                    if scrollOffset <= 0 {
                        // Expanded Header
                HStack {
                    // Brand logo and name
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                        
                        Text("Fye AI")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Streak counter (replacing settings)
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                        
                        Text("\(streakManager.currentStreak)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.2),
                                Color(red: 0.1, green: 0.1, blue: 0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    } else {
                        // Collapsed Header
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Fye AI")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
                
                // Streak Calendar
                StreakCalendarView(streakManager: streakManager)
                    .padding(.top, 4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            .background(
                GeometryReader { geometry in
                    ZStack {
                        // Background image - extended to top safe area
                        Image("bg")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180 + geometry.safeAreaInsets.top)
                            .clipped()
                        
                        // Gradient overlay for shadow transition into black - adjusted for extended height
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: geometry.safeAreaInsets.top / (180 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.4), location: (geometry.safeAreaInsets.top + 126) / (180 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.95), location: 1.0)
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
                        // Recently Added header
                        HStack {
                            Text("Recently Added")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
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
                        
                        // Lyric Tools Section
                        VStack(spacing: 20) {
                            // Grey line divider
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 1)
                                .padding(.horizontal, -24) // Extend to full width
                            
                            // Section Header
                            HStack {
                                Text("Lyric Tools")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { selectedTab = 1 }) {
                                    HStack(spacing: 4) {
                                        Text("More")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                            .padding(.top, 16)
                            
                            // Lyric Tools List - Horizontal Scroll with 2 Rows
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHGrid(rows: [
                                    GridItem(.fixed(70), spacing: 1),
                                    GridItem(.fixed(70), spacing: 1)
                                ], spacing: 16) {
                                    ForEach(Array(lyricTools.enumerated()), id: \.offset) { index, tool in
                                        LyricToolCard(
                                            title: tool.0,
                                            icon: tool.1,
                                            description: tool.2,
                                            index: index,
                                            isPro: tool.3,
                                            backgroundImage: getBackgroundForTool(toolName: tool.0, index: index)
                                        )
                                        .frame(width: 320)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                            }
                            .padding(.horizontal, -24) // Negative padding to extend scroll area
                            
                            // Best of v4.5 Instrumentals Section
                            VStack(alignment: .leading, spacing: 20) {
                                // Grey line divider
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 1)
                                    .padding(.horizontal, -24) // Extend to full width
                                
                                // Header
                                HStack {
                                    Text("Instrumentals")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Button(action: { selectedTab = 2 }) {
                                        HStack(spacing: 4) {
                                            Text("More")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                                .padding(.top, 16)
                                
                                // Horizontal Scrollable Instrumentals
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(Array(sharedManager.instrumentals.enumerated()), id: \.offset) { index, instrumental in
                                            InstrumentalCard(
                                                title: instrumental,
                                                imageName: getInstrumentalImage(for: index),
                                                genres: "Hip Hop, Trap...",
                                                playCount: "\(Int.random(in: 10...100))K",
                                                likeCount: "\(Int.random(in: 1...5))K",
                                                commentCount: "\(Int.random(in: 50...500))"
                                            )
                                            .frame(width: 220, height: 260)
                                        }
                                        
                                        // Add some padding at the end to show partial next item
                                        Spacer()
                                            .frame(width: 80)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .padding(.horizontal, -24) // Negative padding to extend scroll area
                            }
                            .padding(.bottom, 100) // Increased bottom padding to account for tab bar
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
        .background(Color.fyeBackground)
        .navigationBarHidden(true)
    }
    
    // Function to get the correct background for each tool (same logic as ProgressView)
    private func getBackgroundForTool(toolName: String, index: Int) -> String {
        switch toolName {
        case "Finisher", "Rap Name Generator":
            return "tool-bg4"
        case "Ultimate Come Up Song", "Industry Analyzer":
            return "tool-bg1"
        default:
            return toolBackgrounds[index % toolBackgrounds.count]
        }
    }
    
    // Function to get instrumental image based on index - cycles through available instrumental images
    private func getInstrumentalImage(for index: Int) -> String {
        return instrumentalImages[index % instrumentalImages.count]
    }
}

// Preference key for tracking scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Progress View - Shows user's lyric writing progress
struct ProgressView: View {
    @State private var selectedGenre: String = "Rap"
    @State private var currentBackgroundIndex = 0
    @State private var backgroundTimer: Timer?
    
    let genres = ["Rap", "Country", "Pop", "Latin", "Rock", "KPOP"]
    let toolBackgrounds = ["tool-bg1", "tool-bg2", "tool-bg3", "tool-bg4", "tool-bg5", "tool-bg6"]
    
    let tools = [
        ("AI Bar Generator", "wand.and.stars", "Generate relatable bars that rhyme to your inputted lyrics.", false),
        ("Alliterate It", "a.circle", "Before: I hid my gun\nAfter: Silently Snuck Steel", false),
        ("Chorus Creator", "music.note", "A song's repeated, memorable section that conveys the theme.", false),
        ("Creative One-Liner", "lightbulb.circle", "Generate a creative metaphors or simile related to your subject.", true),
        ("Diss Track Generator", "flame.circle", "Generate diss tracks according to your opponent's vulnerabilities.", true),
        ("Double Entendre", "2.circle", "A double entendre is a phrase designed to have two meanings.", true),
        ("Finisher", "checkmark.circle", "Analyze themes/rhyme schemes to finish your incomplete song.", true),
        ("Flex-on-'em", "star.circle", "Create a song relating to your personal accomplishments.", true),
        ("Imperfect Rhyme", "rhombus.circle", "An imperfect rhyme is when two words almost rhyme, but not quite.", true),
        ("Industry Analyzer", "chart.bar.circle", "Analyze the commerciality of a song for radio & record labels.", true),
        ("Quadruple Entendre", "4.circle", "A quadruple entendre is a phrase designed to have four meanings.", true),
        ("Rap Instagram Captions", "camera.circle", "Generate clever Instagram captions for your fans to see.", true),
        ("Rap Name Generator", "person.badge.plus", "Generate modern rap names inspired by your name.", true),
        ("Shapeshift", "arrow.2.squarepath", "Manipulate one word to sound like another word.", true),
        ("Triple Entendre", "3.circle", "A triple entendre is a phrase designed to have three meanings.", true),
        ("Ultimate Come Up Song", "star.circle", "Similar to an artist's style, but unique to your life story.", false)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header and Genre Selector with gradient background
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Lyric Tools")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
                
                // Genre Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(genres, id: \.self) { genre in
                            Button(action: { 
                                if genre == "Rap" {
                                    selectedGenre = genre 
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(genre)
                                        .font(.system(size: 14, weight: .medium))
                                    
                                    if genre != "Rap" {
                                        Text("(Coming Soon)")
                                            .font(.system(size: 10, weight: .light))
                                            .opacity(0.7)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedGenre == genre ? Color(hex: "#e83a51") : 
                                    genre == "Rap" ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)
                                )
                                .foregroundColor(genre == "Rap" ? .white : .white.opacity(0.5))
                                .cornerRadius(16)
                            }
                            .disabled(genre != "Rap")
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
            }
            .background(
                GeometryReader { geometry in
                    ZStack {
                        // Background image - extended to top safe area with cycling tool backgrounds
                        Image(toolBackgrounds[currentBackgroundIndex])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200 + geometry.safeAreaInsets.top)
                            .clipped()
                            .animation(.easeInOut(duration: 1.0), value: currentBackgroundIndex)
                        
                        // Gradient overlay for shadow transition into black - adjusted for smoother transition
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: geometry.safeAreaInsets.top / (200 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.1), location: (geometry.safeAreaInsets.top + 100) / (200 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.3), location: (geometry.safeAreaInsets.top + 120) / (200 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.5), location: (geometry.safeAreaInsets.top + 140) / (200 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.7), location: (geometry.safeAreaInsets.top + 160) / (200 + geometry.safeAreaInsets.top)),
                                .init(color: Color.black.opacity(0.95), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .ignoresSafeArea(.all, edges: .top)
            )
            
            // Tools Grid - Single column layout
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                        ToolCard(
                            title: tool.0,
                            icon: tool.1,
                            description: tool.2,
                            isFirst: index < 2,
                            isPro: tool.3,
                            backgroundImage: getBackgroundForTool(toolName: tool.0, index: index)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .padding(.bottom, 100) // Added extra bottom padding to prevent cutoff
            }
        }
        .background(Color.fyeBackground)
        .navigationBarHidden(true)
        .onAppear {
            startBackgroundTimer()
        }
        .onDisappear {
            stopBackgroundTimer()
        }
    }
    
    // Timer functions for background cycling
    private func startBackgroundTimer() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 1.0)) {
                currentBackgroundIndex = (currentBackgroundIndex + 1) % toolBackgrounds.count
            }
        }
    }
    
    private func stopBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }
    
    // Function to get the correct background for each tool
    private func getBackgroundForTool(toolName: String, index: Int) -> String {
        switch toolName {
        case "Finisher", "Rap Name Generator":
            return "tool-bg4"
        case "Ultimate Come Up Song", "Industry Analyzer":
            return "tool-bg1"
        default:
            return toolBackgrounds[index % toolBackgrounds.count]
        }
    }
}

struct ToolCard: View {
    let title: String
    let icon: String
    let description: String
    let isFirst: Bool
    let isPro: Bool
    let backgroundImage: String
    @State private var showingToolDetail = false
    
    // Map tool titles to their corresponding image names
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
        VStack(spacing: 0) {
            // Card content
            VStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                // Custom tool image between title and description
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .padding(.vertical, 8)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true) // Allow text to expand vertically
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Background image
                    Image(backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    
                    // Dark overlay for text readability
                    Color.black.opacity(0.5)
                }
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            }
        }
        .fullScreenCover(isPresented: $showingToolDetail) {
            ToolDetailView(title: title, description: description, backgroundImage: backgroundImage)
        }
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
                                    .stroke(Color(hex: "#e83a51"), lineWidth: 3)
                            )
                    } else {
                        Image(profileManager.profilePicture)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "#e83a51"), lineWidth: 3)
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
                            .foregroundColor(.white)
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
                        .foregroundColor(.white)
                    
                                Image(systemName: "pencil")
                        .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
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
                                .foregroundColor(.white)
                            Text("Songs")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Streak
                    VStack(spacing: 6) {
                        Text("\(streakManager.currentStreak)")
                            .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Text("Streak")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Words
                    VStack(spacing: 6) {
                        Text(totalWords)
                            .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Text("Words")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 50)
            .padding(.bottom, 40)
            
            // Menu Section
            VStack(spacing: 0) {
                if showingSupportEmail {
                    // Show email address
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color(hex: "#e83a51"))
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Contact Support")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                // Email contact
                                Button(action: {
                                    UIPasteboard.general.string = "support@fye.ai"
                                    showingCopiedFeedback = true
                                    
                                    // Hide the feedback after 2 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        showingCopiedFeedback = false
                                    }
                                }) {
                                    Text(showingCopiedFeedback ? "Copied!" : "support@fye.ai")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(showingCopiedFeedback ? .green : .blue)
                                        .animation(.easeInOut(duration: 0.2), value: showingCopiedFeedback)
                                }
                                
                                // Website contact link
                                Button(action: {
                                    if let url = URL(string: "https://lyricgenerators.com/contact-us") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text("lyricgenerators.com/contact-us")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                        .underline()
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showingSupportEmail = false
                                showingCopiedFeedback = false // Reset feedback when hiding
                            }) {
                                Text("Hide")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                    }
                    .padding(.bottom, 12)
                } else {
                    // Show support button
                    ProfileMenuItem(
                        icon: "envelope",
                        title: "Support",
                        showChevron: false,
                        action: {
                            showingSupportEmail = true
                            showingCopiedFeedback = false // Reset feedback when showing support
                        }
                    )
                }
                
                // Log Out
                ProfileMenuItem(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Log Out",
                    showChevron: false,
                    action: {
                        showingLogoutAlert = true
                    }
                )
                
                // Delete Account
                ProfileMenuItem(
                    icon: "xmark",
                    title: "Delete Account",
                    showChevron: false,
                    isDestructive: false,
                    action: {
                        showingDeleteAlert = true
                    }
                )
            }
            
            Spacer(minLength: 40)
            
            // Footer
            Text("Fye • 2025 • v1.20.1")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 100)
            }
        .padding(.horizontal, 24)
        .background(Color.fyeBackground)
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
        profileManager.userName = "@takeflight395"
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
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isDestructive ? .red : Color(hex: "#e83a51"))
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .white)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.bottom, 12)
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
    
    static func == (lhs: AudioManager, rhs: AudioManager) -> Bool {
        return lhs === rhs
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
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
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Browse Files button
                    Button(action: { showingFilePicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Browse Files")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Image("tool-bg1")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .cornerRadius(16)
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
    @StateObject private var songAudioManager = AudioManager() // Each song gets its own audio manager
    
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
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if showDeleteButton {
                    Button(action: {}) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.fyeDeleteRed)
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
                .foregroundColor(.white)
                .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
            
                    Text(song.displayDate)
                .font(.system(size: 14))
                .foregroundColor(.fyeSecondaryText)
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
                audioManager: songAudioManager, // Use song-specific audio manager to prevent cross-contamination
                onDismiss: {
                    showEditView = false
                }
            )
        }
        .onAppear {
            // Load associated instrumental for this specific song when card appears
            if let associatedInstrumental = song.associatedInstrumental {
                let sharedManager = SharedInstrumentalManager.shared
                let instrumentalAudioManager = sharedManager.getAudioManager(for: associatedInstrumental)
                
                if let sourcePlayer = instrumentalAudioManager.player {
                    do {
                        songAudioManager.player = try AVAudioPlayer(contentsOf: sourcePlayer.url!)
                        songAudioManager.player?.prepareToPlay()
                        songAudioManager.duration = sourcePlayer.duration
                        songAudioManager.audioFileName = associatedInstrumental
                        print("🎵 AlbumCard loaded associated instrumental: \(associatedInstrumental) for song: \(song.title)")
                    } catch {
                        print("❌ AlbumCard failed to load instrumental: \(error)")
                    }
                }
            }
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
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Browse Files button to add new instrumentals
                        Button(action: { showingFilePicker = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("Browse Files")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
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
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
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
    @ObservedObject var audioManager: AudioManager
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var currentLineSyllables: Int = 0
    @State private var cursorPosition: Int = 0
    @State private var currentRhymes: [String] = []
    @State private var lastWord: String = ""
    @StateObject private var rhymeEngine = DatamuseRhymeEngine()
    @StateObject private var rhymeHighlighter = RhymeHighlighter()
    @State private var showingRhymeHighlights = false
    @State private var isEditingTitle = false
    @State private var showingInstrumentalSelector = false
    @State private var showingDeleteAlert = false
    @State private var hasInstrumentalLoaded = false // Track instrumental state for immediate UI updates
    @State private var hasUserEditedText = false // Track if user actually edited lyrics
    @State private var originalLyrics: String = "" // Store original lyrics to detect changes
    @State private var isPlayerHidden = false // Track if audio player is hidden
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isLyricsFocused: Bool
    @State private var isKeyboardVisible = false
    let onDismiss: () -> Void
    
    init(songManager: SongManager, song: Song, audioManager: AudioManager, onDismiss: @escaping () -> Void) {
        self.songManager = songManager
        self.audioManager = audioManager
        self.onDismiss = onDismiss
        self._song = State(initialValue: song)
        
        print("🔧 SongEditView initialized for song: \(song.title)")
        print("🔧 Initial associatedInstrumental: \(song.associatedInstrumental ?? "nil")")
    }
    
    // Function to extract the last complete word from text
    private func getLastWord(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .compactMap { word in
                let separatorSet = CharacterSet.punctuationCharacters
                let cleaned = word.trimmingCharacters(in: separatorSet)
                return cleaned.isEmpty ? nil : cleaned
            }
        return words.last ?? ""
    }
    
    // Function to update rhymes using Datamuse API
    private func updateRhymes() {
        let newLastWord = getLastWord(from: song.lyrics)
        print("🔄 updateRhymes called - newLastWord: '\(newLastWord)', lastWord: '\(lastWord)'")
        
        if newLastWord != lastWord && !newLastWord.isEmpty && newLastWord.count >= 2 {
            print("✅ Conditions met, finding Datamuse rhymes for: '\(newLastWord)'")
            lastWord = newLastWord
            
            // Get immediate fallback rhymes for instant feedback
            currentRhymes = rhymeEngine.getFallbackRhymes(for: newLastWord)
            
            // Then get real API results asynchronously
            Task {
                let apiRhymes = await rhymeEngine.findRhymesAsync(for: newLastWord)
                await MainActor.run {
                    // Only update if we're still on the same word
                    if lastWord == newLastWord {
                        currentRhymes = apiRhymes.isEmpty ? currentRhymes : apiRhymes
                        print("🌐 Updated with Datamuse results: \(currentRhymes)")
                    }
                }
            }
            
            print("🎵 Immediate fallback rhymes: \(currentRhymes)")
        } else if newLastWord.isEmpty {
            print("🧹 Clearing rhymes - word is empty")
            currentRhymes = []
            lastWord = ""
        } else {
            print("⏭️ Skipping update - same word or too short")
        }
    }
    
    // Function to count syllables in a string
    private func countSyllables(in text: String) -> Int {
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { return 0 }
        
        // Common syllable counting patterns
        let vowelPattern = "[aeiouy]+"
        let silentEPattern = "e$"
        let consonantYPattern = "[bcdfghjklmnpqrstvwxz]y"
        
        var syllableCount = 0
        
        // Count vowel groups
        if let regex = try? NSRegularExpression(pattern: vowelPattern, options: .caseInsensitive) {
            syllableCount = regex.numberOfMatches(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.count))
        }
        
        // Subtract silent 'e' at the end
        if let regex = try? NSRegularExpression(pattern: silentEPattern, options: .caseInsensitive) {
            let silentECount = regex.numberOfMatches(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.count))
            syllableCount -= silentECount
        }
        
        // Add consonant + y combinations
        if let regex = try? NSRegularExpression(pattern: consonantYPattern, options: .caseInsensitive) {
            let consonantYCount = regex.numberOfMatches(in: cleanText, options: [], range: NSRange(location: 0, length: cleanText.count))
            syllableCount += consonantYCount
        }
        
        // Ensure at least 1 syllable for non-empty words
        return max(syllableCount, 1)
    }
    
    // Function to get current line text based on cursor position
    private func getCurrentLine(from text: String, cursorPosition: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
        
        // If text is empty, return empty string
        if text.isEmpty {
            return ""
        }
        
        // Get the last line that has content, or the very last line if it's being typed
        for line in lines.reversed() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return line
            }
        }
        
        // If all lines are empty, return the last line (user might be typing)
        return lines.last ?? ""
    }
    
    // Function to update syllable count
    private func updateSyllableCount() {
        let currentLine = getCurrentLine(from: song.lyrics, cursorPosition: cursorPosition)
        var separatorSet = CharacterSet.whitespacesAndNewlines
        separatorSet.formUnion(.punctuationCharacters)
        let words = currentLine.components(separatedBy: separatorSet).filter { !$0.isEmpty }
        currentLineSyllables = words.reduce(0) { total, word in
            total + countSyllables(in: word)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header section - always visible but compact when keyboard is shown
                VStack(spacing: 0) {
                    // Header with navigation - hidden when keyboard is visible
                    if !isKeyboardVisible {
                    HStack {
                        Button(action: { 
                            // Only move to front if user actually edited text
                            if hasUserEditedText {
                                song.lastEdited = Date()
                                songManager.updateSong(song)
                                print("⬅️ Going back - song moved to front due to text edits")
                            } else {
                                print("⬅️ Going back - no text changes, song stays in current position")
                            }
                            onDismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .semibold))
                                Text("back")
                                        .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.1)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                    .padding(.bottom, 16)
                    }
                    
                    // Song content section - collapsed when keyboard is visible
                    if !isKeyboardVisible {
                    HStack(spacing: 16) {
                        // Album artwork - tappable for photo selection
                        Button(action: { showingPhotoPicker = true }) {
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
                            .frame(width: 160, height: 160)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                // Camera icon overlay
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                            .padding(6)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(Circle())
                                            .padding(4)
                                    }
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Rectangle())
                        .frame(width: 160, height: 160)
                        
                        // Song details
                        VStack(alignment: .leading, spacing: 8) {
                            if isEditingTitle {
                                // Expandable TextEditor when editing
                                TextEditor(text: $song.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 50, maxHeight: 120)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .tint(.white) // White cursor
                                    .focused($isTitleFocused)
                                    .onAppear {
                                        isTitleFocused = true
                                    }
                                    .onChange(of: isTitleFocused) { focused in
                                        if !focused {
                                            isEditingTitle = false
                                        }
                                    }
                            } else {
                                // Single line display when not editing
                                Text(song.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        isEditingTitle = true
                                    }
                            }
                            
                            Text(song.displayDate)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .padding(.top, 30)
                }
                }
                .background(Color.black)
                
                // Eye icon and syllables section
                HStack(spacing: 16) {
                    // Keyboard dismiss button - moved to left side
                    if isKeyboardVisible {
                        Button(action: {
                            isLyricsFocused = false
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("back")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                        LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.08)
                            ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        // Show Rhymes button with eye icon and text
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingRhymeHighlights.toggle()
                            }
                            
                            if showingRhymeHighlights {
                                // Trigger rhyme analysis when switching to highlight mode
                                Task {
                                    await rhymeHighlighter.analyzeAndHighlight(song.lyrics)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: showingRhymeHighlights ? "eye.fill" : "eye")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(showingRhymeHighlights ? Color(hex: "#e83a51") : .white.opacity(0.8))
                                
                                Text("Show Rhymes")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(showingRhymeHighlights ? Color(hex: "#e83a51") : .white.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        showingRhymeHighlights ? Color(hex: "#e83a51").opacity(0.2) : Color.white.opacity(0.15),
                                        showingRhymeHighlights ? Color(hex: "#e83a51").opacity(0.1) : Color.white.opacity(0.08)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        showingRhymeHighlights ? Color(hex: "#e83a51").opacity(0.4) : Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                        }
                        
                        // Syllables count with enhanced styling
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("\(currentLineSyllables)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Syllables")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.08)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, isKeyboardVisible ? 6 : 10)
                
                // Lyrics editor/viewer - expand to fill available space
                VStack(spacing: 0) {
                    if showingRhymeHighlights {
                        // Rhyme highlighting view
                        ScrollView {
                            Text(rhymeHighlighter.highlightedText)
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Normal text editor
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $song.lyrics)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .background(Color.black)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 24)
                                .padding(.vertical, isKeyboardVisible ? 16 : 20)
                                .tint(.white) // White cursor
                                .focused($isLyricsFocused)
                                .onChange(of: song.lyrics) { newValue in
                                    updateSyllableCount()
                                    updateRhymes()
                                    
                                    // Check if user actually changed the text (not just programmatic changes)
                                    if newValue != originalLyrics && !hasUserEditedText {
                                        hasUserEditedText = true
                                        song.lastEdited = Date()
                                        songManager.updateSong(song)
                                        print("✍️ User edited lyrics - moved song to front of recently added")
                                    } else if hasUserEditedText && newValue != originalLyrics {
                                        // User continues editing - update timestamp but song already at front
                                        song.lastEdited = Date()
                                        print("✍️ User continues editing lyrics")
                                    }
                                }
                            
                            // Placeholder text when lyrics are empty
                            if song.lyrics.isEmpty {
                                Text("Start writing your lyrics here...")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 28) // Match TextEditor padding + margin
                                    .padding(.top, 24) // Match TextEditor padding
                                    .allowsHitTesting(false) // Allow taps to pass through to TextEditor
                            }
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1) // Give text editor priority to expand when audio player is hidden
                .onTapGesture {
                    // Dismiss title editing when tapping outside
                    if isEditingTitle {
                        isEditingTitle = false
                        isTitleFocused = false
                    }
                }
                .onAppear {
                    print("🎬 onAppear START: song=\(song.title)")
                    print("🎬 onAppear: audioManager.player exists: \(audioManager.player != nil)")
                    print("🎬 onAppear: audioManager.audioFileName: '\(audioManager.audioFileName)'")
                    print("🎬 onAppear: song.associatedInstrumental: '\(song.associatedInstrumental ?? "nil")'")
                    
                    // Store original lyrics to track changes
                    originalLyrics = song.lyrics
                    hasUserEditedText = false
                    print("🎬 onAppear: Stored original lyrics (length: \(originalLyrics.count))")
                    
                    updateSyllableCount()
                    updateRhymes()
                    
                    // Initialize instrumental loaded state before loading associated instrumental
                    hasInstrumentalLoaded = audioManager.player != nil || !audioManager.audioFileName.isEmpty
                    print("🎬 onAppear: hasInstrumentalLoaded initialized to: \(hasInstrumentalLoaded)")
                    print("🎬 onAppear: audioManager.audioFileName: '\(audioManager.audioFileName)'")
                    
                    loadAssociatedInstrumental()
                    
                    // Multiple state checks to catch view recreation issues
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let shouldShow = audioManager.player != nil || !audioManager.audioFileName.isEmpty
                        if shouldShow != hasInstrumentalLoaded {
                            print("🚨 State mismatch detected (200ms)! audioManager.player=\(audioManager.player != nil), audioFileName='\(audioManager.audioFileName)', hasInstrumentalLoaded=\(hasInstrumentalLoaded)")
                            print("🔧 Correcting hasInstrumentalLoaded to: \(shouldShow)")
                            hasInstrumentalLoaded = shouldShow
                            audioManager.objectWillChange.send()
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let shouldShow = audioManager.player != nil || !audioManager.audioFileName.isEmpty
                        if shouldShow != hasInstrumentalLoaded {
                            print("🚨 State mismatch detected (500ms)! audioManager.player=\(audioManager.player != nil), audioFileName='\(audioManager.audioFileName)', hasInstrumentalLoaded=\(hasInstrumentalLoaded)")
                            print("🔧 Correcting hasInstrumentalLoaded to: \(shouldShow)")
                            hasInstrumentalLoaded = shouldShow
                            audioManager.objectWillChange.send()
                        } else {
                            print("✅ State is synchronized: audioManager.player=\(audioManager.player != nil), hasInstrumentalLoaded=\(hasInstrumentalLoaded)")
                        }
                    }
                }
                
                // Bottom section with syllables and rhymes
                bottomToolsSection
                
                // Audio Player Section - hidden when keyboard is visible or title is being edited
                if !isKeyboardVisible && !isEditingTitle {
                VStack(spacing: 16) {
                    // Show audio controls if audio is loaded, or load button if not
                if audioManager.player != nil && (hasInstrumentalLoaded || !audioManager.audioFileName.isEmpty) {
                        // Header with change audio button
                        HStack {
                            Text("Audio Track")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                            
                            // Hide Player button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPlayerHidden.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isPlayerHidden ? "eye" : "eye.slash")
                                        .font(.system(size: 12))
                                    Text(isPlayerHidden ? "Show Player" : "Hide Player")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            // Remove button
                            Button(action: {
                                clearInstrumental()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12))
                                    Text("Remove")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Conditional audio player content - only show when not hidden
                        if !isPlayerHidden {
                            // Instrumental-style audio player
                            instrumentalStylePlayer
                                .padding(.horizontal, 16)
                            
                            // Loop controls - exact same as instrumentals page
                            LoopControlsView()
                                .padding(.horizontal, 16)
                        }
                    } else {
                        // Load audio file button
                        Button(action: {
                            showingInstrumentalSelector = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.badge.plus")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Choose Instrumental")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                Image("tool-bg1")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 20)
                }
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .onChange(of: isLyricsFocused) { focused in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isKeyboardVisible = focused
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        song.customImage = uiImage
                        song.lastEdited = Date()
                        songManager.updateSong(song)
                    }
                }
            }
            .sheet(isPresented: $showingInstrumentalSelector) {
                InstrumentalSelectorView { instrumentalTitle in
                    print("🎯 User selected instrumental: \(instrumentalTitle)")
                    loadInstrumental(instrumentalTitle)
                }
            }
            .alert("Delete Song", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteSong()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete '\(song.title)'? This action cannot be undone.")
            }
        }
    }
    
    // Bottom tools section with rhymes - compact when keyboard is visible
    private var bottomToolsSection: some View {
        VStack(spacing: 0) {
            // Rhyming words grid - hidden when editing title
            if !currentRhymes.isEmpty && !isEditingTitle {
                VStack(spacing: 0) {
                    // Enhanced background with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.95),
                                    Color.black.opacity(0.9)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            // Subtle top border
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 1)
                            , alignment: .top
                        )
                    
                    HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                            ForEach(currentRhymes, id: \.self) { rhyme in
                                Button(action: {
                                    // Add rhyme to lyrics
                                    addRhymeToLyrics(rhyme)
                                }) {
                                    Text(rhyme)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.gray.opacity(0.3),
                                                    Color.gray.opacity(0.2)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                        )
                                        .shadow(color: Color.gray.opacity(0.2), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                }
                }
                .padding(.bottom, 16)
            }
        }
    }
    
    // Function to add selected rhyme to lyrics
    private func addRhymeToLyrics(_ rhyme: String) {
        song.lyrics += " \(rhyme)"
        hasUserEditedText = true // Mark as edited since user added a rhyme
        song.lastEdited = Date()
        songManager.updateSong(song)
        updateSyllableCount()
        updateRhymes()
        print("🎵 User added rhyme '\(rhyme)' - marked as edited")
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
        
        // Clear any playing audio
        audioManager.player = nil
        
        // Delete the song from the manager
        songManager.deleteSong(song)
        
        print("✅ Song deleted successfully")
        
        // Dismiss the view after deletion
        onDismiss()
    }
    
    // Instrumental-style Audio Player - exact same design as instrumentals page
    private var instrumentalStylePlayer: some View {
        VStack(spacing: 12) {
            // Top row with track info and play button - exact same as InstrumentalListItem
            HStack(spacing: 12) {
                // Waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                
                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(audioManager.audioFileName.isEmpty ? "No audio loaded" : audioManager.audioFileName)
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
                        audioManager.play()
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
            
            // Scrubber line with drag gesture - exact same as InstrumentalListItem
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
                            .frame(width: geometry.size.width * CGFloat(audioManager.currentTime / max(audioManager.duration, 1)), height: 4)
                        
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .offset(y: 60),
            alignment: .bottom
        )
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
                            .fill(Color(hex: "#e83a51"))
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
                                .fill(Color(hex: "#e83a51"))
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
}



// Datamuse API Rhyme Engine - Professional rhyming service with massive vocabulary
class DatamuseRhymeEngine: ObservableObject {
    private let baseURL = "https://api.datamuse.com/words"
    
    // Find rhymes using professional Datamuse API (perfect + slant rhymes)
    func findRhymes(for word: String) async -> [String] {
        var separatorSet = CharacterSet.whitespacesAndNewlines
        separatorSet.formUnion(.punctuationCharacters)
        let cleanWord = word.lowercased().trimmingCharacters(in: separatorSet)
        
        guard !cleanWord.isEmpty, cleanWord.count >= 2 else {
            print("⚠️ Word too short or empty: '\(cleanWord)'")
            return []
        }
        
        print("🌐 Datamuse API request for: '\(cleanWord)'")
        
        // Get both perfect rhymes and near rhymes (slant rhymes)
        async let perfectRhymes = fetchRhymes(for: cleanWord, type: "rel_rhy")  // Perfect rhymes
        async let slantRhymes = fetchRhymes(for: cleanWord, type: "rel_nry")    // Near/slant rhymes
        
        do {
            let (perfect, slant) = await (try perfectRhymes, try slantRhymes)
            
            // Combine and deduplicate, prioritizing perfect rhymes
            var allRhymes = perfect
            for rhyme in slant {
                if !allRhymes.contains(rhyme) {
                    allRhymes.append(rhyme)
                }
            }
            
            let finalRhymes = Array(allRhymes.prefix(50))
            print("✅ Datamuse found \(perfect.count) perfect + \(slant.count) slant rhymes = \(finalRhymes.count) total")
            
            return finalRhymes
            
        } catch {
            print("❌ Datamuse API error: \(error)")
            return getFallbackRhymes(for: cleanWord)
        }
    }
    
    // Helper function to fetch specific type of rhymes
    private func fetchRhymes(for word: String, type: String) async throws -> [String] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: type, value: word),            // rel_rhy or rel_nry
            URLQueryItem(name: "md", value: "d,p,r"),         // Include definitions, pronunciations, rhyme info
            URLQueryItem(name: "max", value: "30")            // Limit results per type
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let rhymes = try JSONDecoder().decode([DatamuseWord].self, from: data)
        
        // Extract and filter word strings
        return rhymes.compactMap { rhyme in
            let rhymeWord = rhyme.word.lowercased()
            // Filter out the original word and very short words
            return (rhymeWord != word && rhymeWord.count >= 2) ? rhymeWord : nil
        }
    }
    
    // Synchronous wrapper for compatibility with existing UI
    func findRhymes(for word: String) -> [String] {
        // Return fallback immediately for sync calls
        return getFallbackRhymes(for: word)
    }
    
    // Improved async version for real-time updates
    @MainActor
    func findRhymesAsync(for word: String) async -> [String] {
        return await findRhymes(for: word)
    }
    
    // Get only perfect rhymes
    func findPerfectRhymes(for word: String) async -> [String] {
        var separatorSet = CharacterSet.whitespacesAndNewlines
        separatorSet.formUnion(.punctuationCharacters)
        let cleanWord = word.lowercased().trimmingCharacters(in: separatorSet)
        
        guard !cleanWord.isEmpty, cleanWord.count >= 2 else { return [] }
        
        do {
            return try await fetchRhymes(for: cleanWord, type: "rel_rhy")
        } catch {
            return []
        }
    }
    
    // Get only slant/near rhymes
    func findSlantRhymes(for word: String) async -> [String] {
        var separatorSet = CharacterSet.whitespacesAndNewlines
        separatorSet.formUnion(.punctuationCharacters)
        let cleanWord = word.lowercased().trimmingCharacters(in: separatorSet)
        
        guard !cleanWord.isEmpty, cleanWord.count >= 2 else { return [] }
        
        do {
            return try await fetchRhymes(for: cleanWord, type: "rel_nry")
        } catch {
            return []
        }
    }
    
    // Basic fallback for offline or API failures
    func getFallbackRhymes(for word: String) -> [String] {
        // Simple fallback patterns for common endings
        let commonRhymes: [String: [String]] = [
            "ay": ["day", "way", "say", "play", "stay"],
            "ight": ["night", "light", "fight", "right", "sight"],
            "eart": ["heart", "start", "part", "art", "smart"],
            "ime": ["time", "rhyme", "crime", "climb", "prime"],
            "ove": ["love", "above", "shove", "dove"],
            "ain": ["pain", "rain", "chain", "brain", "main"]
        ]
        
        for (ending, rhymes) in commonRhymes {
            if word.hasSuffix(ending) {
                return rhymes.filter { $0 != word }
            }
        }
        
        return []
    }
}

// Datamuse API Response Model
struct DatamuseWord: Codable {
    let word: String
    let score: Int?
    let tags: [String]?
    
    // Optional fields from API
    let defs: [String]?  // Definitions
}

// Rhyme Highlighting System - Visual rhyme pattern analysis
class RhymeHighlighter: ObservableObject {
    @Published var highlightedText: AttributedString = AttributedString("")
    private let rhymeEngine = DatamuseRhymeEngine()
    
    // Color palette for rhyme groups
    private let rhymeColors: [Color] = [
        .blue, .green, .purple, .orange, .red, .cyan, 
        .pink, .yellow, .indigo, .mint, .brown, .teal
    ]
    
    // Analyze lyrics and create color-coded highlighting
    func analyzeAndHighlight(_ lyrics: String) async {
        print("🎨 Starting rhyme analysis for highlighting...")
        
        let words = extractWords(from: lyrics)
        let rhymeGroups = await findRhymeGroups(words: words)
        let highlighted = createHighlightedText(lyrics: lyrics, rhymeGroups: rhymeGroups)
        
        await MainActor.run {
            self.highlightedText = highlighted
        }
    }
    
    // Extract words while preserving positions for highlighting
    private func extractWords(from text: String) -> [(word: String, range: Range<String.Index>)] {
        var words: [(String, Range<String.Index>)] = []
        
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { substring, range, _, _ in
            if let word = substring {
                let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if cleanWord.count >= 2 {
                    words.append((cleanWord, range))
                }
            }
        }
        
        return words
    }
    
    // Group words by rhymes using Datamuse API (perfect + slant rhymes)
    private func findRhymeGroups(words: [(String, Range<String.Index>)]) async -> [String: (groupIndex: Int, isSlant: Bool)] {
        var rhymeGroups: [String: (Int, Bool)] = [:]
        var groupIndex = 0
        
        for (word, _) in words {
            if rhymeGroups[word] != nil { continue } // Already processed
            
            // Find perfect and slant rhymes separately
            let perfectRhymes = await rhymeEngine.findPerfectRhymes(for: word)
            let slantRhymes = await rhymeEngine.findSlantRhymes(for: word)
            
            // Find which perfect rhymes exist in the lyrics
            var matchingPerfectRhymes: [String] = []
            for rhyme in perfectRhymes {
                if words.contains(where: { $0.0 == rhyme }) {
                    matchingPerfectRhymes.append(rhyme)
                }
            }
            
            // Find which slant rhymes exist in the lyrics (excluding perfect rhymes)
            var matchingSlantRhymes: [String] = []
            for rhyme in slantRhymes {
                if words.contains(where: { $0.0 == rhyme }) && !perfectRhymes.contains(rhyme) {
                    matchingSlantRhymes.append(rhyme)
                }
            }
            
            // Only assign group if this word has rhyming partners in the lyrics
            if !matchingPerfectRhymes.isEmpty || !matchingSlantRhymes.isEmpty {
                // Assign this word and its perfect rhymes to the same group
                rhymeGroups[word] = (groupIndex, false) // false = perfect rhyme
                
                for rhyme in matchingPerfectRhymes {
                    rhymeGroups[rhyme] = (groupIndex, false)
                }
                
                for rhyme in matchingSlantRhymes {
                    rhymeGroups[rhyme] = (groupIndex, true) // true = slant rhyme
                }
                
                groupIndex += 1
            }
        }
        
        print("🎯 Found \(groupIndex) rhyme groups with perfect and slant rhymes")
        return rhymeGroups
    }
    
    // Create AttributedString with color highlighting (perfect + slant rhymes)
    private func createHighlightedText(lyrics: String, rhymeGroups: [String: (groupIndex: Int, isSlant: Bool)]) -> AttributedString {
        var attributed = AttributedString(lyrics)
        
        // Apply styling to all words
        lyrics.enumerateSubstrings(in: lyrics.startIndex..<lyrics.endIndex, options: [.byWords, .localized]) { substring, range, _, _ in
            if let word = substring {
                let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                let attributedRange = Range(range, in: attributed)!
                
                if let rhymeInfo = rhymeGroups[cleanWord] {
                    // Apply highlighting to rhyming words
                    let color = self.rhymeColors[rhymeInfo.groupIndex % self.rhymeColors.count]
                    
                    if rhymeInfo.isSlant {
                        // Slant rhymes: lighter background with border effect
                        attributed[attributedRange].backgroundColor = color.opacity(0.15)
                        attributed[attributedRange].foregroundColor = .white
                        attributed[attributedRange].underlineStyle = .single
                    } else {
                        // Perfect rhymes: solid background (original styling)
                        attributed[attributedRange].backgroundColor = color.opacity(0.3)
                        attributed[attributedRange].foregroundColor = .white
                    }
                } else {
                    // Ensure non-rhyming words remain visible with default styling
                    attributed[attributedRange].foregroundColor = .white
                    attributed[attributedRange].backgroundColor = .clear
                }
            }
        }
        
        return attributed
    }
}

// Old PhoneticRhymeEngine completely removed - now using Datamuse API for professional rhyming

// ... existing code ...

// Add ImagePicker struct before ProfileView
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

struct ToolDetailView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let description: String
    let backgroundImage: String
    @StateObject private var responseManager = ToolResponseManager.shared
    @State private var userInput = ""
    @State private var generatedText = ""
    @State private var isGenerating = false
    @State private var error: Error?
    @State private var showError = false
    @State private var showFullScreenText = false
    
    // Function to get placeholder text based on tool
    private func getPlaceholderText() -> String {
        switch title {
        case "AI Bar Generator":
            return "Type your lyrics here..."
        case "Alliterate It":
            return "Type a phrase to alliterate..."
        case "Chorus Creator":
            return "Insert what your song is about here..."
        case "Creative One-Liner":
            return "Write me a creative one-liner about..."
        case "Diss Track Generator":
            return "Insert 3 of your opponents weaknesses..."
        case "Double Entendre":
            return "Enter a topic for your double meaning..."
        case "Finisher":
            return "Paste your unfinished lyrics here..."
        case "Flex-on-'em":
            return "What accomplishment are you flexing?"
        case "Imperfect Rhyme":
            return "Enter words to create near rhymes..."
        case "Industry Analyzer":
            return "Paste your lyrics for analysis..."
        case "Quadruple Entendre":
            return "Enter a topic for four meanings..."
        case "Rap Instagram Captions":
            return "Enter lyrics or theme for captions..."
        case "Rap Name Generator":
            return "Enter your name or characteristics..."
        case "Shapeshift":
            return "Enter a word to transform..."
        case "Triple Entendre":
            return "Enter a topic for three meanings..."
        case "Ultimate Come Up Song":
            return "Tell us your story or goals..."
        default:
            return "Type your input here..."
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with gradient background
                    VStack(spacing: 0) {
                        // Header with close button
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
                            // Background image
                            Image(backgroundImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                            
                            // Gradient overlay
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
                    
                    // Input area
                    VStack(spacing: 24) {
                        // Text editor with custom styling - fixed touch handling
                        VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                                // Background container
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .cornerRadius(16)
                                    .frame(height: 200)
                                
                                // TextEditor with full touch area
                            TextEditor(text: $userInput)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .frame(height: 200)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .tint(.white) // White cursor
                                    .onChange(of: userInput) { newValue in
                                        responseManager.updateUserInput(for: title, userInput: newValue)
                                    }
                            
                                // Placeholder text overlay
                            if userInput.isEmpty {
                                    VStack {
                                        HStack {
                                Text(getPlaceholderText())
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.system(size: 16))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .allowsHitTesting(false)
                                            Spacer()
                            }
                                        Spacer()
                        }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Rainbow loading bar - same container as other elements
                        if isGenerating {
                            RainbowLoadingBar()
                                .padding(.horizontal, 24) // Match textbox horizontal padding
                                .padding(.top, -12) // Bring closer to textbox
                        }
                        
                        // Generated text (if any) - IMPROVED SCROLLABLE VERSION
                        if !generatedText.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header with copy button
                                HStack {
                                    Text("Generated Result")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    // Show restored indicator if content was loaded from previous session
                                    if let savedResponse = responseManager.toolResponses[title],
                                       !savedResponse.generatedText.isEmpty,
                                       Calendar.current.isDate(savedResponse.timestamp, inSameDayAs: Date()) == false {
                                        Text("Restored")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 6) {
                                        // Full screen view button - icon only
                                        Button(action: {
                                            showFullScreenText = true
                                        }) {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.8))
                                                .frame(width: 28, height: 28)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        
                                        // Copy button - icon only
                                        Button(action: {
                                            UIPasteboard.general.string = generatedText
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.8))
                                                .frame(width: 28, height: 28)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        
                                        // Clear button - icon only
                                        Button(action: {
                                            userInput = ""
                                            generatedText = ""
                                            responseManager.clearResponse(for: title)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.8))
                                                .frame(width: 28, height: 28)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                                
                                // Scrollable text container - max 8 lines then scroll
                                ScrollView {
                                    Text(generatedText)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                        .textSelection(.enabled) // Allow text selection for copying
                                }
                                .frame(height: 160) // Fixed height for approximately 8 lines (20px per line + padding)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }
                                .padding(.horizontal, 24)
                        }
                        
                        // Generate button
                        Button(action: {
                            Task {
                                await generateText()
                            }
                        }) {
                            Text("Generate")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    ZStack {
                                        // Background image
                                        Image(backgroundImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .clipped()
                                        
                                        // Dark overlay
                                        Color.black.opacity(0.3)
                                    }
                                )
                                .cornerRadius(28)
                                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .disabled(userInput.isEmpty || isGenerating)
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 32)
                    
                    Spacer()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "An unknown error occurred")
        }
        .fullScreenCover(isPresented: $showFullScreenText) {
            FullScreenTextView(text: generatedText, title: title)
        }
        .onAppear {
            // Load saved response when view appears
            let savedResponse = responseManager.getResponse(for: title)
            userInput = savedResponse.userInput
            generatedText = savedResponse.generatedText
        }
    }
    
    private func generateText() async {
        guard !userInput.isEmpty else { return }
        
        isGenerating = true
        do {
            let response = try await ToolPromptService.shared.generateResponse(
                for: title,
                input: userInput
            )
            print("✅ Generated text: \(response)")
            await MainActor.run {
                generatedText = response
                // Save the response to persistent storage
                responseManager.saveResponse(for: title, userInput: userInput, generatedText: response)
            }
        } catch {
            print("❌ Error generating text: \(error)")
            await MainActor.run {
                self.error = error
                showError = true
            }
        }
        await MainActor.run {
            isGenerating = false
        }
    }
}

// Full Screen Text View for better readability of long generated content with section copying
struct FullScreenTextView: View {
    @Environment(\.dismiss) var dismiss
    let text: String
    let title: String
    @State private var fontSize: CGFloat = 16
    @State private var copiedSectionIndex: Int? = nil
    
    // Split text into logical sections (by double line breaks or line breaks)
    private var textSections: [String] {
        // First try splitting by double line breaks (common in lyrics for verses/choruses)
        let doubleSplit = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // If we get good sections (2 or more), use them
        if doubleSplit.count > 1 {
            return doubleSplit
        }
        
        // Otherwise, split by single line breaks and group into reasonable chunks
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var sections: [String] = []
        var currentSection: [String] = []
        
        for line in lines {
            currentSection.append(line)
            // Create a new section every 4-6 lines or if line looks like a section header
            if currentSection.count >= 4 || line.lowercased().contains("verse") || line.lowercased().contains("chorus") || line.lowercased().contains("bridge") {
                sections.append(currentSection.joined(separator: "\n"))
                currentSection = []
            }
        }
        
        // Add remaining lines
        if !currentSection.isEmpty {
            sections.append(currentSection.joined(separator: "\n"))
        }
        
        return sections.isEmpty ? [text] : sections
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with controls
                    HStack {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Font size controls
                        HStack(spacing: 12) {
                            Button(action: {
                                fontSize = max(12, fontSize - 2)
                            }) {
                                Image(systemName: "textformat.size.smaller")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Button(action: {
                                fontSize = min(24, fontSize + 2)
                            }) {
                                Image(systemName: "textformat.size.larger")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    
                    // Scrollable content with section-based copying
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(textSections.enumerated()), id: \.offset) { index, section in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Section content
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(section)
                                            .font(.system(size: fontSize))
                                            .foregroundColor(.white)
                                            .lineSpacing(4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                        
                                        // Copy button for this section
                                        Button(action: {
                                            UIPasteboard.general.string = section
                                            copiedSectionIndex = index
                                            
                                            // Reset the copied state after 2 seconds
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                if copiedSectionIndex == index {
                                                    copiedSectionIndex = nil
                                                }
                                            }
                                        }) {
                                            Image(systemName: copiedSectionIndex == index ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 14))
                                                .foregroundColor(copiedSectionIndex == index ? .green : .white.opacity(0.6))
                                                .frame(width: 24, height: 24)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    // Section divider (except for last section)
                                    if index < textSections.count - 1 {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 1)
                                            .padding(.top, 12)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                    .background(Color.black)
                    
                    // Bottom toolbar
                    HStack {
                        Button(action: {
                            UIPasteboard.general.string = text
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy All")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .background(Color.black)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct RainbowLoadingBar: View {
    @State private var animationOffset: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        // Container that matches textbox/button width exactly
        Rectangle()
            .fill(Color.clear)
            .frame(height: 2)
            .overlay(
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 2)
                        .cornerRadius(1)
                    
                    // Animated gradient that flows across - properly contained
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.yellow,
                                        Color.pink,
                                        Color.orange,
                                        Color.yellow,
                                        Color.pink,
                                        Color.orange,
                                        Color.yellow,
                                        Color.pink,
                                        Color.orange,
                                        Color.yellow  // Multiple repetitions for seamless loop
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * 3, height: 2)
                            .cornerRadius(1)
                            .offset(x: animationOffset)
                            .animation(
                                .linear(duration: 1.8)
                                .repeatForever(autoreverses: false),
                                value: animationOffset
                            )
                    }
                    .clipped() // Prevent overflow beyond container
                }
            )
            .opacity(opacity)
            .scaleEffect(y: scale)
            .animation(.easeInOut(duration: 0.3), value: opacity)
            .animation(.easeInOut(duration: 0.3), value: scale)
            .onAppear {
                // Smooth entrance
                withAnimation(.easeInOut(duration: 0.3)) {
                    opacity = 1.0
                    scale = 1.0
                }
                // Start the flowing animation
                startFlowingAnimation()
            }
    }
    
    private func startFlowingAnimation() {
        animationOffset = 0  // Start at normal position
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            // Move left by container width for perfect loop
            animationOffset = -300  // Fixed width instead of screen width
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
        
        // Set initial selection based on current text
        if let time = parseTimeComponents(text) {
            // Ensure we're within valid ranges
            let minuteRow = max(0, min(time.minutes, 9))  // 0-9 -> 0-9
            let secondRow = max(0, min(time.seconds, 59)) // 0-59 -> 0-59
            picker.selectRow(minuteRow, inComponent: 0, animated: false)
            picker.selectRow(secondRow, inComponent: 1, animated: false)
        }
        
        return picker
    }
    
    func updateUIView(_ uiView: UIPickerView, context: Context) {
        if let time = parseTimeComponents(text) {
            // Ensure we're within valid ranges
            let minuteRow = max(0, min(time.minutes, 9))  // 0-9 -> 0-9
            let secondRow = max(0, min(time.seconds, 59)) // 0-59 -> 0-59
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
              minutes >= 0, minutes <= 9,    // Validate minutes range
              seconds >= 0, seconds <= 59    // Validate seconds range
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
        
        // Two components: minutes and seconds
        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            return 2
        }
        
        // Minutes: 0-9, Seconds: 0-59
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            return component == 0 ? 10 : 60  // 0-9 for minutes, 0-59 for seconds
        }
        
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            // Format: single digit for minutes, leading zero for seconds
            if component == 0 {
                label.text = "\(row)"  // Minutes: 0-9
            } else {
                label.text = String(format: "%02d", row)  // Seconds: 00-59
            }
            label.textColor = .white
            label.font = .systemFont(ofSize: 20, weight: .medium)
            label.textAlignment = .center
            return label
        }
        
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let minutes = pickerView.selectedRow(inComponent: 0)  // 0-9
            let seconds = pickerView.selectedRow(inComponent: 1)  // 0-59
            let timeString = "\(minutes):\(String(format: "%02d", seconds))"
            parent.text = timeString
            parent.onUpdate(timeString)
        }
    }
}

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
                // Remove the black background and let parent container color show through
        }
        .sheet(isPresented: $showingPicker) {
            VStack(spacing: 0) {
                // Header with X button
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
                
                // Picker
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
