import SwiftUI
import AVFoundation
import Combine
import WebKit
import AppsFlyerLib
import FirebaseCore
import Combine
import Network
import FirebaseMessaging
import AppTrackingTransparency

@main
struct EggCookStudioApp: App {
    
    @UIApplicationDelegateAdaptor(ApplicationDelegate.self) var appdelegate
    
    var body: some Scene {
        WindowGroup {
            CookStudioEntry()
        }
    }
}

class ApplicationDelegate: UIResponder, UIApplicationDelegate, AppsFlyerLibDelegate, MessagingDelegate, UNUserNotificationCenterDelegate, DeepLinkDelegate {
    
    private var attrData: [AnyHashable: Any] = [:]
    private var mergeTimer: Timer?
    
    private let trckActivationKey = UIApplication.didBecomeActiveNotification
    
    private var deepLinkClickEvent: [AnyHashable: Any] = [:]
    private let hasSentAttributionKey = "hasSentAttributionData"
    
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        retriveAllNeededDataFrom(pushData: userInfo)
        completionHandler(.newData)
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { [weak self] token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: "fcm_token")
            UserDefaults.standard.set(token, forKey: "push_token")
        }
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        setupPushInfrastructure()
        bootstrapAppsFlyer()
        
        if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            retriveAllNeededDataFrom(pushData: remotePayload)
        }
        
        observeAppActivation()
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = notification.request.content.userInfo
        retriveAllNeededDataFrom(pushData: payload)
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        retriveAllNeededDataFrom(pushData: response.notification.request.content.userInfo)
        completionHandler()
    }
    
    @objc private func triggerTracking() {
        if #available(iOS 14.0, *) {
            AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
            ATTrackingManager.requestTrackingAuthorization { _ in
                DispatchQueue.main.async {
                    AppsFlyerLib.shared().start()
                }
            }
        }
    }
    
    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(triggerTracking),
            name: trckActivationKey,
            object: nil
        )
    }
    
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        attrData = data
        fireMergedTimer()
        sendMergedDataTOSplash()
    }
    
    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status,
              let deepLinkObj = result.deepLink else { return }
        
        guard !UserDefaults.standard.bool(forKey: hasSentAttributionKey) else { return }
        
        deepLinkClickEvent = deepLinkObj.clickEvent
        
        NotificationCenter.default.post(name: Notification.Name("deeplink_values"), object: nil, userInfo: ["deeplinksData": deepLinkClickEvent])
        
        mergeTimer?.invalidate()
        
        sendMergedDataTOSplash()
    }
    
    func onConversionDataFail(_ error: Error) {
        broadcastAttributionUpdate(data: [:])
    }
    
    // MARK: - Private Setup
    private func setupPushInfrastructure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    private func bootstrapAppsFlyer() {
        AppsFlyerLib.shared().appsFlyerDevKey = CookStudioConfig.afDevKey
        AppsFlyerLib.shared().appleAppID = CookStudioConfig.afAppID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().deepLinkDelegate = self
    }
    
}


extension ApplicationDelegate {
    
    
    func sendMergedDataTOSplash() {
        var mergedAttrData = attrData
        for (key, value) in deepLinkClickEvent {
            if mergedAttrData[key] == nil {
                mergedAttrData[key] = value
            }
        }
        broadcastAttributionUpdate(data: mergedAttrData)
        UserDefaults.standard.set(true, forKey: hasSentAttributionKey)
        attrData = [:]
        deepLinkClickEvent = [:]
        mergeTimer?.invalidate()
    }
    
    func retriveAllNeededDataFrom(pushData payload: [AnyHashable: Any]) {
        var pushRefreshubal: String?
        
        
        if let url = payload["url"] as? String {
            pushRefreshubal = url
        } else if let data = payload["data"] as? [String: Any],
                  let url = data["url"] as? String {
            pushRefreshubal = url
        }
        
        if let link = pushRefreshubal {
            UserDefaults.standard.set(link, forKey: "temp_url")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadTempURL"),
                    object: nil,
                    userInfo: ["temp_url": link]
                )
            }
        }
    }
    
    func broadcastAttributionUpdate(data: [AnyHashable: Any]) {
        NotificationCenter.default.post(
            name: Notification.Name("ConversionDataReceived"),
            object: nil,
            userInfo: ["conversionData": data]
        )
    }
    
    func fireMergedTimer() {
        mergeTimer?.invalidate()
        mergeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.sendMergedDataTOSplash()
        }
    }
    
}

// MARK: - Models
class CookingModel: ObservableObject {
    @Published var selectedEggSize: EggSize = .medium
    @Published var eggTemperature: EggTemperature = .room
    @Published var cookingMethod: CookingMethod = .boiled
    @Published var doneness: Doneness = .soft
    @Published var timerSeconds: Int = 0
    @Published var isTimerRunning: Bool = false
    @Published var recipes: [Recipe] = defaultRecipes
    @Published var cookingHistory: [CookingRecord] = []
    @Published var errorMessage: String?
    @Published var chefTip: String = ""
    
    private var timerCancellable: AnyCancellable?
    
    func calculateCookingTime() -> Int {
        guard !isTimerRunning else { return timerSeconds }
        let baseTime: [CookingMethod: [Doneness: Int]] = [
            .boiled: [.soft: 240, .medium: 360, .hard: 600],
            .poached: [.soft: 180, .medium: 180, .hard: 180],
            .fried: [.soft: 120, .medium: 180, .hard: 240],
            .baked: [.soft: 900, .medium: 900, .hard: 900]
        ]
        let sizeMultiplier: [EggSize: Double] = [.small: 0.9, .medium: 1.0, .large: 1.1, .extraLarge: 1.2]
        let tempAdjustment: [EggTemperature: Int] = [.fridge: 30, .room: 0]
        
        let time = Double(baseTime[cookingMethod]?[doneness] ?? 360) * sizeMultiplier[selectedEggSize]! + Double(tempAdjustment[eggTemperature]!)
        return max(0, Int(time))
    }
    
    func startTimer() {
        guard timerSeconds > 0 else {
            errorMessage = "Please select a valid cooking time."
            return
        }
        isTimerRunning = true
        updateChefTip()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timerSeconds > 0 {
                    self.timerSeconds -= 1
                    if self.timerSeconds == 0 {
                        self.stopTimer()
                        self.addToHistory()
                        self.playNotificationSound()
                        self.errorMessage = "Your \(self.cookingMethod.rawValue.lowercased()) egg is ready!"
                        self.chefTip = "All done! Enjoy your egg! 🐣"
                    } else if self.timerSeconds % 60 == 0 {
                        self.updateChefTip()
                    }
                }
            }
    }
    
    func stopTimer() {
        isTimerRunning = false
        timerCancellable?.cancel()
        chefTip = ""
    }
    
    func addToHistory() {
        cookingHistory.append(CookingRecord(method: cookingMethod, doneness: doneness, size: selectedEggSize, time: timerSeconds))
        if cookingHistory.count > 10 { cookingHistory.removeFirst() }
    }
    
    func playNotificationSound() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func updateChefTip() {
        let tips = [
            "Just a bit more... Almost ready! 👨‍🍳",
            "Keep an eye on the timer! ⏰",
            "Perfect timing for delicious eggs! 🍳",
            "One more minute! Patience is key. 🐓"
        ]
        chefTip = tips.randomElement() ?? ""
    }
    
    @Published var journal: [JournalEntry] = []
    @Published var nutritionHistory: [NutritionData] = []
    
    // Сохранение в UserDefaults
    private let journalKey = "EggJournal"
    private let nutritionKey = "EggNutrition"
    
}

class SettingsModel: ObservableObject {
    @Published var timeUnit: TimeUnit = .minutes
    @Published var temperatureUnit: TemperatureUnit = .celsius
    @Published var theme: Theme = .light
    @Published var notificationSound: NotificationSound = .rooster
}

struct JournalEntry: Identifiable, Codable {
    let id = UUID()
    let method: CookingMethod
    let doneness: Doneness
    let size: EggSize
    let date: Date
    let photo: Data? // UIImage → Data
    let notes: String
    let rating: Int // 1–5
    let calories: Int
}

// Пара к яйцу
struct FoodPairing: Identifiable {
    let id = UUID()
    let title: String
    let calories: Int
    let prepTime: Int // минут
    let ingredients: [String]
}

// Сезонные рецепты
struct SeasonalRecipe: Identifiable {
    let id = UUID()
    let title: String
    let image: String
    let dateRange: ClosedRange<Date>
    let recipe: Recipe
}

// Советы
struct ProTip: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let details: String
    let icon: String
}

// Питание
struct NutritionData: Codable {
    let protein: Double // грамм
    let calories: Int
    let date: Date
}

// MARK: - Расширения CookingModel
extension CookingModel {
    
    
    func saveJournal() {
        if let data = try? JSONEncoder().encode(journal) {
            UserDefaults.standard.set(data, forKey: journalKey)
        }
    }
    
    func loadJournal() {
        if let data = UserDefaults.standard.data(forKey: journalKey),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            journal = decoded
        }
    }
    
    func saveNutrition() {
        if let data = try? JSONEncoder().encode(nutritionHistory) {
            UserDefaults.standard.set(data, forKey: nutritionKey)
        }
    }
    
    func loadNutrition() {
        if let data = UserDefaults.standard.data(forKey: nutritionKey),
           let decoded = try? JSONDecoder().decode([NutritionData].self, from: data) {
            nutritionHistory = decoded
        }
    }
    
    func addNutritionEntry(method: CookingMethod, doneness: Doneness) {
        let baseCalories = 78
        let extra = method == .fried ? 20 : 0
        let calories = baseCalories + extra
        let protein = 6.0
        
        let entry = NutritionData(protein: protein, calories: calories, date: Date())
        nutritionHistory.append(entry)
        if nutritionHistory.count > 30 { nutritionHistory.removeFirst() }
        saveNutrition()
    }
}

// MARK: - Enums
enum EggSize: String, CaseIterable, Identifiable, Codable {
    case small = "S", medium = "M", large = "L", extraLarge = "XL"
    var id: String { rawValue }
}

