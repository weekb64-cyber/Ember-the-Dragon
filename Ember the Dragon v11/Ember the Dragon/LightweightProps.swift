import RealityKit
import UIKit

/// Small generated props replace the unusually dense imported brush and nest.
@MainActor
func makeLightweightBrush() -> Entity {
    let brush = Entity(); brush.name = "LightweightArtistBrush"
    let wood = EmberMaterials.soft(UIColor(red:0.36,green:0.17,blue:0.08,alpha:1),roughness:0.45)
    let handle = ModelEntity(mesh:.generateBox(size:[0.015,0.14,0.012],cornerRadius:0.006),materials:[wood])
    handle.position.y = -0.055; brush.addChild(handle)
    let ferrule = ModelEntity(mesh:.generateBox(size:[0.032,0.032,0.014],cornerRadius:0.004),materials:[SimpleMaterial(color:UIColor(red:0.80,green:0.65,blue:0.35,alpha:1),roughness:0.3,isMetallic:true)])
    ferrule.position.y = 0.025; brush.addChild(ferrule)
    let bristles = ModelEntity(mesh:.generateBox(size:[0.030,0.041,0.010],cornerRadius:0.004),materials:[EmberMaterials.soft(UIColor(red:0.86,green:0.74,blue:0.51,alpha:1),roughness:0.9)])
    bristles.position.y = 0.060; brush.addChild(bristles)
    let grooveMesh = MeshResource.generateBox(size:[0.0007,0.034,0.001],cornerRadius:0.0003)
    let grooveMaterial = EmberMaterials.soft(UIColor(red:0.53,green:0.38,blue:0.22,alpha:1),roughness:0.9)
    for i in -4...4 {
        let strand = ModelEntity(mesh:grooveMesh,materials:[grooveMaterial]); strand.position = [Float(i)*0.003,0.060,0.005]
        brush.addChild(strand)
    }
    return brush
}

@MainActor
func makeLightweightNest() -> Entity {
    let root = Entity(); root.name = "LightweightMossNest"
    let earth = ModelEntity(mesh:.generateSphere(radius:0.46),materials:[EmberMaterials.soft(UIColor(red:0.25,green:0.15,blue:0.08,alpha:1),roughness:0.95)])
    earth.scale = [1,0.10,1]; earth.position.y = -0.018; root.addChild(earth)
    let moss = ModelEntity(mesh:.generateSphere(radius:0.445),materials:[EmberMaterials.soft(UIColor(red:0.34,green:0.49,blue:0.16,alpha:1),roughness:0.95)])
    moss.scale = [1,0.075,1]; root.addChild(moss)
    var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], triangles: [UInt32] = []
    let around = 64, across = 12
    for i in 0...around {
        let a = Float(i)*2 * .pi/Float(around)
        for j in 0...across {
            let b = Float(j)*2 * .pi/Float(across)
            let tube: Float = 0.027 + 0.003*sin(a*16)
            positions.append([(0.32+tube*cos(b))*cos(a),0.015+tube*sin(b)*0.65,(0.32+tube*cos(b))*sin(a)])
            normals.append([cos(a)*cos(b),sin(b),sin(a)*cos(b)])
            if i < around && j < across {
                let k = UInt32(i*(across+1)+j), next = UInt32(across+1)
                triangles += [k,k+next,k+1,k+1,k+next,k+next+1]
            }
        }
    }
    var descriptor = MeshDescriptor(name:"WovenNestRim")
    descriptor.positions = MeshBuffers.Positions(positions); descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(triangles)
    if let mesh = try? MeshResource.generate(from:[descriptor]) {
        var material = PhysicallyBasedMaterial(); material.baseColor.tint = UIColor(red:0.45,green:0.29,blue:0.12,alpha:1)
        material.roughness = .init(floatLiteral:0.9); material.faceCulling = .none
        root.addChild(ModelEntity(mesh:mesh,materials:[material]))
    }
    return root
}
