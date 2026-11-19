import Foundation
import RealityKit
import UIKit
import CoreGraphics
import simd

@MainActor
enum RenderedStyle {
    static func install(on root: Entity) async {
        // Use visionOS environment lighting: no additional HDR resource or retained scene graph.
    }
    static func polish(_ entity: Entity, asset: String) {
        if let model = entity as? ModelEntity, var component = model.model {
            component.materials = component.materials.map { original in
                guard var material = original as? PhysicallyBasedMaterial else { return original }
                let organic = asset.hasPrefix("EmberAwake") || asset.hasPrefix("EmberSleeping") || asset.contains("Body") || asset.contains("Wing") || asset.contains("Scale")
                let horn = asset.contains("Horn")
                let roughness: Float = organic ? 0.70 : (horn ? 0.50 : 0.88)
                // Keep texture, normal, occlusion and roughness maps; only adjust their response.
                material.roughness.scale = min(max(material.roughness.scale,0.35),roughness)
                material.specular.scale = organic ? 0.45 : 0.35
                material.clearcoat.scale = organic ? 0.12 : (horn ? 0.20 : 0.03)
                material.clearcoatRoughness.scale = 0.32
                return material
            }
            model.model = component
            if asset.hasPrefix("EmberAwake") || asset.hasPrefix("EmberSleeping") || asset == "EmberNestVisual" {
                model.components.set(GroundingShadowComponent(castsShadow:true,receivesShadow:true))
            } else { model.components.remove(GroundingShadowComponent.self) }

        }
        for child in entity.children { polish(child,asset:asset) }
    }
}

extension Entity {
    @MainActor func tintSurfaceRecursively(_ colour: UIColor?) {
        if let entity = self as? ModelEntity, var component = entity.model {
            component.materials = component.materials.map { original in
                guard var material = original as? PhysicallyBasedMaterial else { return original }
                material.baseColor.tint = colour ?? .white
                return material
            }
            entity.model = component
        }
        children.forEach { $0.tintSurfaceRecursively(colour) }
    }
}

/// Linear HDR environment: broad warm key, quieter cool fill and a rear highlight.
/// Generated locally, with no external texture dependency.
func studioEnvironmentImage() -> CGImage? {
    let width = 512, height = 256
    var pixels = [Float](repeating:0,count:width*height*4)
    let key = simd_normalize(SIMD3<Float>(-0.65,0.65,0.65))
    let fill = simd_normalize(SIMD3<Float>(0.8,0.3,0.4))
    let rim = simd_normalize(SIMD3<Float>(0.3,0.6,-0.8))
    for y in 0..<height {
        let latitude = Float.pi*(0.5-Float(y)/Float(height-1))
        for x in 0..<width {
            let longitude = Float(x)/Float(width)*2*Float.pi
            let d = SIMD3<Float>(sin(longitude)*cos(latitude),sin(latitude),cos(longitude)*cos(latitude))
            let k = exp((simd_dot(d,key)-1)*18)*5.5
            let f = exp((simd_dot(d,fill)-1)*12)*1.7
            let r = exp((simd_dot(d,rim)-1)*28)*4.0
            let ambient: Float = 0.16 + max(d.y,0)*0.10
            let rgb = SIMD3<Float>(repeating:ambient) + SIMD3<Float>(1.0,0.91,0.80)*k + SIMD3<Float>(0.78,0.88,1.0)*f + SIMD3<Float>(0.94,0.98,1.0)*r
            let i = (y*width+x)*4
            pixels[i] = rgb.x; pixels[i+1] = rgb.y; pixels[i+2] = rgb.z; pixels[i+3] = 1
        }
    }
    let data = pixels.withUnsafeBytes { Data($0) }
    guard let provider = CGDataProvider(data:data as CFData), let space = CGColorSpace(name:CGColorSpace.extendedLinearSRGB) else { return nil }
    let info = CGBitmapInfo.floatComponents.union(.byteOrder32Little).union(CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue))
    return CGImage(width:width,height:height,bitsPerComponent:32,bitsPerPixel:128,bytesPerRow:width*16,space:space,bitmapInfo:info,provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
}
