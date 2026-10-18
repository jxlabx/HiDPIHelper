import Foundation

func run() throws {
  let args = CommandLine.arguments
  guard args.count >= 3 else {
    throw configurationError(
      "用法：ConfigTool check|install|restore 配置.json，或 generate 配置.json 输出.plist")
  }
  let profile = try DisplayProfile.read(URL(fileURLWithPath: args[2]))
  let configuration = DisplayConfiguration(profile: profile)
  switch args[1] {
  case "check": print(configuration.check())
  case "install": print(try configuration.install())
  case "restore": print(try configuration.restore())
  case "generate":
    guard args.count == 4 else { throw configurationError("请指定输出文件。") }
    let data = try configuration.generated()
    try data.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    print("配置已生成；SHA256：\(configuration.digest(data))")
  default: throw configurationError("未知命令。")
  }
}

do { try run() } catch {
  fputs("\(error.localizedDescription)\n", stderr)
  exit(1)
}
