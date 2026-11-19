import SwiftUI

struct GameTypography {
    static let title: CGFloat = 38
    static let subtitle: CGFloat = 22
    static let instruction: CGFloat = 24
    static let button: CGFloat = 22
}

struct GameColors {
    static let parchment = Color(red: 0.05, green: 0.15, blue: 0.17)
    static let ink = Color(red: 0.94, green: 0.96, blue: 0.92)
    static let moss = Color(red: 0.29, green: 0.62, blue: 0.37)
    static let teal = Color(red: 0.17, green: 0.66, blue: 0.68)
    static let coral = Color(red: 1.0, green: 0.54, blue: 0.48)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.27)
}

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GameModel.self) private var gameModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            if !gameModel.isSceneReady {
                LauncherView(start: { gameModel.startGame() }, gallery: { openWindow(id:"EmberGallery") })
                .allowsHitTesting(appModel.immersiveSpaceState == .closed)
                .overlay(alignment: .bottom) {
                    if appModel.immersiveSpaceState != .closed {
                        VStack(spacing:10) {
                            Text(gameModel.assetLoadError ?? (gameModel.isLoadingAssets ? "Getting Ember ready…" : "Positioning Ember…"))
                                .multilineTextAlignment(.center)
                            if gameModel.assetLoadError != nil {
                                Button("Retry") { gameModel.restartCurrentStage() }.buttonStyle(EmberActionStyle())
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
                        .padding(.bottom,12)
                    }
                }
            }

            if appModel.immersiveSpaceState != .open && (gameModel.isPaused || gameModel.currentPhase == .paused) {
                PauseMenu()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: gameModel.currentPhase)
        .task(id: gameModel.shouldOpenImmersiveSpace) {
            guard gameModel.shouldOpenImmersiveSpace else { return }
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                gameModel.immersiveSpaceOpened()
                if gameModel.isSceneReady { dismissWindow(id: appModel.launcherWindowID) }
                #if DEBUG
                print("Ember spatial presentation: mixed immersive space opened; launcher closes when the scene is ready.")
                #endif
            case .userCancelled, .error:
                appModel.immersiveSpaceState = .closed
                gameModel.immersiveSpaceOpened()
            @unknown default:
                appModel.immersiveSpaceState = .closed
                gameModel.immersiveSpaceOpened()
            }
        }
        .onChange(of: gameModel.isSceneReady) { _, ready in
            if ready { dismissWindow(id: appModel.launcherWindowID) }
        }
        .task(id: gameModel.shouldDismissImmersiveSpace) {
            guard gameModel.shouldDismissImmersiveSpace else { return }
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
            gameModel.immersiveSpaceDismissed()
        }
    }
}

struct LauncherView: View {
    let start: () -> Void
    let gallery: () -> Void
    var body: some View {
        GeometryReader { geometry in
            // Fit, never crop: title and both actions remain visible when the window is resized.
            let width = min(geometry.size.width,geometry.size.height * 1672 / 941)
            let height = width * 941 / 1672
            ZStack {
                Image("EmberSunsetHome")
                    .resizable().interpolation(.high)
                    .frame(width:width,height:height)
                    .accessibilityLabel("Ember")
                    .accessibilityAddTraits(.isHeader)
                    .allowsHitTesting(false)
                Button(action:start) {
                    HStack(spacing:14) { Text("Begin"); Image(systemName:"chevron.right").font(.system(size:18,weight:.medium)) }
                        .frame(width:max(180,width*0.255),height:max(52,height*0.11))
                }
                .buttonStyle(EmberLandingButtonStyle())
                .accessibilityHint("Start Ember")
                .position(x:width/2,y:height*0.82)
            }
            .frame(width:width,height:height)
            .overlay(alignment:.topTrailing) {
                Button(action:gallery) {
                    Label("Gallery",systemImage:"square.grid.2x2.fill")
                        .font(.system(size:17,weight:.semibold,design:.rounded))
                        .frame(width:118,height:48)
                }
                .buttonStyle(EmberGalleryLinkStyle())
                .accessibilityHint("Open saved Embers")
                // Keep the text-only action comfortably inside the artwork corner.
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius:30,style:.continuous))
            .position(x:geometry.size.width/2,y:geometry.size.height/2)
        }
        .frame(minWidth:640,minHeight:360)
        .background(Color(red:0.10,green:0.12,blue:0.16))
    }
}

/// Text and symbol only; no capsule, fill, stroke or glass layer.
struct EmberGalleryLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .shadow(color:.black.opacity(0.6),radius:3,y:1)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            #if os(visionOS)
            .hoverEffect(.lift)
            .onChange(of:configuration.isPressed) { _, pressed in if pressed { GameAudio.shared.play(.tap) } }
            #endif
    }
}

struct EmberLandingButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size:24,weight:.semibold,design:.rounded))
            .foregroundStyle(.white)
            .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:secondary ? 18 : 30,style:.continuous))
            .opacity(secondary ? 0.65 : 1)
            .contentShape(RoundedRectangle(cornerRadius:secondary ? 18 : 30,style:.continuous))
            #if os(visionOS)
            .hoverEffect(.highlight)
            .onChange(of:configuration.isPressed) { _, pressed in if pressed { GameAudio.shared.play(.tap) } }
            #endif
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .environment(\.colorScheme,.dark)
    }
}

struct EmberTitleText: View {
    private let title = "ember"

