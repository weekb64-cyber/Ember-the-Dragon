import SwiftUI
import RealityKit
import UIKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GameModel.self) private var gameModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var world: GameWorld?

    var body: some View {
        RealityView { content, attachments in
            let world = GameWorld(model: gameModel)
            self.world = world
            await world.install(in: &content)
            guard !Task.isCancelled else { world.shutdown(); return }
            if let controls = attachments.entity(for: "game-controls") {
                world.installControls(controls)
            }
            if let instructions = attachments.entity(for:"instructions") {
                world.installInstructionCard(instructions)
            }
            if let pause = attachments.entity(for:"pause-menu") { world.installPauseMenu(pause) }
            if let tray = attachments.entity(for:"scale-tray") { world.installScaleTray(tray) }
            self.world = world
        } update: { _, _ in
            world?.synchronize()
        } attachments: {
            Attachment(id: "game-controls") {
                GameControlPanel().environment(gameModel)
            }
            Attachment(id:"pause-menu") { EmberPauseMenu().environment(gameModel) }
            Attachment(id:"scale-tray") { EmberScaleTrayCard() }
            Attachment(id:"instructions") {
                EmberInstructionCard().environment(gameModel).contentShape(Rectangle()).onTapGesture { openCompletedPortrait() }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    world?.handleDrag(entity: value.entity, translation: value.translation,
                        sceneTranslation: value.convert(value.translation3D, from: .local, to: .scene))
                }
                .onEnded { _ in
                    world?.endDrag()
                }
        )
        .simultaneousGesture(
            RotateGesture3D(constrainedToAxis: .z).targetedToAnyEntity()
                .onChanged { value in
                    world?.rotateHorn(entity:value.entity, radians:Float(value.rotation.angle.radians) * Float(value.rotation.axis.z))
                }
                .onEnded { _ in world?.endDrag() }
        )
        .simultaneousGesture(TapGesture().onEnded { openCompletedPortrait() })
        .simultaneousGesture(SpatialTapGesture().targetedToAnyEntity().onEnded { _ in openCompletedPortrait() })
        .onDisappear {
            world?.shutdown()
            world = nil
        }
        .task(id: gameModel.shouldDismissImmersiveSpace) {
            guard gameModel.shouldDismissImmersiveSpace else { return }
            await dismissImmersiveSpace()
            openWindow(id: appModel.launcherWindowID)
            gameModel.immersiveSpaceDismissed()
        }
    }
    private func openCompletedPortrait() {
        guard !gameModel.isPhotoBoothPresented, !gameModel.isPaused, !gameModel.isLoadingAssets,
              gameModel.activePhase == .celebration || gameModel.activePhase == .complete else { return }
        gameModel.preparePhotoBooth()
        openWindow(id:"EmberPhotoBooth")
    }

}

@MainActor
final class GameWorld {
    private let model: GameModel
    private let gameRoot = Entity()
    private let persistentRoot = Entity()
    private let environmentRoot = Entity()
    private let stageRoot = Entity()
    private let effectsRoot = Entity()
    private let attachmentRoot = Entity()
    private var instructionCard: Entity?
    private var controlCard: Entity?
    private var pauseCard: Entity?
    private let moveHandle = ModelEntity()
    private var movingScene = false
    private var userPlacedScene = false
    private var sceneMoveStart = SIMD3<Float>.zero
    private var dragon: DragonController?
    private var scaleTrayCard: Entity?
    private var activeStage: GameStage?
    private var currentPhase: GamePhase?
    private var currentRevision = -1
    private var restartRevision = -1
    private var lastReachReadyState = false
    private var subscriptions: [EventSubscription] = []
    private var draggedEntity: Entity?
    private var dragStart = SIMD3<Float>.zero
    private var gestureConsumed = false
    private var advanceTask: Task<Void, Never>?
    private var lastSessionRevision = -1
    private var loadTask: Task<Void,Never>?
    private var stopped = false
    private var updatePending = false
    private var placedForViewer = false
    private var reachWorldBeforeMove: [SIMD3<Float>] = []
    private var recenterRevision = 0

    init(model: GameModel) {
        self.model = model
    }

