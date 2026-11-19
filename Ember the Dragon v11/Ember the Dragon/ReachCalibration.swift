import Foundation
import RealityKit
import ARKit
import SwiftUI

struct TrackedHandPose {
    let palm: SIMD3<Float>
    let pinch: SIMD3<Float>
    let orientation: simd_quatf
    let pinching: Bool
    let fist: Bool
    let forearmAxis: SIMD3<Float>
}

@MainActor
final class ReachTrackingService {
    static let shared = ReachTrackingService()
    private var session = ARKitSession()
    private var provider = HandTrackingProvider()
    private var world = WorldTrackingProvider()
    private var task: Task<Void, Never>?
    private var hands: [HandAnchor.Chirality: (TrackedHandPose, TimeInterval)] = [:]
    private var chosenHand: HandAnchor.Chirality?
    private(set) var status = "Starting hand tracking…"
    private(set) var available = false
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    func start() {
        guard task == nil, !isSimulator else { return }
        guard HandTrackingProvider.isSupported else { status = "Hand tracking unavailable. Use Skip stage."; return }
        session = ARKitSession(); provider = HandTrackingProvider(); world = WorldTrackingProvider()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let authorization = await session.requestAuthorization(for: [.handTracking])
            guard !Task.isCancelled else { return }
            do {
                if authorization[.handTracking] == .allowed {
                    try await session.run([world, provider])
                    guard !Task.isCancelled else { return }
                    available = true
                    status = "Move gently with your hands visible."
                    for await update in provider.anchorUpdates {
                        guard !Task.isCancelled else { break }
                        let anchor = update.anchor
                        guard update.event != .removed, anchor.isTracked else { hands[anchor.chirality] = nil; continue }
                        func point(_ name: HandSkeleton.JointName) -> SIMD3<Float>? {
                            guard let skeleton = anchor.handSkeleton else { return nil }
                            let joint = skeleton.joint(name)
                            guard joint.isTracked else { return nil }
                            let t = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
                            return SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z)
                        }
                        let wrist = point(.wrist)
                        let knuckle = point(.middleFingerKnuckle) ?? point(.indexFingerKnuckle)
                        let anchorPosition = SIMD3<Float>(anchor.originFromAnchorTransform.columns.3.x,anchor.originFromAnchorTransform.columns.3.y,anchor.originFromAnchorTransform.columns.3.z)
                        let palm = wrist.flatMap({ w in knuckle.map { (w+$0)*0.5 } }) ?? point(.middleFingerMetacarpal) ?? wrist ?? anchorPosition
                        let index = point(.indexFingerTip), thumb = point(.thumbTip)
                        let curled = [point(.indexFingerTip),point(.middleFingerTip),point(.ringFingerTip),point(.littleFingerTip)]
                        let palmLength = max(0.045,wrist.map { simd_distance($0,palm) } ?? 0.06)
                        let bent = [
                            (point(.indexFingerKnuckle),point(.indexFingerIntermediateBase)),
                            (point(.middleFingerKnuckle),point(.middleFingerIntermediateBase)),
                            (point(.ringFingerKnuckle),point(.ringFingerIntermediateBase))
                        ].filter { base,next in
                            guard let wrist, let base, let next else { return false }
                            let a = base-wrist, b = next-base
                            guard simd_length_squared(a)>0.00001,simd_length_squared(b)>0.00001 else { return false }
                            return simd_dot(simd_normalize(a),simd_normalize(b)) < 0.55
                        }.count
                        let closed = relaxedGripDetected(distances:curled.map { $0.map { simd_distance($0,palm) } },palmLength:palmLength) || bent >= 2
                        let pinch = index != nil && thumb != nil ? (index!+thumb!)/2 : palm
                        let pinching = index != nil && thumb != nil && simd_distance(index!,thumb!) < 0.03
                        let forearm = wrist.map { palm-$0 } ?? SIMD3<Float>(0,0,-1)
                        let axis = simd_length_squared(forearm) > 0.00001 ? simd_normalize(forearm) : SIMD3<Float>(0,0,-1)
                        let pose = TrackedHandPose(palm:palm,pinch:pinch,orientation:simd_quatf(anchor.originFromAnchorTransform),pinching:pinching,fist:closed,forearmAxis:axis)
                        hands[anchor.chirality] = (pose,CACurrentMediaTime())
                    }
                } else {
                    try await session.run([world])
                    status = "Allow hand tracking in Settings, or use Skip stage."
                }
            } catch { status = "Tracking could not start. Exit and reopen the activity." }
        }
    }
    func pose(left: Bool) -> TrackedHandPose? {
        guard provider.state == .running, let (pose,time) = hands[left ? .left : .right], CACurrentMediaTime()-time < 0.12 else { return nil }
        return pose
    }
    func headTransform() -> simd_float4x4? {
        guard world.state == .running, let anchor = world.queryDeviceAnchor(atTimestamp:CACurrentMediaTime()), anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }
    func resetCalibrationHand() { chosenHand = nil }
    func palmPosition() -> SIMD3<Float>? {
        if chosenHand == nil { if pose(left:false) != nil { chosenHand = .right } else if pose(left:true) != nil { chosenHand = .left } }
        return pose(left:chosenHand == .left)?.palm
    }
    func stop() { task?.cancel(); task = nil; session.stop(); available = false; hands.removeAll(); chosenHand = nil }
}