    var body: some View {
        ZStack {
            ForEach(outlineOffsets, id: \.self) { offset in
                Text(title)
                    .font(.system(size: 126, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color(red: 0.28, green: 0.11, blue: 0.04))
                    .offset(offset)
            }

            Text(title)
                .font(.system(size: 126, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.42),
                            Color(red: 1.0, green: 0.56, blue: 0.22),
                            Color(red: 0.94, green: 0.28, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .white.opacity(0.24), radius: 2, x: 0, y: -2)
                .shadow(color: Color(red: 0.16, green: 0.06, blue: 0.02).opacity(0.68), radius: 0, x: 0, y: 7)
        }
        .frame(height: 122)
        .accessibilityHidden(true)
    }

    private var outlineOffsets: [CGSize] {
        [
            CGSize(width: -4, height: 0),
            CGSize(width: 4, height: 0),
            CGSize(width: 0, height: -4),
            CGSize(width: 0, height: 4),
            CGSize(width: -3, height: -3),
            CGSize(width: 3, height: -3),
            CGSize(width: -3, height: 3),
            CGSize(width: 3, height: 3)
        ]
    }
}

struct CozyForestBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.3, blue: 0.26),
                    Color(red: 0.28, green: 0.51, blue: 0.35),
                    Color(red: 0.83, green: 0.57, blue: 0.31)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(red: 1.0, green: 0.76, blue: 0.28).opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 22)
                .offset(x: -210, y: -120)

            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.25, blue: 0.19).opacity(0.22))
                    .frame(width: 90 + CGFloat(index % 3) * 18, height: 250)
                    .rotationEffect(.degrees(Double(index - 3) * 5))
                    .offset(x: CGFloat(index - 3) * 88, y: 112 + CGFloat(index % 2) * 18)
            }
        }
        .overlay {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.24)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
}

struct WoodenTitleSign<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.66, green: 0.34, blue: 0.16),
                            Color(red: 0.48, green: 0.22, blue: 0.1),
                            Color(red: 0.78, green: 0.43, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.34, green: 0.15, blue: 0.07).opacity(index.isMultiple(of: 2) ? 0.22 : 0.14))
                        .frame(height: 5)
                        .padding(.horizontal, CGFloat(18 + index * 7))
                }
            }

            content
        }
        .frame(width: 530, height: 245)
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.77, blue: 0.38).opacity(0.55), lineWidth: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color(red: 0.24, green: 0.1, blue: 0.04).opacity(0.45), lineWidth: 3)
                .padding(10)
        )
        .shadow(color: Color(red: 0.16, green: 0.07, blue: 0.03).opacity(0.42), radius: 18, y: 12)
    }
}

struct SpatialGameControls: View {
    @Environment(GameModel.self) private var gameModel

    var body: some View {
        ZStack {
            PauseButton()
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if [.magicSetup, .bilateralSetup, .precisionSetup].contains(gameModel.currentPhase) {
                HStack(spacing: 12) {
                    Button {
                        gameModel.advanceSetupOrStage()
                    } label: {
                        Label(gameModel.setupButtonTitle, systemImage: "sparkles")
                            .font(.system(size: GameTypography.button * gameModel.textScale, weight: .bold, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(GameButtonStyle(tint: GameColors.moss))

                    Button {
                        gameModel.transition(to: .horns)
                    } label: {
                        Text("Skip setup")
                            .font(.system(size: (GameTypography.button - 3) * gameModel.textScale, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(EmberActionStyle())
                }
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

struct PauseButton: View {
    @Environment(GameModel.self) private var gameModel

    var body: some View {
        Button {
            gameModel.pause()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(GameButtonStyle(tint: GameColors.coral))
        .accessibilityLabel("Pause")
    }
}

struct PauseMenu: View {
    var body: some View { EmberPauseMenu() }
}

struct ComfortView: View {
    @Environment(GameModel.self) private var gameModel

    var body: some View {
        @Bindable var gameModel = gameModel

        VStack(spacing: 12) {
            settingPicker("Movement", selection: $gameModel.comfortSettings.movementAmount, values: MovementAmountSetting.allCases)
            settingPicker("Reach", selection: $gameModel.comfortSettings.reachArea, values: ReachAreaSetting.allCases)
            settingPicker("Text", selection: $gameModel.comfortSettings.textSize, values: TextSizeSetting.allCases)
            settingPicker("Effects", selection: $gameModel.comfortSettings.particleEffects, values: ParticleEffectsSetting.allCases)
            Toggle("Sound", isOn: $gameModel.comfortSettings.soundEnabled)
                .font(.system(size: 18 * gameModel.textScale, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(GameColors.ink)
        .onChange(of: gameModel.comfortSettings.reachArea) { _, _ in gameModel.applyComfortSettings() }
        .onChange(of: gameModel.comfortSettings.movementAmount) { _, _ in gameModel.applyComfortSettings() }
        .onChange(of: gameModel.comfortSettings.particleEffects) { _, _ in gameModel.applyComfortSettings() }
    }

    private func settingPicker<Value: RawRepresentable & CaseIterable & Hashable>(_ title: String, selection: Binding<Value>, values: [Value]) -> some View where Value.RawValue == String {
        HStack {
            Text(title)
                .font(.system(size: 18 * gameModel.textScale, weight: .semibold, design: .rounded))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
    }
}

struct GameButtonStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        EmberActionStyle().makeBody(configuration:configuration)
    }
}
