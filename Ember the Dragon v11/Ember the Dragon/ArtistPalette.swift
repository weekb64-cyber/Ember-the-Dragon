import RealityKit
import UIKit
import CoreGraphics

/// Extruded wooden oval with a real thumb opening, procedural grain and inset paint wells.
@MainActor
func makeArtistPalette() -> Entity {
    let root = Entity(); root.name = "WoodenArtistPalette"
    let count = 96
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    func outer(_ t: Float) -> SIMD2<Float> { [cos(t)*0.17, sin(t)*0.125] }
    func inner(_ t: Float) -> SIMD2<Float> { [-0.085+cos(t)*0.027, -0.025+sin(t)*0.035] }
    func vertex(_ p: SIMD2<Float>, _ z: Float, _ n: SIMD3<Float>) {
        positions.append([p.x,p.y,z]); normals.append(n); uv.append([(p.x+0.17)/0.34,(p.y+0.125)/0.25])
    }
    func quad(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ d: SIMD2<Float>, _ zs: [Float], _ n: SIMD3<Float>) {
        let base = UInt32(positions.count)
        for (i,p) in [a,b,c,d].enumerated() { vertex(p,zs[i],n) }
        indices += [base,base+1,base+2,base,base+2,base+3]
    }
    for i in 0..<count {
        let a = Float(i)*2 * .pi/Float(count), b = Float(i+1)*2 * .pi/Float(count)
        quad(outer(a),outer(b),inner(b),inner(a),[0.006,0.006,0.006,0.006],[0,0,1])
        quad(inner(a),inner(b),outer(b),outer(a),[-0.006,-0.006,-0.006,-0.006],[0,0,-1])
        quad(outer(b),outer(a),outer(a),outer(b),[0.006,0.006,-0.006,-0.006],[cos(a),sin(a),0])
        quad(inner(a),inner(b),inner(b),inner(a),[0.006,0.006,-0.006,-0.006],[-cos(a),-sin(a),0])
    }
    var descriptor = MeshDescriptor(name:"CarvedPalette")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
    descriptor.primitives = .triangles(indices)
    var wood = PhysicallyBasedMaterial()
    wood.baseColor = .init(tint:UIColor(red:0.76,green:0.49,blue:0.26,alpha:1))
    if let image = paletteWoodImage(), let texture = try? TextureResource(image:image,options:.init(semantic:.color)) {
        wood.baseColor = .init(texture:.init(texture))
    }
    wood.roughness = .init(floatLiteral:0.36)
    wood.faceCulling = .none
    if let mesh = try? MeshResource.generate(from:[descriptor]) { root.addChild(ModelEntity(mesh:mesh,materials:[wood])) }
    return root
}

func paletteWoodImage() -> CGImage? {
    let size = 768
    guard let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red:0.70,green:0.43,blue:0.22,alpha:1))
    context.fill(CGRect(x:0,y:0,width:size,height:size))
    for line in 0..<180 {
        let y = CGFloat(line)*4.4
        context.setStrokeColor(CGColor(red:line%3 == 0 ? 0.92 : 0.38,green:line%3 == 0 ? 0.68 : 0.22,blue:line%3 == 0 ? 0.40 : 0.12,alpha:0.24))
        context.setLineWidth(line%3 == 0 ? 1.3 : 0.7)
        context.move(to:CGPoint(x:0,y:y))
        context.addCurve(to:CGPoint(x:768,y:y+8),control1:CGPoint(x:240,y:y+sin(Double(line)*0.13)*24),control2:CGPoint(x:510,y:y-22))
        context.strokePath()
    }
    return context.makeImage()
}