@MainActor
final class ReachCalibrationStage: GameStage {
    let instruction = "Find your comfortable reach"
    private let root: Entity
    private let model: GameModel
    private let tracker = ReachTrackingService.shared
    private var capture = ReachCapture()
    private let previewHand = makeGuideHand(name: "CalibrationPreviewHand", opacity: 0.65)
    private let demonstration = makeGuideHand(name: "ReachDemonstration", opacity: 0.25)
    
    private var elapsed: Float = 0
    private var previewBaseDepth: Float = 0.25

    init(root: Entity, model: GameModel) { self.root = root; self.model = model }
    func start() {
        model.reachSamples = []
        model.hasPhysicalCalibration = false
        model.simulatedHandDepth = 0
        previewHand.position = [-0.35,0.2,previewBaseDepth]
        previewHand.scale = [1.3,1.3,1.3]
        demonstration.scale = [0.85,0.85,0.85]
        previewHand.isEnabled = tracker.isSimulator
        if tracker.isSimulator { previewHand.setInteraction(boxSize: [0.13,0.18,0.09]) }
        root.addChild(previewHand)
        root.addChild(demonstration)
        tracker.resetCalibrationHand()
        tracker.start()
        model.calibrationIsSimulated = tracker.isSimulator
        model.calibrationIsPreparing = true
        model.calibrationMessage = "Ember is waking up…"
        demonstration.isEnabled = false; previewHand.isEnabled = false
    }
    func update(deltaTime: Float) {
        elapsed += min(deltaTime,0.1)
        guard elapsed >= 2.2 else {
            model.calibrationIsPreparing = true
            model.calibrationMessage = elapsed < 1 ? "Ember is waking up…" : "Get comfortable. We’ll measure your reach next."
            demonstration.isEnabled = false; previewHand.isEnabled = false
            model.calibrationHold = 0
            return
        }
        model.calibrationIsPreparing = false
        previewHand.isEnabled = tracker.isSimulator
        let position: SIMD3<Float>?
        if tracker.isSimulator {
            previewHand.position.z = previewBaseDepth + model.simulatedHandDepth
            position = previewHand.position
        } else if let world = tracker.palmPosition() {
            position = root.convert(position: world, from: nil)
        } else { position = nil }
        if capture.update(position: position, deltaTime: deltaTime) {
            GameAudio.shared.play(capture.complete ? .complete : .success)
            model.reachSamples = capture.envelopeSamples
            model.hasPhysicalCalibration = capture.complete && !tracker.isSimulator
        }
        let message = !tracker.isSimulator && position == nil ? tracker.available ? "Hand out of view. Bring the same hand in front of your chest, fingers visible." : tracker.status : capture.instruction
        if model.calibrationMessage != message { model.calibrationMessage = message }
        model.calibrationStep = capture.samples.count
        model.calibrationHold = capture.complete ? 1 : capture.holdProgress
        let neutral = capture.samples.first ?? position ?? SIMD3<Float>(0,0.2,0.25)
        demonstration.isEnabled = !capture.complete
        demonstration.position = neutral + capture.direction * ((1-cos(elapsed * .pi / 2.5))*0.06)
        // Keep the example hand clear of the instruction card to the left of Ember.
        if demonstration.position.x < -0.20 && demonstration.position.y > 0.13 {
            demonstration.position.y = 0.08
        }
    }
    func resetAfterSceneMove() {
        capture = ReachCapture(); elapsed = 0
        model.reachSamples = []; model.hasPhysicalCalibration = false
        model.calibrationStep = 0; model.calibrationHold = 0
        tracker.resetCalibrationHand()
        model.calibrationMessage = "Scene moved. Rest your hand to measure this position."
    }
    func cleanup() { model.calibrationIsPreparing = false; root.removeAllChildren() }
}
