import RealityKit
import UIKit
import ImageIO
import RealityKitContent

@MainActor
enum RegionalPaintTextures {
    static func image(asset: String, regions: [PaintRegion:PaintChoice], wing: PaintRegion? = nil) -> CGImage? {
        guard let folder = realityKitContentBundle.url(forResource:"PebbleTextures",withExtension:nil) else { return nil }
        func load(_ name: String) -> CGImage? {
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL,nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source,0,nil)
        }
        guard let base = load(asset+"_Original.jpg"), let context = CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x:0,y:0,width:1024,height:1024)
        context.draw(base,in:rect)
        for region in PaintRegion.allCases {
            guard let colour = regions[region], wing == nil || wing == region,
                  let tint = load(asset+"_"+colour.assetSuffix+".jpg"),
                  let mask = load(asset+"_Region\(wing == nil ? region.rawValue : 6).png") else { continue }
            context.saveGState(); context.clip(to:rect,mask:mask); context.draw(tint,in:rect); context.restoreGState()
        }
        return context.makeImage()
    }
    static func apply(to entity: Entity, asset: String, regions: [PaintRegion:PaintChoice], wing: PaintRegion? = nil) {
        guard let image = image(asset:asset,regions:regions,wing:wing), let texture = try? TextureResource(image:image,options:.init(semantic:.color)) else { return }
        func visit(_ node: Entity) {
            if let model = node as? ModelEntity, var component = model.model {
                component.materials = component.materials.map { original in
                    guard var material = original as? PhysicallyBasedMaterial else { return original }
                    material.baseColor = .init(tint:.white,texture:.init(texture)); return material
                }; model.model = component
            }
            node.children.forEach(visit)
        }
        visit(entity)
    }
}
