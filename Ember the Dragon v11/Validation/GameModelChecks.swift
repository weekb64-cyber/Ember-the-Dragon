import Foundation
import simd

@main
struct GameModelChecks {
    @MainActor
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        var brushAudio = BrushSoundMotion()
        var stationarySounds = 0
        for _ in 0..<180 { if brushAudio.update(horizontal:0,touching:true,deltaTime:1.0/90) { stationarySounds += 1 } }
        check(stationarySounds == 0,"Stationary brush contact stays silent")
        var jitterSounds = 0
        for i in 0..<180 { if brushAudio.update(horizontal:i%2 == 0 ? 0.0008 : -0.0008,touching:true,deltaTime:1.0/90) { jitterSounds += 1 } }
        check(jitterSounds == 0,"Small tracking jitter cannot trigger brushing audio")
        for steps in [3,12,60,240] {
            brushAudio.reset()
            _ = brushAudio.update(horizontal:-0.065,touching:true,deltaTime:1.0/90)
            for sweep in 0..<4 {
                var sounds = 0
                for i in 1...steps {
                    let progress = Float(i)/Float(steps)
                    let position: Float = sweep%2 == 0 ? -0.065+0.13*progress : 0.065-0.13*progress
                    if brushAudio.update(horizontal:position,touching:true,deltaTime:1.0/90) { sounds += 1 }
                }
                check(sounds == 1,"Each left/right sweep sounds exactly once at fast, medium and slow speeds")
            }
        }
        var holdSounds = 0
        for _ in 0..<180 { if brushAudio.update(horizontal:-0.065,touching:true,deltaTime:1.0/90) { holdSounds += 1 } }
        check(holdSounds == 0,"Holding after a sweep never replays its sound")
        var reversalJitter = 0
        for i in 0..<90 { if brushAudio.update(horizontal:-0.065+(i%2 == 0 ? 0.002 : 0),touching:true,deltaTime:1.0/90) { reversalJitter += 1 } }
        check(reversalJitter == 0,"Tiny reversals at the end of a stroke do not sound like new sweeps")
        check(!brushAudio.update(horizontal:0.1,touching:false,deltaTime:0.1),"Moving off the painting target silences and resets brush audio")
        check(!brushAudio.update(horizontal:0.09,touching:true,deltaTime:0.02),"Re-entering the target cannot replay stale movement")
        brushAudio.reset()
        check(!brushAudio.update(horizontal:0,touching:true,deltaTime:0.02),"Release/pause resets the stroke anchor")
        let leftSocket = PebbleHornFit.socketPosition(left:true), rightSocket = PebbleHornFit.socketPosition(left:false)
        check(abs((leftSocket.x+rightSocket.x)/2-PebbleHornFit.headCenterX)<0.00001,"Horns straddle the beige crown pair's centreline equally")
        check(leftSocket.z == rightSocket.z && leftSocket.z > 0.07,"Both horns share the crown line just beyond the first beige knobs")
        let leftUp = PebbleHornFit.restingOrientation(left:true).act(SIMD3<Float>(0,1,0))
        let rightUp = PebbleHornFit.restingOrientation(left:false).act(SIMD3<Float>(0,1,0))
        check(leftUp.x < -0.45 && leftUp.y > 0.8,"Left horn follows the marked outward lean on the tilted head")
        check(abs(rightUp.x)<0.08 && rightUp.y>0.99,"Right horn stays nearly upright within the tilted head frame")
        for left in [true,false] {
            let rest = PebbleHornFit.restingOrientation(left:left)
            let turn = simd_quatf(angle:0.6,axis:[0,0,1])
            let guide = rest * turn
            check(simd_distance(guide.act(SIMD3<Float>(0,1,0)),rest.act(turn.act(SIMD3<Float>(0,1,0))))<0.00001,"Turn outline includes socket rest orientation, matching the attached horn")
            check(simd_distance((rest * simd_quatf(angle:0,axis:[0,0,1])).act(SIMD3<Float>(0,1,0)),rest.act(SIMD3<Float>(0,1,0)))<0.00001,"Ending a turn returns to the tilted resting pose rather than world upright")
        }
        check(PebbleHornFit.finishAmount(elapsed:0) == 0 && PebbleHornFit.finishAmount(elapsed:1.25) == 1,"Horn settling runs from upright to fully back over 1.25 seconds")
        check(PebbleHornFit.finishAmount(elapsed:0.6)<1,"Continue must wait for the horn transition to finish")
        check(PebbleHornFit.finishAmount(elapsed:0.625) == 0.5,"Horn transition has a smooth midpoint")
        for phase in [GamePhase.horns,.wings,.scales,.hornAlignment] {
            check(!PebbleHornFit.finishedPose(for:phase),"Earlier stages and restarted horn turns use the upright exercise pose")
        }
        for phase in [GamePhase.painting,.celebration,.complete] {
            check(PebbleHornFit.finishedPose(for:phase),"Painting and later stages retain the backward horn pose, including stage skips")
        }
        for left in [true,false] {
            let backward = PebbleHornFit.poseOrientation(left:left,finish:1).act(SIMD3<Float>(0,1,0))
            check(backward.z < -0.8,"Finished horns sweep backward instead of only leaning sideways")
            let breathed = PebbleHornFit.breathingPosition(left:left,scale:[1,1.01,1],offset:[0,0.0031,0],finish:1)
            check(simd_distance((breathed-SIMD3<Float>(0,0.0031,0))/SIMD3<Float>(1,1.01,1),PebbleHornFit.posePosition(left:left,finish:1))<0.00001,"Breathing preserves the settled horn bases")
        }
        let framing = PhotoFraming(zoom:2,x:0.1,y:-0.2)
        check(framing.dragged(x:0.2,y:0.1) == PhotoFraming(zoom:2,x:0.1+0.2,y:-0.1),"Photo drag preserves zoom and moves in normalized viewport coordinates")
        check(PhotoFraming(zoom:9,x:99,y:-99).bounded == PhotoFraming(zoom:3,x:1.35,y:-1.35),"Photo framing limits zoom and excessive drags")
        check(PhotoFraming(zoom:.nan,x:.infinity,y:-.infinity).bounded == PhotoFraming(),"Malformed framing falls back to finite defaults")
        let capNormal = simd_normalize(SIMD3<Float>(0.001651,-0.381800,0.924244))
        check(simd_dot(PebbleHornFit.orientation.act(capNormal),SIMD3<Float>(0,-1,0))>0.99,"Horn cap faces into the crown instead of exposing its rim")
        for left in [true,false] {
            for breath: Float in [0.992,1,1.01] {
                let scale = SIMD3<Float>(1,breath,1), offset = SIMD3<Float>(0,-0.31*(1-breath),0)
                let socket = PebbleHornFit.breathingPosition(left:left,scale:scale,offset:offset)
                let recovered = (socket-offset)/scale
                check(simd_distance(recovered,PebbleHornFit.socketPosition(left:left))<0.00001,"Horn stays fixed to the same head location through breathing")
            }
        }
        let skipHorns = GameModel(); skipHorns.transition(to:.horns); skipHorns.pause(); skipHorns.skipCurrentStage()
        check(skipHorns.currentPhase == .wings && PebbleForm.forPhase(skipHorns.currentPhase) == .repair,"Skipping horns from Pause installs the repair body for wings")
        check(AssetResidency.assets(for:skipHorns.currentPhase).contains("HornVisual"),"Skipping placement still loads both attached horn visuals")
        // Reproduce the post-configure placement reset with no ARKit head anchor in Simulator.
        let simulatorPlacement = EmberViewerPlacement.resolve(head:nil,isSimulator:true,characterCenter:[0,0.23,0])
        check(simulatorPlacement != nil,"Simulator can place Ember without a head anchor after session reset")
        let simulatorCenter = simulatorPlacement!.position + SIMD3<Float>(0,0.23,0)*simulatorPlacement!.scale
        check(abs(simulatorCenter.y-1.57)<0.001 && abs(simulatorCenter.z+1.10)<0.001,"Simulator places Ember near camera height, not the floor")
        check(EmberViewerPlacement.resolve(head:nil,isSimulator:false,characterCenter:.zero) == nil,"Headset waits for a real viewing pose")
        let launch = GameModel(); launch.startGame(); launch.isLoadingAssets = true
        launch.scenePrepared(placedForViewer:simulatorPlacement != nil)
        check(!launch.isSceneReady,"Placement alone must not dismiss the launcher while assets load")
        launch.isLoadingAssets = false
        launch.scenePrepared(placedForViewer:false)
        check(!launch.isSceneReady,"Assets alone must not dismiss the launcher before placement")
        launch.assetLoadError = "test failure"
        launch.scenePrepared(placedForViewer:true)
        check(!launch.isSceneReady,"Failed asset loading keeps Retry accessible")
        launch.assetLoadError = nil
        launch.scenePrepared(placedForViewer:simulatorPlacement != nil)
        check(launch.isSceneReady,"Successful Simulator load releases the launcher without another scene frame")
        check(EmberViewerPlacement.resolve(head:nil,isSimulator:true,characterCenter:[0,0.23,0])?.position == simulatorPlacement?.position,"Simulator recenter does not wait for tracking")
        let tracked = EmberViewerPlacement.resolve(head:matrix_identity_float4x4,isSimulator:false,characterCenter:.zero)
        check(tracked != nil && tracked?.scale == 0.85,"Headset placement still uses its tracked pose and presentation scale")
        for pitch: Float in [-1.1,-0.5,0,0.5,1.1] {
            var head = simd_float4x4(simd_quatf(angle:0.7,axis:[0,1,0]) * simd_quatf(angle:pitch,axis:[1,0,0]))
            head.columns.3 = [0.2,1.1,-0.4,1]
            let center = SIMD3<Float>(0,0.23,0)
            let anchor = initialEmberScenePosition(head:head,characterCenter:center,scale:0.85)
            let worldCenter = anchor+levelSceneOrientation(head).act(center*0.85)
            let eye = SIMD3<Float>(head.columns.3.x,head.columns.3.y,head.columns.3.z)
            let forward = -SIMD3<Float>(head.columns.2.x,head.columns.2.y,head.columns.2.z)
            check(simd_dot(simd_normalize(worldCenter-eye),forward)>0.98,"Ember begins on the viewing ray even when reclined")
        }
        for eyeHeight: Float in [0.65,1.1,1.6] {
            var head = matrix_identity_float4x4; head.columns.3.y = eyeHeight
            let center = SIMD3<Float>(0,0.23,0)
            let placement = EmberViewerPlacement.resolve(head:head,isSimulator:false,characterCenter:center)!
            let displayedCenter = placement.position+placement.orientation.act(center*placement.scale)
            check(abs(displayedCenter.y-eyeHeight+0.03)<0.001,"Device spawn stays at the current eye height when low, seated or standing")
        }
        for footprint: Float in [0.03,0.07,0.12,0.18] {
            for position: SIMD2<Float> in [[0,0],[0.5,0.5],[-0.6,0.3],[0.32,-0.1]] {
                let point = nestDecorationPosition(position,footprint:footprint)
                check(simd_length(point)+footprint <= 0.4351,"The whole decoration footprint stays on the nest")
            }
        }
        var easing = ReachCapture()
        for _ in 0..<5 { _ = easing.update(position:.zero,deltaTime:0.05) }
        let firstFill = easing.holdProgress
        for _ in 0..<4 { _ = easing.update(position:.zero,deltaTime:0.05) }
        let secondFill = easing.holdProgress
        check(firstFill > 0 && secondFill-firstFill > firstFill,"Calibration fill speeds up during a genuine stable hold")
        _ = easing.update(position:nil,deltaTime:0.05)
        check(easing.holdProgress == 0 && easing.samples.isEmpty,"Lost tracking cannot complete an eased calibration bar")
        let model = GameModel()
        model.startGame()
        check(model.currentPhase == .introduction, "Fresh session starts sleeping introduction")
        let session = model.sessionRevision
        model.startGame()
        check(model.sessionRevision == session, "Repeated start while opening is ignored")
        model.immersiveSpaceOpened()
        model.advanceSetupOrStage()
        check(model.currentPhase == .magicSetup, "Wake action enters reach calibration")
        check(!model.isReachSetupReady, "Empty calibration cannot continue")
        var capture = ReachCapture()
        for _ in 0..<100 { _ = capture.update(position:.zero,deltaTime:0.05) }
        check(capture.samples.count == 1, "Standing still captures neutral once, not repeated success")
        for _ in 0..<20 { _ = capture.update(position:[0.1,0,0],deltaTime:0.05) }
        check(capture.samples.count == 1, "Sideways movement cannot satisfy forward depth")
        let positions: [SIMD3<Float>] = [[0,0,-0.1],[-0.1,0,0],[0.1,0,0]]
        for position in positions {
            let before = capture.samples.count
            for _ in 0..<35 { _ = capture.update(position:.zero,deltaTime:0.05) }
            for _ in 0..<40 { _ = capture.update(position:position,deltaTime:0.05) }
            check(capture.samples.count == before+1, "Directional reach requires movement and dwell")
        }
        check(capture.complete, "Four poses complete calibration")
        model.reachSamples = capture.envelopeSamples
        model.calibrationIsSimulated = true
        model.advanceSetupOrStage()
        check(model.currentPhase == .horns, "Ready setup enters horns")
        check(!model.hasPhysicalCalibration, "Simulator is never marked physical calibration")
        model.pause(); model.pause(); model.resume()
        check(model.currentPhase == .horns && !model.isPaused, "Repeated pause preserves resume phase")
        model.advanceSetupOrStage()
        model.restartCurrentStage()
        check(model.currentPhase == .wings, "Restart targets active stage, not last paused stage")
        model.isRestartingStage = false
        model.pause(); model.goBackStage()
        check(model.currentPhase == .horns && !model.isPaused, "Back works from pause")
        for expected: GamePhase in [.wings,.scales,.hornAlignment,.painting] {
            model.advanceSetupOrStage()
            check(model.currentPhase == expected, "Progression to \(expected)")
        }
        check(model.appliedPaint == nil, "Ember stays unpainted before a valid stroke")
        model.selectedPaint = .orange; model.appliedPaint = .orange
        model.pause(); model.resume()
        check(model.appliedPaint == .orange, "Pause preserves paint")
        model.restartCurrentStage()
        check(model.currentPhase == .painting && model.appliedPaint == nil, "Restart painting restores unpainted state")
        model.appliedPaint = .white
        model.advanceSetupOrStage(); model.advanceSetupOrStage()
        check(model.currentPhase == .complete && model.appliedPaint == .white, "Completed paint survives finale")
        model.pause(); model.goBackStage()
        check(model.currentPhase == .celebration, "Can go back from completion")
        model.replay()
        check(model.sessionRevision == session+1 && model.appliedPaint == nil, "Replay clears paint")
        model.startOver()
        check(model.currentPhase == .introduction && !model.hasCompletedSetupThisSession, "Start over resets setup")
        check(model.reachSamples.isEmpty && !model.hasPhysicalCalibration, "Start over resets physical reach data")
        var lost = ReachCapture()
        for _ in 0..<5 { _ = lost.update(position:.zero,deltaTime:0.05) }
        _ = lost.update(position:nil,deltaTime:0.05)
        for _ in 0..<5 { _ = lost.update(position:.zero,deltaTime:0.05) }
        check(lost.samples.isEmpty, "Tracking loss resets incomplete dwell")
        var invalid = ReachCapture()
        for _ in 0..<30 { _ = invalid.update(position:[Float.nan,0,0],deltaTime:0.05) }
        check(invalid.samples.isEmpty, "Invalid tracking positions are rejected")
        var route = RouteProgress(checkpoints:[[0.1,0,0],[0.2,0,0]])
        route.visit([0.2,0,0],radius:0.03)
        check(route.completedCount == 0, "Route cannot skip the first checkpoint")
        route.visit([0.1,0,0],radius:0.03); route.visit([0.2,0,0],radius:0.03)
        check(route.complete, "Ordered checkpoint route completes")
        var wings = WingPractice(requiredCycles:2)
        for _ in 0..<30 { wings.update(progress:1,isHeld:false,deltaTime:0.05,threshold:0.78) }
        check(!wings.returning, "Idle wing cannot complete a hold")
        for _ in 0..<10 { wings.update(progress:1,isHeld:true,deltaTime:0.05,threshold:0.78) }
        check(wings.returning && wings.completedCycles == 0, "Open hold needs controlled return")
        for _ in 0..<10 { wings.update(progress:0,isHeld:true,deltaTime:0.05,threshold:0.78) }
        check(wings.completedCycles == 1 && !wings.complete, "One cycle does not finish practice")
        for value: Float in [1,0] { for _ in 0..<10 { wings.update(progress:value,isHeld:true,deltaTime:0.05,threshold:0.78) } }
        check(wings.complete, "Two full cycles finish gentle practice")
        var area = PaintAreaProgress(requiredDistance:0.16,requiredCells:3)
        for _ in 0..<10 { area.stroke(length:0.03,cell:0) }
        check(!area.complete, "Painting one spot cannot fill an area")
        area.stroke(length:0.03,cell:1); area.stroke(length:0.03,cell:2)
        check(area.complete, "Broad strokes fill a paint area")
        model.markStageReady("Done")
        model.pause(); model.resume()
        check(model.stageReady, "Pause preserves completed stage for inspection")
        model.restartCurrentStage()
        check(!model.stageReady, "Restart clears completion gate")
        var heldRoute = RouteProgress(checkpoints:[[0.1,0,0],[0.2,0,0]])
        heldRoute.update([0.1,0,0],held:true,radius:0.04,deltaTime:0.05)
        check(heldRoute.completedCount == 0, "Passing a horn checkpoint does not satisfy the hold")
        for _ in 0..<20 { heldRoute.update([0.1,0,0],held:false,radius:0.04,deltaTime:0.05) }
        check(heldRoute.completedCount == 0, "A released horn cannot complete a checkpoint")
        for _ in 0..<10 { heldRoute.update([0.1,0,0],held:true,radius:0.04,deltaTime:0.05) }
        check(heldRoute.completedCount == 1, "Controlled hold completes one checkpoint")
        check(wings.fill(progress:0,threshold:0.78) == 1, "Completed wing fills its donut")
        let surface = paintPlanePosition([0.03,0.02,1.2],surfaceZ:0.2,minimum:[-0.2,-0.3,0],maximum:[0.2,0.3,0.2])
        check(surface.z == 0.2 && surface.x == 0.03 && surface.y == 0.02, "Brush ignores depth drift while preserving lateral movement")
        check(scaleSocketFacesPlayer(yaw:0,socketAngle:0), "Front scales are visible initially")
        check(!scaleSocketFacesPlayer(yaw:0,socketAngle:2*Float.pi/3), "Hidden scales cannot snap through Ember")
        check(scaleSocketFacesPlayer(yaw:-2*Float.pi/3,socketAngle:2*Float.pi/3), "Turning exposes side and back scales")
        for index in PaintChoice.palettes.indices {
            check((0..<20).allSatisfy { _ in PaintChoice.nextPalette(after:index) != index }, "Randomizer changes the palette")
            check(Set(PaintChoice.palettes[index]).count == 3, "Each harmonious palette has three distinct colours")
        }
        let revision = model.paletteRevision
        model.randomizePalette()
        check(model.paletteRevision == revision+1 && model.palette.contains(model.selectedPaint), "Randomizer selects an available colour and signals reset")
        check(PebbleForm.forPhase(.introduction) == .sleeping, "Introduction uses the new sleeping mesh")
        for phase: GamePhase in [.magicSetup,.horns,.wings,.scales,.hornAlignment,.painting] {
            check(PebbleForm.forPhase(phase) == .repair, "Interactive activities use the modular body")
        }
        check(PebbleForm.forPhase(.celebration) == .complete && PebbleForm.forPhase(.complete) == .complete, "Finale uses the supplied complete mesh")
        check(abs((-PebbleForm.complete.normalizedSize/2 + PebbleForm.complete.offset.y) - (-PebbleForm.repair.normalizedSize/2)) < 0.0001, "Complete and modular forms share their floor height")
        var turning = HornTurnPractice(requiredCycles:3,direction:-1)
        for _ in 0..<50 { turning.update(angle:0,held:true,deltaTime:0.05) }
        check(turning.cycles == 0 && !turning.returning, "Idle upright horn does not count as exercise")
        for _ in 0..<50 { turning.update(angle:-35,held:false,deltaTime:0.05) }
        check(turning.cycles == 0 && !turning.returning, "Unheld horn cannot earn progress")
        turning.update(angle:-35,held:true,deltaTime:0.05)
        turning.update(angle:0,held:true,deltaTime:0.05)
        check(turning.hold == 0, "Sweeping through a target does not pass its hold")
        for cycle in 0..<3 {
            let target = turning.targetDegrees
            for _ in 0..<11 { turning.update(angle:target,held:true,deltaTime:0.05) }
            check(turning.returning && turning.cycles == cycle, "Outward turn must be followed by a return")
            for _ in 0..<11 { turning.update(angle:0,held:true,deltaTime:0.05) }
            check(turning.cycles == cycle+1, "Held return completes exactly one repetition")
        }
        check(turning.complete && turning.fill == 1, "Three complete turn-return cycles fill the ring")
        for _ in 0..<50 { turning.update(angle:35,held:true,deltaTime:0.05) }
        check(turning.cycles == 3, "Completed horn cannot count extra turns")
        let design = [0,2,4,6,8,10,12,14,16].map { ScaleDecoration(slot:$0,shape:.leaf,quarterTurns:0) }
        check(ScaleDesignLayout.valid(design), "A unique nine-scale pattern is valid")
        check(ScaleDesignLayout.ready(design,gentle:false), "Three decorated sides meet the standard movement goal")
        check(!ScaleDesignLayout.ready(Array(design.prefix(6)),gentle:false), "Too few scales cannot complete standard mode")
        check(ScaleDesignLayout.ready(Array(design.prefix(6)),gentle:true), "Gentle mode accepts six scales across two sides")
        check(!ScaleDesignLayout.valid([design[0],design[0]]), "Duplicate sockets are rejected")
        check(!ScaleDesignLayout.valid([.init(slot:36,shape:.round,quarterTurns:0)]), "Out-of-range saved sockets are rejected")
        for i in 0..<36 {
            for full in [false,true] {
                let v = ScaleDesignLayout.position(i,complete:full)
                check(v.x.isFinite && v.y.isFinite && v.z.isFinite, "Every placement has finite coordinates")
            }
        }
        let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("EmberGalleryTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:testFolder) }
        let store = EmberGalleryStore(folder:testFolder)
        let entry = EmberCreation(sessionID:UUID(),name:"Test Ember",paint:.blue,scales:design,backdrop:.moonlight,yaw:0.5)
        let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        do {
            try store.save(entry,png:png)
            try store.save(entry,png:png)
            check(store.entries.count == 1, "Repeated save is idempotent")
            let reloaded = EmberGalleryStore(folder:testFolder)
            check(reloaded.entries == [entry], "A saved colour, pattern and camera configuration survive reopening")
            let savedPNG = try Data(contentsOf:reloaded.imageURL(entry))
            check(savedPNG == png, "Portrait bytes survive saving")
            do { try store.save(EmberCreation(sessionID:UUID(),name:"Bad",paint:nil,scales:[],backdrop:.forest,yaw:0),png:Data()); check(false,"Invalid image must fail") }
            catch { check(store.entries.count == 1,"Failed save leaves existing creations intact") }
            try Data("broken index".utf8).write(to:testFolder.appendingPathComponent("gallery.json"))
            let damaged = EmberGalleryStore(folder:testFolder)
            check(damaged.errorMessage != nil, "Unreadable gallery reports an error")
            do { try damaged.save(entry,png:png); check(false,"Corrupt index must not be overwritten") }
            catch { check(true,"Corrupt gallery cannot be silently replaced") }
        } catch { preconditionFailure("Gallery validation failed: \(error)") }
        model.scaleDesign = design
        let oldPhotoID = model.photoSessionID
        model.replay()
        check(model.scaleDesign.isEmpty && oldPhotoID != model.photoSessionID, "Replay resets the live pattern and photo session")
        check(AssetResidency.assets(for:.introduction) == ["EmberSleepingWinglessHornlessVisual"], "Introduction requests only the sleeping character")
        check(AssetResidency.assets(for:.magicSetup) == ["EmberAwakeWinglessHornlessVisual"], "Calibration does not preload attachments")
        check(!AssetResidency.assets(for:.horns).contains("WingVisual"), "Horn stage does not preload wings")
        check(!AssetResidency.assets(for:.painting).contains("MagicBrushVisual"), "Painting generates its brush instead of loading the heavy archive")
        check(!AssetResidency.assets(for:.complete).contains("MagicBrushVisual"), "Finale releases the brush")
        for phase in GameModel.playablePhases {
            let requested = AssetResidency.assets(for:phase)
            let bodies = requested.filter { $0.hasPrefix("EmberAwake") || $0.hasPrefix("EmberSleeping") }
            check(bodies.count == 1, "Each playable phase requests exactly one body")
        }
        var demand = AssetDemand()
        demand.request(AssetResidency.assets(for:.introduction),owner:"game")
        demand.request(AssetResidency.portrait,owner:"gallery")
        demand.request(AssetResidency.assets(for:.horns),owner:"game")
        check(!demand.wanted.contains("EmberSleepingWinglessHornlessVisual"), "Stage changes relinquish old body sources")
        check(demand.wanted.contains("EmberAwakeFullVisual"), "Another view retains its independently requested assets")
        demand.release("gallery")
        check(demand.wanted == AssetResidency.assets(for:.horns), "Closing gallery retains only the live game request")
        demand.release("game")
        check(demand.wanted.isEmpty, "Closing all views empties the source cache demand")
        var bilateral = BilateralPractice()
        for _ in 0..<60 { bilateral.update(left:1,right:0,engaged:true,deltaTime:0.05) }
        check(!bilateral.returning && bilateral.cycles == 0, "One arm alone cannot open both wings")
        for _ in 0..<10 { bilateral.update(left:1,right:1,engaged:true,deltaTime:0.05) }
        bilateral.update(left:1,right:1,engaged:false,deltaTime:0.05)
        check(bilateral.hold > 0 && bilateral.hold < 1, "Tracking interruption freezes the incomplete bilateral hold")
        for cycle in 0..<10 {
            for _ in 0..<21 { bilateral.update(left:1,right:1,engaged:true,deltaTime:0.05) }
            check(bilateral.returning && bilateral.cycles == cycle, "Both arms hold open before returning")
            for _ in 0..<21 { bilateral.update(left:0,right:0,engaged:true,deltaTime:0.05) }
            check(bilateral.cycles == cycle+1, "A full simultaneous return earns one rep")
        }
        check(bilateral.complete && bilateral.fill == 1, "Ten bilateral cycles complete the exercise")
        var brush = BrushRepetitions()
        for _ in 0..<100 { brush.update(horizontal:0.04,inside:true) }
        check(brush.halfStrokes == 0, "Stationary painting never counts")
        for _ in 0..<100 { brush.update(horizontal:0.001,inside:true) }
        check(brush.halfStrokes == 0, "Tiny tracking jitter never counts as a brush stroke")
        brush.update(horizontal:-0.04,inside:false)
        check(brush.halfStrokes == 0, "Outside the panel does not count")
        for i in 0..<8 { brush.update(horizontal:i.isMultiple(of:2) ? -0.04 : 0.04,inside:true) }
        check(brush.complete, "Four back-and-forth brush repetitions finish a region")
        model.regionPaint = [.head:.orange,.body:.teal]
        model.randomizePalette()
        check(model.regionPaint[.head] == .orange && model.regionPaint[.body] == .teal, "Palette randomizer preserves completed regions")
        model.reachSamples = [.zero,[0,0,-0.3],[-0.4,0,0],[0.4,0,0],[0,0.2,0],[0,-0.2,0],[0,0,0.15]]
        model.comfortSettings.movementAmount = .standard
        let bigger = model.wingExcursion
        check(abs(model.reachTarget([-1,0,0]).x + 0.36)<0.0001, "Standard targets use 90 percent of measured reach")
        model.reachSamples[2].x = -0.15; model.reachSamples[3].x = 0.15
        check(model.wingExcursion < bigger, "Smaller measured reach reduces the wing excursion")
        var returning = ReachCapture()
        for _ in 0..<40 { _ = returning.update(position:.zero,deltaTime:0.05) }
        for _ in 0..<60 { _ = returning.update(position:[0,0,-0.12],deltaTime:0.05) }
        for _ in 0..<100 { _ = returning.update(position:[-0.12,0,-0.12],deltaTime:0.05) }
        check(returning.samples.count == 3, "Direct movement to the next direction needs no return-to-rest step")
        let free = ScaleDecoration(slot:100,shape:.diamond,quarterTurns:2,surfacePosition:[0.1,-0.1,0.1],surfaceNormal:[0,0,1],finalPosition:[0.11,-0.1,0.1],finalNormal:[0,0,1])
        check(ScaleDesignLayout.valid([free]), "Freeform surface placements need no fixed socket")
        do {
            let custom = EmberCreation(sessionID:UUID(),name:"Personal Ember",paint:nil,scales:[free],backdrop:.forest,yaw:0,framing:PhotoFraming(zoom:2.25,x:-0.17,y:0.28),regionPaint:[.head:.orange,.back:.blue])
            let decoded = try JSONDecoder().decode(EmberCreation.self,from:JSONEncoder().encode(custom))
            check(decoded.framing == custom.framing,"Gallery round trip preserves zoom and drag composition for portrait refresh")
            check(decoded == custom, "Freeform pattern and individual region colours round-trip through saving")
            let oldData = try JSONEncoder().encode(entry)
            var object = try JSONSerialization.jsonObject(with:oldData) as! [String:Any]
            object.removeValue(forKey:"regionPaint")
            let legacy = try JSONDecoder().decode(EmberCreation.self,from:JSONSerialization.data(withJSONObject:object))
            check(legacy.framing == nil,"Existing gallery saves without framing remain readable")
            check(legacy.regionPaint == nil && legacy.scales == design, "Older gallery entries still decode")
        } catch { preconditionFailure("V8 persistence validation failed: \(error)") }
        let positive = simd_quatf(angle:Float.pi/4,axis:[0,0,1])
        check(abs(signedWristTurnDegrees(current:positive,initial:simd_quatf(angle:0,axis:[0,1,0]),forearmAxis:[0,0,-1],towardViewer:[0,0,1])-45)<0.001, "Wrist direction is preserved when the forearm points away")
        check(abs(signedWristTurnDegrees(current:positive.inverse,initial:simd_quatf(angle:0,axis:[0,1,0]),forearmAxis:[0,0,-1],towardViewer:[0,0,1])+45)<0.001, "Opposite wrist turn rotates the horn the opposite way")
        check(abs(signedWristTurnDegrees(current:simd_quatf(vector:-positive.vector),initial:simd_quatf(angle:0,axis:[0,1,0]),forearmAxis:[0,0,-1],towardViewer:[0,0,1])-45)<0.001, "Equivalent quaternion signs cannot cause a rotation jump")
        var interrupted = BilateralPractice()
        for _ in 0..<21 { interrupted.update(left:1,right:1,engaged:true,deltaTime:0.05) }
        interrupted.update(left:1,right:1,engaged:false,deltaTime:0.05)
        for _ in 0..<30 { interrupted.update(left:0,right:0,engaged:true,deltaTime:0.05) }
        check(interrupted.cycles == 1, "An interrupted open hold resumes into a tracked held return")
        for pitch: Float in [-1.5707963,-0.6,0,0.7,1.5707963] {
            for roll: Float in [-0.6,0,0.7] {
                let head = simd_float4x4(simd_quatf(angle:0.4,axis:[0,1,0]) * simd_quatf(angle:pitch,axis:[1,0,0]) * simd_quatf(angle:roll,axis:[0,0,1]))
                let upright = levelSceneOrientation(head)
                check(simd_distance(upright.act([0,1,0]),[0,1,0])<0.0001, "Reclined and tilted viewing never tilts the nest")
                check(upright.vector.x.isFinite && upright.vector.w.isFinite, "Vertical viewing produces a finite upright rotation")
            }
        }
        for scale: Float in [0.15,0.5,1] {
            let low = SIMD3<Float>(-0.5,-0.2,-0.4)*scale, high = SIMD3<Float>(0.5,0.6,0.4)*scale
            let layout = SceneChromeLayout(minimum:low,maximum:high)
            check(layout.activity.x >= 0.38 && layout.activity.x <= 0.52, "Activity strip stays close beside Ember")
            check(layout.activity.z <= 0.28 && layout.pause.z <= 0.305, "Controls never advance into the wearer’s near space")
            check(layout.pause.y <= 0.43 && layout.instruction.y <= 0.32, "Instruction and pause anchors stay below the eye line")
        }
        // The old fixed Z=0.30 sat underneath the actual front edge at Z=0.58.
        // Exercise the translated, resized nest and a decoration extending past its edge.
        for scale: Float in [0.75,0.85,1,1.5,2.5] {
            let offset = SIMD3<Float>(0.06,-0.2,0.12)
            let low = SIMD3<Float>(-0.46,-0.064,-0.46)*scale+offset
            let high = SIMD3<Float>(0.46,0.035,0.46)*scale+offset
            for extraFront: Float in [0,0.12] {
                let front = high.z+extraFront
                let bar = SceneMoveHandleLayout.position(nestMinimum:low,nestMaximum:high,gardenFront:front)
                check(bar.z-SceneMoveHandleLayout.hitSize.z/2 > front+0.05, "Move bar hit target clears the garden front at every scene size")
                check(bar.y-SceneMoveHandleLayout.hitSize.y/2 > high.y, "Move bar stays above the nest surface rather than hidden below it")
                check(abs(bar.x-offset.x)<0.0001, "Move bar stays centred on the translated nest")
                check(bar.y-high.y < 0.06 && bar.z-front < 0.10, "Move bar stays close to the rim without a distant floating control")
            }
        }
        check(capture.samples.count == 4 && capture.envelopeSamples.count == 7, "Four real poses produce the compatible reach envelope")
        check(capture.envelopeSamples[4].y <= 0.09, "Unmeasured vertical reach remains conservative")
        check(relaxedGripDetected(distances:[0.025,nil,0.03,nil],palmLength:0.06), "Two visible curled fingers can establish a relaxed fist")
        check(!relaxedGripDetected(distances:[nil,nil,nil,nil],palmLength:0.06), "Missing fingers never invent a fist")
        check(!relaxedGripDetected(distances:[0.14,0.14,0.15,0.13],palmLength:0.06), "An open hand does not become a fist")
        var freeze = BilateralPractice()
        for _ in 0..<10 { freeze.update(left:1,right:1,engaged:true,deltaTime:0.05) }
        let progress = freeze.fill
        for _ in 0..<200 { freeze.update(left:1,right:1,engaged:false,deltaTime:0.05) }
        check(freeze.fill == progress && freeze.cycles == 0, "No progress or regression during missing hand data")
        let lo = SIMD3<Float>(-0.4,0.1,0.1), hi = SIMD3<Float>(0.4,0.4,0.6)
        for side in [true,false] {
            let route = hornRoute(minimum:lo,maximum:hi,obstacleMin:[-0.2,-0.1,-0.2],obstacleMax:[0.2,0.3,0.25],left:side)
            check(route.count == 6, "A clear horn corridor has six varied positions")
            for point in route {
                check((0..<3).allSatisfy { point[$0] >= lo[$0] && point[$0] <= hi[$0] }, "Horn checkpoints stay inside measured reach")
                check(point.z >= 0.335, "Entire horn route clears the body by the prop radius")
            }
            check(zip(route,route.dropFirst()).reduce(Float(0)) { $0+simd_distance($1.0,$1.1) } > 0.5, "Reach route retains meaningful travel")
        }
        check(hornRoute(minimum:[-0.1,0,0],maximum:[0.1,0.1,0.1],obstacleMin:[-0.3,-0.3,-0.3],obstacleMax:[0.3,0.3,0.3],left:true).isEmpty, "Blocked reach asks for repositioning rather than spawning inside Ember")
        let leftRoute = hornRoute(minimum:lo,maximum:hi,obstacleMin:[-0.2,-0.1,-0.2],obstacleMax:[0.2,0.3,0.25],left:true)
        let rightRoute = hornRoute(minimum:lo,maximum:hi,obstacleMin:[-0.2,-0.1,-0.2],obstacleMax:[0.2,0.3,0.25],left:false)
        check(leftRoute.first!.x < -0.2 && rightRoute.first!.x > 0.2, "Horns spawn on clearly opposite sides, never at the averaged centre")
        check(leftRoute.allSatisfy { $0.x < 0 } && rightRoute.allSatisfy { $0.x > 0 }, "Each horn keeps its matching side corridor")
        check(leftRoute.map(\.x).max()!-leftRoute.map(\.x).min()! > 0.3, "Horn path spans most of its reachable side")
        let blockedLeft = hornRoute(minimum:[-0.1,0,0],maximum:[0.6,0.3,0.1],obstacleMin:[-0.2,-0.1,-0.2],obstacleMax:[0.2,0.3,0.25],left:true)
        check(blockedLeft.isEmpty, "A blocked left corridor must not silently become a right-hand route")
        model.reachSamples = [.zero,[0,0,-0.3],[-0.5,0,0],[0.5,0,0],[0,0.1,0],[0,-0.1,0],[0,0,0.1]]
        check(model.wingExcursion > 0.3, "Wider measured reach is no longer capped at 16 centimetres")
        check(abs(model.wingTravel(startX:-0.1,left:true)-0.35)<0.001, "Left wing endpoint respects the measured left boundary")
        check(abs(model.wingTravel(startX:0.1,left:false)-0.35)<0.001, "Right wing endpoint respects the measured right boundary")
        var fullRange = BilateralPractice()
        for _ in 0..<50 { fullRange.update(left:0.8,right:0.8,engaged:true,deltaTime:0.05) }
        check(!fullRange.returning, "Partial wing travel no longer prematurely satisfies the open hold")
        let deepRoute = hornRoute(minimum:lo,maximum:hi,obstacleMin:[-0.2,-0.1,-0.2],obstacleMax:[0.2,0.3,0.25],left:true)
        check(deepRoute.map(\.z).max()!-deepRoute.map(\.z).min()! > 0.2, "A free depth corridor requires forward and backward reach")
        let standardReach = model.wingTravel(startX:-0.1,left:true)
        model.comfortSettings.movementAmount = .gentle
        check(model.wingTravel(startX:-0.1,left:true) < standardReach, "Gentle visibly reduces the same calibrated excursion")
        model.comfortSettings.movementAmount = .standard
        let freePoint = clearReachPoint([0,0.2,0.2],minimum:lo,maximum:hi,obstacleMin:[-0.2,0,-0.2],obstacleMax:[0.2,0.3,0.25])
        check(freePoint != nil, "An intersecting hand guide can move into available clear space")
        if let q = freePoint {
            check(q.z >= 0.35 || q.y >= 0.4 || abs(q.x) >= 0.3, "Hand guide clears the expanded body bounds")
            check((0..<3).allSatisfy { q[$0] >= lo[$0] && q[$0] <= hi[$0] }, "Relocated guides remain inside measured reach")
        }
        check(clearReachPoint(.zero,minimum:[-0.1,-0.1,-0.1],maximum:[0.1,0.1,0.1],obstacleMin:[-1,-1,-1],obstacleMax:[1,1,1]) == nil, "No hand target is invented when Ember fills the reachable space")
        var slowReach = ReachCapture()
        for _ in 0..<20 { _ = slowReach.update(position:.zero,deltaTime:0.05) }
        for _ in 0..<18 { _ = slowReach.update(position:[0,0,-0.05],deltaTime:0.05) }
        check(slowReach.samples.count == 1, "An early pause during reaching does not immediately capture a tiny range")
        model.currentPhase = .celebration; model.isPaused = false
        model.preparePhotoBooth()
        check(model.currentPhase == .complete && model.isPhotoBoothPresented, "Every photo entry marks the scene for input suspension")
        model.isPhotoBoothPresented = false
        model.preparePhotoBooth()
        check(model.isPhotoBoothPresented, "Closing and reopening the booth is supported")
        model.requestHornGrip(0)
        check(model.hornGripRequest == 0, "An explicit left grip request is independent of fingertip classification")
        let gripRevision = model.hornGripRevision
        model.requestHornGrip(nil)
        check(model.hornGripRequest == nil && model.hornGripRevision > gripRevision, "Release explicitly clears the grip request")
        var gripLatch = WristGripLatch()
        gripLatch.observe(isGrip:false,near:true)
        check(!gripLatch.isHeld, "Proximity alone never automatically grabs a horn")
        gripLatch.observe(isGrip:true,near:true)
        gripLatch.observe(isGrip:false,near:false)
        check(gripLatch.isHeld, "Losing fingertip classification does not release an intentional grip")
        gripLatch.release()
        check(!gripLatch.isHeld, "Explicit release ends the grip")
        gripLatch.engage()
        check(gripLatch.isHeld, "Grip button works independently of closed-finger detection")
        print("Passed \(checks) gameplay and calibration checks")
    }
}