enum EggTemperature: String, CaseIterable, Identifiable {
    case fridge = "Fridge", room = "Room"
    var id: String { rawValue }
}

enum CookingMethod: String, CaseIterable, Identifiable, Codable {
    case boiled = "Boiled", poached = "Poached", fried = "Fried", baked = "Baked"
    var id: String { rawValue }
}

enum Doneness: String, CaseIterable, Identifiable, Codable {
    case soft = "Soft", medium = "Medium", hard = "Hard"
    var id: String { rawValue }
}

enum TimeUnit: String, CaseIterable, Identifiable {
    case minutes = "Minutes", seconds = "Seconds"
    var id: String { rawValue }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "°C", fahrenheit = "°F"
    var id: String { rawValue }
}

enum Theme: String, CaseIterable, Identifiable {
    case light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum NotificationSound: String, CaseIterable, Identifiable {
    case rooster = "Rooster", bell = "Bell", soft = "Soft"
    var id: String { rawValue }
}

struct Recipe: Identifiable {
    let id = UUID()
    let title: String
    let category: String
    let calories: Int
    let steps: [String]
    let image: String
    let tips: String
}

struct CookingRecord: Identifiable {
    let id = UUID()
    let method: CookingMethod
    let doneness: Doneness
    let size: EggSize
    let time: Int
    let date: Date = Date()
}

let defaultRecipes = [
    Recipe(title: "Classic Soft-Boiled Egg", category: "Breakfast", calories: 78, steps: ["Boil water", "Add egg", "Cook for 4 min"], image: "soft_boiled", tips: "Cool under cold water for easy peeling."),
    Recipe(title: "Perfect Poached Egg", category: "Diet", calories: 75, steps: ["Boil water", "Add vinegar", "Swirl water", "Cook for 3 min"], image: "poached", tips: "Use fresh eggs for a perfect shape."),
    Recipe(title: "Sunny Side Up Fried Egg", category: "Breakfast", calories: 90, steps: ["Heat oil", "Crack egg", "Cook for 2 min"], image: "fried", tips: "Low heat for runny yolk."),
    Recipe(title: "Baked Egg Souffle", category: "Festive", calories: 120, steps: ["Preheat oven", "Mix ingredients", "Bake for 15 min"], image: "baked", tips: "Don't open oven door early.")
]

let foodPairings: [CookingMethod: [FoodPairing]] = [
    .boiled: [
        FoodPairing(title: "Avocado Toast", calories: 180, prepTime: 5, ingredients: ["Bread", "Avocado", "Salt", "Pepper"]),
        FoodPairing(title: "Soldiers & Dip", calories: 90, prepTime: 3, ingredients: ["Toast", "Butter"]),
        FoodPairing(title: "Ramen Topping", calories: 50, prepTime: 1, ingredients: ["Noodles", "Broth"])
    ],
    .poached: [
        FoodPairing(title: "Arugula Salad", calories: 120, prepTime: 7, ingredients: ["Arugula", "Parmesan", "Olive Oil"]),
        FoodPairing(title: "Eggs Benedict", calories: 320, prepTime: 15, ingredients: ["Muffin", "Ham", "Hollandaise"]),
        FoodPairing(title: "Grain Bowl", calories: 210, prepTime: 10, ingredients: ["Quinoa", "Veggies"])
    ],
    .fried: [
        FoodPairing(title: "Burger Upgrade", calories: 280, prepTime: 5, ingredients: ["Bun", "Patty", "Cheese"]),
        FoodPairing(title: "Breakfast Sandwich", calories: 350, prepTime: 8, ingredients: ["Bacon", "Bread", "Cheese"]),
        FoodPairing(title: "Rice Bowl", calories: 180, prepTime: 6, ingredients: ["Rice", "Soy Sauce"])
    ],
    .baked: [
        FoodPairing(title: "Herb Salad", calories: 80, prepTime: 5, ingredients: ["Herbs", "Lemon"]),
        FoodPairing(title: "Crusty Bread", calories: 150, prepTime: 2, ingredients: ["Bread"]),
        FoodPairing(title: "Tomato Soup", calories: 110, prepTime: 10, ingredients: ["Tomato", "Cream"])
    ]
]

let proTips = [
    ProTip(title: "Why vinegar in poaching?", subtitle: "It helps the egg white set faster", details: "A splash of vinegar lowers the pH, causing proteins to coagulate quickly and form a tight, neat shape.", icon: "drop.fill"),
    ProTip(title: "How to peel a soft-boiled egg?", subtitle: "Cool it under cold water first", details: "Shock the egg in ice water for 30 seconds — the shell contracts and separates from the membrane.", icon: "hand.tap.fill"),
    ProTip(title: "Perfect yolk = 63°C", subtitle: "The magic temperature", details: "At 63°C, the yolk is silky and custard-like. Use a thermometer for precision!", icon: "thermometer")
]

func currentSeasonalRecipes() -> [SeasonalRecipe] {
    let calendar = Calendar.current
    let now = Date()
    
    let easter = calendar.date(from: DateComponents(month: 4, day: 5))!
    let halloween = calendar.date(from: DateComponents(month: 10, day: 31))!
    let christmas = calendar.date(from: DateComponents(month: 12, day: 25))!
    
    return [
        SeasonalRecipe(
            title: "Deviled Eggs for Halloween",
            image: "devil_egg",
            dateRange: halloween...halloween,
            recipe: Recipe(title: "Deviled Eggs", category: "Halloween", calories: 95, steps: ["Boil", "Halve", "Mix yolk with mayo", "Pipe back"], image: "devil_egg", tips: "Add black food coloring for spooky effect!")
        ),
        SeasonalRecipe(
            title: "Easter Egg Nest",
            image: "easter_nest",
            dateRange: easter...calendar.date(byAdding: .day, value: 7, to: easter)!,
            recipe: Recipe(title: "Easter Egg Nest", category: "Easter", calories: 180, steps: ["Bake pastry", "Fill with custard", "Top with mini eggs"], image: "easter_nest", tips: "Use pastel colors!")
        ),
        SeasonalRecipe(
            title: "Christmas Eggnog Soufflé",
            image: "eggnog_souffle",
            dateRange: christmas...christmas,
            recipe: Recipe(title: "Eggnog Soufflé", category: "Christmas", calories: 220, steps: ["Mix eggnog", "Fold whites", "Bake 25 min"], image: "eggnog_souffle", tips: "Don’t open the oven!")
        )
    ].filter { $0.dateRange.contains(now) }
}

extension Color {
    static let backgroundLight = Color(hex: "#FFE8B6")
    static let backgroundLightSecondary = Color(hex: "#FFF8E1")
    static let accentOrange = Color(hex: "#FF8C00")
    static let accentWhite = Color(hex: "#FFFFFF")
    static let accentGold = Color(hex: "#FFD700")
    static let shellBrown = Color(hex: "#8B5A2B")
    static let accentBlue = Color(hex: "#87CEEB")
    static let darkBackground = Color(hex: "#1C2526")
    static let darkAccent = Color(hex: "#2E3B3E")
    static let glowOrange = Color(hex: "#FF8C00").opacity(0.7)
    static let glowGold = Color(hex: "#FFD700").opacity(0.5)
    
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - View Extensions
extension View {
    func premiumGlow(color: Color = Color.glowOrange, radius: CGFloat = 12) -> some View {
        self
            .shadow(color: color.opacity(0.8), radius: radius / 3, x: 0, y: 0)
            .shadow(color: color.opacity(0.6), radius: radius / 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
    }
    
    func premiumCardStyle(theme: Theme) -> some View {
        self
            .padding(20)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: theme == .light ? [Color.accentWhite, Color.backgroundLightSecondary.opacity(0.9)] : [Color.darkAccent, Color.darkBackground.opacity(0.9)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(30)
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(LinearGradient(gradient: Gradient(colors: [Color.accentGold, Color.accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(theme == .light ? 0.15 : 0.3), radius: 15, x: 0, y: 8)
            .premiumGlow(color: theme == .light ? Color.glowGold : Color.glowOrange)
    }
    
    func premiumButtonStyle() -> some View {
        self
            .padding(18)
            .background(
                LinearGradient(gradient: Gradient(colors: [Color.accentOrange, Color.accentGold]), startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundColor(Color.accentWhite)
            .cornerRadius(25)
            .shadow(color: Color.accentOrange.opacity(0.7), radius: 12, x: 0, y: 6)
            .premiumGlow()
    }
}

// MARK: - Background View
struct BackgroundView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                gradient: Gradient(colors: settingsModel.theme == .light ? [Color.backgroundLight, Color.backgroundLightSecondary.opacity(0.8)] : [Color.darkBackground, Color.darkAccent.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            .overlay(
                ParticleView(frameSize: geo.size)
                    .blendMode(.softLight)
            )
        }
    }
}

// MARK: - Particle View
struct ParticleView: View {
    let frameSize: CGSize
    @State private var particles: [Particle] = []
    
    var body: some View {
        ForEach(particles) { particle in
            Circle()
                .foregroundColor(particle.color)
                .frame(width: particle.size, height: particle.size)
                .offset(x: particle.x, y: particle.y)
                .opacity(particle.opacity)
                .blur(radius: particle.blur)
                .animation(.easeInOut(duration: particle.duration).repeatForever(autoreverses: true), value: particle.y)
        }
        .onAppear {
            for _ in 0..<15 {
                particles.append(Particle(frameSize: frameSize))
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let opacity: Double
    let blur: CGFloat
    let duration: Double
    
    init(frameSize: CGSize) {
        x = CGFloat.random(in: 0...frameSize.width)
        y = CGFloat.random(in: 0...frameSize.height)
        size = CGFloat.random(in: 4...12)
        color = [Color.accentGold, Color.accentOrange, Color.accentBlue].randomElement()!.opacity(0.4)
        opacity = Double.random(in: 0.3...0.6)
        blur = CGFloat.random(in: 1.5...3.5)
        duration = Double.random(in: 3...7)
    }
}

// MARK: - Main View
struct MainView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            BackgroundView()
            TabView(selection: $selectedTab) {
                DashboardView().tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }.tag(0)
                CookingModesView().tabItem {
                    Image(systemName: "frying.pan.fill")
                    Text("Modes")
                }.tag(1)
                TimerView().tabItem {
                    Image(systemName: "timer")
                    Text("Timer")
                }.tag(2)
                RecipesView().tabItem {
                    Image(systemName: "book.fill")
                    Text("Recipes")
                }.tag(3)
                JournalView().tabItem {  // НОВАЯ ВКЛАДКА
                    Image(systemName: "book.closed.fill")
                    Text("Journal")
                }.tag(4)
            }
            .accentColor(Color.accentOrange)
            .font(.custom("Quicksand-Bold", size: 16))
            .onChange(of: selectedTab) { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .preferredColorScheme(settingsModel.theme == .light ? .light : .dark)
    }
}

struct ProTipsCarousel: View {
    @State private var currentIndex = 0
    let tips = proTips
    
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(tips.indices, id: \.self) { i in
                let tip = tips[i]
                VStack(spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(.system(size: 32))
                        .foregroundColor(.accentOrange)
                    Text(tip.title)
                        .font(.custom("Quicksand-SemiBold", size: 20))
                    Text(tip.subtitle)
                        .font(.custom("Quicksand-Regular", size: 16))
                        .foregroundColor(.shellBrown.opacity(0.8))
                    Button("Learn More") {
                        // Показать модалку
                    }
                    .font(.custom("Quicksand-Medium", size: 14))
                    .foregroundColor(.accentBlue)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentWhite.opacity(0.9))
                .cornerRadius(20)
                .padding(.horizontal)
                .tag(i)
            }
        }
        .tabViewStyle(PageTabViewStyle())
        .frame(height: 180)
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var scaleEffect: CGFloat = 1.0
    @State private var viewOpacity: Double = 0
    
    var body: some View {
        ZStack {
            BackgroundView()
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Welcome to EggCook Studio!")
                            .font(.custom("Quicksand-Bold", size: 34))
                            .foregroundColor(Color.shellBrown)
                            .padding(.top)
                            .premiumGlow(color: Color.glowGold, radius: 8)
                            .accessibilityLabel("Welcome to Egg Cook Studio")
                        
                        // Grid Section: Poached, Fried, Baked
                        GeometryReader { geo in
                            VStack {
                                HStack(spacing: 10) {
                                    ForEach([CookingMethod.poached, .fried, .baked]) { method in
                                        NavigationLink(destination: CookingDetailView(method: method)) {
                                            CookingCardView(method: method, isFullWidth: false, width: (geo.size.width - 40) / 3)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .frame(height: 180)
                        
                        // Hero Section: Egg of the Day
                        let randomRecipe = cookingModel.recipes.randomElement() ?? defaultRecipes[0]
                        VStack(spacing: 14) {
                            Text("Egg of the Day")
                                .font(.custom("Quicksand-SemiBold", size: 26))
                                .foregroundColor(Color.shellBrown)
                            Image(randomRecipe.image)
                                .resizable()
                                .frame(height: 240)
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 30))
                                .overlay(RoundedRectangle(cornerRadius: 30).stroke(LinearGradient(gradient: Gradient(colors: [Color.accentGold, Color.accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
                                .premiumGlow()
                                .accessibilityLabel(randomRecipe.title)
                            Text(randomRecipe.title)
                                .font(.custom("Quicksand-Medium", size: 22))
                                .foregroundColor(Color.accentOrange)
                            Text("Calories: \(randomRecipe.calories) kcal")
                                .font(.custom("Quicksand-Regular", size: 18))
                                .foregroundColor(Color.shellBrown)
                        }
                        .premiumCardStyle(theme: settingsModel.theme)
                        .padding(.horizontal)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.55, blendDuration: 0.1)) {
                                scaleEffect = 0.9
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    scaleEffect = 1.0
                                }
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }) {
                            Text("Start Cooking")
                                .font(.custom("Quicksand-Bold", size: 22))
                                .premiumButtonStyle()
                        }
                        .scaleEffect(scaleEffect)
                        .padding(.horizontal)
                        .accessibilityLabel("Start Cooking Button")
                    }
                    .padding(.vertical)
                    .opacity(viewOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.5)) {
                            viewOpacity = 1.0
                        }
                    }
                }
                .navigationTitle("EggCook Studio")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(cookingModel)
                }
            }
        }
    }
    
    @State var showSettings = false
    
}

struct JournalView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @State private var showingCamera = false
    @State private var selectedEntry: JournalEntry?
    @State private var filterMethod: CookingMethod = .boiled
    @State private var filterSize: EggSize = .medium
    
    var filteredEntries: [JournalEntry] {
        cookingModel.journal.filter { entry in
            (entry.method == filterMethod || filterMethod == .boiled) &&
            (entry.size == filterSize || filterSize == .medium)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            BackgroundView()
            NavigationView {
                VStack {
                    HStack {
                        Picker("Method", selection: $filterMethod) {
                            Text("All").tag(CookingMethod.boiled)
                            ForEach(CookingMethod.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        Picker("Size", selection: $filterSize) {
                            Text("All").tag(EggSize.medium)
                            ForEach(EggSize.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .padding(.horizontal)
                    
                    if filteredEntries.isEmpty {
                        Spacer()
                        Text("No eggs yet. Cook your first!")
                            .font(.custom("Quicksand-Regular", size: 18))
                            .foregroundColor(.shellBrown.opacity(0.7))
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredEntries) { entry in
                                JournalCard(entry: entry)
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                .navigationTitle("Egg Journal")
                .toolbar {
                    Button(action: { showingCamera = true }) {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.accentOrange)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                if let img = image {
                    let data = img.jpegData(compressionQuality: 0.8)
                    let entry = JournalEntry(
                        method: cookingModel.cookingMethod,
                        doneness: cookingModel.doneness,
                        size: cookingModel.selectedEggSize,
                        date: Date(),
                        photo: data,
                        notes: "",
                        rating: 5,
                        calories: 78 + (cookingModel.cookingMethod == .fried ? 20 : 0)
                    )
                    cookingModel.journal.append(entry)
                    cookingModel.saveJournal()
                    cookingModel.addNutritionEntry(method: cookingModel.cookingMethod, doneness: cookingModel.doneness)
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            JournalDetailView(entry: entry)
        }
        .onAppear {
            cookingModel.loadJournal()
            cookingModel.loadNutrition()
        }
    }
}

struct JournalCard: View {
    let entry: JournalEntry
    var body: some View {
        HStack {
            if let data = entry.photo, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "egg.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentOrange)
                    .background(Color.backgroundLightSecondary.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            VStack(alignment: .leading) {
                Text("\(entry.method.rawValue) • \(entry.doneness.rawValue)")
                    .font(.custom("Quicksand-SemiBold", size: 18))
                Text(entry.date, style: .relative)
                    .font(.custom("Quicksand-Regular", size: 14))
                    .foregroundColor(.shellBrown.opacity(0.7))
                HStack {
                    ForEach(0..<entry.rating, id: \.self) { _ in
                        Image(systemName: "star.fill").foregroundColor(.accentGold)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.accentWhite.opacity(0.9))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentGold.opacity(0.5), lineWidth: 1))
    }
}

struct CameraView: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            completion(image)
            picker.dismiss(animated: true)
        }
    }
}


struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var notes: String
    @State private var rating: Int
    
    init(entry: JournalEntry) {
        self.entry = entry
        _notes = State(initialValue: entry.notes)
        _rating = State(initialValue: entry.rating)
    }
    
    var body: some View {
        ZStack {
            BackgroundView()
            ScrollView {
                VStack(spacing: 20) {
                    if let data = entry.photo, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    
                    Text("\(entry.method.rawValue) Egg")
                        .font(.custom("Quicksand-Bold", size: 28))
                    
                    HStack {
                        Text("Size: \(entry.size.rawValue)")
                        Text("•")
                        Text("Calories: \(entry.calories)")
                    }
                    .foregroundColor(.shellBrown.opacity(0.8))
                    
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundColor(star <= rating ? .accentGold : .gray)
                                .onTapGesture { rating = star }
                        }
                    }
                    
                    TextField("Add notes...", text: $notes)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button("Save") {
                        // Сохранение в модель
                    }
                    .premiumButtonStyle()
                }
                .padding()
            }
        }
        .navigationTitle("Journal Entry")
    }
}

struct CookingCardView: View {
    let method: CookingMethod
    let isFullWidth: Bool
    let width: CGFloat?
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var isHovered = false
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        VStack {
            Image(method.rawValue.lowercased())
                .resizable()
                .frame(height: isFullWidth ? 200 : 100)
                .scaledToFit()
                .foregroundColor(Color.accentOrange)
                .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(scale)
                .cornerRadius(12)
                .animation(.easeInOut(duration: 0.6), value: rotation)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: scale)
            Text(method.rawValue)
                .font(.custom("Quicksand-SemiBold", size: isFullWidth ? 24 : 18))
                .foregroundColor(Color.shellBrown)
        }
        .frame(maxWidth: isFullWidth ? .infinity : width)
        .premiumCardStyle(theme: settingsModel.theme)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            rotation = hovering ? 10 : 0
            scale = hovering ? 1.05 : 1.0
        }
        .accessibilityLabel("\(method.rawValue) cooking method")
    }
}

// MARK: - Cooking Modes View
struct CookingModesView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var viewOpacity: Double = 0
    
    var body: some View {
        ZStack {
            BackgroundView()
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(CookingMethod.allCases) { method in
                            NavigationLink(destination: CookingDetailView(method: method)) {
                                CookingCardView(method: method, isFullWidth: true, width: nil)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                    .opacity(viewOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.5)) {
                            viewOpacity = 1.0
                        }
                    }
                }
                .navigationTitle("Cooking Modes")
                .accentColor(Color.accentOrange)
            }
        }
    }
}

struct CookingDetailView: View {
    let method: CookingMethod
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var showTimer = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var viewOpacity: Double = 0
    
    var body: some View {
        ZStack {
            BackgroundView()
            ScrollView {
                VStack(spacing: 28) {
                    Text(method.rawValue)
                        .font(.custom("Quicksand-Bold", size: 34))
                        .foregroundColor(Color.shellBrown)
                        .premiumGlow(color: Color.glowGold, radius: 8)
                    
                    if method == .boiled {
                        BoiledEggView()
                    } else if method == .poached {
                        PoachedEggView()
                    } else if method == .fried {
                        FriedEggView()
                    } else if method == .baked {
                        BakedEggView()
                    }
                    
                    if let error = cookingModel.errorMessage {
                        Text(error)
                            .foregroundColor(Color.red)
                            .font(.custom("Quicksand-Regular", size: 18))
                            .padding()
                    }
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                            buttonScale = 0.9
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                buttonScale = 1.0
                            }
                        }
                        cookingModel.timerSeconds = cookingModel.calculateCookingTime()
                        showTimer = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        Text("Start \(method.rawValue) Cooking")
                            .font(.custom("Quicksand-Bold", size: 22))
                            .premiumButtonStyle()
                    }
                    .scaleEffect(buttonScale)
                    .padding(.horizontal)
                    .accessibilityLabel("Start \(method.rawValue) cooking button")
                }
                .padding(.vertical)
                .opacity(viewOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.5)) {
                        viewOpacity = 1.0
                    }
                }
            }
        }
        .sheet(isPresented: $showTimer) {
            TimerView()
        }
    }
}