    func install(in content: inout RealityViewContent) async {
        gameRoot.name = "SpatialGameRoot"
        persistentRoot.name = "PersistentRoot"
        environmentRoot.name = "EnvironmentRoot"
        stageRoot.name = "StageRoot"
        effectsRoot.name = "EffectsRoot"
        attachmentRoot.name = "AttachmentRoot"
        gameRoot.position = [0, 1.3745, -1.10]
        placedForViewer = ReachTrackingService.shared.isSimulator
        gameRoot.isEnabled = placedForViewer
        ReachTrackingService.shared.start()
        gameRoot.scale = [1, 1, 1]
        persistentRoot.scale = [1, 1, 1]
        environmentRoot.scale = [1, 1, 1]
        stageRoot.scale = [1, 1, 1]
        effectsRoot.scale = [1, 1, 1]
        attachmentRoot.scale = [1, 1, 1]
        environmentRoot.position = model.configuration.layout.nestPosition

        gameRoot.addChild(persistentRoot)
        gameRoot.addChild(environmentRoot)
        gameRoot.addChild(stageRoot)
        gameRoot.addChild(effectsRoot)
        gameRoot.addChild(attachmentRoot)
        content.add(gameRoot)
        installMoveHandle()

        await RenderedStyle.install(on:gameRoot)
        model.isLoadingAssets = true
        do { try await GameAssetLibrary.shared.prepare(AssetResidency.environment, owner:"environment") }
        catch { print("Ember: environment uses lightweight fallbacks: \(error)") }
        guard !stopped, !Task.isCancelled else { shutdown(); return }
        makeEnvironment()
        GameAssetLibrary.shared.release(owner:"environment")
        makeDragon()
        debugLogWorldState()
        synchronize()
        // Readiness is published when assets and a device or Simulator placement are ready.

        subscriptions.append(content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            // At most one queued update; a busy renderer must not accumulate frame tasks.
            guard let self, !self.updatePending else { return }
            self.updatePending = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.updatePending = false }
                self.update(deltaTime: Float(event.deltaTime))
            }
        })
    }

    func installInstructionCard(_ card: Entity) {
        instructionCard = card
        card.position = [-0.43,0.32,0.22]
        card.scale = [0.8,0.8,0.8]
        gameRoot.addChild(card)
    }

    func installControls(_ controls: Entity) {
        controlCard = controls
        controls.position = [0.43,-0.04,0.16]
        controls.scale = [0.85,0.85,0.85]
        gameRoot.addChild(controls)
        layoutChrome()
    }
    func installPauseMenu(_ card: Entity) {
        pauseCard = card; card.scale = [0.85,0.85,0.85]
        gameRoot.addChild(card); layoutChrome()
    }
    func installScaleTray(_ card: Entity) {
        scaleTrayCard = card; card.name = "ScaleSupplyCard"; card.scale = [0.85,0.85,0.85]
        gameRoot.addChild(card); layoutChrome()
    }
    private func installMoveHandle() {
        moveHandle.name = "SceneMoveHandle"
        moveHandle.model = ModelComponent(mesh:.generateBox(size:SceneMoveHandleLayout.size,cornerRadius:0.005),materials:[UnlitMaterial(color:.white)])
        moveHandle.setInteraction(boxSize:SceneMoveHandleLayout.hitSize)
        moveHandle.components.set(HoverEffectComponent())
        gameRoot.addChild(moveHandle)
        layoutChrome()
    }
    private func layoutChrome() {
        let body = dragon?.parts.bodyControl.visualBounds(relativeTo:gameRoot) ?? persistentRoot.visualBounds(relativeTo:gameRoot)
        let layout = SceneChromeLayout(minimum:body.min,maximum:body.max)
        instructionCard?.position = layout.instruction
        controlCard?.position = layout.activity
        if let pauseCard {
            // Attachment origins are centred; place the visible top button, not the hidden menu centre.
            let halfHeight = pauseCard.visualBounds(relativeTo:gameRoot).extents.y/2
            pauseCard.position = layout.pause + [0,model.activePhase == .scales ? 0.04 : 0,0] - [0,max(0,halfHeight-0.025),0]
        }
        if let nest = environmentRoot.findEntity(named:"LightweightMossNest") {
            let nestBounds = nest.visualBounds(relativeTo:gameRoot)
            let gardenBounds = environmentRoot.visualBounds(relativeTo:gameRoot)
            moveHandle.position = SceneMoveHandleLayout.position(nestMinimum:nestBounds.min,
                nestMaximum:nestBounds.max,gardenFront:max(gardenBounds.max.z,body.max.z))
            moveHandle.isEnabled = true
        } else {
            // Wait for the nest's real bounds instead of showing a handle at an arbitrary origin.
            moveHandle.isEnabled = false
        }
        if let card = scaleTrayCard {
            card.position = layout.scaleSupply
            card.isEnabled = model.activePhase == .scales && !model.isPaused
        }
    }
    private func placeForViewer() {
        guard let placement = EmberViewerPlacement.resolve(head:ReachTrackingService.shared.headTransform(),
            isSimulator:ReachTrackingService.shared.isSimulator,characterCenter:model.configuration.layout.dragonCenterPosition) else { return }
        // Only heading follows the wearer. The nest remains level with gravity.
        let savedReach = model.reachSamples.map { gameRoot.convert(position:$0,to:nil) }
        gameRoot.orientation = placement.orientation
        gameRoot.position = placement.position
        gameRoot.scale = SIMD3(repeating:placement.scale)
        gameRoot.isEnabled = true
        placedForViewer = true
        preserveReachAfterMoving(savedReach)
    }
    func shutdown() {
        ReachTrackingService.shared.stop()
        stopped = true
        loadTask?.cancel(); loadTask = nil
        advanceTask?.cancel()
        subscriptions.removeAll()
        activeStage?.cleanup()
        activeStage = nil
        dragon?.releaseVisuals(); dragon = nil
        gameRoot.removeAllChildren(); gameRoot.removeFromParent()
        GameAssetLibrary.shared.release(owner:"gameplay")
        GameAssetLibrary.shared.release(owner:"environment")
        PebblePaintTextures.clearCache()
        model.isLoadingAssets = false
        model.isSceneReady = false
        logEmberMemory("scene released")
    }

    func synchronize() {
        gameRoot.isEnabled = placedForViewer && !model.isPhotoBoothPresented
        scaleTrayCard?.isEnabled = model.activePhase == .scales && !model.isPaused
        guard !stopped, currentRevision != model.phaseRevision || restartRevision != model.restartRevision else { return }
        currentRevision = model.phaseRevision
        restartRevision = model.restartRevision
        let phase = model.currentPhase
        if phase == .paused { (activeStage as? PaintingStage)?.endDrag() }
        if phase == .paused || (currentPhase == .paused && phase == model.previousPhaseBeforePause && activeStage != nil && !model.isRestartingStage && lastSessionRevision == model.sessionRevision) {
            configure(phase:phase)
            return
        }
        let waking = currentPhase == .introduction && phase == .magicSetup
        loadTask?.cancel(); advanceTask?.cancel(); cancelDrag()
        activeStage?.cleanup(); activeStage = nil
        stageRoot.removeAllChildren(); effectsRoot.removeAllChildren()
        if !waking { dragon?.releaseVisuals(); dragon?.root.components.set(OpacityComponent(opacity:1)) }
        PebblePaintTextures.clearCache()
        model.isLoadingAssets = true; model.assetLoadError = nil
        let revision = model.phaseRevision
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if waking {
                    try await self.fadeDragon(to:0,duration:0.30)
                    self.dragon?.releaseVisuals()
                }
                try await GameAssetLibrary.shared.prepare(AssetResidency.assets(for:phase),owner:"gameplay")
                try Task.checkCancellation()
                guard !self.stopped, self.model.phaseRevision == revision else { return }
                self.dragon?.refreshAttachments()
                self.configure(phase:phase)
                if !self.placedForViewer { self.placeForViewer() }
                self.model.isLoadingAssets = false
                self.model.scenePrepared(placedForViewer:self.placedForViewer)
                if waking { try await self.fadeDragon(to:1,duration:0.85) }
                print("Ember assets: ready for \(phase.rawValue)")
                logEmberMemory("stage " + phase.rawValue)
            } catch is CancellationError { }
            catch {
                guard !self.stopped, self.model.phaseRevision == revision else { return }
                self.model.isLoadingAssets = false
                self.model.assetLoadError = "Could not load Ember’s next activity. Please retry."
                print("Ember asset load failed: \(error)")
            }
        }
    }

    private func fadeDragon(to target: Float, duration: Double) async throws {
        guard let subject = dragon?.root else { return }
        let initial = subject.components[OpacityComponent.self]?.opacity ?? 1
        for step in 1...24 {
            try Task.checkCancellation()
            let t = Float(step)/24
            subject.components.set(OpacityComponent(opacity:initial+(target-initial)*(t*t*(3-2*t))))
            try await Task.sleep(for:.seconds(duration/24))
        }
    }

    func handleDrag(entity: Entity, translation: CGSize, sceneTranslation: SIMD3<Float>) {
        guard !model.isPhotoBoothPresented else { return }
        if movingScene || entity === moveHandle || entity.isDescendant(of:moveHandle) {
            if !movingScene {
                reachWorldBeforeMove = model.reachSamples.map { gameRoot.convert(position:$0,to:nil) }
                cancelDrag(); movingScene = true; userPlacedScene = true; sceneMoveStart = gameRoot.position
                placedForViewer = true
            }
            if [sceneTranslation.x,sceneTranslation.y,sceneTranslation.z].allSatisfy({ $0.isFinite }) {
                gameRoot.position = sceneMoveStart + sceneTranslation
            }
            return
        }
        // A targeted gesture stays owned by its initial entity until release.
        // Buttons act once, even if their action replaces the entire stage.
        guard !model.isPhotoBoothPresented, !gestureConsumed, !model.isPaused, !model.isLoadingAssets, model.assetLoadError == nil else { return }
        if draggedEntity == nil {
            if let painting = activeStage as? PaintingStage, painting.handleAction(entity: entity) {
                gestureConsumed = true
                return
            }
            if handleSpatialControl(entity) {
                gestureConsumed = true
                return
            }
            guard !model.isPaused else { return }
            var owner: Entity? = entity
            while let candidate = owner, candidate.components[InputTargetComponent.self] == nil {
                owner = candidate.parent
            }
            guard let owner, owner.isEnabledInHierarchy else { return }
            draggedEntity = owner
            dragStart = owner.position
            owner.stopAllAnimations(recursive: false)
            #if DEBUG
            print("Ember input: begin \(owner.name), phase \(model.currentPhase.rawValue)")
            #endif
        }
        guard let owner = draggedEntity, owner.isEnabledInHierarchy, !model.isPaused else { return }
        if model.currentPhase == .complete {
            gestureConsumed = true
            activeStage?.handleDrag(entity: owner, translation: translation)
            return
        }
        let delta = owner.parent?.convert(direction: sceneTranslation, from: nil) ?? sceneTranslation
        if let painting = activeStage as? PaintingStage {
            painting.drag(entity: owner, start: dragStart, delta: delta)
        } else if let scales = activeStage as? ScaleStage {
            scales.drag(entity: owner, start: dragStart, delta: delta, translation: translation)
        } else if let wings = activeStage as? WingStage {
            wings.drag(entity: owner, displacement: delta)
        } else if model.currentPhase == .hornAlignment {
            activeStage?.handleDrag(entity: owner, translation: translation)
        } else {
            let candidate = dragStart + delta
            if candidate.x.isFinite && candidate.y.isFinite && candidate.z.isFinite {
                owner.position = candidate
                activeStage?.handleDrag(entity: owner, translation: translation)
                (activeStage as? PaintingStage)?.setBrushHeld(true)
            }
        }
    }

    func rotateHorn(entity: Entity, radians: Float) {
        guard !model.isPaused, !model.isLoadingAssets else { return }
        (activeStage as? HornAlignmentStage)?.rotate(entity:entity,radians:radians)
    }
    func endDrag() {
        if movingScene {
            movingScene = false
            preserveReachAfterMoving(reachWorldBeforeMove)
            reachWorldBeforeMove = []
            (activeStage as? ReachCalibrationStage)?.resetAfterSceneMove()
            (activeStage as? WingStage)?.resetPosition()
            (activeStage as? HornAlignmentStage)?.resetGrip()
            activeStage?.endDrag()
            gestureConsumed = false
            return
        }
        if let entity = draggedEntity {
            activeStage?.release(entity: entity)
            #if DEBUG
            print("Ember input: release \(entity.name)")
            #endif
        }
        activeStage?.endDrag()
        draggedEntity = nil
        gestureConsumed = false
    }

    private func preserveReachAfterMoving(_ worldPoints: [SIMD3<Float>]) {
        guard worldPoints.count == 7 else { return }
        // The user's measured space stays in the room when Ember is moved.
        model.reachSamples = worldPoints.map { gameRoot.convert(position:$0,from:nil) }
        if model.activePhase == .horns { model.restartCurrentStage() }
        (activeStage as? WingStage)?.resetPosition()
        (activeStage as? HornAlignmentStage)?.resetGrip()
    }

    private func cancelDrag() {
        activeStage?.endDrag()
        // Preserve suppression only while an actual gesture is in flight.
        gestureConsumed = gestureConsumed || draggedEntity != nil
        draggedEntity = nil
    }

    private func update(deltaTime: Float) {
        if recenterRevision != model.recenterRevision { recenterRevision = model.recenterRevision; placedForViewer = false; userPlacedScene = false }
        if !placedForViewer { placeForViewer() }
        synchronize()
        model.scenePrepared(placedForViewer:placedForViewer)
        if GameAudio.shared.isEnabled != model.soundEffectsEnabled { GameAudio.shared.isEnabled = model.soundEffectsEnabled }
        guard !model.isPhotoBoothPresented, !movingScene, !stopped, !model.isLoadingAssets, model.assetLoadError == nil, !model.isPaused, model.currentPhase != .paused else { return }
        updateReachReadyControlsIfNeeded()
        dragon?.update(deltaTime: deltaTime)
        let ready = model.stageReady || (model.currentPhase == .painting && model.paintingComplete)
        activeStage?.update(deltaTime: deltaTime)
        if !ready && (model.stageReady || (model.currentPhase == .painting && model.paintingComplete)) { GameAudio.shared.play(.complete) }
    }

    private func configure(phase: GamePhase) {
        advanceTask?.cancel()
        cancelDrag()
        if phase == .paused {
            instructionCard?.isEnabled = false
            currentPhase = .paused
            attachmentRoot.removeAllChildren()
            showPauseControls()
            return
        }

        // Resume the existing stage, including its partially completed work.
        if currentPhase == .paused, phase == model.previousPhaseBeforePause,
           activeStage != nil,
           lastSessionRevision == model.sessionRevision, !model.isRestartingStage {
            currentPhase = phase
            showInstruction(phase.instructionTitle, subtitle: nil, duration: 0)
            showPersistentSpatialControls(for: phase)
            return
        }
        model.isRestartingStage = false
        currentPhase = phase
        activeStage?.cleanup()
        activeStage = nil
        stageRoot.removeAllChildren()
        effectsRoot.removeAllChildren()
        attachmentRoot.removeAllChildren()

        guard let dragon else { return }
        assertDragonPersistence()
        if lastSessionRevision != model.sessionRevision {
            lastSessionRevision = model.sessionRevision
            if !model.hasCompletedSetupThisSession {
                if !movingScene && !userPlacedScene { placedForViewer = false }
            }
            dragon.resetSession()
        }
        // Calibration changes exercise targets, never the character's presentation scale.
        let center = model.configuration.layout.dragonCenterPosition
        persistentRoot.scale = SIMD3(repeating:model.sceneSize)
        persistentRoot.position = center * (1-model.sceneSize)
        environmentRoot.scale = SIMD3(repeating:model.sceneSize)
        environmentRoot.position = center + (model.configuration.layout.nestPosition-center)*model.sceneSize
        prepareAppearance(for: phase)
        layoutChrome()
        // Restore only presentation; never reset earned parts at a boundary.
        dragon.restore(at: model.configuration.layout.dragonCenterPosition)

        switch phase {
        case .introduction:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            dragon.setHornsVisible(false)
            dragon.setWingsVisible(false)
            showInstruction("Meet Ember", subtitle: "Help Ember get ready to fly.", duration: 2.8)
            // Continue is explicit so the sleeping introduction can be seen.
            showPersistentSpatialControls(for: phase)
        case .magicSetup:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            lastReachReadyState = model.isReachSetupReady
            start(ReachCalibrationStage(root: stageRoot, model: model))
        case .bilateralSetup:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            start(BilateralSetupStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .precisionSetup:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            start(PrecisionSetupStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .horns:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            start(HornStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .wings:
            dragon.fly(to: model.configuration.layout.dragonCenterPosition)
            start(WingStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .scales:
            dragon.fly(to: model.configuration.layout.dragonCenterPosition)
            start(ScaleStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .hornAlignment:
            dragon.fly(to: model.configuration.layout.dragonCenterPosition)
            start(HornAlignmentStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .painting:
            dragon.fly(to: model.configuration.layout.dragonCenterPosition)
            start(PaintingStage(root: stageRoot, model: model, dragon: dragon))
        case .celebration:
            dragon.fly(to: model.configuration.layout.dragonCenterPosition)
            dragon.celebrate(effectsRoot: effectsRoot)
            showInstruction("You did it!", subtitle: "Ember is ready to fly.", duration: 4.2)
            scheduleAdvance(from: .celebration, after: 5.0)
        case .complete:
            dragon.restore(at: model.configuration.layout.dragonCenterPosition)
            start(CompletionStage(root: stageRoot, effectsRoot: effectsRoot, model: model, dragon: dragon))
        case .paused:
            break
        }
    }

    private func start(_ stage: GameStage) {
        activeStage = stage
        showInstruction(stage.instruction, subtitle: nil, duration: 3.4)
        stage.start()
        showPersistentSpatialControls(for: model.currentPhase)
    }

    private func scheduleAdvance(from phase: GamePhase, after delay: TimeInterval) {
        let revision = model.phaseRevision
        advanceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            guard self.model.currentPhase == phase, self.model.phaseRevision == revision, !self.model.isPaused else { return }
            self.model.advanceSetupOrStage()
        }
    }

    private func showInstruction(_ title: String, subtitle: String? = nil, duration: TimeInterval) {
        instructionCard?.isEnabled = !model.isPaused
    }

    private func showPersistentSpatialControls(for phase: GamePhase) {}
    private func updateReachReadyControlsIfNeeded() {}
    private func showPauseControls() {}
    private func handleSpatialControl(_ entity: Entity) -> Bool { false }

    private func prepareAppearance(for phase: GamePhase) {
        guard let dragon else { return }
        let order = GameModel.playablePhases.firstIndex(of: phase) ?? 0
        dragon.setForm(PebbleForm.forPhase(phase))
        dragon.resetHorns(finished:PebbleHornFit.finishedPose(for:phase))
        for (index,socket) in dragon.parts.scaleSockets.enumerated() {
            socket.position = ScaleDesignLayout.position(index,complete:order >= 7)
            socket.orientation = simd_quatf(from:[0,0,1],to:ScaleDesignLayout.normal(index,complete:order >= 7))
        }
        if order < 6 {
            model.appliedPaint = nil
            dragon.applyPaint(nil)
        } else { dragon.applyPaint(model.appliedPaint); if !model.regionPaint.isEmpty { dragon.applyRegionalPaint(model.regionPaint) } }
        dragon.setHornsVisible(order >= 3 && order < 7)
        dragon.setWingsVisible(order >= 3 && order < 7)
        if order < 4 { dragon.removeAttachedScales() }
        if order >= 5 {
            dragon.removeAttachedScales()
            for item in model.scaleDesign {
                dragon.addDecoration(item)
            }
        }
    }

    private func makeDragon() {
        let dragon = DragonFactory.makeDragon()
        dragon.root.position = model.configuration.layout.dragonCenterPosition
        persistentRoot.addChild(dragon.root)
        self.dragon = DragonController(parts: dragon)
    }

    private func makeEnvironment() {
        let clearingRoot = Entity()
        clearingRoot.name = "MagicalClearingRoot"
        clearingRoot.position = .zero
        environmentRoot.addChild(clearingRoot)

        let nestDropTarget = Entity()
        nestDropTarget.name = "EmberNestDropTarget"
        nestDropTarget.position = [0, 0, 0.08]
        let nest = makeLightweightNest()
        nest.position = [0,-0.025,0.04]
        nestDropTarget.addChild(nest)
        clearingRoot.addChild(nestDropTarget)

        let props: [(String,String,Float,SIMD2<Float>)] = [
            ("BushVisual","BushFrontLeft",0.18,[-0.23,0.25]),
            ("BushVisual","BushBackRight",0.18,[0.27,-0.18]),
            ("RockVisual","RockBackLeft",0.17,[-0.27,-0.21]),
            ("RockVisual","RockFrontRight",0.17,[0.23,0.26]),
            ("RockVisual","RockBack",0.15,[0,-0.33]),
            ("MushroomVisual","MushroomLeft",0.11,[-0.35,0.025]),
            ("MushroomVisual","MushroomRight",0.10,[0.35,0.035])
        ]
        for (asset,name,size,position) in props {
            let wrapper = Entity(); wrapper.name = name
            let variation = Float.random(in:0.9...1.18)
            let target: AssetTarget = asset == "RockVisual" ? .largest(size*variation) : .height(size*variation)
            wrapper.orientation = simd_quatf(angle:Float.random(in:-0.45...0.45),axis:[0,1,0])
            guard let visual = GameAssetLibrary.shared.cloneVisual(named:asset,target:target,canonicalName:asset) else { continue }
            visual.clearGameplayComponentsRecursively(); wrapper.addChild(visual); clearingRoot.addChild(wrapper)
            let bounds = wrapper.visualBounds(relativeTo:clearingRoot)
            let radius = simd_length(SIMD2<Float>(bounds.extents.x,bounds.extents.z))/2
            let anchor = nestDecorationPosition(position,footprint:radius)
            let height = 0.0334*sqrt(max(0,1-simd_length_squared(anchor)/(0.445*0.445)))
            // The moss disk is centred at Z .12. Ground each model by its actual lowest vertex bounds.
            wrapper.position = [anchor.x,height-0.025-bounds.min.y,anchor.y+0.12]
        }
    }

    private func assertDragonPersistence() {
        #if DEBUG
        guard let dragon else { return }
        if dragon.root.parent !== persistentRoot {
            print("Ember persistence warning: DragonRoot parent is not PersistentRoot")
        }
        if !dragon.root.isEnabled || !dragon.root.position.x.isFinite || !dragon.root.position.y.isFinite || !dragon.root.position.z.isFinite {
            print("Ember persistence warning: invalid DragonRoot state")
        }
        #endif
    }

    private func debugLogWorldState() {
        #if DEBUG
        print("Ember spatial presentation: no RealityKit backdrop/panel is created; active gameplay uses SpatialGameRoot in mixed ImmersiveSpace.")
        print("SpatialGameRoot position \(gameRoot.position(relativeTo: nil)), local scale \(gameRoot.scale)")
        print("EnvironmentRoot world position \(environmentRoot.position(relativeTo: nil)), local scale \(environmentRoot.scale)")
        if let dragon {
            print("DragonRoot world position \(dragon.root.position(relativeTo: nil)), local scale \(dragon.root.scale)")
            print("DragonRoot world bounds \(dragon.root.visualBounds(relativeTo: nil).extents)")
            print("LeftWingControl local \(dragon.parts.leftWingControl.position), RightWingControl local \(dragon.parts.rightWingControl.position)")
            print("LeftHornSocket local \(dragon.parts.leftHornSocket.position), RightHornSocket local \(dragon.parts.rightHornSocket.position)")
        }
        #endif
    }
}

protocol GameStage: AnyObject {
    var instruction: String { get }
    func start()
    func update(deltaTime: Float)
    func handleDrag(entity: Entity, translation: CGSize)
    func endDrag()
    func release(entity: Entity)
    func cleanup()
}

extension GameStage {
    func handleDrag(entity: Entity, translation: CGSize) {}
    func endDrag() {}
    func release(entity: Entity) {}
}

enum WingSide {
    case left
    case right
}

enum HornSide {
    case left
    case right
}

struct DragonParts {
    let root: Entity
    let bodyControl: Entity
    let leftWingControl: ModelEntity
    let rightWingControl: ModelEntity
    let leftHornSocket: Entity
    let rightHornSocket: Entity
    let leftHornControl: ModelEntity
    let rightHornControl: ModelEntity
    let scaleSockets: [Entity]
}

@MainActor
final class DragonController {
    let parts: DragonParts
    private var idleTime: Float = 0
    private var basePosition: SIMD3<Float>
    private let bodyBottomLocalY: Float
    private let leftWingClosed: Transform
    private let rightWingClosed: Transform
    private var hornFinish: Float = 0
    private var displayedBody = ""
    private var form: PebbleForm = .repair
    private var appliedColour: PaintChoice?

    var root: Entity { parts.root }

    init(parts: DragonParts) {
        self.parts = parts
        self.basePosition = parts.root.position
        self.bodyBottomLocalY = -0.31
        self.leftWingClosed = parts.leftWingControl.transform
        self.rightWingClosed = parts.rightWingControl.transform
    }

    func update(deltaTime: Float) {
        idleTime += deltaTime
        let cycle = (sin(idleTime * 1.05 - .pi / 2) + 1) * 0.5
        let easedBreath = cycle * cycle * (3 - 2 * cycle)
        let subtlePause = 0.12 * max(0, sin(idleTime * 2.1 + 0.7))
        let breathScale = 1 + (easedBreath * 2 - 1) * 0.008 + subtlePause * 0.006
        parts.bodyControl.scale = [1, breathScale, 1]
        parts.bodyControl.position.y = bodyBottomLocalY * (1 - breathScale)
        syncHornSockets()
    }

    func restore(at position: SIMD3<Float>) {
        basePosition = position
        parts.root.stopAllAnimations(recursive: false)
        parts.root.isEnabled = true
        parts.root.position = position
        parts.root.orientation = simd_quatf(angle:0,axis:[0,1,0])
        parts.root.scale = [1, 1, 1]
    }

    func releaseVisuals() {
        parts.bodyControl.removeAllChildren()
        for control in [parts.leftWingControl,parts.rightWingControl,parts.leftHornControl,parts.rightHornControl] {
            control.removeAllChildren()
            control.disableInteractionRecursively()
        }
        removeAttachedScales()
        displayedBody = ""
        appliedColour = nil
    }

    func refreshAttachments() {
        for (index,wing) in [parts.leftWingControl,parts.rightWingControl].enumerated() {
            wing.removeAllChildren()
            DragonFactory.addWingVisual(to:wing,side:index == 0 ? .left : .right)
        }
        for (index,horn) in [parts.leftHornControl,parts.rightHornControl].enumerated() {
            horn.removeAllChildren()
            if GameAssetLibrary.shared.contains("HornVisual") {
                DragonFactory.addVisual("HornVisual",target:.largest(AssetScaleConfiguration.current.hornLength),name:"HornVisual",to:horn,offset:.zero,mirrorX:index == 1,material:nil)
            }
        }
    }

    func resetSession() {
        root.stopAllAnimations(recursive: true)
        setHornsVisible(false)
        setWingsVisible(false)
        resetWings()
        resetHorns()
        removeAttachedScales()
        for wing in [parts.leftWingControl,parts.rightWingControl] {
            wing.removeAllChildren()
            DragonFactory.addWingVisual(to:wing,side:wing === parts.leftWingControl ? .left : .right)
        }
        appliedColour = nil
        form = .repair
        displayedBody = ""
        updateBodyVisual()
    }

    func fly(to position: SIMD3<Float>) {
        // Static asset: retain a stable position through activity changes.
        restore(at: position)
    }

    func setForm(_ value: PebbleForm) {
        form = value
        updateBodyVisual()
    }

    func applyRegionalPaint(_ regions: [PaintRegion:PaintChoice]) {
        RegionalPaintTextures.apply(to:parts.bodyControl,asset:form.assetName,regions:regions)
        if form == .repair {
            RegionalPaintTextures.apply(to:parts.leftWingControl,asset:"WingVisual",regions:regions,wing:.leftWing)
            RegionalPaintTextures.apply(to:parts.rightWingControl,asset:"WingVisual",regions:regions,wing:.rightWing)
        }
    }
    func applyPaint(_ colour: PaintChoice?) {
        guard appliedColour != colour || displayedBody.isEmpty else { return }
        appliedColour = colour
        updateBodyVisual()
        for wing in [parts.leftWingControl,parts.rightWingControl] {
            if let colour { PebblePaintTextures.apply(to:wing,asset:"WingVisual",colour:colour) }
            else {
                wing.removeAllChildren()
                DragonFactory.addWingVisual(to:wing,side:wing === parts.leftWingControl ? .left : .right)
            }
        }
        // Pattern scales stay pearl grey so their shapes remain visible against the chosen coat.
    }

    private func updateBodyVisual() {
        let key = form.assetName + (appliedColour?.assetSuffix ?? "Original")
        guard key != displayedBody else { return }
        guard let visual = GameAssetLibrary.shared.cloneVisual(named:form.assetName,target:form.target,canonicalName:"EmberBodyVisual") else { return }
        visual.position = form.offset
        if form == .sleeping {
            let bounds = visual.visualBounds(relativeTo:nil)
            visual.position.y += -0.31-bounds.min.y
        }
        if let colour = appliedColour, form != .sleeping {
            PebblePaintTextures.apply(to:visual,asset:form.assetName,colour:colour)
        }
        parts.bodyControl.removeAllChildren()
        parts.bodyControl.addChild(visual)
        displayedBody = key
    }

    func setHornFinish(_ amount: Float) {
        hornFinish = min(1,max(0,amount)); syncHornSockets()
    }
    func resetHorns(finished: Bool = false) {
        hornFinish = finished ? 1 : 0
        // A phase change or skip installs a complete attachment pose, independent of previous manipulation.
        for (horn,socket) in [(parts.leftHornControl,parts.leftHornSocket),(parts.rightHornControl,parts.rightHornSocket)] {
            horn.stopAllAnimations(recursive:true)
            if horn.parent !== socket { socket.addChild(horn) }
            horn.transform = Transform()
        }
        syncHornSockets()
    }

    private func syncHornSockets() {
        for (index,socket) in [parts.leftHornSocket,parts.rightHornSocket].enumerated() {
            socket.orientation = PebbleHornFit.poseOrientation(left:index == 0,finish:hornFinish)
            socket.scale = parts.bodyControl.scale
            socket.position = PebbleHornFit.breathingPosition(left:index == 0,scale:parts.bodyControl.scale,offset:parts.bodyControl.position,finish:hornFinish)
        }
    }

    func setHornsVisible(_ visible: Bool) {
        parts.leftHornSocket.isEnabled = true
        parts.rightHornSocket.isEnabled = true
        parts.leftHornControl.isEnabled = visible
        parts.rightHornControl.isEnabled = visible
    }

    func setWingsVisible(_ visible: Bool) {
        parts.leftWingControl.isEnabled = visible
        parts.rightWingControl.isEnabled = visible
    }

    func setHornVisible(_ side: HornSide, visible: Bool) {
        hornControl(side).isEnabled = visible
    }

    func hornControl(_ side: HornSide) -> ModelEntity {
        side == .left ? parts.leftHornControl : parts.rightHornControl
    }

    func hornSocket(_ side: HornSide) -> Entity {
        side == .left ? parts.leftHornSocket : parts.rightHornSocket
    }

    func resetWings() {
        parts.leftWingControl.transform = leftWingClosed
        parts.rightWingControl.transform = rightWingClosed
    }

    func setWingOpen(side: WingSide, progress: Float) {
        let amount = clamped(progress)
        let direction: Float = side == .left ? -1 : 1
        let wing = side == .left ? parts.leftWingControl : parts.rightWingControl
        let closed = side == .left ? leftWingClosed : rightWingClosed
        wing.position = closed.translation
        wing.orientation = closed.rotation * simd_quatf(angle: degreesToRadians(direction * amount * 36), axis: [0, 0, 1])
        wing.scale = closed.scale
    }

    func addDecoration(_ item: ScaleDecoration) {
        let scale = makePatternScale(item)
        scale.name = String(format:"AttachedScale%02d",item.slot+1)
        scale.position = item.position(complete:form == .complete)
        scale.orientation = simd_quatf(from:[0,0,1],to:item.normal(complete:form == .complete))
        parts.root.addChild(scale)
    }
    func removeAttachedScales() {
        for child in parts.root.children where child.name.hasPrefix("AttachedScale") {
            child.removeFromParent()
        }
    }

    func addAttachedScale(from loose: Entity, at socket: Entity, index: Int) {
        let attached = loose.clone(recursive: true)
        attached.name = String(format: "AttachedScale%02d", index + 1)
        attached.disableInteractionRecursively()
        attached.position = socket.position(relativeTo: parts.root)
        attached.orientation = socket.orientation(relativeTo: parts.root)
        attached.scale = loose.scale
        parts.root.addChild(attached)
    }

    func happyBounce() {
        idleTime = 0
    }

    func wingFlutter(side: WingSide? = nil) {
        // Keep the attachment pivots fixed; stage progress owns wing pose.
    }

    func celebrate(effectsRoot: Entity) {
        happyBounce()
        burst(at: parts.root.position(relativeTo: effectsRoot) + [0, 0.28, 0], in: effectsRoot, count: 10)
    }

}

enum DragonFactory {
    @MainActor
    static func makeDragon() -> DragonParts {
        let root = Entity()
        root.name = "DragonRoot"

        let bodyControl = Entity()
        bodyControl.name = "EmberBodyControl"
        root.addChild(bodyControl)

        let leftWing = controlModel("LeftWingControl", position: [-0.085, -0.005, -0.035])
        addWingVisual(to: leftWing, side: .left)
        root.addChild(leftWing)
        let rightWing = controlModel("RightWingControl", position: [0.085, -0.005, -0.035])
        addWingVisual(to: rightWing, side: .right)
        root.addChild(rightWing)

        let leftHornSocket = socket("LeftHornSocket", position: PebbleHornFit.socketPosition(left:true), parent: root)
        let rightHornSocket = socket("RightHornSocket", position: PebbleHornFit.socketPosition(left:false), parent: root)
        let leftHorn = controlModel("LeftHornControl", position: .zero)
        addVisual("HornVisual", target: .largest(AssetScaleConfiguration.current.hornLength), name: "LeftHornVisual", to: leftHorn, offset: .zero, material: nil)
        leftHornSocket.addChild(leftHorn)
        let rightHorn = controlModel("RightHornControl", position: .zero)
        addVisual("HornVisual", target: .largest(AssetScaleConfiguration.current.hornLength), name: "RightHornVisual", to: rightHorn, offset: .zero, mirrorX: true, material: nil)
        rightHornSocket.addChild(rightHorn)

        let scalePositions = (0..<ScaleDesignLayout.slotCount).map { ScaleDesignLayout.position($0) }
        let scaleSockets = scalePositions.enumerated().map { index, position in
            let result = socket(String(format: "ScaleSocket%02d", index + 1), position: position, parent: root)
            result.orientation = simd_quatf(from:[0,0,1],to:ScaleDesignLayout.normal(index))
            result.scale = [0.55,0.55,0.55]
            return result
        }

        leftWing.isEnabled = false
        rightWing.isEnabled = false
        leftHorn.isEnabled = false
        rightHorn.isEnabled = false
        leftHornSocket.isEnabled = true
        rightHornSocket.isEnabled = true
        return DragonParts(root: root, bodyControl: bodyControl, leftWingControl: leftWing, rightWingControl: rightWing, leftHornSocket: leftHornSocket, rightHornSocket: rightHornSocket, leftHornControl: leftHorn, rightHornControl: rightHorn, scaleSockets: scaleSockets)
    }

    @MainActor
    static func addWingVisual(to control: Entity, side: WingSide) {
        guard let visual = GameAssetLibrary.shared.cloneVisual(named: "WingVisual", target: .largest(AssetScaleConfiguration.current.wingLength), canonicalName: "WingVisual") else { return }
        let mirror = Entity()
        mirror.scale.x = side == .right ? -1 : 1
        // New wing's shoulder is at MAXIMUM X; its membrane extends towards -X.
        visual.position = [-0.132,0.023,-0.0004]
        mirror.addChild(visual)
        control.addChild(mirror)
    }

    @MainActor
    static func controlModel(_ name: String, position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.004), materials: [EmberMaterials.invisible])
        entity.name = name
        entity.position = position
        return entity
    }

    @MainActor
    static func socket(_ name: String, position: SIMD3<Float>, parent: Entity) -> Entity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [name.contains("Horn") ? EmberMaterials.invisible : EmberMaterials.socketGlow])
        entity.name = name
        entity.position = position
        entity.isEnabled = false
        parent.addChild(entity)
        return entity
    }

    @MainActor
    static func addVisual(_ asset: String, target: AssetTarget, name: String, to parent: Entity, offset: SIMD3<Float>, mirrorX: Bool = false, material: SimpleMaterial? = nil) {
        if let visual = GameAssetLibrary.shared.cloneVisual(named: asset, target: target, canonicalName: name) {
            if let material {
                visual.applyMaterialRecursively(material)
            }
            let mirrorWrapper = Entity()
            mirrorWrapper.name = "\(name)MirrorWrapper"
            mirrorWrapper.scale = [mirrorX ? -1 : 1, 1, 1]
            visual.position = offset
            if asset == "HornVisual" {
                // Anchor the measured centre of the flat cap, shared by attached, loose and ghost horns.
                visual.orientation = PebbleHornFit.orientation
                visual.position = offset - simd_act(PebbleHornFit.orientation,PebbleHornFit.baseCenter)
            }
            mirrorWrapper.addChild(visual)
            parent.addChild(mirrorWrapper)
        }
    }
}

