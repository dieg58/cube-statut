import Cocoa
import CoreAudio
import CoreMediaIO
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    KwartorSystem.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Fenêtre cachée au lancement : Dart l'affiche (premier lancement) ou la laisse dans la barre de menus.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// Canal "kwartor/system" : détection micro / caméra et lancement à l'ouverture de session.
enum KwartorSystem {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kwartor/system", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "mediaInUse":
        result(["mic": micInUse(), "camera": cameraInUse()])
      case "launchAtLogin":
        if #available(macOS 13.0, *) {
          result(SMAppService.mainApp.status == .enabled)
        } else {
          result(false)
        }
      case "setLaunchAtLogin":
        guard #available(macOS 13.0, *) else {
          result(FlutterError(code: "unsupported", message: "macOS 13 ou plus récent requis", details: nil))
          return
        }
        let on = (call.arguments as? Bool) ?? false
        do {
          if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
          result(true)
        } catch {
          result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Micro (CoreAudio)

  /// Vrai si un périphérique d'entrée audio est utilisé par une application quelconque.
  /// Ne lit que l'état du périphérique : aucune autorisation micro n'est demandée.
  static func micInUse() -> Bool {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr else { return false }

    for dev in devices {
      var streams = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
      var sSize: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(dev, &streams, 0, nil, &sSize) == noErr, sSize > 0 else { continue }

      var running = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      var value: UInt32 = 0
      var vSize = UInt32(MemoryLayout<UInt32>.size)
      if AudioObjectGetPropertyData(dev, &running, 0, nil, &vSize, &value) == noErr, value != 0 {
        return true
      }
    }
    return false
  }

  // MARK: Caméra (CoreMediaIO)

  static func cameraInUse() -> Bool {
    var addr = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return false }
    let count = Int(size) / MemoryLayout<CMIOObjectID>.size
    var devices = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr else { return false }

    for dev in devices {
      var running = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
      var value: UInt32 = 0
      var vUsed: UInt32 = 0
      if CMIOObjectGetPropertyData(dev, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &vUsed, &value) == noErr, value != 0 {
        return true
      }
    }
    return false
  }
}
