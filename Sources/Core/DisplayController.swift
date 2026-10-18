import AppKit
import CoreGraphics
import IOKit.graphics

struct ConnectedDisplay {
  let id: CGDirectDisplayID
  let name: String
  let vendorID: UInt32
  let productID: UInt32
  let serialNumber: UInt32

  func matches(_ profile: DisplayProfile) -> Bool {
    vendorID == profile.vendorID && productID == profile.productID
      && serialNumber == profile.serialNumber
  }
}

enum DisplayController {
  static func connected() -> [ConnectedDisplay] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
      let screen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == id
      }
      return ConnectedDisplay(
        id: id, name: screen?.localizedName ?? localized("外接显示器 \(id)", "External Display \(id)"),
        vendorID: CGDisplayVendorNumber(id),
        productID: CGDisplayModelNumber(id), serialNumber: CGDisplaySerialNumber(id))
    }
  }

  static func modes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
    CGDisplayCopyAllDisplayModes(
      id, [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary)
      as? [CGDisplayMode] ?? []
  }

  static func target(_ id: CGDirectDisplayID, profile: DisplayProfile) -> CGDisplayMode? {
    modes(id).filter { matches($0, profile: profile) }.max { $0.refreshRate < $1.refreshRate }
  }

  static func native(_ id: CGDirectDisplayID) -> CGDisplayMode? {
    modes(id).filter {
      ($0.ioFlags & UInt32(kDisplayModeNativeFlag)) != 0 && $0.width == $0.pixelWidth
        && $0.height == $0.pixelHeight
    }.max { $0.refreshRate < $1.refreshRate }
  }

  static func matches(_ mode: CGDisplayMode, profile: DisplayProfile) -> Bool {
    mode.width == profile.width && mode.height == profile.height
      && mode.pixelWidth == profile.width * 2 && mode.pixelHeight == profile.height * 2
  }

  static func same(_ a: CGDisplayMode, _ b: CGDisplayMode) -> Bool {
    a.width == b.width && a.height == b.height && a.pixelWidth == b.pixelWidth
      && a.pixelHeight == b.pixelHeight && abs(a.refreshRate - b.refreshRate) < 0.1
  }
}
