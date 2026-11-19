import RealityKit
import UIKit

struct DragonParts {
    let root: Entity
    let body: ModelEntity
    let head: ModelEntity
    let leftWing: ModelEntity
    let rightWing: ModelEntity
    let leftHorn: ModelEntity
    let rightHorn: ModelEntity
    let tail: ModelEntity
    let leftHornSocket: Entity
    let rightHornSocket: Entity
    let tailSocket: Entity
    let scaleSockets: [Entity]
}

@MainActor
enum DragonFactory {
    static func makePlaceholderDragon() -> DragonParts {
        let root = Entity()
        root.name = "DragonRoot"

        let body = model(name: "Body", mesh: .generateSphere(radius: 0.16), color: .emberCoral)
        body.scale = [1.05, 0.82, 0.82]
        body.position = [0, 0, 0]
        root.addChild(body)

        let belly = model(name: "Belly", mesh: .generateSphere(radius: 0.105), color: .emberCream)
        belly.scale = [0.85, 1.1, 0.28]
        belly.position = [0, -0.02, 0.12]
        body.addChild(belly)

        let head = model(name: "Head", mesh: .generateSphere(radius: 0.13), color: .emberCoral)
        head.scale = [1.08, 0.95, 0.95]
        head.position = [0, 0.2, 0.03]
        root.addChild(head)

        let leftEye = model(name: "LeftEye", mesh: .generateSphere(radius: 0.023), color: .white)
        leftEye.position = [-0.047, 0.035, 0.105]
        head.addChild(leftEye)
        let rightEye = model(name: "RightEye", mesh: .generateSphere(radius: 0.023), color: .white)
        rightEye.position = [0.047, 0.035, 0.105]
        head.addChild(rightEye)
        let leftPupil = model(name: "LeftPupil", mesh: .generateSphere(radius: 0.011), color: .black)
        leftPupil.position = [0, 0, 0.018]
        leftEye.addChild(leftPupil)
        let rightPupil = model(name: "RightPupil", mesh: .generateSphere(radius: 0.011), color: .black)
        rightPupil.position = [0, 0, 0.018]
        rightEye.addChild(rightPupil)

        let leftWing = model(name: "LeftWing", mesh: .generateBox(size: [0.18, 0.04, 0.012]), color: .emberSky)
        leftWing.position = [-0.17, 0.04, -0.015]
        leftWing.orientation = simd_quatf(angle: degreesToRadians(-18), axis: [0, 0, 1])
        root.addChild(leftWing)

        let rightWing = model(name: "RightWing", mesh: .generateBox(size: [0.18, 0.04, 0.012]), color: .emberSky)
        rightWing.position = [0.17, 0.04, -0.015]
        rightWing.orientation = simd_quatf(angle: degreesToRadians(18), axis: [0, 0, 1])
        root.addChild(rightWing)

        let leftHorn = model(name: "LeftHorn", mesh: .generateBox(size: [0.038, 0.11, 0.038]), color: .emberGold)
        leftHorn.position = [-0.055, 0.115, 0.015]
        head.addChild(leftHorn)

        let rightHorn = model(name: "RightHorn", mesh: .generateBox(size: [0.038, 0.11, 0.038]), color: .emberGold)
        rightHorn.position = [0.055, 0.115, 0.015]
        head.addChild(rightHorn)

        let tail = model(name: "Tail", mesh: .generateBox(size: [0.055, 0.055, 0.19]), color: .emberCoral)
        tail.position = [0, -0.04, -0.19]
        root.addChild(tail)

        let leftHornSocket = socket(name: "leftHornSocket", position: [-0.055, 0.315, 0.045], parent: root)
        let rightHornSocket = socket(name: "rightHornSocket", position: [0.055, 0.315, 0.045], parent: root)
        let tailSocket = socket(name: "tailSocket", position: [0, -0.04, -0.32], parent: root)

        let socketPositions: [SIMD3<Float>] = [
            [-0.07, 0.07, 0.16],
            [0.0, 0.095, 0.17],
            [0.07, 0.07, 0.16],
            [-0.04, -0.02, 0.17],
            [0.04, -0.02, 0.17]
        ]
        let scaleSockets = socketPositions.enumerated().map { index, position in
            socket(name: "scaleSocket\(index + 1)", position: position, parent: root)
        }

        root.scale = [1, 1, 1]
        return DragonParts(root: root, body: body, head: head, leftWing: leftWing, rightWing: rightWing, leftHorn: leftHorn, rightHorn: rightHorn, tail: tail, leftHornSocket: leftHornSocket, rightHornSocket: rightHornSocket, tailSocket: tailSocket, scaleSockets: scaleSockets)
    }

    static func model(name: String, mesh: MeshResource, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, roughness: 0.65, isMetallic: false)])
        entity.name = name
        return entity
    }

    static func socket(name: String, position: SIMD3<Float>, parent: Entity) -> Entity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [SimpleMaterial(color: UIColor.emberGold.withAlphaComponent(0.35), roughness: 0.2, isMetallic: false)])
        entity.name = name
        entity.position = position
        entity.isEnabled = false
        parent.addChild(entity)
        return entity
    }
}