final class BilateralSetupStage: GameStage {
    let instruction = "Move the two lights apart as far as feels comfortable."
    private let root: Entity
    private let effectsRoot: Entity
    private let model: GameModel
    private let dragon: DragonController
    private var wisps: [ModelEntity] = []

    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) {
        self.root = root
        self.effectsRoot = effectsRoot
        self.model = model
        self.dragon = dragon
    }

    func start() {
        for (name, x) in [("LeftWingWisp", Float(-0.18)), ("RightWingWisp", Float(0.18))] {
            let wisp = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [EmberMaterials.sparkFallback])
            wisp.name = name
            wisp.position = [x, 0.1, -model.configuration.layout.sparkDepth]
            wisp.setInteraction(radius: 0.13)
            root.addChild(wisp)
            wisps.append(wisp)
        }
    }

    func update(deltaTime: Float) {
        guard wisps.count == 2 else { return }
        model.recordBilateralSpan(abs(wisps[1].position(relativeTo: nil).x - wisps[0].position(relativeTo: nil).x))
    }

    func cleanup() {
        root.removeAllChildren()
        wisps.removeAll()
    }
}

final class PrecisionSetupStage: GameStage {
    let instruction = "Place Ember's first magic scale."
    private let root: Entity
    private let effectsRoot: Entity
    private let model: GameModel
    private let dragon: DragonController
    private var gem: ModelEntity?

    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) {
        self.root = root
        self.effectsRoot = effectsRoot
        self.model = model
        self.dragon = dragon
    }

    func start() {
        let gem = makeScale(name: "SetupScale", material: EmberMaterials.grey)
        gem.position = [-0.22, -0.08, -model.configuration.layout.objectDepth]
        gem.setInteraction(radius: 0.13)
        root.addChild(gem)
        self.gem = gem
        dragon.parts.scaleSockets.first?.isEnabled = true
    }

    func update(deltaTime: Float) {
        guard let gem, let socket = dragon.parts.scaleSockets.first else { return }
        if distance(gem.position(relativeTo: nil), socket.position(relativeTo: nil)) < 0.28 {
            model.recordFineMotorSuccess()
            gem.isEnabled = false
            socket.isEnabled = false
            burst(at: socket.position(relativeTo: root), in: root, count: 5)
        } else if distance(gem.position, [-0.22, -0.08, -model.configuration.layout.objectDepth]) > model.configuration.objectResetDistance {
            model.markFineMotorNeedsHelp()
            gem.position = [-0.22, -0.08, -model.configuration.layout.objectDepth]
        }
    }

    func cleanup() {
        root.removeAllChildren()
        dragon.parts.scaleSockets.forEach { $0.isEnabled = false }
    }
}

