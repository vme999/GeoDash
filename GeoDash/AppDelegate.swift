import UIKit

/// Locks the interface to portrait while Info.plist declares all orientations (iPadOS 26+ / TN3192).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
