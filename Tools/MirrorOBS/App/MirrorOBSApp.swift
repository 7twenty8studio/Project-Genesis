import SwiftUI

@main
struct MirrorOBSApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup { MirrorScreen().environment(store) }
    }
}
