import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LigMasasiInstagram") {
      InstagramShare.register(messenger: registrar.messenger())
    }
  }
}

/// Görseli Instagram uygulamasında açar (Android'deki MainActivity ile aynı
/// kanal): hikâye düzenleyicisi ya da gönderi ekranı. Paylaşım Instagram'da o
/// an açık olan hesaptan yapılır.
enum InstagramShare {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ligmasasi/instagram", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isInstalled":
        result(canOpen("instagram://app"))
      case "share":
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "args", message: "Görsel yok", details: nil))
          return
        }
        let story = args["story"] as? Bool ?? false
        let appId = (args["appId"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if story && !appId.isEmpty && shareStory(bytes.data, appId: appId) {
          result(true)
        } else {
          sharePost(bytes.data, result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func canOpen(_ s: String) -> Bool {
    guard let url = URL(string: s) else { return false }
    return UIApplication.shared.canOpenURL(url)
  }

  /// Hikâye: görsel panoya konur, Instagram'ın hikâye düzenleyicisi açılır.
  private static func shareStory(_ data: Data, appId: String) -> Bool {
    guard let url = URL(string: "instagram-stories://share?source_application=\(appId)"),
          UIApplication.shared.canOpenURL(url) else { return false }
    UIPasteboard.general.setItems(
      [["com.instagram.sharedSticker.backgroundImage": data]],
      options: [.expirationDate: Date().addingTimeInterval(300)]
    )
    UIApplication.shared.open(url)
    return true
  }

  /// Gönderi: görsel fotoğraflara kaydedilir, Instagram o fotoğrafla açılır
  /// (gönderi / hikâye seçimi Instagram'da). Olmazsa paylaşım menüsü.
  private static func sharePost(_ data: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: data) else {
      result(false)
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async { result(shareSheet(image)) }
        return
      }
      var localId: String?
      PHPhotoLibrary.shared().performChanges({
        localId = PHAssetChangeRequest.creationRequestForAsset(from: image)
          .placeholderForCreatedAsset?.localIdentifier
      }) { ok, _ in
        DispatchQueue.main.async {
          if ok, let id = localId,
             let url = URL(string: "instagram://library?LocalIdentifier=\(id)"),
             UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            result(true)
          } else {
            result(shareSheet(image))
          }
        }
      }
    }
  }

  private static func shareSheet(_ image: UIImage) -> Bool {
    let root = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    guard var top = root else { return false }
    while let presented = top.presentedViewController { top = presented }
    let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = top.view
    sheet.popoverPresentationController?.sourceRect = CGRect(
      x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
    top.present(sheet, animated: true)
    return true
  }
}
