import SwiftUI

enum EmberUI {
    static let panelRadius: CGFloat = 28
    static let controlRadius: CGFloat = 20
    static let padding: CGFloat = 24
}

struct EmberGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = EmberUI.panelRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            // A single charcoal tint over glass keeps white labels readable against bright rooms.
            .background(Color(white:0.06).opacity(reduceTransparency ? 0.98 : (contrast == .increased ? 0.82 : 0.66)),
                        in:RoundedRectangle(cornerRadius:cornerRadius,style:.continuous))
        #if os(visionOS)
            .glassBackgroundEffect(in:RoundedRectangle(cornerRadius:cornerRadius,style:.continuous))
        #else
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:cornerRadius,style:.continuous))
        #endif
    }
}

struct EmberPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing:20) {
            if let title {
                Text(title).font(.system(size:26,weight:.bold,design:.rounded))
                    .frame(maxWidth:.infinity).multilineTextAlignment(.center)
            }
            content.frame(maxWidth:.infinity)
        }
        .padding(EmberUI.padding)
        .foregroundStyle(.primary)
        .modifier(EmberGlassPanel())
        .environment(\.colorScheme,.dark)
    }
}

struct EmberActionStyle: ButtonStyle {
    var prominent = false
    var secondary = false
    var panelGlass = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size:19,weight:prominent ? .bold : .medium,design:.rounded))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(.primary)
            .padding(.horizontal,18).padding(.vertical,12)
            .frame(minWidth:52,minHeight:52)
            .background {
                if panelGlass {
                    Color.clear.modifier(EmberGlassPanel(cornerRadius:EmberUI.controlRadius))
                } else {
                    RoundedRectangle(cornerRadius:EmberUI.controlRadius,style:.continuous)
                        .fill(.regularMaterial)
                        .background(Color.white.opacity(prominent ? 0.13 : 0),in:RoundedRectangle(cornerRadius:EmberUI.controlRadius,style:.continuous))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius:EmberUI.controlRadius,style:.continuous))
            #if os(visionOS)
            .hoverEffect(.highlight)
            .onChange(of:configuration.isPressed) { _, pressed in if pressed { GameAudio.shared.play(.tap) } }
            #endif
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.40)
            .environment(\.colorScheme,.dark)
    }
}

/// A transient tracking frame must not replace the instruction and immediately replace it back.
struct StableInstructionText: View {
    let text: String
    @State private var shown = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(shown.isEmpty ? text : shown)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal:false,vertical:true)
            .frame(maxWidth:.infinity)
            .contentTransition(.opacity)
            .task(id:text) {
                if shown.isEmpty { shown = text; return }
                do { try await Task.sleep(for:.milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) { shown = text }
            }
    }
}

struct EmberScaleTrayCard: View {
    var body: some View {
        VStack(spacing:12) {
            Text("Scales").font(.system(size:26,weight:.bold,design:.rounded)).frame(height:32)
            Color.clear.frame(height:82)
            Text("Pinch to pick up").font(.system(size:15,weight:.medium,design:.rounded)).foregroundStyle(.secondary).frame(height:20)
        }.frame(width:228).padding(24)
         .modifier(EmberGlassPanel()).foregroundStyle(.primary)
         .environment(\.colorScheme,.dark).allowsHitTesting(false)
    }
}

