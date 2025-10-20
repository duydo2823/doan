// ios/Runner/AppDelegate.swift
import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)
    // KHÔNG tạo engine thủ công, để storyboard "Main" lo khởi tạo FlutterViewController.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