final class HornStage: GameStage {
    let instruction = "Reattach Ember's horns!"
    private struct HornItem {
        let side: HornSide
        let entity: ModelEntity
        let hint: Entity
        let ghost: Entity
        let hand: Entity
        let startPosition: SIMD3<Float>
        var attached = false
        var socketHold: Float = 0
        var route: RouteProgress
    }

    private let root: Entity
    private let effectsRoot: Entity
    private let model: GameModel
    private let dragon: DragonController
    private var horns: [HornItem] = []
    private var guideTime: Float = 0
    private var heldHorn: Entity?

    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) {
        self.root = root
        self.effectsRoot = effectsRoot
        self.model = model
        self.dragon = dragon
    }

    func start() {
        model.hornLeftFill = 0; model.hornRightFill = 0
        model.hornLeftCue = "Follow lights"; model.hornRightCue = "Follow lights"
        dragon.setHornsVisible(false)
        dragon.setWingsVisible(false)
        addLooseHorn(side: .left, position: model.reachTarget([-0.65,0,0]))
        addLooseHorn(side: .right, position: model.reachTarget([0.65,0,0]))
    }

    func update(deltaTime: Float) {
        guideTime += deltaTime
        for index in horns.indices where !horns[index].attached {
            let previousStops = horns[index].route.completedCount
            horns[index].route.update(horns[index].entity.position(relativeTo: root), held: heldHorn === horns[index].entity, radius: model.comfortSettings.movementAmount == .gentle ? 0.055 : 0.04, deltaTime: deltaTime)
            if horns[index].route.completedCount > previousStops { GameAudio.shared.play(.success) }
            let socket = dragon.hornSocket(horns[index].side)
            let distanceToSocket = distance(horns[index].entity.position(relativeTo: nil), socket.position(relativeTo: nil))
            socket.isEnabled = true
            if heldHorn === horns[index].entity {
                model.activityHint = horns[index].route.complete ? "Move the horn base into its outline. Hold briefly to attach." : "Follow the pulsing lights. Hold at bright stop \(horns[index].route.completedCount+1) of \(horns[index].route.checkpoints.count)."
            }
            // A brief, tracked hold docks the base. Releasing slightly early also accepts the same volume.
            if horns[index].route.complete && heldHorn === horns[index].entity && distanceToSocket < socketRadius {
                horns[index].socketHold += min(deltaTime,0.05)
                if horns[index].socketHold >= 0.3 { attach(index:index) }
            } else { horns[index].socketHold = 0 }
            updateHint(for: horns[index], distanceToSocket: distanceToSocket)

        }
        for horn in horns {
            let fill = horn.attached ? Float(1) : horn.route.fill / Float(horn.route.checkpoints.count + 1)
            let cue = horn.attached ? "Attached ✓" : (horn.route.complete ? "Hold in outline" : "Follow & hold")
            if horn.side == .left { model.hornLeftFill = fill; model.hornLeftCue = cue }
            else { model.hornRightFill = fill; model.hornRightCue = cue }
        }
        if !horns.isEmpty, horns.allSatisfy(\.attached) {
            if !model.stageReady { dragon.happyBounce() }
            model.markStageReady("Both horns are home. Take a look, then continue.")
        }
    }

    func cleanup() {
        root.removeAllChildren()
        dragon.parts.leftHornSocket.isEnabled = true
        dragon.parts.rightHornSocket.isEnabled = true
    }

    private func addLooseHorn(side: HornSide, position: SIMD3<Float>) {
        let horn = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [EmberMaterials.invisible])
        horn.name = side == .left ? "LooseHornLeft" : "LooseHornRight"
        horn.position = position
        DragonFactory.addVisual("HornVisual", target: .largest(AssetScaleConfiguration.current.hornLength), name: "HornVisual", to: horn, offset: .zero, mirrorX: side == .right, material: nil)
        horn.scale = dragon.hornControl(side).scale(relativeTo:root)
        horn.orientation = dragon.hornSocket(side).orientation(relativeTo:root)
        horn.setVisualInteraction(padding:0.025)
        root.addChild(horn)
        let hint = makeHornHint(name: "\(horn.name)Guidance")
        root.addChild(hint)
        let ghost = makeGhost(of: dragon.hornControl(side), name: "HornDestination")
        ghost.position = dragon.hornSocket(side).position(relativeTo: root)
        ghost.orientation = dragon.hornSocket(side).orientation(relativeTo:root)
        ghost.scale = dragon.hornControl(side).scale(relativeTo:root)
        root.addChild(ghost)
        let hand = makeGuideHand(name: side == .left ? "LeftHornHandGuide" : "RightHornHandGuide", opacity: 0.4)
        root.addChild(hand)
        let body = dragon.parts.bodyControl.visualBounds(relativeTo:root)
        let nestTop = root.parent?.findEntity(named:"LightweightMossNest")?.visualBounds(relativeTo:root).max.y ?? model.configuration.layout.nestPosition.y+0.06
        var low = model.reachTarget([-1,-1,-1])
        low.y = max(low.y,nestTop+0.085)
        let points = hornRoute(minimum:low,maximum:model.reachTarget([1,1,1]),obstacleMin:body.min,obstacleMax:body.max,left:side == .left)
        guard let start = points.first else {
            horn.removeFromParent(); hint.removeFromParent(); ghost.removeFromParent(); hand.removeFromParent()
            model.activityHint = "This scene size leaves too little room for the horn route. Reduce Scene size in Pause, or use Back to measure a wider comfortable reach."
            return
        }
        let pickup = start
        horn.position = pickup
        horns.append(HornItem(side: side, entity: horn, hint: hint, ghost: ghost, hand: hand, startPosition: pickup, route: RouteProgress(checkpoints: points)))
    }

    private var socketRadius: Float { (model.comfortSettings.movementAmount == .gentle ? 0.13 : 0.10) * model.sceneSize }

    private func attach(index: Int) {
        guard !horns[index].attached else { return }
        horns[index].attached = true
        GameAudio.shared.play(.success)
        let side = horns[index].side
        let horn = horns[index].entity
        horn.disableInteractionRecursively()
        dragon.setHornVisible(side, visible: true)
        horn.isEnabled = false
        horns[index].hint.removeFromParent()
        horns[index].ghost.removeFromParent()
        horns[index].hand.removeFromParent()
        dragon.hornSocket(side).isEnabled = true
        burst(at: dragon.hornSocket(side).position(relativeTo: root), in: root, count: 7)
    }

    func handleDrag(entity: Entity, translation: CGSize) {
        guard let index = horns.firstIndex(where: { $0.entity === entity && !$0.attached }) else { return }
        heldHorn = entity
        model.activityHint = horns[index].route.complete ? "Move the horn base into its outline. Hold briefly to attach." : "Follow the pulsing lights and hold briefly at each bright light. Stop \(horns[index].route.completedCount + 1) of \(horns[index].route.checkpoints.count)."
    }

    func release(entity: Entity) {
        guard let index = horns.firstIndex(where: { $0.entity === entity && !$0.attached }) else { return }
        let socket = dragon.hornSocket(horns[index].side)
        if horns[index].route.complete && distance(entity.position(relativeTo: nil), socket.position(relativeTo: nil)) < socketRadius {
            attach(index: index)
        } else {
            entity.position = horns[index].route.completedCount > 0 ? horns[index].route.checkpoints[horns[index].route.completedCount-1] : horns[index].startPosition
            #if DEBUG
            print("Ember input: rejected horn drop; outside socket")
            #endif
        }
    }

    func endDrag() { heldHorn = nil }

    private func makeHornHint(name: String) -> Entity {
        let hint = Entity()
        hint.name = name
        for index in 0..<7 {
            let mote = ModelEntity(mesh: .generateSphere(radius: 0.011), materials: [UnlitMaterial(color: .init(red:1,green:0.85,blue:0.25,alpha:1))])
            mote.name = "HornGuidanceMote\(index)"
            var haloMaterial = UnlitMaterial(color:UIColor(red:1,green:0.78,blue:0.18,alpha:1))
            haloMaterial.blending = .transparent(opacity:.init(floatLiteral:0.12))
            mote.addChild(ModelEntity(mesh:.generateSphere(radius:0.02),materials:[haloMaterial]))
            hint.addChild(mote)
        }
        return hint
    }

    private func updateHint(for horn: HornItem, distanceToSocket: Float) {
        let start = horn.entity.position(relativeTo: root)
        let destination = dragon.hornSocket(horn.side).position(relativeTo: root)
        let end = horn.route.next ?? destination
        horn.hint.isEnabled = !horn.attached && !horn.route.complete
        horn.ghost.position = destination
        horn.ghost.orientation = dragon.hornSocket(horn.side).orientation(relativeTo:root)
        // The held horn already matches the destination angle, avoiding a rotation pop on docking.
        if !horn.attached { horn.entity.orientation = horn.ghost.orientation }
        horn.ghost.scale = dragon.hornControl(horn.side).scale(relativeTo:root)
        let travel = min(guideTime.truncatingRemainder(dividingBy:3)/2.2,1)
        horn.hand.position = horn.route.complete ? destination+[0,0,0.05] : start + (end - start) * travel + [0,0,0.035]
        for (index, child) in horn.hint.children.enumerated() {
            let t = Float(index + 1) / Float(horn.hint.children.count)
            child.position = start + (end - start) * t
            let pulse = pow(max(0,cos(guideTime*4 - t*Float.pi*2)),6)
            child.scale = SIMD3<Float>(repeating: (index == horn.hint.children.count-1 ? 1.5 : 0.65) + pulse*0.65)
            let final = index == horn.hint.children.count-1
            let close = distance(start,end) < (model.comfortSettings.movementAmount == .gentle ? 0.055 : 0.04) && heldHorn === horn.entity
            child.components.set(OpacityComponent(opacity:final ? (close ? 1 : 0.4) : 0.1 + pulse*0.22))
            if final { child.position = end }
        }
    }
}

