import RealityKit
import UIKit

@MainActor
private enum HandOverlayTexture {
    static let fistImage: TextureResource? = {
        guard let image = guideFistImage() else { return nil }
        return try? TextureResource(image:image,options:.init(semantic:.color))
    }()
    static let openImage: TextureResource? = {
        guard let cgImage = guideOpenHandImage() else { return nil }
        return try? TextureResource(image:cgImage,options:.init(semantic:.color))
    }()
    static let image: TextureResource? = {
        guard let cgImage = guideHandImage() else { return nil }
        return try? TextureResource(image:cgImage, options:.init(semantic:.color))
    }()
}

@MainActor
func makeGuideHand(name: String, opacity: Float) -> Entity {
    let hand = Entity()
    hand.name = name
    guard let texture = (name.contains("Fist") ? HandOverlayTexture.fistImage : (name.contains("Calibration") || name.contains("ReachDemonstration") ? HandOverlayTexture.openImage : HandOverlayTexture.image)) else { return hand }
    var material = UnlitMaterial()
    material.color = .init(tint:.white, texture:.init(texture))
    material.blending = .transparent(opacity:.init(floatLiteral:1))
    material.opacityThreshold = 0.04 // Discard the transparent rectangle instead of writing it into depth.
    material.faceCulling = .none
    let overlay = ModelEntity(mesh:.generatePlane(width:0.15,height:0.18),materials:[material])
    overlay.name = "TranslucentHandOverlay"
    if name.contains("Right") { overlay.scale.x = -1 }
    hand.addChild(overlay)
    hand.components.set(OpacityComponent(opacity:min(0.72,max(0.35,opacity))))
    return hand
}

@MainActor
final class GuidancePath {
    let root = Entity()
    private var dots: [ModelEntity] = []
    init() {
        root.name = "GlowingMovementGuide"
        for _ in 0..<12 {
            let dot = ModelEntity(mesh:.generateSphere(radius:0.006),materials:[UnlitMaterial(color:.init(red:1,green:0.84,blue:0.38,alpha:0.8))])
            var glow = UnlitMaterial(color:UIColor(red:1,green:0.78,blue:0.18,alpha:1))
            glow.blending = .transparent(opacity:.init(floatLiteral:0.12))
            // A single surface avoids transparent halo sorting flicker.
            root.addChild(dot); dots.append(dot)
        }
    }
    func pulse(time: Float) {
        for (index,dot) in dots.enumerated() {
            let phase = Float(index)/Float(dots.count)
            let bright = pow(max(0,cos(time*4-phase*Float.pi*2)),6)
            dot.scale = SIMD3<Float>(repeating:0.65 + bright*0.35)
            dot.components.set(OpacityComponent(opacity:0.32 + bright*0.20))
        }
    }
    func update(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        for (i,dot) in dots.enumerated() {
            let t=Float(i+1)/Float(dots.count+1)
            dot.position = start + (end-start)*t + [0,sin(t * .pi)*0.025,0]
        }
    }
}

@MainActor
func makeGhost(of entity: Entity, name: String) -> Entity {
    let ghost = entity.clone(recursive: true)
    ghost.name = name
    ghost.isEnabled = true
    ghost.clearGameplayComponentsRecursively()
    func removeShadow(_ entity: Entity) {
        entity.components.remove(GroundingShadowComponent.self)
        for child in entity.children { removeShadow(child) }
    }
    removeShadow(ghost)
    ghost.applyMaterialRecursively(EmberMaterials.soft(UIColor.white.withAlphaComponent(0.32), roughness:0.4))
    return ghost
}

/// Lightweight, unlit outline to identify interactive tools without a bloom light or extra texture.
@MainActor
func makeObjectHighlight(width: Float, height: Float) -> Entity {
    let group = Entity()
    for (size,position) in [(SIMD3<Float>(width,0.002,0.002),SIMD3<Float>(0,height/2,0)),([width,0.002,0.002],[0,-height/2,0]),([0.002,height,0.002],[-width/2,0,0]),([0.002,height,0.002],[width/2,0,0])] {
        let line = ModelEntity(mesh:.generateBox(size:size,cornerRadius:0.001),materials:[UnlitMaterial(color:.white)])
        line.position = position; group.addChild(line)
    }
    group.components.set(OpacityComponent(opacity:0.65))
    return group
}
