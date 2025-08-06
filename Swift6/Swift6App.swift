//
//  Swift6App.swift
//  Swift6
//
//  Created by Keigo Nakagawa on 2025/07/30.
//

import SwiftUI

@main
struct Swift6App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Deprecate Application Main → Yesにしても変わらず
//@UIApplicationMain
//class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {
//
//    var window: UIWindow?
//
//    func application(
//        _ application: UIApplication,
//        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
//        -> Bool
//    {
//        return true
//    }
//}