final class WingStage: GameStage {
    let instruction = "Open both wings together"
    private let root: Entity
    private let model: GameModel
    private let dragon: DragonController
    private let tracker = ReachTrackingService.shared
    private var practice = BilateralPractice()
    private var starts: [SIMD3<Float>] = []
    private var guidePlane: SIMD3<Float>?
    private var travel: [Float] = [0.16,0.16]
    private var left: Float = 0
    private var right: Float = 0
    private var guideTime: Float = 0
    private let leftGuide = GuidancePath()
    private let rightGuide = GuidancePath()
    private let leftHand = makeGuideHand(name:"LeftWingHandGuide",opacity:0.4)
    private let rightHand = makeGuideHand(name:"RightWingHandGuide",opacity:0.4)
    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) { self.root = root; self.model = model; self.dragon = dragon }
    func start() {
        dragon.setHornsVisible(true); dragon.setWingsVisible(true); dragon.resetWings()
        model.wingLeftFill = 0; model.wingRightFill = 0
        root.addChild(leftGuide.root); root.addChild(rightGuide.root); root.addChild(leftHand); root.addChild(rightHand)
    }
    // Physical repetitions deliberately require the two tracked hands, not a one-pointer gesture.
    func drag(entity: Entity, displacement: SIMD3<Float>) {}
    func release(entity: Entity) {}
    func resetPosition() { starts = []; guidePlane = nil; practice.resetPosition() }
    func endDrag() {} // A system pinch release must not reset a physical repetition.
    func update(deltaTime: Float) {
        guideTime += deltaTime
        let neutral = model.reachTarget([0,0,0])
        let body = dragon.parts.bodyControl.visualBounds(relativeTo:root)
        var low = model.reachTarget([-1,-1,-1]), high = model.reachTarget([1,1,1])
        // One fixed clear plane for both hands; no animated geometry can pass through the nest/body.
        low.x = neutral.x; high.x = neutral.x
        let nestTop = root.parent?.findEntity(named:"LightweightMossNest")?.visualBounds(relativeTo:root).max.y ?? -0.04
        low.y = max(low.y,nestTop+0.10)
        if guidePlane == nil { guidePlane = clearReachPoint(neutral,minimum:low,maximum:high,obstacleMin:body.min,obstacleMax:body.max) }
        guard let plane = guidePlane else {
            leftGuide.root.isEnabled = false; rightGuide.root.isEnabled = false
            leftHand.isEnabled = false; rightHand.isEnabled = false
            model.activityHint = "Move Ember farther away with the white bar. Your hands need clear space in front."
            return
        }
        var engaged = false
        if let l = tracker.pose(left:true), let r = tracker.pose(left:false), !starts.isEmpty || (l.pinching && r.pinching) {
            let lp = root.convert(position:l.palm,from:nil), rp = root.convert(position:r.palm,from:nil)
            if starts.isEmpty {
                let lo = model.reachTarget([-1,0,0]).x, hi = model.reachTarget([1,0,0]).x
                if lp.x >= lo+(hi-lo)*0.30 && rp.x <= hi-(hi-lo)*0.30 && lp.x < rp.x && abs(lp.z-plane.z)<0.18 && abs(rp.z-plane.z)<0.18 {
                    starts = [[lp.x,plane.y,plane.z],[rp.x,plane.y,plane.z]]
                    travel = [model.wingTravel(startX:lp.x,left:true),model.wingTravel(startX:rp.x,left:false)]
                }
            }
            if starts.count == 2 {
                left = min(1,max(0,(starts[0].x-lp.x)/travel[0]))
                right = min(1,max(0,(rp.x-starts[1].x)/travel[1]))
                engaged = abs(lp.z-plane.z)<0.22 && abs(rp.z-plane.z)<0.22 && abs(lp.y-plane.y)<0.22 && abs(rp.y-plane.y)<0.22
            }
        }
        let previousCycles = practice.cycles
        practice.update(left:left,right:right,engaged:engaged,deltaTime:deltaTime)
        if practice.cycles > previousCycles && !practice.complete { GameAudio.shared.play(.success) }
        dragon.setWingOpen(side:.left,progress:left); dragon.setWingOpen(side:.right,progress:right)
        model.wingLeftFill = practice.fill; model.wingRightFill = practice.fill
        let cue = practice.complete ? "Complete" : (practice.hold > 0 ? "Hold together" : (practice.returning ? "Return together" : "Open together"))
        model.wingLeftCue = cue; model.wingRightCue = cue
        if !engaged {
            model.activityHint = tracker.isSimulator ? "Two-hand tracking needs Vision Pro. Use Skip stage for testing." : (starts.isEmpty ? "Hands close together at the outlines. Pinch both to start.\nOpen both arms outward like a chest fly." : "Bring both hands forward, below shoulder height.\nTracking paused — your progress is saved.")
        } else {
            model.activityHint = "\(cue). \(practice.cycles) of 10 complete.\nOpen wide to the outlines, hold, then return together."
        }
        for (index,path,hand) in [(0,leftGuide,leftHand),(1,rightGuide,rightHand)] {
            let sign: Float = index == 0 ? -1 : 1
            var start = starts.count == 2 ? starts[index] : model.reachTarget([sign*0.12,0,0])
            start.y = plane.y; start.z = plane.z
            let end = SIMD3<Float>(model.reachTarget([sign,0,0]).x,plane.y,plane.z)
            // A continuous outward-and-return demonstration, with separate depth to avoid transparent overlap.
            let t = (1-cos(guideTime * .pi / 2.5))/2
            path.update(from:practice.returning ? end : start,to:practice.returning ? start : end)
            path.pulse(time:guideTime)
            hand.position = starts.isEmpty ? start+[0,0,0.025] : start+(end-start)*t+[0,0,0.025]
            path.root.isEnabled = !practice.complete; hand.isEnabled = !practice.complete
        }
        if practice.complete { model.markStageReady("Ten repetitions complete. Rest, then continue.") }
    }
    func cleanup() { root.removeAllChildren() }
}

