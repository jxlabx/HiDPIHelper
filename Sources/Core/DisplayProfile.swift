import Foundation

struct DisplayProfile: Codable, Equatable {
  let vendorID: UInt32
  let productID: UInt32
  let serialNumber: UInt32
  let width: Int
  let height: Int

  static let dellPreset = DisplayProfile(
    vendorID: 4268, productID: 16700, serialNumber: 0, width: 2048, height: 1152)

  var modelKey: String { String(format: "%x-%x", vendorID, productID) }
  var relativeTarget: String {
    String(
      format:
        "Library/Displays/Contents/Resources/Overrides/DisplayVendorID-%x/DisplayProductID-%x",
      vendorID, productID)
  }
  var entry: Data {
    var data = Data()
    // 使用系统预设中常见的 12 字节缩放条目，独立请求目标模式。
    for value in [UInt32(width * 2), UInt32(height * 2), 1] {
      var big = value.bigEndian
      withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
    return data
  }

  func validate() throws {
    guard vendorID > 0, productID > 0, (320...8192).contains(width), (200...8192).contains(height)
    else {
      throw configurationError(
        localized(
          "显示器标识无效，或目标宽高超出允许范围（宽 320–8192，高 200–8192）。",
          "Invalid display identifiers or target dimensions (width: 320–8192; height: 200–8192)."))
    }
  }

  static func read(_ url: URL) throws -> DisplayProfile {
    let profile = try JSONDecoder().decode(DisplayProfile.self, from: Data(contentsOf: url))
    try profile.validate()
    return profile
  }
}

func configurationError(_ message: String) -> NSError {
  NSError(domain: "HiDPIHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// 跟随系统首选语言；其他语言使用英文。
func localized(_ chinese: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String
{
  Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese() : english()
}
