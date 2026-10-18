import Flutter
import UIKit
import workmanager_apple
import UserNotifications
import QuickLook

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appChannel: FlutterMethodChannel?
  private var ticketPreviewURL: URL?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the known refresh handler on the first launch as well as
    // restoring handlers persisted by Workmanager on later launches.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.rail_automation.ticketSearch"
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // UIScene creates the Flutter engine after didFinishLaunching. Register
    // channels here rather than relying on a root controller that is still nil.
    appChannel = FlutterMethodChannel(
      name: "com.example.rail_automation/overlay",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
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
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "Ticket viewer is unavailable", details: nil))
          return
        }
        self.saveAndOpenPdf(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func saveAndOpenPdf(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let bytes = arguments["bytes"] as? FlutterStandardTypedData,
          !bytes.data.isEmpty,
          let rawName = arguments["fileName"] as? String else {
      result(FlutterError(code: "invalid_pdf", message: "Ticket PDF is missing", details: nil))
      return
    }
    let fileName = (rawName as NSString).lastPathComponent
    guard !fileName.isEmpty, (fileName as NSString).pathExtension.lowercased() == "pdf" else {
      result(FlutterError(code: "invalid_name", message: "A PDF filename is required", details: nil))
      return
    }
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "unavailable", message: "Open Rail Pro to view the ticket", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    guard !(presenter is QLPreviewController) else {
      result(FlutterError(code: "viewer_busy", message: "Close the current ticket first", details: nil))
      return
    }
    do {
      let directory = try FileManager.default.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Tickets", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(fileName)
      try bytes.data.write(to: url, options: .atomic)
      ticketPreviewURL = url
      let preview = QLPreviewController()
      preview.dataSource = self
      presenter.present(preview, animated: true) { result(url.path) }
    } catch {
      result(FlutterError(code: "pdf_save_failed", message: "Could not save the ticket PDF", details: nil))
    }
  }
}

extension AppDelegate: QLPreviewControllerDataSource {
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    return ticketPreviewURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    return ticketPreviewURL! as NSURL
  }
}