final class ScaleStage: GameStage {
    let instruction = "Create your own scale pattern"
    private let root: Entity
    private let model: GameModel
    private let dragon: DragonController
    private let supply = ModelEntity()
    private let surface = BodySurface()
    private var selected = false
    private var displayedShape: ScaleShape?
    private var displayedTurn = -1
    private var candidate: BodySurface.Sample?
    private var yaw: Float = 0
    private var turnBaseline: Float?
    private var initialYaw: Float = 0
    private var undoRevision = 0
    private var nextID = 100
    private var home = SIMD3<Float>.zero
    private var guideTime: Float = 0
    private let placeHand = makeGuideHand(name:"RightScalePlaceGuide",opacity:0.48)
    private let turnLeftHand = makeGuideHand(name:"LeftScaleTurnGuide",opacity:0.48)
    private let turnRightHand = makeGuideHand(name:"RightScaleTurnGuide",opacity:0.48)
    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) { self.root = root; self.model = model; self.dragon = dragon }
    func start() {
        dragon.removeAttachedScales(); model.scaleDesign = []; model.scaleRotation = 0
        undoRevision = model.scaleUndoRevision
        let body = dragon.parts.bodyControl.visualBounds(relativeTo:root)
        let chrome = SceneChromeLayout(minimum:body.min,maximum:body.max)
        home = chrome.scaleSupply
        // The supply sits in front of the native translucent Scales attachment.
        for guide in [placeHand,turnLeftHand,turnRightHand] { root.addChild(guide) }
        supply.name = "ScaleSupply"; root.addChild(supply); replenish()
        dragon.parts.scaleSockets.forEach { $0.isEnabled = false }
    }
    private func supplyHome() -> SIMD3<Float> {
        guard let card = root.parent?.findEntity(named:"ScaleSupplyCard") else { return home }
        let bounds = card.visualBounds(relativeTo:root)
        // The 82-point preview slot is centred 6 points below the 206-point card centre.
        return [bounds.center.x,bounds.center.y-bounds.extents.y*6/206,bounds.max.z+0.004]
    }
    private func installSupplyVisual(preview: Bool) {
        supply.removeAllChildren()
        let item = ScaleDecoration(slot:0,shape:displayedShape ?? model.scaleShape,quarterTurns:displayedTurn >= 0 ? displayedTurn : model.scaleTurn)
        let visual = makePatternScale(item)
        let bounds = visual.visualBounds(relativeTo:visual)
        visual.position = -bounds.center
        let wrapper = Entity(); wrapper.addChild(visual)
        if preview {
            let extent = max(bounds.extents.x,bounds.extents.y)
            wrapper.scale = SIMD3<Float>(repeating:min(1,0.052/max(0.001,extent)))
        }
        supply.addChild(wrapper)
    }
    private func replenish() {
        home = supplyHome()
        displayedShape = model.scaleShape; displayedTurn = model.scaleTurn
        supply.removeAllChildren(); supply.position = home; supply.orientation = simd_quatf(angle:0,axis:[0,1,0]); supply.scale = [1,1,1]
        installSupplyVisual(preview:true)
        supply.setInteraction(radius:0.05)
        selected = false; candidate = nil
    }
    func drag(entity: Entity, start: SIMD3<Float>, delta: SIMD3<Float>, translation: CGSize) {
        guard entity === supply else { return }
        guideTime = 0
        if !selected { GameAudio.shared.play(.scalePickup); installSupplyVisual(preview:false); selected = true }
        let position = start+delta
        let local = simd_quatf(angle:yaw,axis:[0,1,0]).act(dragon.root.convert(position:position,from:root))
        candidate = surface.projected(local,yaw:yaw)
        if let candidate {
            supply.position = dragon.root.convert(position:candidate.position+candidate.normal*0.004,to:root)
            supply.orientation = dragon.root.orientation * simd_quatf(from:[0,0,1],to:candidate.normal)
            supply.scale = dragon.root.scale(relativeTo:root)
        } else { supply.position = position; supply.orientation = simd_quatf(angle:0,axis:[0,1,0]); supply.scale = [1,1,1] }
    }
    func update(deltaTime: Float) {
        if !selected {
            if displayedShape != model.scaleShape || displayedTurn != model.scaleTurn { replenish() }
            home = supplyHome(); supply.position = home
        }
        if undoRevision != model.scaleUndoRevision {
            undoRevision = model.scaleUndoRevision
            if let last = model.scaleDesign.popLast() { dragon.root.findEntity(named:String(format:"AttachedScale%02d",last.slot+1))?.removeFromParent() }
            model.stageReady = false
        }
        guideTime += min(deltaTime,0.1)
        let tracker = ReachTrackingService.shared
        if !selected, let l = tracker.pose(left:true), let r = tracker.pose(left:false), l.pinching && r.pinching {
            let lp = root.convert(position:l.palm,from:nil), rp = root.convert(position:r.palm,from:nil)
            let vector = rp-lp
            if simd_length(vector)>0.12 {
                let angle = atan2(-vector.z,vector.x)
                if let baseline = turnBaseline {
                    let delta = atan2(sin(angle-baseline),cos(angle-baseline))
                    yaw = initialYaw+delta
                } else { turnBaseline = angle; initialYaw = yaw }
            }
        } else { turnBaseline = nil }
        dragon.root.orientation = simd_quatf(angle:yaw,axis:[0,1,0])
        let demonstrating = !selected && turnBaseline == nil
        let phase = guideTime.truncatingRemainder(dividingBy:12)
        placeHand.isEnabled = demonstrating && phase < 6
        turnLeftHand.isEnabled = demonstrating && phase >= 6
        turnRightHand.isEnabled = demonstrating && phase >= 6
        let body = dragon.parts.bodyControl.visualBounds(relativeTo:root)
        let center = SIMD3<Float>((body.min.x+body.max.x)/2,(body.min.y+body.max.y)/2,body.max.z+0.12)
        let t = min(1,max(0,(phase-1)/3)); let eased = t*t*(3-2*t)
        placeHand.position = home+(center-home)*eased+[0,0,0.04]
        let turn = sin((phase-6) * Float.pi / 3)*0.55
        let rotation = simd_quatf(angle:turn,axis:[0,1,0])
        turnLeftHand.position = center+rotation.act([-0.17,0,0])
        turnRightHand.position = center+rotation.act([0.17,0,0])
        dragon.parts.scaleSockets.forEach { $0.isEnabled = false }
        if model.scaleDesign.count >= 6 { model.markStageReady("Add more scales, or continue.\nTo turn Ember: pinch with both hands and turn them together.") }
        else { model.activityHint = "Drag a scale from the right tray onto Ember.\nTo turn Ember: pinch with both hands and turn them together." }
    }
    func release(entity: Entity) {
        guard entity === supply, selected else { return }
        if let candidate {
            let item = ScaleDecoration(slot:nextID,shape:displayedShape ?? model.scaleShape,quarterTurns:displayedTurn,surfacePosition:candidate.position+candidate.normal*0.004,surfaceNormal:candidate.normal,finalPosition:candidate.fullPosition+candidate.fullNormal*0.004,finalNormal:candidate.fullNormal)
            nextID += 1; model.scaleDesign.append(item); dragon.addDecoration(item)
            GameAudio.shared.play(.scalePlace)
        }
        replenish()
    }
    func endDrag() { if selected { replenish() }; selected = false; candidate = nil; turnBaseline = nil }
    func cleanup() { dragon.root.orientation = simd_quatf(angle:0,axis:[0,1,0]); root.removeAllChildren() }
}

/// Pearl details keep a child's chosen silhouette and orientation through painting.
func makePatternScale(_ item: ScaleDecoration) -> ModelEntity {
    let root = ModelEntity()
    let shape: ModelEntity
    let pearl = EmberMaterials.soft(UIColor(red:0.84,green:0.86,blue:0.83,alpha:1),roughness:0.35)
    switch item.shape {
    case .leaf:
        shape = makeScale(name:"LeafScale",material:pearl)
        shape.scale = [0.58,0.72,0.32]
    case .diamond:
        shape = ModelEntity(mesh:.generateBox(size:[0.029,0.029,0.009],cornerRadius:0.006),materials:[pearl])
        shape.orientation = simd_quatf(angle:.pi/4,axis:[0,0,1])
    case .round:
        shape = ModelEntity(mesh:.generateSphere(radius:0.021),materials:[pearl]); shape.scale = [1,0.8,0.27]
    }
    let turn = Entity(); turn.orientation = simd_quatf(angle:Float(item.quarterTurns) * .pi / 2,axis:[0,0,1]); turn.addChild(shape); root.addChild(turn)
    return root
}

