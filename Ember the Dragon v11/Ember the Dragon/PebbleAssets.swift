import Foundation
import RealityKit
import UIKit
import ImageIO
import RealityKitContent

extension PebbleForm {
    var target: AssetTarget { self == .sleeping ? .largest(normalizedSize) : .height(normalizedSize) }
}

@MainActor
enum PebblePaintTextures {
    private static var cache: [String:TextureResource] = [:]
    static func clearCache() { cache.removeAll() }
    static func apply(to entity: Entity, asset: String, colour: PaintChoice) {
        let name = asset + "_" + colour.assetSuffix
        let texture: TextureResource?
        if let existing = cache[name] { texture = existing }
        else if let folder = realityKitContentBundle.url(forResource:"PebbleTextures",withExtension:nil),
                let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name+".jpg") as CFURL,nil),
                let image = CGImageSourceCreateImageAtIndex(source,0,nil),
                let loaded = try? TextureResource(image:image,withName:name,options:.init(semantic:.color)) {
            // Keep only the current coat in the lookup cache; visible materials retain their resources.
            if cache.count >= 3 { cache.removeAll() }
            cache[name] = loaded; texture = loaded
        } else {
            texture = nil
            print("Ember: missing Pebble paint texture \(name)")
        }
        func visit(_ node: Entity) {
            if let model = node as? ModelEntity, var component = model.model {
                component.materials = component.materials.map { original in
                    guard var material = original as? PhysicallyBasedMaterial else { return original }
                    if let texture { material.baseColor = .init(tint:.white,texture:.init(texture)) }
                    else { material.baseColor.tint = colour.uiColor }
                    return material
                }
                model.model = component
            }
            node.children.forEach(visit)
        }
        visit(entity)
    }
}
