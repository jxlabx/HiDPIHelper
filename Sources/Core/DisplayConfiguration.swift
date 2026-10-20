import CryptoKit
import Foundation

struct DisplayConfiguration {
  let profile: DisplayProfile
  var relativeTarget: String { profile.relativeTarget }
  static let relativeJournal = "Library/Application Support/LocalHiDPIHelper"
  var entry: Data { profile.entry }
  func generated() throws -> Data {
    try profile.validate()
    return try PropertyListSerialization.data(
      fromPropertyList: [
        "DisplayVendorID": profile.vendorID, "DisplayProductID": profile.productID,
        "scale-resolutions": [entry],
      ], format: .xml, options: 0)
  }
  func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  func checked(_ data: Data) throws -> [String: Any] {
    guard
      let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any],
      (dict["DisplayVendorID"] as? NSNumber)?.intValue == Int(profile.vendorID),
      (dict["DisplayProductID"] as? NSNumber)?.intValue == Int(profile.productID)
    else {
      throw error(
        localized(
          "现有配置的显示器标识不匹配，已停止。",
          "The existing configuration has different display identifiers. Operation stopped."))
    }
    return dict
  }
  func error(_ message: String) -> NSError {
    NSError(domain: "HiDPIConfig", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  func target(_ root: URL = URL(fileURLWithPath: "/")) -> URL {
    root.appendingPathComponent(relativeTarget)
  }
  func check(root: URL = URL(fileURLWithPath: "/")) -> String {
    let url = target(root)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return localized(
        "独立配置未安装；可点击“创建/修复 HiDPI 配置”。",
        "No override is installed. Click Create / Repair to install one.")
    }
    do {
      let data = try Data(contentsOf: url)
      let dict = try checked(data)
      return (dict["scale-resolutions"] as? [Data] ?? []).contains(entry)
        ? localized(
          "目标缩放条目已写入文件；是否生效须检查系统模式。", "The target scaling entry is on disk; check system modes to verify activation.")
        : localized(
          "已找到显示配置，但缺少目标 HiDPI 条目。",
          "A display configuration was found, but the target HiDPI entry is missing.")
    } catch {
      return localized(
        "配置检查失败：\(error.localizedDescription)",
        "Configuration check failed: \(error.localizedDescription)")
    }
  }
  // 修改受保护文件前拒绝符号链接，避免写入预期路径之外。
  func rejectSymlinks(_ url: URL) throws {
    var path = URL(fileURLWithPath: "/")
    for component in url.standardizedFileURL.pathComponents.dropFirst() {
      path.appendPathComponent(component)
      if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
        attrs[.type] as? FileAttributeType == .typeSymbolicLink
      {
        throw error(
          localized(
            "拒绝写入符号链接：\(path.path)", "Refusing to write through a symbolic link: \(path.path)"))
      }
    }
  }
  func rootDirectories(_ root: URL) throws -> URL {
    let journal = root.appendingPathComponent(Self.relativeJournal).appendingPathComponent(
      profile.modelKey)
    try rejectSymlinks(target(root))
    try rejectSymlinks(journal)
    try FileManager.default.createDirectory(
      at: target(root).deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755])
    try FileManager.default.createDirectory(
      at: journal, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    return journal
  }
  func install(root: URL = URL(fileURLWithPath: "/")) throws -> String {
    if root.path == "/" && geteuid() != 0 {
      throw error(
        localized(
          "安装系统配置需要管理员授权。",
          "Installing a system configuration requires administrator authorization."))
    }
    try profile.validate()
    let fm = FileManager.default
    let journal = try rootDirectories(root)
    let url = target(root)
    let existed = fm.fileExists(atPath: url.path)
    let original = existed ? try Data(contentsOf: url) : nil
    var dict =
      try original.map { try checked($0) } ?? [
        "DisplayVendorID": profile.vendorID, "DisplayProductID": profile.productID,
      ]
    if dict["scale-resolutions"] != nil && !(dict["scale-resolutions"] is [Data]) {
      throw error(
        localized(
          "现有缩放条目格式异常，已停止以保留原配置。查明格式后再处理。",
          "The existing scaling entries have an unexpected format. Operation stopped to preserve the configuration. Inspect the format before proceeding."
        ))
    }
    var entries = dict["scale-resolutions"] as? [Data] ?? []
    if entries.contains(entry) {
      return localized(
        "配置已有目标模式，无需修改。\n\(check(root:root))",
        "The target mode is already configured. No changes are needed.\n\(check(root:root))")
    }
    entries.append(entry)
    dict["scale-resolutions"] = entries
    let installed = try PropertyListSerialization.data(
      fromPropertyList: dict, format: .xml, options: 0)
    let recordURL = journal.appendingPathComponent("install-\(UUID().uuidString).plist")
    var record: [String: Any] = [
      "date": Date(), "target": relativeTarget, "hadOriginal": existed, "installed": installed,
      "sha256": digest(installed),
    ]
    if let original = original { record["original"] = original }
    let recordData = try PropertyListSerialization.data(
      fromPropertyList: record, format: .xml, options: 0)
    try recordData.write(to: recordURL, options: .atomic)
    try installed.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    guard try Data(contentsOf: url) == installed else {
      throw error(
        localized(
          "安装后校验失败；备份：\(recordURL.path)",
          "Verification after installation failed. Backup: \(recordURL.path)"))
    }
    try Data(recordURL.lastPathComponent.utf8).write(
      to: journal.appendingPathComponent("latest.txt"), options: .atomic)
    return
      localized(
        "独立 HiDPI 配置安装并校验成功。\nSHA256：\(digest(installed))\n备份记录：\(recordURL.path)\n请保存工作后重启。安装成功不等于系统已加载；重启后再检查当前模式。",
        "The HiDPI override was installed and verified.\nSHA256: \(digest(installed))\nBackup record: \(recordURL.path)\nSave your work and restart. Installation does not mean the system has loaded the mode; check the current mode after restarting."
      )
  }
  func restore(root: URL = URL(fileURLWithPath: "/")) throws -> String {
    if root.path == "/" && geteuid() != 0 {
      throw error(
        localized("恢复配置需要管理员授权。", "Restoring a configuration requires administrator authorization.")
      )
    }
    try profile.validate()
    let journal = try rootDirectories(root)
    let fm = FileManager.default
    let url = target(root)
    try rejectSymlinks(journal.appendingPathComponent("latest.txt"))
    let name = try String(contentsOf: journal.appendingPathComponent("latest.txt"), encoding: .utf8)
    guard name.hasPrefix("install-"), !name.contains("/"), name.hasSuffix(".plist") else {
      throw error(localized("备份索引无效。", "The backup index is invalid."))
    }
    let recordURL = journal.appendingPathComponent(name)
    try rejectSymlinks(recordURL)
    guard
      let record = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: recordURL), options: [], format: nil) as? [String: Any],
      record["target"] as? String == relativeTarget, let installed = record["installed"] as? Data
    else { throw error(localized("备份记录无效。", "The backup record is invalid.")) }
    guard try Data(contentsOf: url) == installed else {
      throw error(
        localized(
          "配置在安装后已发生变化，停止自动恢复，避免覆盖其他更改。",
          "The configuration has changed since installation. Restoration stopped to preserve those changes."
        ))
    }
    if let original = record["original"] as? Data {
      try original.write(to: url, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    } else {
      try fm.moveItem(
        at: url, to: journal.appendingPathComponent("disabled-\(UUID().uuidString).plist"))
    }
    return localized(
      "已恢复本工具安装前的状态。请重启使配置生效。",
      "The state before installation has been restored. Restart to apply the configuration.")
  }
}
