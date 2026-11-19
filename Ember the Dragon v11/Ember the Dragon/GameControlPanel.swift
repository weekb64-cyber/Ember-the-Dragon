import SwiftUI

/// Activity actions have their own small strip beside the nest, independent of Pause.
struct GameControlPanel: View {
    @Environment(GameModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        @Bindable var model = model
        Group {
            if !model.isPaused && (model.isLoadingAssets || model.assetLoadError != nil || model.stageReady || [.introduction,.magicSetup,.scales,.hornAlignment,.painting,.complete].contains(model.currentPhase)) {
                VStack(spacing:12) {
                    if model.isLoadingAssets { ProgressView("Getting ready…") }
                    else if let error = model.assetLoadError {
                        Text(error).font(.caption)
                        Button("Retry") { model.phaseRevision += 1 }
                    } else {
                        if model.stageReady && model.currentPhase != .scales { Button("Continue",systemImage:"arrow.right") { model.advanceSetupOrStage() } }
                        if model.currentPhase == .introduction { Button("Wake Ember",systemImage:"sun.max") { model.advanceSetupOrStage() } }
                        if model.currentPhase == .magicSetup && !model.calibrationIsPreparing {
                            if model.calibrationIsSimulated {
                                HStack(spacing:12) {
                                    Button("Forward") { model.simulatedHandDepth = max(-0.24,model.simulatedHandDepth-0.05) }
                                    Button("Closer") { model.simulatedHandDepth = min(0.24,model.simulatedHandDepth+0.05) }
                                }
                            }
                            Button("Use this reach",systemImage:"checkmark") { model.advanceSetupOrStage() }.disabled(!model.isReachSetupReady)
                        }
                        if model.currentPhase == .scales {
                            VStack(spacing:12) {
                                Menu {
                                    Picker("Shape",selection:$model.scaleShape) {
                                        ForEach(ScaleShape.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                                    }
                                } label: { Label(model.scaleShape.rawValue,systemImage:"diamond").frame(maxWidth:.infinity) }
                                HStack(spacing:12) {
                                    Button { model.scaleTurn = (model.scaleTurn+1)%4 } label: {
                                        Label("Rotate",systemImage:"rotate.right").frame(maxWidth:.infinity)
                                    }
                                    Button { model.scaleUndoRevision += 1 } label: {
                                        Label("Undo",systemImage:"arrow.uturn.backward").frame(maxWidth:.infinity)
                                    }.disabled(model.scaleDesign.isEmpty)
                                }
                                if model.stageReady {
                                    Button("Continue",systemImage:"arrow.right") { model.advanceSetupOrStage() }
                                }
                            }.frame(height:168,alignment:.top)
                        }
                        if model.currentPhase == .hornAlignment {
                            Button("Grip left horn",systemImage:"hand.point.up.left") { model.requestHornGrip(0) }
                            Button("Grip right horn",systemImage:"hand.point.up.left") { model.requestHornGrip(1) }
                            Button("Release grip",systemImage:"hand.raised") { model.requestHornGrip(nil) }
                        }
                        if model.currentPhase == .painting {
                            VStack(spacing:12) {
                                Button("New colours",systemImage:"shuffle") { model.randomizePalette() }
                                Button("Finished",systemImage:"checkmark") { model.advanceSetupOrStage() }.disabled(!model.paintingComplete)
                            }
                        }
                        if model.currentPhase == .complete {
                            VStack(spacing:12) {
                                Button("Photo",systemImage:"camera") { model.preparePhotoBooth(); openWindow(id:"EmberPhotoBooth") }
                                Button("Gallery",systemImage:"square.grid.2x2") { openWindow(id:"EmberGallery") }
                                Button("Replay",systemImage:"arrow.clockwise") { model.replay() }
                            }
                        }
                    }
                }.padding(12)
            }
        }.font(.system(size:15,weight:.medium,design:.rounded))
        .buttonStyle(EmberActionStyle(panelGlass:true)).frame(width:300).environment(\.colorScheme,.dark)
    }
}

struct EmberPauseMenu: View {
    enum Page { case main, settings, activity }
    @State private var requestedSize: Double = 1
    @State private var page: Page
    init(showSettings: Bool = false) { _page = State(initialValue:showSettings ? .settings : .main) }
    @Environment(GameModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment:.trailing,spacing:12) {
            Button {
                if model.isPaused { model.resume() } else { page = .main; model.pause() }
            } label: { Image(systemName:model.isPaused ? "xmark" : "pause.fill").frame(width:28,height:28) }
                .buttonStyle(EmberActionStyle(panelGlass:true))
                .accessibilityLabel(model.isPaused ? "Close pause menu and resume" : "Pause")
            if model.isPaused {
                EmberPanel(title:page == .main ? "Paused" : (page == .settings ? "Settings" : "Activity controls")) {
                    VStack(spacing:12) {
                        if page == .main {
                            row("Resume",icon:"play.fill",prominent:true) { model.resume() }
                            row("Restart activity",icon:"arrow.clockwise") { model.restartCurrentStage() }
                            row("Settings",icon:"slider.horizontal.3") { page = .settings }
                            row("Activity controls",icon:"forward.end") { page = .activity }
                            Divider().padding(.vertical,4)
                            row("Return to start",icon:"house",secondary:true) { model.finish() }
                        } else {
                            row("Back",icon:"chevron.left") { page = .main }
                            if page == .settings {
                                HStack {
                                    Text("Movement")
                                    Picker("Movement",selection:$model.comfortSettings.movementAmount) {
                                        ForEach(MovementAmountSetting.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                                    }.pickerStyle(.segmented).labelsHidden()
                                }.onChange(of:model.comfortSettings.movementAmount) { _, _ in model.applyComfortSettings() }
                                Toggle("Sound effects",isOn:$model.soundEffectsEnabled).padding(.vertical,6)
                                    .onChange(of:model.soundEffectsEnabled) { _, enabled in
                                        #if os(visionOS)
                                        GameAudio.shared.isEnabled = enabled
                                        #endif
                                    }
                                Text("Scene size · \(Int(requestedSize*100))%")
                                HStack(spacing:12) {
                                    Button("Smaller",systemImage:"minus") { requestedSize = max(0.75,requestedSize-0.25) }.disabled(requestedSize <= 0.75)
                                    Button("Larger",systemImage:"plus") { requestedSize = min(2.5,requestedSize+0.25) }.disabled(requestedSize >= 2.5)
                                }
                                row("Apply size & restart",icon:"checkmark") { model.sceneSize = Float(requestedSize); model.restartCurrentStage() }
                                    .disabled(abs(requestedSize-Double(model.sceneSize)) < 0.01)
                                row("Recenter here",icon:"viewfinder") { model.recenterRevision += 1; model.resume() }
                            } else {
                                Text("Move between activities for testing.").font(.callout).foregroundStyle(.secondary)
                                row("Previous activity",icon:"backward.end") { model.goBackStage() }.disabled(!model.canGoBack)
                                row("Skip activity",icon:"forward.end") { model.skipCurrentStage() }.disabled(model.activePhase == .complete)
                                Divider().padding(.vertical,4)
                                row("Start over",icon:"arrow.counterclockwise",secondary:true) { model.startOver() }
                            }
                        }
                    }
                }.transition(.opacity.combined(with:.move(edge:.top)))
            }
        }.buttonStyle(EmberActionStyle())
        .frame(width:420,height:700,alignment:.topTrailing)
        .animation(.easeInOut(duration:0.2),value:model.isPaused)
        .onChange(of:model.isPaused) { _, paused in if paused { requestedSize = Double(model.sceneSize) } }
    }
    private func row(_ title: String, icon: String, prominent: Bool = false, secondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action:action) { Label(title,systemImage:icon).frame(maxWidth:.infinity,alignment:.leading) }
            .buttonStyle(EmberActionStyle(prominent:prominent,secondary:secondary))
    }
}
