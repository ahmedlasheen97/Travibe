import Flutter
import UIKit
import Photos
import AVFoundation
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingShare: FlutterResult?
  private var sharingChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let media = FlutterMethodChannel(name: "travibe/chat_media", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    media.setMethodCallHandler { call, result in
      DispatchQueue.main.async { TravibeChatMedia.handle(call, result: result) }
    }
    // This is an application channel on the actual storyboard/scene engine.
    let channel = FlutterMethodChannel(name: "travibe/post_sharing",
                                      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    sharingChannel = channel
    #if DEBUG
    NSLog("TravibePostSharing: registered travibe/post_sharing on the implicit engine")
    #endif
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "Sharing is unavailable.", details: "App delegate was released"))
          return
        }
        self.sharePost(call.arguments, result: result)
      }
    }
  }

  private func sharePost(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pendingShare == nil else {
      result(FlutterError(code: "busy", message: "Sharing options are already open.", details: nil))
      return
    }
    guard let args = arguments as? [String: Any] else {
      result(FlutterError(code: "empty_content", message: "No post text or link is available.", details: nil))
      return
    }
    let content: Any
    if let rawURL = args["url"] as? String {
      guard let url = URL(string: rawURL), url.scheme == "https",
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
        result(FlutterError(code: "invalid_url", message: "A verified public post link is required.", details: nil))
        return
      }
      content = url
    } else if let text = args["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      content = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      result(FlutterError(code: "empty_content", message: "No post text or link is available.", details: nil))
      return
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let activeWindows = scenes.filter {
      $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
    }.flatMap { $0.windows }
    guard let window = activeWindows.first(where: { $0.isKeyWindow }) ?? self.window,
          let root = window.rootViewController else {
      result(FlutterError(code: "unavailable", message: "Unable to open sharing options.", details: "No foreground window/root view controller"))
      return
    }
    let presenter = topViewController(root)
    guard presenter.viewIfLoaded?.window != nil,
          !presenter.isBeingDismissed, !presenter.isBeingPresented else {
      result(FlutterError(code: "presentation_busy", message: "Please try sharing again.", details: "Presenter is detached or transitioning"))
      return
    }
    let activity = UIActivityViewController(activityItems: [content], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      let sourceView = flutterViewController(root)?.view ?? root.view!
      popover.sourceView = presenter.view
      let values = ["x", "y", "width", "height"].map { (args[$0] as? NSNumber)?.doubleValue ?? 0 }
      var rect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      if values.allSatisfy({ $0.isFinite }) && values[2] > 0 && values[3] > 0 {
        let flutterRect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        let converted = presenter.view.convert(flutterRect, from: sourceView)
          .intersection(presenter.view.bounds)
        if !converted.isNull && !converted.isEmpty { rect = converted }
      }
      popover.sourceRect = rect
    }
    pendingShare = result
    activity.completionWithItemsHandler = { [weak self] _, _, _, error in
      guard let completion = self?.pendingShare else { return }
      self?.pendingShare = nil
      if error != nil {
        completion(FlutterError(code: "share_failed", message: "Unable to share the post.", details: error?.localizedDescription))
      } else {
        // Dismissal and completion do not establish delivery to another user.
        completion(nil)
      }
    }
    presenter.present(activity, animated: true)
  }

  private func topViewController(_ controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController, !presented.isBeingDismissed {
      return topViewController(presented)
    }
    if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
      return topViewController(visible)
    }
    if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
      return topViewController(selected)
    }
    return controller
  }

  private func flutterViewController(_ controller: UIViewController) -> FlutterViewController? {
    if let flutter = controller as? FlutterViewController { return flutter }
    for child in controller.children {
      if let flutter = flutterViewController(child) { return flutter }
    }
    return nil
  }

}


private enum TravibeChatMedia {
  private static let pathMonitor = NWPathMonitor()
  private static var hasPath = false
  private static var monitoring = false
  private static func currentNetworkStatus() -> Bool? {
    if !monitoring {
      monitoring = true
      pathMonitor.pathUpdateHandler = { _ in
        DispatchQueue.main.async { hasPath = true }
      }
      pathMonitor.start(queue: DispatchQueue(label: "travibe.chat.network"))
    }
    // Read the live path: a cached handler value can stay unsatisfied after
    // connectivity returns (notably on the iOS Simulator).
    guard hasPath else { return nil }
    let status = pathMonitor.currentPath.status
    return status == .satisfied ? true : status == .unsatisfied ? false : nil
  }

  static func microphoneStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .notDetermined: return "notDetermined"
    case .denied: return "permanentlyDenied"
    case .restricted: return "restricted"
    @unknown default: return "restricted"
    }
  }
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "networkStatus": result(currentNetworkStatus())
    case "microphoneStatus": result(microphoneStatus())
    case "requestMicrophone":
      guard microphoneStatus() == "notDetermined" else { result(microphoneStatus()); return }
      AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { result(microphoneStatus()) } }
    case "openSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(FlutterError(code: "unavailable", message: "Settings unavailable.", details: nil)); return
      }
      UIApplication.shared.open(url) { opened in
        result(opened ? nil : FlutterError(code: "unavailable", message: "Settings unavailable.", details: nil))
      }
    case "saveVideo":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String,
            URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path),
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 100 * 1024 * 1024 else {
        result(FlutterError(code: "invalid_video", message: "Unable to save video.", details: nil)); return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async { result(FlutterError(code: "permission_denied", message: "Allow adding media in Settings.", details: nil)) }; return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: URL(fileURLWithPath: path), options: nil)
        }) { success, _ in
          DispatchQueue.main.async { result(success ? nil : FlutterError(code: "save_failed", message: "Unable to save video.", details: nil)) }
        }
      }
    case "saveImage":
      guard let args = call.arguments as? [String: Any], let bytes = args["bytes"] as? FlutterStandardTypedData,
            !bytes.data.isEmpty, bytes.data.count <= 20 * 1024 * 1024, UIImage(data: bytes.data) != nil else {
        result(FlutterError(code: "invalid_image", message: "Unable to save this image.", details: nil)); return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async { result(FlutterError(code: "permission_denied", message: "Allow adding photos in Settings to save this image.", details: nil)) }; return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.forAsset().addResource(with: .photo, data: bytes.data, options: nil)
        }) { success, _ in
          DispatchQueue.main.async {
            result(success ? nil : FlutterError(code: "save_failed", message: "Unable to save image. Check available storage and try again.", details: nil))
          }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