struct EmberInstructionCard: View {
    @Environment(GameModel.self) private var model
    var body: some View {
        EmberPanel(title:model.isLoadingAssets ? "Getting Ember ready…" : (model.stageReady ? "Activity complete" : (model.activePhase == .magicSetup && model.calibrationIsPreparing ? "Getting ready" : model.activePhase.instructionTitle))) {
            VStack(spacing:20) {
            if model.activePhase == .magicSetup {
                HStack {
                    Image(systemName: ["hand.raised.fill","arrow.up.forward","arrow.left","arrow.right","checkmark.circle.fill"][min(model.calibrationStep,4)])
                        .font(.system(size:32,weight:.bold))
                    StableInstructionText(text:model.calibrationMessage).font(.system(size:22,weight:.bold,design:.rounded))
                }
                if !model.calibrationIsPreparing {
                GeometryReader { geometry in
                    ZStack(alignment:.leading) {
                        Capsule().fill(Color(white:0.14))
                        Capsule().fill(Color(red:0.48,green:0.92,blue:0.68))
                            .frame(width:geometry.size.width * CGFloat(min(max(model.calibrationHold,0),1)))
                    }.overlay(Capsule().strokeBorder(.white.opacity(0.72),lineWidth:1))
                }.frame(height:18).animation(.linear(duration:0.08),value:model.calibrationHold)
                 .accessibilityLabel("Hold progress")
                 .accessibilityValue("\(Int(model.calibrationHold*100)) percent")
                Text(model.calibrationIsPreparing ? "We’ll measure your reach in a moment." : (model.calibrationStep == 4 ? "Your reach will set the exercise distances." : "Hold comfortably while the bar fills."))
                    .font(.system(size:16,weight:.medium,design:.rounded))
                HStack(spacing:8) { ForEach(0..<4) { index in Circle().fill(index < model.calibrationStep ? Color(red:0.48,green:0.92,blue:0.68) : Color(white:0.14)).overlay(Circle().strokeBorder(.white.opacity(0.72),lineWidth:1)).frame(width:10,height:10) } }
                }
            } else {
            StableInstructionText(text:model.isLoadingAssets ? "Getting the next activity ready…" : (model.assetLoadError ?? (model.activityHint.isEmpty ? model.activePhase.movementHint : model.activityHint)))
                .id(model.activePhase)
                .font(.system(size:20 * model.textScale,weight:.medium,design:.rounded))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true)
            }
            if model.activePhase == .scales { Text("\(model.scaleDesign.count) placed").font(.system(size:20,weight:.semibold,design:.rounded)) }
            if !model.isLoadingAssets && (model.activePhase == .horns || model.activePhase == .hornAlignment) {
                HStack(spacing:44) {
                    ExerciseRing(title:"Left horn",cue:model.hornLeftCue,progress:model.hornLeftFill)
                    ExerciseRing(title:"Right horn",cue:model.hornRightCue,progress:model.hornRightFill)
                }
            }
            if !model.isLoadingAssets && model.activePhase == .painting {
                ExerciseRing(title:model.paintingRegion,cue:"Brush left ↔ right",progress:model.paintingFill)
            }
            if !model.isLoadingAssets && model.activePhase == .wings {
                HStack(spacing:44) {
                    ExerciseRing(title:"Left wing",cue:model.wingLeftCue,progress:model.wingLeftFill)
                    ExerciseRing(title:"Right wing",cue:model.wingRightCue,progress:model.wingRightFill)
                }
            }
            }
        }
        .frame(width:500)
        .accessibilityElement(children:.combine)
    }
}

struct ExerciseRing: View {
    let title: String
    let cue: String
    let progress: Float
    var body: some View {
        VStack(spacing:16) {
            ZStack {
                Circle().stroke(Color.white,lineWidth:10)
                Circle().trim(from:0,to:CGFloat(min(max(progress,0),1)))
                    .stroke(Color(red:0.20,green:0.65,blue:0.35),style:StrokeStyle(lineWidth:10,lineCap:.round))
                    .rotationEffect(.degrees(-90))
                Image(systemName:progress >= 1 ? "checkmark" : (cue.contains("Turn") ? "arrow.trianglehead.2.clockwise.rotate.90" : (cue == "Open" ? "arrow.up.left.and.arrow.down.right" : "hand.draw")))
                    .font(.system(size:22,weight:.bold))
            }.frame(width:76,height:76).padding(.top,8)
            Text(title).font(.system(size:16,weight:.bold,design:.rounded))
            StableInstructionText(text:cue).font(.system(size:15,weight:.medium,design:.rounded))
        }.accessibilityElement(children:.ignore)
         .accessibilityLabel(title + ". " + cue)
         .accessibilityValue("\(Int(progress*100)) percent")
    }
}