struct BoiledEggView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Doneness")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            Picker("Doneness", selection: $cookingModel.doneness) {
                ForEach(Doneness.allCases) { doneness in
                    Text(doneness.rawValue).tag(doneness)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .accentColor(Color.accentOrange)
            
            Text("Egg Size")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            Picker("Size", selection: $cookingModel.selectedEggSize) {
                ForEach(EggSize.allCases) { size in
                    Text(size.rawValue).tag(size)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .accentColor(Color.accentOrange)
            
            Text("Egg Temperature")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            Picker("Temperature", selection: $cookingModel.eggTemperature) {
                ForEach(EggTemperature.allCases) { temp in
                    Text(temp.rawValue).tag(temp)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .accentColor(Color.accentOrange)
        }
        .premiumCardStyle(theme: settingsModel.theme)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

struct PoachedEggView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var bubbleOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Poached Egg Instructions")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            ForEach(["Boil water", "Add vinegar", "Swirl water", "Gently add egg"], id: \.self) { step in
                Text(step)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .foregroundColor(Color.shellBrown)
            }
            ZStack {
                ForEach(0..<10) { i in
                    Circle()
                        .frame(width: CGFloat.random(in: 8...25), height: CGFloat.random(in: 8...25))
                        .foregroundColor(Color.accentBlue.opacity(0.7))
                        .offset(x: CGFloat.random(in: -30...30), y: -bubbleOffset + CGFloat(i * 30))
                        .animation(.easeInOut(duration: 3).delay(Double(i)*0.15).repeatForever(autoreverses: false), value: bubbleOffset)
                        .blur(radius: 1.5)
                }
            }
            .frame(height: 140)
            .onAppear {
                bubbleOffset = 140
            }
        }
        .premiumCardStyle(theme: settingsModel.theme)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

struct FriedEggView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Doneness")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            Picker("Doneness", selection: $cookingModel.doneness) {
                ForEach(Doneness.allCases) { doneness in
                    Text(doneness.rawValue).tag(doneness)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .accentColor(Color.accentOrange)
            
            Text("Oil Type")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            Picker("Oil", selection: .constant("Butter")) {
                Text("Butter").tag("Butter")
                Text("Sunflower").tag("Sunflower")
                Text("Olive").tag("Olive")
            }
            .pickerStyle(SegmentedPickerStyle())
            .accentColor(Color.accentOrange)
            
            Text("Tip: Don’t overcook the white to keep it soft!")
                .font(.custom("Quicksand-Regular", size: 18))
                .foregroundColor(Color.shellBrown)
                .italic()
        }
        .premiumCardStyle(theme: settingsModel.theme)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

struct BakedEggView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Baked Egg Options")
                .font(.custom("Quicksand-SemiBold", size: 22))
                .foregroundColor(Color.shellBrown)
            ForEach(["Egg in Bun", "Soufflé", "Mini Casserole"], id: \.self) { option in
                Text(option)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .foregroundColor(Color.shellBrown)
            }
        }
        .premiumCardStyle(theme: settingsModel.theme)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Timer View
struct TimerView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var progress: CGFloat = 0
    @State private var scaleEffect: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var glowIntensity: Double = 0.5
    @State private var viewOpacity: Double = 0
    
    var body: some View {
        ZStack {
            BackgroundView()
            VStack(spacing: 28) {
                Text("Smart Timer")
                    .font(.custom("Quicksand-Bold", size: 34))
                    .foregroundColor(Color.shellBrown)
                    .premiumGlow(color: Color.glowGold, radius: 8)
                
                ZStack {
                    Circle()
                        .frame(width: 260, height: 260)
                        .foregroundColor(Color.accentWhite.opacity(0.85))
                        .overlay(Circle().stroke(LinearGradient(gradient: Gradient(colors: [Color.accentGold, Color.accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 6))
                        .premiumGlow(color: Color.glowOrange.opacity(glowIntensity))
                        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 8)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(LinearGradient(gradient: Gradient(colors: [Color.accentOrange, Color.accentGold]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 12)
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                        .premiumGlow()
                    
                    Image(systemName: "egg.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 130, height: 130)
                        .foregroundColor(Color.accentGold)
                        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                        .scaleEffect(cookingModel.isTimerRunning ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: cookingModel.isTimerRunning)
                }
                .onChange(of: cookingModel.isTimerRunning) { running in
                    if running {
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                            rotation += 360
                            glowIntensity = 1.0
                        }
                    } else {
                        glowIntensity = 0.5
                    }
                }
                
                Text(formattedTime)
                    .font(.custom("Quicksand-Bold", size: 40))
                    .foregroundColor(Color.shellBrown)
                    .premiumGlow(color: Color.glowOrange.opacity(0.3), radius: 5)
                    .accessibilityLabel("Timer: \(formattedTime)")
                
                if !cookingModel.chefTip.isEmpty {
                    Text(cookingModel.chefTip)
                        .font(.custom("Quicksand-Italic", size: 20))
                        .foregroundColor(Color.accentBlue)
                        .padding(12)
                        .background(Color.accentWhite.opacity(0.7))
                        .cornerRadius(20)
                        .premiumGlow(color: Color.accentBlue.opacity(0.5), radius: 10)
                        .transition(.opacity.combined(with: .scale))
                }
                
                HStack(spacing: 28) {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                            scaleEffect = 0.9
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                scaleEffect = 1.0
                            }
                        }
                        if cookingModel.isTimerRunning {
                            cookingModel.stopTimer()
                        } else {
                            cookingModel.startTimer()
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        Text(cookingModel.isTimerRunning ? "Pause" : "Start")
                            .font(.custom("Quicksand-Bold", size: 22))
                            .premiumButtonStyle()
                    }
                    .scaleEffect(scaleEffect)
                    
                    Button(action: {
                        cookingModel.timerSeconds += 60
                        cookingModel.errorMessage = nil
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        Text("Add Egg")
                            .font(.custom("Quicksand-Bold", size: 22))
                            .premiumButtonStyle()
                    }
                }
                .padding(.horizontal)
                
                if let error = cookingModel.errorMessage {
                    Text(error)
                        .font(.custom("Quicksand-Regular", size: 18))
                        .foregroundColor(Color.red)
                        .padding()
                }
            }
            .padding(.vertical)
            .opacity(viewOpacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) {
                    viewOpacity = 1.0
                }
            }
        }
    }
    
    var formattedTime: String {
        let minutes = cookingModel.timerSeconds / 60
        let seconds = cookingModel.timerSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recipes View
struct RecipesView: View {
    @EnvironmentObject var cookingModel: CookingModel
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var viewOpacity: Double = 0
    
    let seasonal = currentSeasonalRecipes()
    
    var body: some View {
        ZStack {
            BackgroundView()
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Recipes")
                            .font(.custom("Quicksand-Bold", size: 34))
                            .foregroundColor(Color.shellBrown)
                            .padding(.top)
                            .premiumGlow(color: Color.glowGold, radius: 8)
                        
                        // === Seasonal Banner ===
                        if !seasonal.isEmpty {
                            ForEach(seasonal) { s in
                                NavigationLink(destination: RecipeDetailView(recipe: s.recipe).environmentObject(cookingModel)) {
                                    HStack {
                                        Image(s.image)
                                            .resizable()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        VStack(alignment: .leading) {
                                            Text(s.title)
                                                .font(.custom("Quicksand-SemiBold", size: 20))
                                            Text("Seasonal Special")
                                                .font(.custom("Quicksand-Regular", size: 14))
                                                .foregroundColor(.accentOrange)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding()
                                    .background(LinearGradient(gradient: Gradient(colors: [.accentGold, .accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        ForEach(cookingModel.recipes) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)
                                .environmentObject(cookingModel)) {
                                RecipeCardView(recipe: recipe)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                    .opacity(viewOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.5)) {
                            viewOpacity = 1.0
                        }
                    }
                }
                .navigationTitle("Recipes")
                .accentColor(Color.accentOrange)
            }
        }
    }
}

struct RecipeCardView: View {
    let recipe: Recipe
    @EnvironmentObject var settingsModel: SettingsModel
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Image(recipe.image)
                .resizable()
                .frame(width: 100, height: 100)
                .scaledToFit()
                .foregroundColor(Color.accentOrange)
                .clipShape(Circle())
                .overlay(Circle().stroke(LinearGradient(gradient: Gradient(colors: [Color.accentGold, Color.accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                .premiumGlow()
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.custom("Quicksand-Medium", size: 22))
                    .foregroundColor(Color.shellBrown)
                Text("Calories: \(recipe.calories) kcal")
                    .font(.custom("Quicksand-Regular", size: 18))
                    .foregroundColor(Color.shellBrown)
            }
            Spacer()
        }
        .premiumCardStyle(theme: settingsModel.theme)
        .padding(.horizontal)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.title), \(recipe.calories) calories")
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject var settingsModel: SettingsModel
    @EnvironmentObject var cookingModel: CookingModel
    @State private var stepOpacity: Double = 0
    @State private var imageScale: CGFloat = 1.0
    @State private var viewOpacity: Double = 0
    
    var pairings: [FoodPairing] {
        foodPairings[cookingModel.cookingMethod] ?? []
    }
    
    var body: some View {
        ZStack {
            BackgroundView()
            ScrollView {
                VStack(spacing: 28) {
                    Image(recipe.image)
                        .resizable()
                        .frame(height: 260)
                        .scaledToFit()
                        .foregroundColor(Color.accentOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                        .overlay(RoundedRectangle(cornerRadius: 30).stroke(LinearGradient(gradient: Gradient(colors: [Color.accentGold, Color.accentOrange]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 4))
                        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 8)
                        .premiumGlow()
                        .scaleEffect(imageScale)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: imageScale)
                        .onAppear {
                            imageScale = 1.05
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation {
                                    imageScale = 1.0
                                }
                            }
                        }
                        .accessibilityLabel("\(recipe.title) image")
                    Text(recipe.title)
                        .font(.custom("Quicksand-Bold", size: 30))
                        .foregroundColor(Color.shellBrown)
                    Text("Calories: \(recipe.calories) kcal")
                        .font(.custom("Quicksand-Regular", size: 20))
                        .foregroundColor(Color.shellBrown)
                    ForEach(recipe.steps, id: \.self) { step in
                        Text(step)
                            .font(.custom("Quicksand-Regular", size: 20))
                            .foregroundColor(Color.shellBrown)
                            .padding(.vertical, 10)
                            .opacity(stepOpacity)
                            .onAppear {
                                withAnimation(.easeIn(duration: 0.6).delay(0.2)) {
                                    stepOpacity = 1.0
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Perfect with")
                            .font(.custom("Quicksand-SemiBold", size: 24))
                            .foregroundColor(.shellBrown)
                        
                        ForEach(pairings) { pairing in
                            HStack {
                                Image(systemName: "fork.knife")
                                    .foregroundColor(.accentOrange)
                                VStack(alignment: .leading) {
                                    Text(pairing.title)
                                        .font(.custom("Quicksand-Medium", size: 18))
                                    Text("\(pairing.calories) kcal • \(pairing.prepTime) min")
                                        .font(.custom("Quicksand-Regular", size: 14))
                                        .foregroundColor(.shellBrown.opacity(0.7))
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.accentWhite.opacity(0.7))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    
                    Text(recipe.tips)
                        .font(.custom("Quicksand-Regular", size: 18))
                        .foregroundColor(Color.shellBrown)
                        .italic()
                        .padding(12)
                        .background(Color.accentBlue.opacity(0.25))
                        .cornerRadius(20)
                        .premiumGlow(color: Color.accentBlue.opacity(0.4), radius: 8)
                }
                .padding(.vertical)
                .opacity(viewOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.5)) {
                        viewOpacity = 1.0
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .accentColor(Color.accentOrange)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var settingsModel: SettingsModel
    @EnvironmentObject var cookingModel: CookingModel
    @State private var viewOpacity: Double = 0
    
    var todayCalories: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return cookingModel.nutritionHistory
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }
    }
    
    var todayProtein: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return cookingModel.nutritionHistory
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.protein }
    }
    
    var body: some View {
        ZStack {
            BackgroundView()
            NavigationView {
                Form {
                    Section(header: Text("Units").font(.custom("Quicksand-SemiBold", size: 22)).foregroundColor(Color.shellBrown)) {
                        Picker("Time Unit", selection: $settingsModel.timeUnit) {
                            ForEach(TimeUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        Picker("Temperature Unit", selection: $settingsModel.temperatureUnit) {
                            ForEach(TemperatureUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                    }
                    Section(header: Text("Appearance").font(.custom("Quicksand-SemiBold", size: 22)).foregroundColor(Color.shellBrown)) {
                        Picker("Theme", selection: $settingsModel.theme) {
                            ForEach(Theme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                    }
                    Section(header: Text("Notifications").font(.custom("Quicksand-SemiBold", size: 22)).foregroundColor(Color.shellBrown)) {
                        Picker("Sound", selection: $settingsModel.notificationSound) {
                            ForEach(NotificationSound.allCases) { sound in
                                Text(sound.rawValue).tag(sound)
                            }
                        }
                    }
                    Section(header: Text("Cooking History").font(.custom("Quicksand-SemiBold", size: 22)).foregroundColor(Color.shellBrown)) {
                        Text("Last 10 dishes")
                            .font(.custom("Quicksand-Regular", size: 20))
                            .foregroundColor(Color.shellBrown)
                    }
                    Section(header: Text("Nutrition Today").font(.custom("Quicksand-SemiBold", size: 22))) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.accentOrange)
                            Text("\(todayCalories) kcal")
                            Spacer()
                            Text("\(String(format: "%.1f", todayProtein))g protein")
                                .foregroundColor(.accentBlue)
                        }
                    }
                    Section(header: Text("Privacy").font(.custom("Quicksand-SemiBold", size: 22))) {
                        Button {
                            UIApplication.shared.open(URL(string: "https://cookstudiio.com/privacy-policy.html")!)
                        } label: {
                            HStack {
                                Text("Privacy policy")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
                .accentColor(Color.accentOrange)
                .opacity(viewOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.5)) {
                        viewOpacity = 1.0
                    }
                }
            }
        }
    }
}

//struct MainView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainView()
//            .environmentObject(CookingModel())
//            .environmentObject(SettingsModel())
//            .previewDevice("iPhone 12")
//    }
//}


final class LaunchDirector: ObservableObject {
    
    @Published var currentStage: LaunchStage = .booting
    @Published var resolvedDestination: URL?
    @Published var displayPushRequest = false
    
    private var conversionData: [AnyHashable: Any] = [:]
    private var cachedDeeplinks: [AnyHashable: Any] = [:]
    private var bag = Set<AnyCancellable>()
    private lazy var connectivityWatcher = NWPathMonitor()
    
    private var neverLaunchedBefore: Bool {
        !UserDefaults.standard.bool(forKey: "hasEverRunBefore")
    }
    
    enum LaunchStage {
        case booting
        case webExperience
        case classicFlow
        case offlineScreen
    }
    
    init() {
        setupAttributionListeners()
        beginConnectivityTracking()
    }
    
    deinit {
        connectivityWatcher.cancel()
    }
    
    private func setupAttributionListeners() {
        NotificationCenter.default.publisher(for: Notification.Name("ConversionDataReceived"))
            .compactMap { $0.userInfo?["conversionData"] as? [AnyHashable: Any] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.conversionData = data
                self?.evaluateNextStep()
            }
            .store(in: &bag)
        
        NotificationCenter.default.publisher(for: Notification.Name("deeplink_values"))
            .compactMap { $0.userInfo?["deeplinksData"] as? [AnyHashable: Any] }
            .sink { [weak self] dict in
                self?.cachedDeeplinks = dict
            }
            .store(in: &bag)
    }
    
    @objc private func evaluateNextStep() {
        guard !conversionData.isEmpty else {
            resolveFromCacheOrFallback()
            return
        }
        
        if UserDefaults.standard.string(forKey: "app_mode") == "Funtik" {
            enterClassicMode()
            return
        }
        
        if neverLaunchedBefore,
           conversionData["af_status"] as? String == "Organic" {
            triggerOrganicValidationFlow()
            return
        }
        
        if let tempRaw = UserDefaults.standard.string(forKey: "temp_url"),
           let url = URL(string: tempRaw), !tempRaw.isEmpty {
            resolvedDestination = url
            transition(to: .webExperience)
            return
        }
        
        if resolvedDestination == nil {
            if !UserDefaults.standard.bool(forKey: "accepted_notifications") && !UserDefaults.standard.bool(forKey: "system_close_notifications") {
                needsPushPermissionPrompt()
            } else {
                fetchServerSideConfig()
            }
        }
    }
    
    private func beginConnectivityTracking() {
        connectivityWatcher.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status != .satisfied {
                    self?.reactToNetworkDrop()
                }
            }
        }
        connectivityWatcher.start(queue: DispatchQueue.global(qos: .background))
    }
    
    private func reactToNetworkDrop() {
        let currentMode = UserDefaults.standard.string(forKey: "app_mode") ?? ""
        if currentMode == "HenView" {
            transition(to: .offlineScreen)
        } else {
            enterClassicMode()
        }
    }
    
    private func triggerOrganicValidationFlow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            Task { await self.performOrganicValidation() }
        }
    }
    
    private func performOrganicValidation() async {
        let validator = OrganicValidator()
            .setAppID(CookStudioConfig.afAppID)
            .setDevKey(CookStudioConfig.afDevKey)
            .setDeviceID(AppsFlyerLib.shared().getAppsFlyerUID())
        
        guard let requestURL = validator.buildRequestURL() else {
            enterClassicMode()
            return
        }
        
        do {
            let (data, resp) = try await URLSession.shared.data(from: requestURL)
            try await handleOrganicValidationResult(data: data, response: resp)
        } catch {
            enterClassicMode()
        }
    }
    
    private func handleOrganicValidationResult(data: Data, response: URLResponse) async throws {
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            enterClassicMode()
            return
        }
        
        var mergedPayload: [AnyHashable: Any] = json
        for (key, value) in cachedDeeplinks where mergedPayload[key] == nil {
            mergedPayload[key] = value
        }
        
        await MainActor.run {
            conversionData = mergedPayload
            fetchServerSideConfig()
        }
    }
    
    private func fetchServerSideConfig() {
        guard let configURL = URL(string: "https://cookstudiio.com/config.php") else {
            resolveFromCacheOrFallback()
            return
        }
        
        var payload = conversionData
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["os"] = "iOS"
        payload["store_id"] = "id\(CookStudioConfig.afAppID)"
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["bundle_id"] = "com.hsstuinhappchick.CookStudio"
        payload["locale"] = Locale.current.languageCode?.uppercased() ?? "EN"
        payload["push_token"] = UserDefaults.standard.string(forKey: "fcm_token") ?? Messaging.messaging().fcmToken
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            resolveFromCacheOrFallback()
            return
        }
        
        var request = URLRequest(url: configURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if error != nil || data == nil {
                self?.resolveFromCacheOrFallback()
                return
            }
            
            guard
                let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any],
                let success = json["ok"] as? Bool, success,
                let urlStr = json["url"] as? String,
                let expires = json["expires"] as? TimeInterval
            else {
                self?.resolveFromCacheOrFallback()
                return
            }
            
            DispatchQueue.main.async {
                self?.persistSuccessfulConfig(url: urlStr, expires: expires)
                self?.resolvedDestination = URL(string: urlStr)
                self?.transition(to: .webExperience)
            }
        }.resume()
    }
    
    private func persistSuccessfulConfig(url: String, expires: TimeInterval) {
        UserDefaults.standard.set(url, forKey: "saved_trail")
        UserDefaults.standard.set(expires, forKey: "saved_expires")
        UserDefaults.standard.set("HenView", forKey: "app_mode")
        UserDefaults.standard.set(true, forKey: "hasEverRunBefore")
    }
    
    private func resolveFromCacheOrFallback() {
        if let saved = UserDefaults.standard.string(forKey: "saved_trail"),
           let url = URL(string: saved) {
            if currentStage == .offlineScreen {
                currentStage = .offlineScreen
            } else {
                resolvedDestination = url
                transition(to: .webExperience)
            }
        } else {
            enterClassicMode()
        }
    }
    
    private func enterClassicMode() {
        UserDefaults.standard.set("Funtik", forKey: "app_mode")
        UserDefaults.standard.set(true, forKey: "hasEverRunBefore")
        transition(to: .classicFlow)
    }
    
    private func needsPushPermissionPrompt() {
        if let lastCheck = UserDefaults.standard.value(forKey: "last_notification_ask") as? Date,
           Date().timeIntervalSince(lastCheck) < 259200 {
            fetchServerSideConfig()
            return
        }
        displayPushRequest = true
    }
    
    func userDeclinedPush() {
        UserDefaults.standard.set(Date(), forKey: "last_notification_ask")
        displayPushRequest = false
        fetchServerSideConfig()
    }
    
    func userAcceptedPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(granted, forKey: "accepted_notifications")
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                else { UserDefaults.standard.set(true, forKey: "system_close_notifications") }
                
                self?.displayPushRequest = false
                self?.fetchServerSideConfig()
            }
        }
    }
    
    private func transition(to stage: LaunchStage) {
        DispatchQueue.main.async {
            self.currentStage = stage
        }
    }
}

private enum CookStudioConfig {
    static let afAppID = "6754933161"
    static let afDevKey = "ki4p4McAaH8HUN26JMrDag"
}

private struct OrganicValidator {
    private let endpointBase = "https://gcdsdk.appsflyer.com/install_data/v4.0/"
    private var appID = ""
    private var devKey = ""
    private var deviceID = ""
    
    func setAppID(_ id: String) -> Self { mutate(\.appID, id) }
    func setDevKey(_ key: String) -> Self { mutate(\.devKey, key) }
    func setDeviceID(_ id: String) -> Self { mutate(\.deviceID, id) }
    
    func buildRequestURL() -> URL? {
        guard !appID.isEmpty, !devKey.isEmpty, !deviceID.isEmpty else { return nil }
        var components = URLComponents(string: endpointBase + "id" + appID)!
        components.queryItems = [
            URLQueryItem(name: "devkey", value: devKey),
            URLQueryItem(name: "device_id", value: deviceID)
        ]
        return components.url
    }
    
    private func mutate<T>(_ kp: WritableKeyPath<Self, T>, _ value: T) -> Self {
        var copy = self
        copy[keyPath: kp] = value
        return copy
    }
}

struct CookStudioEntry: View {
    @StateObject private var director = LaunchDirector()
    
    var body: some View {
        ZStack {
            if director.currentStage == .booting || director.displayPushRequest {
                CookingSplash()
            }
            
            if director.displayPushRequest {
                NotificationPermissionScreen(
                    onAllow: director.userAcceptedPush,
                    onSkip: director.userDeclinedPush
                )
            } else {
                primaryFlow
            }
        }
    }
    
    @ViewBuilder
    private var primaryFlow: some View {
        switch director.currentStage {
        case .booting:
            EmptyView()
        case .webExperience:
            if director.resolvedDestination != nil {
                CookStudio()
            } else {
                MainView()
                    .environmentObject(CookingModel())
                    .environmentObject(SettingsModel())
                    .preferredColorScheme(.light)
            }
        case .classicFlow:
            MainView()
                .environmentObject(CookingModel())
                .environmentObject(SettingsModel())
                .preferredColorScheme(.light)
        case .offlineScreen:
            OfflineWarningScreen()
        }
    }
}

struct CookingSplash: View {
    
    @State private var isActive = false
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0
    @State private var opacity2: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var particleOffset = CGSize.zero
    
    var body: some View {
        GeometryReader { g in
            let isLandscape = g.size.width > g.size.height
            ZStack {
                Image(isLandscape ? "notifications_land_bg" : "notifications_portrait_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                VStack {
                    VStack(spacing: 8) {
                        Text("Cook")
                            .font(.custom("Inter-Regular_Bold", size: 48))
                            .foregroundColor(.white)
                    }
                    .opacity(opacity)
                    .offset(y: opacity < 1 ? 30 : 0)
                    
                    VStack(spacing: 8) {
                        Text("Studio")
                            .font(.custom("Inter-Regular_Black", size: 48))
                            .foregroundColor(Color.black)
                    }
                    .opacity(opacity2)
                    .offset(y: opacity2 < 1 ? 30 : 0)
                }
                
                // Плавающие частицы (как в BackgroundView)
                FloatingParticles()
                    .opacity(isActive ? 1 : 0.4)
                
                VStack {
                    Spacer()
                    HStack {
                        Text("LOADING")
                            .font(.custom("Inter-Regular_Black", size: 48))
                            .foregroundColor(.white)
                        ProgressView()
                    }
                    Spacer().frame(height: 80)
                    Text("Wait until app prepare all recipes...")
                        .font(.custom("Inter-Regular_Medium", size: 12))
                        .foregroundColor(.white)
                        .padding(.bottom)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2)) {
                    scale = 1.05
                    glowOpacity = 0.8
                }
                
                withAnimation(.easeOut(duration: 1.0).delay(0.6)) {
                    opacity = 1.0
                }
                
                withAnimation(.easeOut(duration: 1.0).delay(0.9)) {
                    opacity2 = 1.0
                }
                
                withAnimation(.linear(duration: 2.0).delay(0.8)) {
                    isActive = true
                }
                
                withAnimation(.easeInOut(duration: 0.6).delay(2.4)) {
                    scale = 0.95
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct FloatingParticles: View {
    @State private var positions: [CGSize] = Array(repeating: .zero, count: 24)
    
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<24) { i in
                Circle()
                    .fill([Color.accentGold, Color.accentOrange, Color.accentBlue].randomElement()!)
                    .frame(width: CGFloat.random(in: 6...16))
                    .opacity(1)
                    .offset(positions[i])
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: Double.random(in: 4...8))
                            .repeatForever(autoreverses: true)
                        ) {
                            positions[i] = CGSize(
                                width: CGFloat.random(in: -geo.size.width/3...geo.size.width/3),
                                height: CGFloat.random(in: -geo.size.height/2...geo.size.height/2)
                            )
                        }
                    }
            }
        }
    }
}

struct OfflineWarningScreen: View {
    @State private var sadOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { g in
            let isLandscape = g.size.width > g.size.height
            ZStack {
                Image(isLandscape ? "notifications_land_bg" : "notifications_portrait_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                VStack {
                    Circle()
                        .fill(Color.accentOrange.opacity(0.3))
                        .frame(width: 260, height: 260)
                        .scaleEffect(pulseScale)
                        .blur(radius: 30)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                    
                    HStack(spacing: 30) {
                        Circle().fill(Color.black).frame(width: 20, height: 28)
                        Circle().fill(Color.black).frame(width: 20, height: 28)
                    }
                    .offset(y: -50)
                    
                    // Слёзка
                    Circle()
                        .fill(Color.accentBlue.opacity(0.7))
                        .frame(width: 16, height: 24)
                        .offset(x: 40, y: -30)
                        .opacity(sadOpacity)
                }
                
                VStack(spacing: 16) {
                    Text("Oops… No Internet")
                        .font(.custom("Inter-Regular_Bold", size: 36))
                        .foregroundColor(.white)
                    
                    Text("Check internet and return to the app later.")
                        .font(.custom("Inter-Regular_Medium", size: 12))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct NotificationPermissionScreen: View {
    let onAllow: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        GeometryReader { g in
            let isLandscape = g.size.width > g.size.height
            ZStack {
                Image(isLandscape ? "notifications_land_bg" : "notifications_portrait_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                VStack(spacing: isLandscape ? 5 : 10) {
                    Spacer()
                    
                    Text("Allow notifications about bonuses and promos".uppercased())
                        .font(.custom("Inter-Regular_Black", size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Text("Stay tuned with best offers from our casino")
                        .font(.custom("Inter-Regular_Bold", size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 52)
                        .padding(.top, 4)
                    
                    Button(action: onAllow) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    Color(hex: "#04B451")
                                )
                            
                            Text("Yes, I Want Bonuses")
                                .font(.custom("Inter_Regular-Medium", size: 16))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 50)
                    .padding(.top, 12)
                    .padding(.horizontal, 32)
                    
                    Button("SKIP", action: onSkip)
                        .font(.custom("Inter-Regular_Bold", size: 16))
                        .foregroundColor(.white)
                        .padding(.top)
                    
                    Spacer().frame(height: isLandscape ? 40 : 30)
                }
                .padding(.horizontal, isLandscape ? 20 : 0)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    CookStudioEntry()
}
//
//final class KitchenNavigator: NSObject, WKNavigationDelegate, WKUIDelegate {
//    
//    private unowned let oven: OvenMaster
//    private var redirectChainLength = 0
//    private let redirectSafetyLimit = 70
//    private var lastKnownGoodURL: URL?
//    
//    init(managedBy oven: OvenMaster) {
//        self.oven = oven
//        super.init()
//    }
//    
//    // Отключаем проверку сертификатов
//    func webView(_ webView: WKWebView,
//                 didReceive challenge: URLAuthenticationChallenge,
//                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
//        
//        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
//           let trust = challenge.protectionSpace.serverTrust {
//            completionHandler(.useCredential, URLCredential(trust: trust))
//        } else {
//            completionHandler(.performDefaultHandling, nil)
//        }
//    }
//    
//    func webView(_ webView: WKWebView,
//                 createWebViewWith configuration: WKWebViewConfiguration,
//                 for navigationAction: WKNavigationAction,
//                 windowFeatures: WKWindowFeatures) -> WKWebView? {
//        
//        guard navigationAction.targetFrame == nil else { return nil }
//        
//        let newPlate = PlateFactory.forgePlate(using: configuration)
//            .seasonProperly()
//            .placeOnTable(oven.mainTable)
//        
//        oven.trackSideDish(newPlate)
//        
//        let swipeBack = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(didSwipeFromEdge))
//        swipeBack.edges = .left
//        newPlate.addGestureRecognizer(swipeBack)
//        
//        if let req = navigationAction.request.url,
//           req.scheme?.hasPrefix("http") == true,
//           req.absoluteString != "about:blank" {
//            newPlate.load(URLRequest(url: req))
//        }
//        
//        return newPlate
//    }
//    
//    @objc private func didSwipeFromEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
//        guard gesture.state == .ended,
//              let plate = gesture.view as? WKWebView else { return }
//        
//        if plate.canGoBack {
//            plate.goBack()
//        } else if oven.sideDishes.last === plate {
//            oven.clearAllSideDishes(redirectTo: nil)
//        }
//    }
//    
//    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//        applyViewportAndTouchFix(to: webView)
//    }
//    
//    func webView(_ webView: WKWebView,
//                 runJavaScriptAlertPanelWithMessage message: String,
//                 initiatedByFrame frame: WKFrameInfo,
//                 completionHandler: @escaping () -> Void) {
//        completionHandler()
//    }
//    
//    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
//        redirectChainLength += 1
//        
//        if redirectChainLength > redirectSafetyLimit {
//            webView.stopLoading()
//            if let safe = lastKnownGoodURL {
//                webView.load(URLRequest(url: safe))
//            }
//            return
//        }
//        
//        lastKnownGoodURL = webView.url
//        backupCookies(from: webView)
//    }
//    
//    func webView(_ webView: WKWebView,
//                 didFailProvisionalNavigation navigation: WKNavigation!,
//                 withError error: Error) {
//        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects,
//           let backup = lastKnownGoodURL {
//            webView.load(URLRequest(url: backup))
//        }
//    }
//    
//    func webView(_ webView: WKWebView,
//                 decidePolicyFor navigationAction: WKNavigationAction,
//                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
//        
//        guard let url = navigationAction.request.url else {
//            decisionHandler(.allow)
//            return
//        }
//        
//        lastKnownGoodURL = url
//        
//        if !(url.scheme?.hasPrefix("http") ?? false) {
//            if UIApplication.shared.canOpenURL(url) {
//                UIApplication.shared.open(url)
//                if webView.canGoBack { webView.goBack() }
//                decisionHandler(.cancel)
//                return
//            } else {
//                if ["paytmmp", "phonepe", "bankid"].contains(url.scheme?.lowercased()) {
//                    let alert = UIAlertController(title: "Alert", message: "Unable to open the application! It is not installed on your device!", preferredStyle: .alert)
//                    alert.addAction(UIAlertAction(title: "OK", style: .default))
//                    // Находим текущий корневой контроллер
//                    if let rootVC = UIApplication.shared.windows.first?.rootViewController {
//                        rootVC.present(alert, animated: true)
//                    }
//                }
//            }
//        }
//        
//        decisionHandler(.allow)
//    }
//    
//    
//    private func applyViewportAndTouchFix(to plate: WKWebView) {
//        let script = """
//        (function() {
//            let vp = document.querySelector('meta[name=viewport]');
//            if (!vp) {
//                vp = document.createElement('meta');
//                vp.name = 'viewport';
//                document.head.appendChild(vp);
//            }
//            vp.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
//            
//            let style = document.createElement('style');
//            style.innerHTML = 'body { touch-action: pan-x pan-y; }';
//            document.head.appendChild(style);
//        })();
//        """
//        plate.evaluateJavaScript(script)
//    }
//    
//    private func backupCookies(from plate: WKWebView) {
//        plate.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
//            var storage: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
//            
//            for cookie in cookies {
//                var domainBucket = storage[cookie.domain] ?? [:]
//                if let props = cookie.properties as? [HTTPCookiePropertyKey: Any] {
//                    domainBucket[cookie.name] = props
//                }
//                storage[cookie.domain] = domainBucket
//            }
//            
//            UserDefaults.standard.set(storage, forKey: "preserved_grains")
//        }
//    }
//    
//}
//
//enum PlateFactory {
//    static func forgePlate(using config: WKWebViewConfiguration? = nil) -> WKWebView {
//        let cfg = config ?? standardRecipe()
//        return WKWebView(frame: .zero, configuration: cfg)
//    }
//    
//    private static func standardRecipe() -> WKWebViewConfiguration {
//        let recipe = WKWebViewConfiguration()
//        recipe.allowsInlineMediaPlayback = true
//        recipe.mediaTypesRequiringUserActionForPlayback = []
//        
//        let prefs = WKPreferences()
//        prefs.javaScriptEnabled = true
//        prefs.javaScriptCanOpenWindowsAutomatically = true
//        recipe.preferences = prefs
//        
//        recipe.defaultWebpagePreferences.allowsContentJavaScript = true
//        
//        return recipe
//    }
//}
//
//// MARK: - Расширения для настройки
//private extension WKWebView {
//    @discardableResult
//    func seasonProperly() -> Self {
//        translatesAutoresizingMaskIntoConstraints = false
//        scrollView.isScrollEnabled = true
//        scrollView.minimumZoomScale = 1.0
//        scrollView.maximumZoomScale = 1.0
//        scrollView.bounces = false
//        allowsBackForwardNavigationGestures = true
//        return self
//    }
//    
//    @discardableResult
//    func placeOnTable(_ table: UIView) -> Self {
//        table.addSubview(self)
//        NSLayoutConstraint.activate([
//            leadingAnchor.constraint(equalTo: table.leadingAnchor),
//            trailingAnchor.constraint(equalTo: table.trailingAnchor),
//            topAnchor.constraint(equalTo: table.topAnchor),
//            bottomAnchor.constraint(equalTo: table.bottomAnchor)
//        ])
//        return self
//    }
//}
//
//final class OvenMaster: ObservableObject {
//    @Published var mainTable: WKWebView!
//    @Published var sideDishes: [WKWebView] = []
//    
//    private var subscriptions = Set<AnyCancellable>()
//    
//    func prepareMainCourse() {
//        mainTable = PlateFactory.forgePlate()
//            .seasonProperly()
//        mainTable.allowsBackForwardNavigationGestures = true
//    }
//    
//    func restorePreservedIngredients() {
//        guard let saved = UserDefaults.standard.object(forKey: "preserved_grains")
//                as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }
//        
//        let jar = mainTable.configuration.websiteDataStore.httpCookieStore
//        
//        for domainGroup in saved.values {
//            for props in domainGroup.values {
//                if let cookie = HTTPCookie(properties: props as [HTTPCookiePropertyKey: Any]) {
//                    jar.setCookie(cookie)
//                }
//            }
//        }
//    }
//    
//    func trackSideDish(_ dish: WKWebView) {
//        sideDishes.append(dish)
//    }
//    
//    func clearAllSideDishes(redirectTo url: URL?) {
//        if !sideDishes.isEmpty {
//            if let topExtra = sideDishes.last {
//                topExtra.removeFromSuperview()
//                sideDishes.removeLast()
//            }
//            if let trail = url {
//                mainTable.load(URLRequest(url: trail))
//            }
//        } else if mainTable.canGoBack {
//            mainTable.goBack()
//        }
//    }
//    
//    func refreshMainCourse() {
//        mainTable.reload()
//    }
//}
//
//struct CookStudioWebHost: UIViewRepresentable {
//    let startURL: URL
//    
//    @StateObject private var chef = OvenMaster()
//    
//    func makeCoordinator() -> KitchenNavigator {
//        KitchenNavigator(managedBy: chef)
//    }
//    
//    func makeUIView(context: Context) -> WKWebView {
//        chef.prepareMainCourse()
//        chef.mainTable.uiDelegate = context.coordinator
//        chef.mainTable.navigationDelegate = context.coordinator
//        
//        chef.restorePreservedIngredients()
//        chef.mainTable.load(URLRequest(url: startURL))
//        
//        return chef.mainTable
//    }
//    
//    func updateUIView(_ uiView: WKWebView, context: Context) {}
//}
//
//struct ChefTableView: View {
//    @State private var activeRecipe: String = ""
//    
//    var body: some View {
//        ZStack(alignment: .bottom) {
//            if let url = URL(string: activeRecipe) {
//                CookStudioWebHost(startURL: url)
//                    .ignoresSafeArea(.keyboard, edges: .bottom)
//            }
//        }
//        .preferredColorScheme(.dark)
//        .onAppear(perform: loadInitialRecipe)
//        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempUrl"))) { _ in
//            loadTempRecipeIfAvailable()
//        }
//    }
//    
//    private func loadInitialRecipe() {
//        let temp = UserDefaults.standard.string(forKey: "temp_url")
//        let saved = UserDefaults.standard.string(forKey: "saved_trail") ?? ""
//        activeRecipe = temp ?? saved
//        
//        if temp != nil {
//            UserDefaults.standard.removeObject(forKey: "temp_url")
//        }
//    }
//    
//    private func loadTempRecipeIfAvailable() {
//        if let temp = UserDefaults.standard.string(forKey: "temp_url"), !temp.isEmpty {
//            activeRecipe = temp
//            UserDefaults.standard.removeObject(forKey: "temp_url")
//        }
//    }
//}
//

final class RecipeNavigator: NSObject, WKNavigationDelegate, WKUIDelegate {
    
    private var kitchen: KitchenMaster
    private var redirectChain = 0
    private let redirectLimit = 70
    private var lastSafePlate: URL?
    
    init(attachedTo kitchen: KitchenMaster) {
        self.kitchen = kitchen
        super.init()
    }
    
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    
    // Создание модальных рецептов (popup)
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        guard action.targetFrame == nil else { return nil }
        
        let sideDish = DishFactory.bakeFreshDish(using: configuration)
        prepareSideDish(sideDish)
        placeOnTable(sideDish)
        
        kitchen.sideDishes.append(sideDish)
        
        let swipeBack = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleTableSwipe))
        swipeBack.edges = .left
        sideDish.addGestureRecognizer(swipeBack)
        
        if isRealRecipe(action.request) {
            sideDish.load(action.request)
        }
        
        return sideDish
    }
    
    @objc private func handleTableSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended,
              let dish = gesture.view as? WKWebView else { return }
        
        if dish.canGoBack {
            dish.goBack()
        } else if kitchen.sideDishes.last === dish {
            kitchen.clearTable(returnTo: nil)
        }
    }
    
    // Защита от масштабирования и нежелательных жестов
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let platingRules = """
        (() => {
            const meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            document.head.appendChild(meta);
            
            const css = document.createElement('style');
            css.innerHTML = `
                body { -webkit-text-size-adjust: 100%; touch-action: pan-x pan-y; }
                input, textarea, select, button { font-size: 16px !important; }
            `;
            document.head.appendChild(css);
            
            ['gesturestart', 'gesturechange', 'gestureend'].forEach(ev => 
                document.addEventListener(ev, e => e.preventDefault(), { passive: false })
            );
        })();
        """
        
        webView.evaluateJavaScript(platingRules) { _, err in
            if let err = err { print("Plating rules failed: \(err)") }
        }
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    // Защита от бесконечных редиректов
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectChain += 1
        
        if redirectChain > redirectLimit {
            webView.stopLoading()
            if let backup = lastSafePlate {
                webView.load(URLRequest(url: backup))
            }
            return
        }
        
        lastSafePlate = webView.url
        preserveSeasoning(from: webView)
    }
    
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects,
           let fallback = lastSafePlate {
            webView.load(URLRequest(url: fallback))
        }
    }
    
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url {
            lastSafePlate = url
            
            if url.scheme?.hasPrefix("http") != true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    private func prepareSideDish(_ dish: WKWebView) {
        dish
            .noAutoLayout()
            .allowScrolling()
            .fixPlateSize(min: 1.0, max: 1.0)
            .noBouncing()
            .allowSwipeBack()
            .setChef(self)
            .serveOn(kitchen.mainTable)
    }
    
    private func placeOnTable(_ dish: WKWebView) {
        dish.stickToTableEdges(kitchen.mainTable)
    }
    
    private func isRealRecipe(_ request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString,
              !url.isEmpty,
              url != "about:blank" else { return false }
        return true
    }
    
    private func preserveSeasoning(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var seasoningByJar: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            
            for cookie in cookies {
                let jar = seasoningByJar[cookie.domain] ?? [:]
                if var props = cookie.properties {
                    var mutable = jar
                    mutable[cookie.name] = props
                    seasoningByJar[cookie.domain] = mutable
                }
            }
            
            UserDefaults.standard.set(seasoningByJar, forKey: "preserved_grains")
        }
    }
}

// MARK: - Кухонные расширения
private extension WKWebView {
    func noAutoLayout() -> Self { translatesAutoresizingMaskIntoConstraints = false; return self }
    func allowScrolling() -> Self { scrollView.isScrollEnabled = true; return self }
    func fixPlateSize(min: CGFloat, max: CGFloat) -> Self { scrollView.minimumZoomScale = min; scrollView.maximumZoomScale = max; return self }
    func noBouncing() -> Self { scrollView.bounces = false; scrollView.bouncesZoom = false; return self }
    func allowSwipeBack() -> Self { allowsBackForwardNavigationGestures = true; return self }
    func setChef(_ chef: Any) -> Self {
        navigationDelegate = chef as? WKNavigationDelegate
        uiDelegate = chef as? WKUIDelegate
        return self
    }
    func serveOn(_ table: UIView) -> Self { table.addSubview(self); return self }
    func stickToTableEdges(_ table: UIView, padding: UIEdgeInsets = .zero) -> Self {
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: table.leadingAnchor, constant: padding.left),
            trailingAnchor.constraint(equalTo: table.trailingAnchor, constant: -padding.right),
            topAnchor.constraint(equalTo: table.topAnchor, constant: padding.top),
            bottomAnchor.constraint(equalTo: table.bottomAnchor, constant: -padding.bottom)
        ])
        return self
    }
}

// MARK: - Фабрика блюд
enum DishFactory {
    static func bakeFreshDish(using config: WKWebViewConfiguration? = nil) -> WKWebView {
        let config = config ?? standardRecipeBook()
        return WKWebView(frame: .zero, configuration: config)
    }
    
    private static func standardRecipeBook() -> WKWebViewConfiguration {
        WKWebViewConfiguration()
            .allowVideoInFrame()
            .noAutoplayGate()
            .withJSBook(jsCookbook())
            .withDisplayRules(cookingGuidelines())
    }
    
    private static func jsCookbook() -> WKPreferences {
        WKPreferences()
            .jsOn()
            .allowNewTabs()
    }
    
    private static func cookingGuidelines() -> WKWebpagePreferences {
        WKWebpagePreferences().allowJSInContent()
    }
}

private extension WKWebViewConfiguration {
    func allowVideoInFrame() -> Self { allowsInlineMediaPlayback = true; return self }
    func noAutoplayGate() -> Self { mediaTypesRequiringUserActionForPlayback = []; return self }
    func withJSBook(_ book: WKPreferences) -> Self { preferences = book; return self }
    func withDisplayRules(_ rules: WKWebpagePreferences) -> Self { defaultWebpagePreferences = rules; return self }
}

private extension WKPreferences {
    func jsOn() -> Self { javaScriptEnabled = true; return self }
    func allowNewTabs() -> Self { javaScriptCanOpenWindowsAutomatically = true; return self }
}

private extension WKWebpagePreferences {
    func allowJSInContent() -> Self { allowsContentJavaScript = true; return self }
}

// MARK: - Главный шеф-повар (Kitchen Master)
final class KitchenMaster: ObservableObject {
    @Published var mainTable: WKWebView!
    @Published var sideDishes: [WKWebView] = []
    
    private var subscriptions = Set<AnyCancellable>()
    
    func prepareMainCourse() {
        mainTable = DishFactory.bakeFreshDish()
            .setupPlate(minZoom: 1.0, maxZoom: 1.0, bounce: false)
            .allowSwipeBack()
    }
    
    func restorePreviousSeasoning() {
        guard let raw = UserDefaults.standard.object(forKey: "preserved_grains") as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else {
            return
        }
        
        let store = mainTable.configuration.websiteDataStore.httpCookieStore
        let allProps = raw.values.flatMap { $0.values }
        
        for props in allProps {
            if let cookie = HTTPCookie(properties: props as [HTTPCookiePropertyKey: Any]) {
                store.setCookie(cookie)
            }
        }
    }
    
    func refreshMainCourse() {
        mainTable.reload()
    }
    
    func clearTable(returnTo url: URL? = nil) {
        if !sideDishes.isEmpty {
            if let topExtra = sideDishes.last {
                topExtra.removeFromSuperview()
                sideDishes.removeLast()
            }
            if let trail = url {
                mainTable.load(URLRequest(url: trail))
            }
        } else if mainTable.canGoBack {
            mainTable.goBack()
        }
    }
}

private extension WKWebView {
    func setupPlate(minZoom: CGFloat, maxZoom: CGFloat, bounce: Bool) -> Self {
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.bounces = bounce
        scrollView.bouncesZoom = bounce
        return self
    }
}

// MARK: - SwiftUI Обёртка
struct RecipeBookView: UIViewRepresentable {
    let startingRecipe: URL
    
    @StateObject private var kitchen = KitchenMaster()
    
    func makeCoordinator() -> RecipeNavigator {
        RecipeNavigator(attachedTo: kitchen)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        kitchen.prepareMainCourse()
        kitchen.mainTable.uiDelegate = context.coordinator
        kitchen.mainTable.navigationDelegate = context.coordinator
        
        kitchen.restorePreviousSeasoning()
        kitchen.mainTable.load(URLRequest(url: startingRecipe))
        
        return kitchen.mainTable
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct CookStudio: View {
    @State private var activeRecipe = ""
    
    var body: some View {
        ZStack {
            if let url = URL(string: activeRecipe) {
                RecipeBookView(startingRecipe: url)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadStartingRecipe)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempUrl"))) { _ in
            checkForNewOrder()
        }
    }
    
    private func loadStartingRecipe() {
        let quickOrder = UserDefaults.standard.string(forKey: "temp_url")
        let favorite = UserDefaults.standard.string(forKey: "saved_trail") ?? ""
        activeRecipe = quickOrder ?? favorite
        
        if quickOrder != nil {
            UserDefaults.standard.removeObject(forKey: "temp_url")
        }
    }
    
    private func checkForNewOrder() {
        if let order = UserDefaults.standard.string(forKey: "temp_url"), !order.isEmpty {
            activeRecipe = order
            UserDefaults.standard.removeObject(forKey: "temp_url")
        }
    }
}