final class HornAlignmentStage: GameStage {
    let instruction = "Turn, hold, and return"
    private let root: Entity
    private let model: GameModel
    private let dragon: DragonController
    private var practices: [HornTurnPractice] = []
    private var finishElapsed: Float = 0
    private var finishRotations: [simd_quatf]?
    private var angles: [Float] = [0,0]
    private var held: Int?
    private var lastTranslation: CGFloat = 0
    private var rotationStart: Float?
    private var gripLatched = [WristGripLatch(),WristGripLatch()]
    private var gripRevision = -1
    private var gripRotations: [simd_quatf?] = [nil,nil]
    private var gripAxes: [SIMD3<Float>] = [[0,0,-1],[0,0,-1]]
    private var gripAngles: [Float] = [0,0]
    private var ghosts: [Entity] = []
    private var fistGuides: [Entity] = []
    private var gripPositions: [SIMD3<Float>] = []
    private var guideTime: Float = 0
    private var controls: [ModelEntity] { [dragon.parts.leftHornControl, dragon.parts.rightHornControl] }
    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) {
        self.root = root; self.model = model; self.dragon = dragon
    }
    func start() {
        dragon.setHornsVisible(true)
        model.requestHornGrip(nil)
        let reps = model.comfortSettings.movementAmount == .gentle ? 4 : 6
        practices = [HornTurnPractice(requiredCycles:reps,direction:-1,excursionDegrees:model.comfortSettings.movementAmount == .gentle ? 35 : 50),HornTurnPractice(requiredCycles:reps,direction:1,excursionDegrees:model.comfortSettings.movementAmount == .gentle ? 35 : 50)]
        model.hornLeftFill = 0; model.hornRightFill = 0
        for (i,horn) in controls.enumerated() {
            let guide = makeGuideHand(name:i == 0 ? "LeftFistGuide" : "RightFistGuide",opacity:0.55)
            let position = guidePosition(i)
            guide.position = position; root.addChild(guide); fistGuides.append(guide); gripPositions.append(position)
            horn.orientation = simd_quatf(angle:0,axis:[0,1,0]); horn.setVisualInteraction(padding:0.035)
            let ghost = makeGhost(of:horn,name:"TurnTarget")
            ghost.position = horn.position(relativeTo:root); ghost.scale = horn.scale(relativeTo:root); ghost.orientation = horn.orientation(relativeTo:root); root.addChild(ghost); ghosts.append(ghost)
        }
    }
    private func index(_ entity: Entity) -> Int? { controls.firstIndex { entity === $0 || entity.isDescendant(of:$0) } }
    func handleDrag(entity: Entity, translation: CGSize) {
        guard ReachTrackingService.shared.isSimulator, rotationStart == nil, let i = index(entity), !practices[i].complete else { return }
        held = i
        angles[i] = min(55,max(-55,angles[i] + Float(translation.width-lastTranslation)*0.45))
        lastTranslation = translation.width
    }
    func rotate(entity: Entity, radians: Float) {
        guard ReachTrackingService.shared.isSimulator, let i = index(entity), !practices[i].complete else { return }
        held = i
        if rotationStart == nil { rotationStart = angles[i] }
        angles[i] = min(55,max(-55,(rotationStart ?? 0) + radiansToDegrees(radians)))
    }
    private func guidePosition(_ i: Int) -> SIMD3<Float> {
        // Keep the demonstration next to its horn, never clamped down to the reach-box floor.
        let horn = controls[i].visualBounds(relativeTo:root)
        let body = dragon.parts.bodyControl.visualBounds(relativeTo:root)
        return [horn.center.x + (i == 0 ? -0.07 : 0.07),horn.center.y,max(horn.max.z+0.07,body.max.z+0.07)]
    }
    func resetGrip() {
        gripRotations = [nil,nil]; gripLatched = [WristGripLatch(),WristGripLatch()]
        for i in gripPositions.indices {
            gripPositions[i] = guidePosition(i)
            fistGuides[i].position = gripPositions[i]
        }
    }
    func endDrag() { held = nil; lastTranslation = 0; rotationStart = nil }
    func update(deltaTime: Float) {
        if finishRotations != nil { finishHorns(deltaTime:deltaTime); return }
        guideTime += deltaTime
        var messages: [String] = []
        if gripRevision != model.hornGripRevision {
            gripRevision = model.hornGripRevision
            gripLatched = [WristGripLatch(),WristGripLatch()]; gripRotations = [nil,nil]
            if let side = model.hornGripRequest, (0..<2).contains(side) { gripLatched[side].engage() }
        }
        for i in 0..<2 {
            gripPositions[i] = guidePosition(i)
            fistGuides[i].position = gripPositions[i]
            ghosts[i].position = controls[i].position(relativeTo:root)
            ghosts[i].scale = controls[i].scale(relativeTo:root)
            var gripping = held == i
            if !ReachTrackingService.shared.isSimulator && !practices[i].complete {
                gripping = false
                let side = i == 0 ? "Left" : "Right"
                if let hand = ReachTrackingService.shared.pose(left:i == 0) {
                    let local = root.convert(position:hand.palm,from:nil)
                    gripLatched[i].observe(isGrip:hand.fist || hand.pinching,near:distance(local,gripPositions[i]) < 0.25)
                    if gripLatched[i].isHeld {
                        if gripRotations[i] == nil { gripRotations[i] = hand.orientation; gripAngles[i] = angles[i]; gripAxes[i] = hand.forearmAxis }
                        let turn = signedWristTurnDegrees(current:hand.orientation,initial:gripRotations[i]!,forearmAxis:gripAxes[i],towardViewer:root.orientation(relativeTo:nil).act([0,0,1]))
                        angles[i] = min(75,max(-75,gripAngles[i]+turn)); gripping = true
                    } else {
                        gripRotations[i] = nil
                        messages.append(side+": make a loose fist at the outline, or select Grip "+side.lowercased()+" horn.")
                    }
                } else {
                    gripRotations[i] = nil
                    messages.append(side+" hand out of view. Bring it forward, below shoulder height.")
                }
            }
            let lower = model.reachTarget([-1,-1,-1]), upper = model.reachTarget([1,1,1])
            let reachable = (0..<3).allSatisfy { gripPositions[i][$0] >= lower[$0] && gripPositions[i][$0] <= upper[$0] }
            fistGuides[i].isEnabled = !practices[i].complete && !gripping
            if !ReachTrackingService.shared.isSimulator && !reachable && !gripping { messages.append("Reposition Ember within comfortable reach using the white bar, or choose Grip.") }
            let rest = controls[i].parent?.orientation(relativeTo:root) ?? PebbleHornFit.restingOrientation(left:i == 0)
            fistGuides[i].orientation = rest * simd_quatf(angle:sin(guideTime*1.5)*0.35,axis:[0,0,1])
            let previousCycles = practices[i].cycles
            practices[i].update(angle:angles[i],held:gripping,deltaTime:deltaTime)
            if practices[i].cycles > previousCycles { GameAudio.shared.play(.success) }
            if practices[i].complete { controls[i].disableInteractionRecursively() }
            controls[i].orientation = simd_quatf(angle:degreesToRadians(angles[i]),axis:[0,0,1])
            ghosts[i].orientation = rest * simd_quatf(angle:degreesToRadians(practices[i].targetDegrees),axis:[0,0,1])
            ghosts[i].isEnabled = !practices[i].complete
            let cue = practices[i].complete ? "Done ✓" : (practices[i].hold > 0 ? "Hold gently" : (practices[i].returning ? "Return upright" : (practices[i].targetDegrees > 0 ? "Turn left ↶" : "Turn right ↷")))
            if i == 0 { model.hornLeftFill = practices[i].fill; model.hornLeftCue = cue }
            else { model.hornRightFill = practices[i].fill; model.hornRightCue = cue }
        }
        if practices.allSatisfy(\.complete) {
            finishRotations = controls.map(\.orientation)
            controls.forEach { $0.disableInteractionRecursively() }
            finishHorns(deltaTime:0)
        } else {
            let task = "Make a loose fist beside a horn, or select Grip.\nTurn your whole forearm to match its outline.\nHold, return, and repeat until both rings fill."
            let help = messages.contains { $0.contains("out of view") } ? "Keep your hands in view, below shoulder height." : (messages.contains { $0.contains("Reposition Ember") } ? "Use the white bar to bring Ember within reach." : "")
            model.activityHint = task + (help.isEmpty ? "" : "\n"+help)
        }
    }
    private func finishHorns(deltaTime: Float) {
        finishElapsed += max(0,min(deltaTime,0.1))
        let amount = PebbleHornFit.finishAmount(elapsed:finishElapsed)
        dragon.setHornFinish(amount)
        for i in controls.indices {
            controls[i].orientation = simd_slerp(finishRotations?[i] ?? simd_quatf(angle:0,axis:[0,0,1]),simd_quatf(angle:0,axis:[0,0,1]),amount)
            ghosts[i].isEnabled = false; fistGuides[i].isEnabled = false
        }
        if amount >= 1 { model.markStageReady("Horns set. Continue to paint Ember.") }
        else { model.activityHint = "Turns complete. Watch the horns settle back." }
    }
    func cleanup() { controls.forEach { $0.disableInteractionRecursively(); $0.orientation = simd_quatf(angle:0,axis:[0,1,0]) }; root.removeAllChildren() }
}

final class CompletionStage: GameStage {
    let instruction = "Ember is ready to fly."
    private let root: Entity
    private let effectsRoot: Entity
    private let model: GameModel
    private let dragon: DragonController

    init(root: Entity, effectsRoot: Entity, model: GameModel, dragon: DragonController) {
        self.root = root
        self.effectsRoot = effectsRoot
        self.model = model
        self.dragon = dragon
    }

    func start() {}

    func handleDrag(entity: Entity, translation: CGSize) {
        if entity.name == "PlayAgainButton" || entity.isDescendant(named: "PlayAgainButton") {
            model.replay()
        } else if entity.name == "ExitButton" || entity.isDescendant(named: "ExitButton") {
            model.finish()
        }
    }

    func update(deltaTime: Float) {}

    func cleanup() {
        root.removeAllChildren()
    }
}

struct AssetScaleConfiguration {
    static let current = AssetScaleConfiguration()
    let emberHeight: Float = 0.62
    let wingLength: Float = 0.27
    let hornLength: Float = PebbleHornFit.normalizedLength
    let scaleSize: Float = 0.09
    let brushLength: Float = 0.22
    let sparkSize: Float = 0.09
    let nestDiameter: Float = 0.92
    let nestThickness: Float = 0.10
    let bushHeight: Float = 0.12
    let rockSize: Float = 0.09
    let mushroomHeight: Float = 0.08
}

enum AssetTarget {
    case height(Float)
    case largest(Float)
}

struct AssetMeasurement {
    let sourceExtents: SIMD3<Float>
    let target: AssetTarget
    let scale: Float
    let normalizedExtents: SIMD3<Float>
}

