import SwiftUI
import AVFoundation
import Combine

@main
struct EggCookStudioApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(CookingModel())
                .environmentObject(SettingsModel())
                .preferredColorScheme(.light)
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
}

class SettingsModel: ObservableObject {
    @Published var timeUnit: TimeUnit = .minutes
    @Published var temperatureUnit: TemperatureUnit = .celsius
    @Published var theme: Theme = .light
    @Published var notificationSound: NotificationSound = .rooster
}

// MARK: - Enums
enum EggSize: String, CaseIterable, Identifiable {
    case small = "S", medium = "M", large = "L", extraLarge = "XL"
    var id: String { rawValue }
}

enum EggTemperature: String, CaseIterable, Identifiable {
    case fridge = "Fridge", room = "Room"
    var id: String { rawValue }
}

enum CookingMethod: String, CaseIterable, Identifiable {
    case boiled = "Boiled", poached = "Poached", fried = "Fried", baked = "Baked"
    var id: String { rawValue }
}

enum Doneness: String, CaseIterable, Identifiable {
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
                SettingsView().tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
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
            }
        }
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
                        
                        ForEach(cookingModel.recipes) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
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
    @State private var stepOpacity: Double = 0
    @State private var imageScale: CGFloat = 1.0
    @State private var viewOpacity: Double = 0
    
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
    @State private var viewOpacity: Double = 0
    
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

// MARK: - Preview
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(CookingModel())
            .environmentObject(SettingsModel())
            .previewDevice("iPhone 12")
    }
}
