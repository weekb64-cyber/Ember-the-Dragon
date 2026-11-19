import Foundation
import RealityKit
import RealityKitContent

/// Only the wingless, hornless body contributes samples. Imported attachments cannot receive scales.
struct BodySurface {
    struct Sample { let position: SIMD3<Float>; let normal: SIMD3<Float>; let fullPosition: SIMD3<Float>; let fullNormal: SIMD3<Float> }
    let samples: [Sample]
    init() {
        guard let folder = realityKitContentBundle.url(forResource:"PebbleTextures",withExtension:nil), let data = try? Data(contentsOf:folder.appendingPathComponent("BodySurface.bin")) else { samples = []; return }
        samples = data.withUnsafeBytes { raw in
            stride(from:0,to:raw.count-47,by:48).map { i in
                func f(_ j: Int) -> Float { raw.loadUnaligned(fromByteOffset:i+j*4,as:Float.self) }
                return Sample(position:[f(0),f(1),f(2)],normal:[f(3),f(4),f(5)],fullPosition:[f(6),f(7),f(8)],fullNormal:[f(9),f(10),f(11)])
            }
        }
    }
    func projected(_ position: SIMD3<Float>, yaw: Float) -> Sample? {
        let rotation = simd_quatf(angle:yaw,axis:[0,1,0])
        var best: Sample?; var score = Float.infinity
        for sample in samples {
            let normal = rotation.act(sample.normal)
            guard normal.z > 0.15 else { continue }
            let p = rotation.act(sample.position), d = p-position
            let candidate = d.x*d.x+d.y*d.y + max(0,-d.z)*0.0001
            if candidate < score { score = candidate; best = sample }
        }
        return score < 0.035*0.035 ? best : nil
    }
}
