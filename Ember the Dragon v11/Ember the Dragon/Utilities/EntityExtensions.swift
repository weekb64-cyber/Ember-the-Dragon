import RealityKit
import UIKit

extension Entity {
    func child(named name: String) -> Entity? {
        if self.name == name { return self }
        for child in children {
            if let match = child.child(named: name) {
                return match
            }
        }
        return nil
    }

    func removeAllChildren() {
        for child in children {
            child.removeFromParent()
        }
    }

    func setInteraction(radius: Float, manipulation: Bool = true) {
        components.set(InputTargetComponent())
        components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        components.set(HoverEffectComponent())
        if manipulation {
            components.set(ManipulationComponent())
        }
    }

    func setInteraction(boxSize: SIMD3<Float>, manipulation: Bool = true) {
        components.set(InputTargetComponent())
        components.set(CollisionComponent(shapes: [.generateBox(size: boxSize)]))
        components.set(HoverEffectComponent())
        if manipulation {
            components.set(ManipulationComponent())
        }
    }

    func disableInteraction() {
        components.remove(InputTargetComponent.self)
        components.remove(HoverEffectComponent.self)
        components.remove(ManipulationComponent.self)
    }
}

extension UIColor {
    static let emberCoral = UIColor(red: 1.0, green: 0.42, blue: 0.32, alpha: 1)
    static let emberGold = UIColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 1)
    static let emberCream = UIColor(red: 1.0, green: 0.9, blue: 0.72, alpha: 1)
    static let emberTeal = UIColor(red: 0.22, green: 0.74, blue: 0.74, alpha: 1)
    static let emberSky = UIColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1)
    static let emberLavender = UIColor(red: 0.72, green: 0.55, blue: 0.94, alpha: 1)
}
