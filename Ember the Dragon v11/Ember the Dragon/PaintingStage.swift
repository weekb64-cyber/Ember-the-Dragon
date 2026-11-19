import RealityKit
import UIKit

extension PaintChoice {
    var uiColor: UIColor {
        switch self {
        case .orange: UIColor(red:1, green:0.46, blue:0.08, alpha:1)
        case .teal: UIColor(red:0.13, green:0.70, blue:0.66, alpha:1)
        case .coral: UIColor(red:0.96,green:0.39,blue:0.30,alpha:1)
        case .lavender: UIColor(red:0.63,green:0.49,blue:0.83,alpha:1)
        case .blue: UIColor(red:0.22,green:0.49,blue:0.81,alpha:1)
        case .mint: UIColor(red:0.40,green:0.77,blue:0.58,alpha:1)
        case .gold: UIColor(red:0.96,green:0.72,blue:0.22,alpha:1)
        case .rose: UIColor(red:0.89,green:0.43,blue:0.61,alpha:1)
        case .white: UIColor(white:0.96, alpha:1)
        }
    }
}

@MainActor
final class PaintingStage: GameStage {
    let instruction = "Paint Ember your way"
    private let root: Entity
    private let model: GameModel
    private let dragon: DragonController
    private let brush = Entity()
    private let tip = Entity()
    private var paletteEntity = Entity()
    private var paletteRevision = 0
    private var held = false
    private var colourChosen = false
    private let brushHighlight = makeObjectHighlight(width:0.065,height:0.22)
    private var brushSound = BrushSoundMotion()
    private var repetitions = BrushRepetitions()
    private var regionIndex = 0
    private var target = SIMD3<Float>(0,0.2,0.25)
    private let panel = Entity()
    private let hand = makeGuideHand(name:"RightPaintingHandGuide",opacity:0.4)
    private var time: Float = 0
    private var spawn = SIMD3<Float>.zero
    private var nestTop: Float { root.parent?.findEntity(named:"LightweightMossNest")?.visualBounds(relativeTo:root).max.y ?? model.configuration.layout.nestPosition.y+0.06 }
    private var swatches: [PaintChoice:ModelEntity] = [:]
    init(root: Entity, model: GameModel, dragon: DragonController) { self.root = root; self.model = model; self.dragon = dragon }
    func start() {
        model.regionPaint = [:]; model.paintingComplete = false; model.paintingFill = 0
        let body = dragon.root.visualBounds(relativeTo:root)
        let chrome = SceneChromeLayout(minimum:body.min,maximum:body.max)
        spawn = chrome.activity + [-0.08,-0.05,0.06]
        target = model.reachTarget([0,0,-0.3])
        spawn.y = max(spawn.y,nestTop+0.12)
        brush.name = "PaintingBrush"; brush.position = spawn; brush.orientation = simd_quatf(angle:-Float.pi/2,axis:[1,0,0]); brush.addChild(makeLightweightBrush())
        brushHighlight.position = [0,0,0.025]; brush.addChild(brushHighlight)
        tip.position = [0,0.08,0]; brush.addChild(tip); brush.setInteraction(boxSize:[0.13,0.27,0.12]); root.addChild(brush)
        for (size,offset) in [(SIMD3<Float>(0.16,0.003,0.003),SIMD3<Float>(0,0.065,0)),([0.16,0.003,0.003],[0,-0.065,0]),([0.003,0.13,0.003],[-0.08,0,0]),([0.003,0.13,0.003],[0.08,0,0])] {
            let edge = ModelEntity(mesh:.generateBox(size:size),materials:[EmberMaterials.soft(.white,roughness:0.8)])
            edge.position = offset; panel.addChild(edge)
        }
        panel.position = target; root.addChild(panel); root.addChild(hand)
        buildPalette(); paletteRevision = model.paletteRevision
        dragon.applyRegionalPaint(model.regionPaint)
    }
    private func buildPalette() {
        paletteEntity.removeFromParent(); swatches.removeAll(); paletteEntity = makeArtistPalette()
        let body = dragon.root.visualBounds(relativeTo:root)
        let chrome = SceneChromeLayout(minimum:body.min,maximum:body.max)
        paletteEntity.position = [-chrome.activity.x,max(nestTop+0.13,0.04),chrome.activity.z]
        paletteEntity.scale = [0.80,0.80,0.80]
        paletteEntity.orientation = simd_quatf(angle:-0.25,axis:[1,0,0])
        root.addChild(paletteEntity)
        let positions: [SIMD3<Float>] = [[0,0.067,0.023],[0.085,0.005,0.023],[0.015,-0.065,0.023]]
        for (index,colour) in model.palette.enumerated() {
            let swatch = ModelEntity(mesh:.generateSphere(radius:0.033),materials:[EmberMaterials.soft(colour.uiColor,roughness:0.35)])
            swatch.name = "PaintPalette"+colour.rawValue; swatch.position = positions[index]; swatch.scale = [1,0.88,0.24]
            swatch.components.set(HoverEffectComponent())
            swatch.setInteraction(boxSize:[0.085,0.085,0.20]); paletteEntity.addChild(swatch); swatches[colour] = swatch
        }
        updateSelection()
    }
    private func updateSelection() {
        for (colour,swatch) in swatches { swatch.scale = SIMD3<Float>(1,0.88,0.24)*(colour == model.selectedPaint ? 1.15 : 1) }
    }
    func handleAction(entity: Entity) -> Bool {
        guard let colour = model.palette.first(where: { entity.name == "PaintPalette"+$0.rawValue || entity.isDescendant(named:"PaintPalette"+$0.rawValue) }) else { return false }
        colourChosen = true; model.selectedPaint = colour; updateSelection(); GameAudio.shared.play(.paintDip); return true
    }
    func drag(entity: Entity, start: SIMD3<Float>, delta: SIMD3<Float>) {
        guard entity === brush else { return }
        var point = start+delta; point.z = target.z - brush.orientation.act(tip.position).z
        brush.position = point; held = true
    }
    func setBrushHeld(_ value: Bool) { held = value; if !value { stopBrushSound() } }
    func release(entity: Entity) { endDrag() }
    func endDrag() { held = false; repetitions.release(); stopBrushSound() }
    private func stopBrushSound() { brushSound.reset(); GameAudio.shared.stop(.brushStroke) }
    func update(deltaTime: Float) {
        time += deltaTime
        if paletteRevision != model.paletteRevision { paletteRevision = model.paletteRevision; buildPalette() }
        guard regionIndex < PaintRegion.allCases.count else { panel.isEnabled = false; hand.isEnabled = false; stopBrushSound(); return }
        let region = PaintRegion.allCases[regionIndex]
        model.paintingRegion = region.title
        // Show back and tail in context while their region is painted; return front for other parts.
        dragon.root.orientation = simd_quatf(angle:(region == .back || region == .tail) ? .pi : 0,axis:[0,1,0])
        let site: SIMD3<Float>
        switch region {
        case .head: site = [0,0.17,0.22]
        case .body: site = [0,-0.05,0.18]
        case .back: site = [0,-0.05,-0.18]
        case .arms: site = [-0.12,-0.10,0.10]
        case .legs: site = [0,-0.23,0.14]
        case .leftWing: site = [-0.20,0.02,0]
        case .rightWing: site = [0.20,0.02,0]
        case .tail: site = [0,-0.18,-0.27]
        }
        target = dragon.root.convert(position:site,to:root) + [0,0,0.04]
        let surfaceBounds: BoundingBox
        if region == .leftWing { surfaceBounds = dragon.parts.leftWingControl.visualBounds(relativeTo:root) }
        else if region == .rightWing { surfaceBounds = dragon.parts.rightWingControl.visualBounds(relativeTo:root) }
        else { surfaceBounds = dragon.parts.bodyControl.visualBounds(relativeTo:root) }
        // Put the complete painting plane in front of the visible surface, including the snout.
        target.z = max(target.z,surfaceBounds.max.z+0.065)
        panel.position = target
        model.activityHint = colourChosen ? "Sweep the brush left and right across the outlined \(region.title.lowercased()).\nFour back-and-forth sweeps fill this part’s ring.\nSelect another palette colour whenever you like." : "Choose a colour from the palette on your left.\nPick up the brush on your right, then sweep it\nleft and right across the outlined part."
        brushHighlight.isEnabled = !held

        hand.position = target + [sin(time*2)*0.065,0,0.025]; hand.isEnabled = !held
        if held && colourChosen {
            let offset = tip.position(relativeTo:root)-target
            let inside = abs(offset.y)<0.085 && abs(offset.x)<0.11 && abs(offset.z)<0.06
            repetitions.update(horizontal:offset.x,inside:inside)
            if brushSound.update(horizontal:offset.x,touching:inside,deltaTime:deltaTime) { GameAudio.shared.play(.brushStroke) }
            if !inside { GameAudio.shared.stop(.brushStroke) }
        } else { stopBrushSound() }
        model.paintingFill = repetitions.fill
        if repetitions.complete {
            model.regionPaint[region] = model.selectedPaint
            dragon.applyRegionalPaint(model.regionPaint)
            stopBrushSound(); GameAudio.shared.play(.success)
            regionIndex += 1; repetitions = BrushRepetitions(); held = false
            if regionIndex == PaintRegion.allCases.count {
                model.paintingComplete = true; model.activityHint = "Every part has its own colour. Your Ember is ready for a portrait!"
                dragon.root.orientation = simd_quatf(angle:0,axis:[0,1,0])
            }
        }
    }
    func cleanup() { stopBrushSound(); dragon.root.orientation = simd_quatf(angle:0,axis:[0,1,0]); held = false; root.removeAllChildren() }
}
