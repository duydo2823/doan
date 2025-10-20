import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Đăng ký plugin do Flutter tạo (image_picker, permission_handler, …)
    GeneratedPluginRegistrant.register(with: self)

    // KHÔNG khởi tạo engine thủ công, KHÔNG set rootViewController thủ công
    // để storyboard “Main” của Runner quản lý như mặc định.

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
