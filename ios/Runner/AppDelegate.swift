import Flutter
import UIKit
import workmanager_apple
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let controller = window?.rootViewController as? FlutterViewController
    if let binaryMessenger = controller?.binaryMessenger {
      let overlayChannel = FlutterMethodChannel(
        name: "com.example.rail_automation/overlay",
        binaryMessenger: binaryMessenger
      )
      overlayChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "appVersion" {
          let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
          let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
          let build = Int(buildString) ?? 2
          result(["version": version, "build": build])
        } else if call.method == "canDrawOverlays" {
          result(true)
        } else if call.method == "requestOverlayPermission" {
          result(true)
        } else if call.method == "saveAndOpenPdf" {
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
