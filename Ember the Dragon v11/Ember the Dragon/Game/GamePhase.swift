import Foundation

enum GamePhase: String, CaseIterable, Equatable {
    case welcome
    case calibration
    case introduction
    case reach
    case stretch
    case pinch
    case rotate
    case sweep
    case celebration
    case complete

    var childTitle: String {
        switch self {
        case .welcome:
            "Meet Ember"
        case .calibration:
            "Find Your Stars"
        case .introduction:
            "This is Ember."
        case .reach:
            "Oh no!"
        case .stretch:
            "Tiny Wings"
        case .pinch:
            "Magic Scales"
        case .rotate:
            "A Little Wonky"
        case .sweep:
            "One Last Thing"
        case .celebration:
            "You did it!"
        case .complete:
            "Ember is ready!"
        }
    }

    var childSubtitle: String {
        switch self {
        case .welcome:
            "Ember needs a little help getting ready."
        case .calibration:
            "Touch the stars that feel comfortable."
        case .introduction:
            "Ember needs your help getting ready to fly!"
        case .reach:
            "Bring Ember's pieces back."
        case .stretch:
            "Stretch Ember's wings!"
        case .pinch:
            "Add the magic scales!"
        case .rotate:
            "Twist the horns into place."
        case .sweep:
            "Brush away the dust!"
        case .celebration:
            "Ember is ready to fly!"
        case .complete:
            "Thanks for helping Ember."
        }
    }
}
