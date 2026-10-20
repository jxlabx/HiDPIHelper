import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else { fatalError(message) }
}
func rejects(_ message: String, _ body: () throws -> Void) {
  do {
    try body()
    fatalError(message)
  } catch { print("通过：\(message)") }
}
expect(DisplayProfile.dellPreset.entry == Data([
  0, 0, 0x10, 0, 0, 0, 9, 0, 0, 0, 0, 1,
]), "2048×1152 应请求 4096×2304 的独立缩放模式，使用 12 字节独立缩放条目")
let fileManager = FileManager.default
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
let profiles = [
  DisplayProfile.dellPreset,
  DisplayProfile(vendorID: 1234, productID: 5678, serialNumber: 0, width: 1920, height: 1200),
  DisplayProfile(vendorID: 9876, productID: 4321, serialNumber: 12, width: 2752, height: 1152),
]
for profile in profiles {
  let configuration = DisplayConfiguration(profile: profile)
  let root = base.appendingPathComponent(profile.modelKey)
  try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  let generated = try configuration.generated()
  let dictionary = try configuration.checked(generated)
  expect(dictionary["scale-resolutions"] as? [Data] == [profile.entry], "生成目标条目")
  expect(configuration.relativeTarget.contains(String(profile.productID, radix: 16)), "型号路径应匹配")
  _ = try configuration.install(root: root)
  let installed = try Data(contentsOf: configuration.target(root))
  let installedConfiguration = try configuration.checked(installed)
  expect(installedConfiguration["scale-resolutions"] as? [Data] == [profile.entry], "空目录安装应写入目标条目")
  _ = try configuration.install(root: root)
  let unchanged = try Data(contentsOf: configuration.target(root))
  expect(unchanged == installed, "重复安装不改变配置")
  _ = try configuration.restore(root: root)
  expect(!fileManager.fileExists(atPath: configuration.target(root).path), "原本没有文件时，恢复应将其归档")
  let original: [String: Any] = [
    "DisplayVendorID": profile.vendorID, "DisplayProductID": profile.productID,
    "ExistingSetting": "保留", "scale-resolutions": [Data([0, 0, 8, 0, 0, 0, 4, 128])],
  ]
  let originalData = try PropertyListSerialization.data(
    fromPropertyList: original, format: .xml, options: 0)
  try originalData.write(to: configuration.target(root))
  _ = try configuration.install(root: root)
  let merged = try configuration.checked(Data(contentsOf: configuration.target(root)))
  expect(merged["ExistingSetting"] as? String == "保留", "保留其他设置")
  expect((merged["scale-resolutions"] as? [Data])?.count == 2, "保留既有模式")
  let installedMerge = try Data(contentsOf: configuration.target(root))
  try Data("后续修改".utf8).write(to: configuration.target(root))
  rejects("拒绝覆盖安装后的其他修改") { _ = try configuration.restore(root: root) }
  try installedMerge.write(to: configuration.target(root))
  _ = try configuration.restore(root: root)
  let restored = try Data(contentsOf: configuration.target(root))
  expect(restored == originalData, "恢复原文件字节")
  print("通过：\(profile.modelKey) · \(profile.width)×\(profile.height)")
}
let configuration = DisplayConfiguration(profile: .dellPreset)
let legacyRoot = base.appendingPathComponent("legacy-entry")
_ = try configuration.install(root: legacyRoot)
let legacyEntry = Data([0, 0, 0x10, 0, 0, 0, 9, 0, 0, 0, 0, 9, 0, 0x20, 0, 0])
let legacyData = try PropertyListSerialization.data(fromPropertyList: [
  "DisplayVendorID": 4268, "DisplayProductID": 16700, "scale-resolutions": [legacyEntry],
], format: .xml, options: 0)
try legacyData.write(to: configuration.target(legacyRoot))
_ = try configuration.install(root: legacyRoot)
let repaired = try Data(contentsOf: configuration.target(legacyRoot))
let repairedEntries = try configuration.checked(repaired)["scale-resolutions"] as? [Data]
expect(repairedEntries == [legacyEntry, DisplayProfile.dellPreset.entry], "旧条目存在时仍须追加独立缩放条目")
_ = try configuration.install(root: legacyRoot)
let repeatedRepair = try Data(contentsOf: configuration.target(legacyRoot))
expect(repeatedRepair == repaired, "修复后重复安装不改文件")
_ = try configuration.restore(root: legacyRoot)
let restoredLegacy = try Data(contentsOf: configuration.target(legacyRoot))
expect(restoredLegacy == legacyData, "修复回滚应恢复旧配置原字节")
rejects("拒绝错误厂商标识") { _ = try configuration.checked(Data("<plist><dict/></plist>".utf8)) }
rejects("拒绝溢出尺寸") {
  try DisplayProfile(vendorID: 1, productID: 2, serialNumber: 0, width: Int.max, height: 1080)
    .validate()
}
rejects("拒绝负数尺寸") {
  try DisplayProfile(vendorID: 1, productID: 2, serialNumber: 0, width: -1, height: 1080).validate()
}
let symlinkRoot = base.appendingPathComponent("symlink-case")
try fileManager.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
try fileManager.createSymbolicLink(
  at: symlinkRoot.appendingPathComponent("Library"),
  withDestinationURL: base.appendingPathComponent(profiles[0].modelKey).appendingPathComponent(
    "Library"))
rejects("拒绝符号链接父目录") { _ = try configuration.install(root: symlinkRoot) }
let malformedRoot = base.appendingPathComponent("malformed")
_ = try configuration.install(root: malformedRoot)
let malformed: [String: Any] = [
  "DisplayVendorID": 4268, "DisplayProductID": 16700, "scale-resolutions": "格式异常",
]
try PropertyListSerialization.data(fromPropertyList: malformed, format: .xml, options: 0).write(
  to: configuration.target(malformedRoot))
rejects("拒绝丢弃格式异常的原配置") { _ = try configuration.install(root: malformedRoot) }
print("全部配置测试通过；测试仅写入隔离目录。")
