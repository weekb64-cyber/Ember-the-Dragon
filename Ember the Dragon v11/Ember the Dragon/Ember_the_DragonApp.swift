import SwiftUI

@main
struct Ember_the_DragonApp: App {
    @State private var appModel = AppModel()
    @State private var gameModel = GameModel()

    @State private var gallery = EmberGalleryStore()

    var body: some Scene {
        WindowGroup(id: appModel.launcherWindowID) {
            ContentView()
                .environment(appModel)
                .environment(gameModel)
        }.defaultSize(width:960,height:540)

        WindowGroup(id:"EmberPhotoBooth") {
            EmberPhotoBooth().environment(gameModel).environment(gallery)
        }.defaultSize(width:1010,height:700)

        WindowGroup(id:"EmberGallery") {
            EmberGalleryView().environment(gallery)
        }.defaultSize(width:860,height:660)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environment(gameModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
