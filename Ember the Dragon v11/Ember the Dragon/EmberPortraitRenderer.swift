import Foundation
import SceneKit
import Metal
import UIKit
import RealityKitContent

/// Offscreen, app-only portrait: never captures the room or the wearer.
@MainActor
final class EmberPortraitRenderer {
    private let renderer: SCNRenderer
    private let subject = SCNNode()
    init(paint: PaintChoice?, scales: [ScaleDecoration], regions: [PaintRegion:PaintChoice] = [:]) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let folder = realityKitContentBundle.url(forResource:"PhotoBoothAssets",withExtension:nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        renderer = SCNRenderer(device:device,options:nil)
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(subject)
        let body = try Self.load(folder.appendingPathComponent("EmberAwakeFullVisual.usdz"),size:0.73,height:true)
        body.simdPosition = PebbleForm.complete.offset
        if let paint {
            guard let textures = realityKitContentBundle.url(forResource:"PebbleTextures",withExtension:nil),
                  let image = UIImage(contentsOfFile:textures.appendingPathComponent("EmberAwakeFullVisual_\(paint.assetSuffix).jpg").path) else { throw CocoaError(.fileReadNoSuchFile) }
            body.enumerateChildNodes { node, _ in node.geometry?.materials.forEach { $0.diffuse.contents = image } }
        }
        if !regions.isEmpty, let image = RegionalPaintTextures.image(asset:"EmberAwakeFullVisual",regions:regions) {
            body.enumerateChildNodes { node,_ in node.geometry?.materials.forEach { $0.diffuse.contents = UIImage(cgImage:image) } }
        }
        subject.addChildNode(body)
        let leaf = try Self.load(folder.appendingPathComponent("MagicScaleVisual_Grey.usdz"),size:AssetScaleConfiguration.current.scaleSize,height:false)
        for item in scales {
            let socket = SCNNode(); socket.simdPosition = item.position(complete:true)
            socket.simdOrientation = simd_quatf(from:[0,0,1],to:item.normal(complete:true))
            let turn = SCNNode(); turn.eulerAngles.z = Float(item.quarterTurns) * .pi / 2
            let scale: SCNNode
            switch item.shape {
            case .leaf: scale = leaf.clone(); scale.simdScale = [0.58,0.72,0.32]
            case .diamond:
                scale = SCNNode(geometry:SCNBox(width:0.029,height:0.029,length:0.009,chamferRadius:0.006)); scale.eulerAngles.z = .pi/4
            case .round:
                scale = SCNNode(geometry:SCNSphere(radius:0.021)); scale.simdScale = [1,0.8,0.27]
            }
            if item.shape != .leaf {
                let material = SCNMaterial(); material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(red:0.84,green:0.86,blue:0.83,alpha:1); material.roughness.contents = 0.35
                scale.geometry?.materials = [material]
            }
            turn.addChildNode(scale); socket.addChildNode(turn); subject.addChildNode(socket)
        }
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -1.5
        camera.camera?.bloomIntensity = 0
        camera.camera?.orthographicScale = 0.53; camera.camera?.zNear = 0.01; camera.camera?.zFar = 20
        camera.simdPosition = [0,0.12,2.4]; camera.look(at:SCNVector3(0,0.055,0))
        scene.rootNode.addChildNode(camera); renderer.pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 70; ambient.light?.color = UIColor(red:0.85,green:0.91,blue:1,alpha:1); scene.rootNode.addChildNode(ambient)
        for (position,power) in [(SIMD3<Float>(-1,2,2),CGFloat(180)),(SIMD3<Float>(1,1,-1),CGFloat(60))] {
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni; light.light?.intensity = power
            light.simdPosition = position; scene.rootNode.addChildNode(light)
        }
        renderer.scene = scene; renderer.autoenablesDefaultLighting = false
    }
    func render(yaw: Float) throws -> UIImage {
        subject.eulerAngles.y = yaw
        let image = renderer.snapshot(atTime:0,with:CGSize(width:800,height:800),antialiasingMode:.multisampling2X)
        guard image.cgImage != nil else { throw CocoaError(.fileReadUnknown) }
        return image
    }
    private static func load(_ url: URL, size: Float, height: Bool) throws -> SCNNode {
        let scene = try SCNScene(url:url,options:nil)
        let visual = SCNNode()
        for node in scene.rootNode.childNodes { visual.addChildNode(node.clone()) }
        visual.enumerateChildNodes { node,_ in
            node.light = nil; node.camera = nil
            node.geometry?.materials = node.geometry?.materials.map { original in
                let material = original.copy() as! SCNMaterial
                material.lightingModel = .physicallyBased
                material.emission.contents = UIColor.black
                material.emission.intensity = 0
                material.metalness.contents = 0
                material.roughness.contents = 0.8
                material.diffuse.intensity = 0.75
                material.multiply.contents = UIColor(white:0.82,alpha:1)
                return material
            } ?? []
        }
        let bounds = visual.boundingBox
        let extent = SIMD3<Float>(bounds.max.x-bounds.min.x,bounds.max.y-bounds.min.y,bounds.max.z-bounds.min.z)
        let denominator = height ? extent.y : max(extent.x,max(extent.y,extent.z))
        guard denominator > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let factor = size/denominator
        visual.simdScale = SIMD3(repeating:factor)
        visual.simdPosition = -SIMD3<Float>(bounds.max.x+bounds.min.x,bounds.max.y+bounds.min.y,bounds.max.z+bounds.min.z) * factor / 2
        let wrapper = SCNNode(); wrapper.addChildNode(visual); return wrapper
    }
}