@MainActor
final class GameAssetLibrary {
    static let shared = GameAssetLibrary()
    private let greyNames: Set<String> = ["MagicScaleVisual"]
    private var sources: [String: Entity] = [:]
    private var demand = AssetDemand()
    private(set) var measurements: [String: AssetMeasurement] = [:]
    private init() {}
    func contains(_ name: String) -> Bool { sources[name] != nil }
    private var wanted: Set<String> { demand.wanted }
    private func evictUnused() {
        let keep = wanted
        for name in Array(sources.keys) where !keep.contains(name) { sources.removeValue(forKey:name); measurements.removeValue(forKey:name) }
    }
    func release(owner: String) { demand.release(owner); evictUnused() }
    func prepare(_ names: Set<String>, owner: String) async throws {
        demand.request(names,owner:owner)
        evictUnused() // Drop previous source references before allocating the next stage.
        for name in names.sorted() {
            try Task.checkCancellation()
            guard sources[name] == nil else { continue }
            print("Ember assets: loading \(name)")
            let entity = try await Entity(named:name,in:realityKitContentBundle)
            try Task.checkCancellation()
            guard wanted.contains(name) else { continue }
            entity.name = name; entity.clearGameplayComponentsRecursively()
            sources[name] = entity
            logEmberMemory("loaded " + name)
            await Task.yield()
        }
        print("Ember assets: source cache \(sources.keys.sorted())")
    }

    func cloneVisual(named name: String, target: AssetTarget, canonicalName: String) -> Entity? {
        let sourceName = greyNames.contains(name) ? name + "_Grey" : name
        guard let source = sources[sourceName] else { return nil }
        let clone = source.clone(recursive: true)
        clone.name = canonicalName
        clone.clearGameplayComponentsRecursively()
        RenderedStyle.polish(clone,asset:name)
        let wrapper = Entity()
        wrapper.name = canonicalName + "Normalized"
        wrapper.addChild(clone)
        let bounds = clone.visualBounds(relativeTo: wrapper)
        let sourceExtents = bounds.extents
        let dimension: Float = switch target {
        case .height(let height): height
        case .largest(let largest): largest
        }
        let divisor: Float = switch target {
        case .height: max(sourceExtents.y, 0.0001)
        case .largest: max(sourceExtents.x, sourceExtents.y, sourceExtents.z, 0.0001)
        }
        let factor = dimension / divisor
        clone.position -= bounds.center
        wrapper.scale = SIMD3<Float>(repeating: factor)
        measurements[name] = AssetMeasurement(sourceExtents: sourceExtents, target: target,
            scale: factor, normalizedExtents: sourceExtents * factor)
        return wrapper
    }

    private func extents(of entity: Entity) -> SIMD3<Float> {
        entity.visualBounds(relativeTo: entity).extents
    }
}

enum EmberMaterials {
    static let body = soft(UIColor(white: 0.62, alpha: 1), roughness: 0.72)
    static let wing = soft(.emberSky, roughness: 0.68)
    static let horn = soft(.emberIvory, roughness: 0.74)
    static let hornGold = soft(UIColor(red: 1.0, green: 0.75, blue: 0.16, alpha: 1), roughness: 0.22)
    static let hornGlow = soft(UIColor(red: 1.0, green: 0.82, blue: 0.28, alpha: 0.82), roughness: 0.18)
    static let sparkFallback = soft(.emberGold, roughness: 0.28)
    static let socketGlow = soft(UIColor.emberGold.withAlphaComponent(0.34), roughness: 0.24)
    static let nestFallback = soft(.emberGrass, roughness: 0.84)
    static let invisible = soft(.clear, roughness: 1)
    static let grey = soft(UIColor(white: 0.62, alpha: 1), roughness: 0.74)
    static let text = soft(.emberIvory, roughness: 0.5)
    static let textSecondary = soft(.white, roughness: 0.5)

    static let scalePalette: [SimpleMaterial] = [
        soft(.emberAqua, roughness: 0.42),
        soft(.emberPink, roughness: 0.42),
        soft(.emberGold, roughness: 0.38),
        soft(.emberGrass, roughness: 0.5),
        soft(.emberLavender, roughness: 0.46)
    ]

    static func soft(_ color: UIColor, roughness: Float) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .float(roughness), isMetallic: false)
    }
}

func makeScale(name: String, material: SimpleMaterial) -> ModelEntity {
    let scale = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [material])
    scale.name = name

    if let visual = GameAssetLibrary.shared.cloneVisual(named: "MagicScaleVisual", target: .largest(AssetScaleConfiguration.current.scaleSize), canonicalName: "MagicScaleVisual") {
        scale.model?.materials = [EmberMaterials.invisible]
        visual.tintSurfaceRecursively(nil)
        scale.addChild(visual)
    }
    return scale
}

func actionButton(name: String, title: String, position: SIMD3<Float>, tint: UIColor, textColor: UIColor = .white, size: SIMD3<Float> = [0.24, 0.075, 0.022], fontSize: CGFloat = 0.026) -> ModelEntity {
    let button = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(size.y * 0.45, 0.04)), materials: [EmberMaterials.soft(tint, roughness: 0.7)])
    button.name = name
    button.position = position
    button.setInteraction(boxSize: [size.x + 0.08, size.y + 0.06, 0.09], manipulation: false)
    let label = textEntity(title, size: fontSize, material: EmberMaterials.soft(textColor, roughness: 0.5), width: CGFloat(size.x * 3.2))
    label.name = "\(name)Label"
    center(label, on: button, zOffset: size.z / 2 + 0.003)
    button.addChild(label)
    return button
}

func pauseButtonEntity(name: String, position: SIMD3<Float>) -> ModelEntity {
    let button = ModelEntity(mesh: .generateSphere(radius: 0.042), materials: [EmberMaterials.soft(UIColor.emberTeal.withAlphaComponent(0.22), roughness: 0.62)])
    button.name = name
    button.position = position
    button.scale = [1, 1, 0.18]
    button.setInteraction(radius: 0.07, manipulation: false)

    for x in [-0.011, 0.011] as [Float] {
        let bar = ModelEntity(mesh: .generateBox(size: [0.008, 0.034, 0.006], cornerRadius: 0.002), materials: [EmberMaterials.soft(UIColor.white.withAlphaComponent(0.64), roughness: 0.48)])
        bar.position = [x, 0, 0.011]
        button.addChild(bar)
    }
    return button
}

func textEntity(_ text: String, size: CGFloat, material: SimpleMaterial, width: CGFloat = 0.62) -> ModelEntity {
    let mesh = MeshResource.generateText(
        text,
        extrusionDepth: 0.001,
        font: .systemFont(ofSize: size, weight: .bold),
        containerFrame: CGRect(x: -width / 2, y: -size * 0.8, width: width, height: size * 4.5),
        alignment: .center,
        lineBreakMode: .byWordWrapping
    )
    return ModelEntity(mesh: mesh, materials: [material])
}

func center(_ label: ModelEntity, on button: ModelEntity, zOffset: Float) {
    let bounds = label.visualBounds(relativeTo: label)
    label.position = [-bounds.center.x, -bounds.center.y, zOffset]
}

func burst(at position: SIMD3<Float>, in parent: Entity, count: Int) {
    for index in 0..<count {
        let mote = ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [EmberMaterials.sparkFallback])
        mote.name = "MagicBurst"
        mote.position = position
        parent.addChild(mote)
        let angle = Float(index) / Float(max(count, 1)) * .pi * 2
        let target = position + [cos(angle) * 0.08, 0.04 + Float(index % 3) * 0.015, sin(angle) * 0.04]
        mote.move(to: Transform(scale: [0.08, 0.08, 0.08], rotation: simd_quatf(angle:0,axis:[0,1,0]), translation: target), relativeTo: parent, duration: 0.35, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            mote.removeFromParent()
        }
    }
}

func trail(from start: SIMD3<Float>, to end: SIMD3<Float>, in parent: Entity) {
    let travel = end - start
    guard simd_length(travel) > 0.018 else { return }
    for step in 1...3 {
        let mote = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [EmberMaterials.socketGlow])
        mote.position = start + travel * (Float(step) / 4)
        parent.addChild(mote)
        mote.move(to: Transform(scale: [0.05, 0.05, 0.05], rotation: simd_quatf(angle:0,axis:[0,1,0]), translation: mote.position + [0, 0.02, 0]), relativeTo: parent, duration: 0.3, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            mote.removeFromParent()
        }
    }
}

func distance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    simd_length(lhs - rhs)
}

func degreesToRadians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

func radiansToDegrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

func clamped(_ value: Float, lower: Float = 0, upper: Float = 1) -> Float {
    min(max(value, lower), upper)
}

extension Entity {
    @discardableResult
    func adjustVisualHeight(from currentHeight: Float, to targetHeight: Float) -> Float {
        guard currentHeight > 0.0001 else { return 1 }
        let multiplier = targetHeight / currentHeight
        scale.y *= multiplier
        return multiplier
    }

    func removeAllChildren() {
        for child in children {
            child.removeFromParent()
        }
    }

    func setVisualInteraction(padding: Float) {
        let bounds = visualBounds(relativeTo:self)
        let size = simd_max(bounds.extents + SIMD3<Float>(repeating:padding), SIMD3<Float>(repeating:0.08))
        setInteraction(boxSize:size)
        components.set(CollisionComponent(shapes:[ShapeResource.generateBox(size:size).offsetBy(translation:bounds.center)]))
    }

    func setInteraction(radius: Float, manipulation: Bool = true) {
        components.set(InputTargetComponent())
        components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        components.set(HoverEffectComponent())
        components.remove(ManipulationComponent.self)
    }

    func setInteraction(boxSize: SIMD3<Float>, manipulation: Bool = true) {
        components.set(InputTargetComponent())
        components.set(CollisionComponent(shapes: [.generateBox(size: boxSize)]))
        components.set(HoverEffectComponent())
        components.remove(ManipulationComponent.self)
    }

    func disableInteractionRecursively() {
        components.remove(InputTargetComponent.self)
        components.remove(CollisionComponent.self)
        components.remove(HoverEffectComponent.self)
        components.remove(ManipulationComponent.self)
        for child in children {
            child.disableInteractionRecursively()
        }
    }

    func clearGameplayComponentsRecursively() {
        disableInteractionRecursively()
        components.remove(CollisionComponent.self)
        for child in children {
            child.clearGameplayComponentsRecursively()
        }
    }

    func applyMaterialRecursively(_ material: SimpleMaterial) {
        if let modelEntity = self as? ModelEntity {
            modelEntity.model?.materials = [material]
        }
        for child in children {
            child.applyMaterialRecursively(material)
        }
    }

    func isDescendant(of ancestor: Entity) -> Bool {
        var current = parent
        while let entity = current {
            if entity === ancestor { return true }
            current = entity.parent
        }
        return false
    }

    func isDescendant(named name: String) -> Bool {
        var current = parent
        while let entity = current {
            if entity.name == name { return true }
            current = entity.parent
        }
        return false
    }
}

extension UIColor {
    static let emberGold = UIColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 1)
    static let emberIvory = UIColor(red: 1.0, green: 0.94, blue: 0.78, alpha: 1)
    static let emberTeal = UIColor(red: 0.22, green: 0.74, blue: 0.74, alpha: 1)
    static let emberSky = UIColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1)
    static let emberAqua = UIColor(red: 0.34, green: 0.83, blue: 0.88, alpha: 1)
    static let emberPink = UIColor(red: 1.0, green: 0.58, blue: 0.72, alpha: 1)
    static let emberLavender = UIColor(red: 0.72, green: 0.55, blue: 0.94, alpha: 1)
    static let emberGrass = UIColor(red: 0.34, green: 0.72, blue: 0.42, alpha: 1)
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(GameModel())
}
