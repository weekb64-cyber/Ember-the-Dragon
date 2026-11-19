# Interface references

The pause hierarchy separates settings and testing controls from the primary Resume action. Reference examples reviewed:

- [Monument Valley settings menu](https://interfaceingame.com/screenshots/monument-valley-settings-menu/)
- [Monument Valley camera and exit menu](https://interfaceingame.com/screenshots/monument-valley-in-game-camera-and-exit-menu/)

These informed the separation of actions into focused pages; Ember keeps labelled controls rather than adopting their exact interface or artwork.

For readability, Apple’s [Design for spatial user interfaces](https://developer.apple.com/videos/play/wwdc2023/10076/) demonstrates the Music app’s darker content cells, lighter controls and white text, as well as Photos’ borderless ornament actions. Its recommendations include medium body weights, bold titles, primary/secondary vibrancy and avoiding stacked light materials. Ember applies a darker panel tint, primary foreground text and a clearly bounded progress track. These are design adaptations, not a claim that the game exactly reproduces Apple’s apps.

The visionOS panels use [SwiftUI glassBackgroundEffect](https://developer.apple.com/documentation/swiftui/glassbackgroundeffect). Buttons use native translucent materials with gaze highlighting. SwiftUI’s named Liquid Glass button style is unavailable on visionOS in the installed SDK, so this implementation uses supported visionOS materials.
