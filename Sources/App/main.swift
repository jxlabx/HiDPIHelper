import AppKit
import CoreGraphics
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var statusItem: NSStatusItem!
  private var displayPicker: NSPopUpButton!
  private var widthField: NSTextField!
  private var heightField: NSTextField!
  private var statusLabel: NSTextField!
  private var configLabel: NSTextField!
  private var automaticButton: NSButton!
  private var loginButton: NSButton!
  private var editControls: [NSControl] = []
  private var displays: [ConnectedDisplay] = []
  private var profile: DisplayProfile?
  private var previous: (CGDirectDisplayID, CGDisplayMode)?
  private var pendingHiDPI = true
  private var confirmationTimer: Timer?
  private var debounce: DispatchWorkItem?
  private let preferences = UserDefaults.standard

  func applicationDidFinishLaunching(_ notification: Notification) {
    preferences.register(defaults: ["automatic": false, "useHiDPI": true])
    if let data = preferences.data(forKey: "profile"),
      let saved = try? JSONDecoder().decode(DisplayProfile.self, from: data),
      (try? saved.validate()) != nil
    {
      profile = saved
    }
    let menu = NSMenu()
    menu.addItem(
      withTitle: localized("显示设置", "Display Settings"), action: #selector(show), keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: localized("退出", "Quit"), action: #selector(quit), keyEquivalent: "q")
      .target = self
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "display", accessibilityDescription: "HiDPI Helper")
    statusItem.menu = menu
    let main = NSMenu()
    let item = NSMenuItem()
    let appMenu = NSMenu()
    main.addItem(item)
    appMenu.addItem(
      withTitle: localized("退出 HiDPI Helper", "Quit HiDPI Helper"), action: #selector(quit),
      keyEquivalent: "q"
    )
    .target = self
    item.submenu = appMenu
    NSApp.mainMenu = main
    buildWindow()
    reloadDisplays()
    refresh()
    show()
    CGDisplayRegisterReconfigurationCallback(
      { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context = context else { return }
        let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { owner.scheduleRecovery() }
      }, Unmanaged.passUnretained(self).toOpaque())
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    scheduleStartupRecovery()
  }

  private func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "HiDPI Helper"
    window.isReleasedWhenClosed = false
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: localized("让文字大小刚刚好", "Text at just the right size"))
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    stack.addArrangedSubview(title)
    let subtitle = NSTextField(
      labelWithString: localized(
        "为外接显示器设置和恢复 HiDPI 缩放", "Set and restore HiDPI scaling for external displays"))
    subtitle.textColor = .secondaryLabelColor
    stack.addArrangedSubview(subtitle)
    displayPicker = NSPopUpButton()
    displayPicker.target = self
    displayPicker.action = #selector(selectDisplay)
    let reload = button(localized("刷新显示器", "Refresh Displays"), #selector(reload))
    stack.addArrangedSubview(row([displayPicker, reload]))
    widthField = NSTextField(string: "2048")
    heightField = NSTextField(string: "1152")
    widthField.widthAnchor.constraint(equalToConstant: 80).isActive = true
    heightField.widthAnchor.constraint(equalToConstant: 80).isActive = true
    let save = button(localized("保存目标尺寸", "Save Target Size"), #selector(saveTarget))
    stack.addArrangedSubview(
      row([
        NSTextField(labelWithString: localized("桌面尺寸", "Desktop Size")), widthField,
        NSTextField(labelWithString: "×"),
        heightField, save,
      ]))
    editControls = [displayPicker, widthField, heightField, save]
    statusLabel = NSTextField(wrappingLabelWithString: "")
    statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    stack.addArrangedSubview(statusLabel)
    let apply = button(localized("切换到 HiDPI", "Use HiDPI"), #selector(applyHiDPI))
    apply.bezelColor = .controlAccentColor
    stack.addArrangedSubview(
      row([
        apply, button(localized("切换到原生模式", "Use Native Mode"), #selector(applyNative)),
        button(localized("保留设置", "Keep Changes"), #selector(confirm)),
      ]))
    let confirmHint = NSTextField(
      labelWithString: localized(
        "切换后请在 15 秒内保留，否则自动恢复。",
        "Keep changes within 15 seconds, or the previous mode will be restored."))
    confirmHint.font = .systemFont(ofSize: 12)
    confirmHint.textColor = .secondaryLabelColor
    stack.addArrangedSubview(confirmHint)
    automaticButton = NSButton(
      checkboxWithTitle: localized(
        "登录、唤醒及重新连接后恢复已保留的模式", "Restore the saved mode at login, on wake, and on reconnect"),
      target: self, action: #selector(toggleAutomatic))
    loginButton = NSButton(
      checkboxWithTitle: localized("登录时启动", "Launch at Login"), target: self,
      action: #selector(toggleLogin))
    stack.addArrangedSubview(automaticButton)
    stack.addArrangedSubview(loginButton)
    let divider = NSBox()
    divider.boxType = .separator
    divider.widthAnchor.constraint(equalToConstant: 616).isActive = true
    stack.addArrangedSubview(divider)
    configLabel = NSTextField(wrappingLabelWithString: "")
    configLabel.textColor = .secondaryLabelColor
    stack.addArrangedSubview(configLabel)
    stack.addArrangedSubview(
      row([
        button(localized("检查配置", "Check Configuration"), #selector(checkConfiguration)),
        button(localized("创建 / 修复配置…", "Create / Repair…"), #selector(installConfiguration)),
        button(
          localized("恢复安装前配置…", "Restore Previous Configuration…"), #selector(restoreConfiguration)),
      ]))
    let hint = NSTextField(
      wrappingLabelWithString: localized(
        "配置安装需要管理员验证并重启。关闭窗口后仍在菜单栏运行。",
        "Installing a configuration requires administrator authentication and a restart. The app stays in the menu bar when the window is closed."
      ))
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    stack.addArrangedSubview(hint)
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -32),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 30),
      stack.bottomAnchor.constraint(
        lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24),
    ])
    let github = NSButton(
      title: "GitHub · jxlabx/HiDPIHelper", target: self, action: #selector(openGitHub))
    github.isBordered = false
    github.contentTintColor = .linkColor
    github.font = .systemFont(ofSize: 12)
    github.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(github)
    NSLayoutConstraint.activate([
      github.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
      github.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: github.topAnchor, constant: -16),
    ])
    window.center()
  }

  @objc private func openGitHub() {
    NSWorkspace.shared.open(URL(string: "https://github.com/jxlabx/HiDPIHelper")!)
  }

  private func button(_ title: String, _ action: Selector) -> NSButton {
    let control = NSButton(title: title, target: self, action: action)
    control.bezelStyle = .rounded
    return control
  }

  private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = 8
    return stack
  }

  private var selectedDisplay: ConnectedDisplay? {
    guard let id = displayPicker.selectedItem?.representedObject as? UInt32 else { return nil }
    return displays.first { $0.id == id }
  }

  private func reloadDisplays() {
    let selectedID = selectedDisplay?.id
    displays = DisplayController.connected()
    displayPicker.removeAllItems()
    for display in displays {
      displayPicker.addItem(withTitle: "\(display.name) · \(display.id)")
      displayPicker.lastItem?.representedObject = display.id
    }
    let index =
      displays.firstIndex { $0.id == selectedID }
      ?? displays.firstIndex { display in profile.map { display.matches($0) } == true }
    if let index = index { displayPicker.selectItem(at: index) }
    loadFields()
  }

  private func loadFields() {
    guard let display = selectedDisplay else { return }
    if let profile = profile, display.matches(profile) {
      widthField.stringValue = String(profile.width)
      heightField.stringValue = String(profile.height)
    } else if display.vendorID == DisplayProfile.dellPreset.vendorID
      && display.productID == DisplayProfile.dellPreset.productID
    {
      widthField.stringValue = String(DisplayProfile.dellPreset.width)
      heightField.stringValue = String(DisplayProfile.dellPreset.height)
    } else if let current = CGDisplayCopyDisplayMode(display.id) {
      widthField.stringValue = String(current.width)
      heightField.stringValue = String(current.height)
    }
  }

  @objc private func selectDisplay() {
    loadFields()
    refresh()
  }
  @objc private func reload() {
    guard previous == nil else { return }
    reloadDisplays()
    refresh()
  }
  @objc private func saveTarget() {
    do {
      try saveProfile()
      refresh()
    } catch { refresh(error.localizedDescription) }
  }

  private func saveProfile() throws {
    guard previous == nil else {
      throw configurationError(
        localized(
          "请先保留当前切换，或等待恢复。",
          "Keep the current changes first, or wait for the previous mode to be restored."))
    }
    guard let display = selectedDisplay, let width = Int(widthField.stringValue),
      let height = Int(heightField.stringValue)
    else {
      throw configurationError(
        localized(
          "请选择外接显示器并输入整数宽高。",
          "Select an external display and enter whole numbers for width and height."))
    }
    let candidate = DisplayProfile(
      vendorID: display.vendorID, productID: display.productID, serialNumber: display.serialNumber,
      width: width, height: height)
    try candidate.validate()
    if profile != candidate { preferences.set(false, forKey: "automatic") }
    profile = candidate
    preferences.set(try JSONEncoder().encode(candidate), forKey: "profile")
  }

  private func refresh(_ message: String? = nil) {
    automaticButton.state = preferences.bool(forKey: "automatic") ? .on : .off
    loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
    editControls.forEach { $0.isEnabled = previous == nil }
    if let message = message {
      statusLabel.stringValue = message
      return
    }
    if let display = selectedDisplay, let current = CGDisplayCopyDisplayMode(display.id) {
      statusLabel.stringValue =
        localized("当前", "Current") + " \(current.width) × \(current.height)  ·  "
        + localized("渲染", "Rendered") + " \(current.pixelWidth) × \(current.pixelHeight)\n"
        + (previous == nil
          ? localized("已就绪", "Ready")
          : localized("等待确认，15 秒后恢复", "Awaiting confirmation; restoring after 15 seconds"))
    } else {
      statusLabel.stringValue = localized("等待外接显示器连接", "Waiting for an external display")
    }
    if let profile = profile, selectedDisplay?.matches(profile) == true {
      configLabel.stringValue = DisplayConfiguration(profile: profile).check()
    } else {
      configLabel.stringValue = localized(
        "先保存目标尺寸，再检查或创建该显示器的配置。",
        "Save the target size before checking or creating this display’s configuration.")
    }
  }

  @objc private func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    refresh()
  }
  @objc private func quit() { NSApp.terminate(nil) }
  @objc private func applyHiDPI() { change(hiDPI: true) }
  @objc private func applyNative() { change(hiDPI: false) }

  private func change(hiDPI: Bool) {
    do {
      try saveProfile()
      guard let profile = profile, let display = selectedDisplay,
        let old = CGDisplayCopyDisplayMode(display.id)
      else { throw configurationError(localized("显示器不可用。", "The display is unavailable.")) }
      let target =
        hiDPI
        ? DisplayController.target(display.id, profile: profile)
        : DisplayController.native(display.id)
      guard let target = target else {
        throw configurationError(
          hiDPI
            ? localized(
              "目标 HiDPI 模式尚不可用，请创建配置并重启后再检查。",
              "The target HiDPI mode is unavailable. Create a configuration, restart, and check again."
            )
            : localized(
              "系统没有提供可识别的原生模式。", "The system did not provide an identifiable native mode."))
      }
      if DisplayController.same(old, target) {
        preferences.set(hiDPI, forKey: "useHiDPI")
        refresh()
        return
      }
      previous = (display.id, old)
      pendingHiDPI = hiDPI
      guard CGDisplaySetDisplayMode(display.id, target, nil) == .success,
        let actual = CGDisplayCopyDisplayMode(display.id), DisplayController.same(actual, target)
      else {
        restore()
        throw configurationError(
          localized("切换失败，已尝试恢复。", "The mode change failed. Restoration was attempted."))
      }
      confirmationTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) {
        [weak self] _ in self?.restore()
      }
      refresh()
    } catch { refresh(error.localizedDescription) }
  }

  @objc private func confirm() {
    guard previous != nil else { return }
    confirmationTimer?.invalidate()
    confirmationTimer = nil
    previous = nil
    preferences.set(pendingHiDPI, forKey: "useHiDPI")
    refresh()
  }

  private func restore() {
    confirmationTimer?.invalidate()
    confirmationTimer = nil
    if let (id, mode) = previous { _ = CGDisplaySetDisplayMode(id, mode, nil) }
    previous = nil
    refresh()
  }

  @objc private func toggleAutomatic() {
    preferences.set(automaticButton.state == .on, forKey: "automatic")
    if automaticButton.state == .on { scheduleStartupRecovery() }
    refresh()
  }

  @objc private func toggleLogin() {
    do {
      if loginButton.state == .on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refresh(
        SMAppService.mainApp.status == .requiresApproval
          ? localized("请在系统设置的登录项中允许此应用。", "Allow this app in Login Items in System Settings.")
          : nil)
    } catch {
      refresh(
        localized(
          "登录项设置失败：\(error.localizedDescription)",
          "Could not update Login Items: \(error.localizedDescription)"))
    }
  }

  @objc private func wake() { scheduleStartupRecovery() }
  private func scheduleStartupRecovery() {
    for delay in [2.0, 5, 10, 20, 40] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.recover() }
    }
  }
  private func scheduleRecovery() {
    debounce?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.recover() }
    debounce = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
  }
  private func recover() {
    guard preferences.bool(forKey: "automatic"), previous == nil, let profile = profile else {
      return
    }
    reloadDisplays()
    let matches = displays.filter { $0.matches(profile) }
    guard matches.count == 1, let display = matches.first,
      let current = CGDisplayCopyDisplayMode(display.id)
    else {
      refresh()
      return
    }
    let useHiDPI = preferences.bool(forKey: "useHiDPI")
    guard
      let target = useHiDPI
        ? DisplayController.target(display.id, profile: profile)
        : DisplayController.native(display.id)
    else {
      refresh(
        localized(
          "自动恢复暂停：系统没有提供已保存的目标模式。", "Automatic restoration paused: the saved mode is unavailable."))
      return
    }
    if DisplayController.same(current, target) {
      refresh()
      return
    }
    guard CGDisplaySetDisplayMode(display.id, target, nil) == .success,
      let actual = CGDisplayCopyDisplayMode(display.id), DisplayController.same(actual, target)
    else {
      preferences.set(false, forKey: "automatic")
      refresh(localized("自动恢复失败，已关闭自动恢复。", "Automatic restoration failed and has been disabled."))
      return
    }
    refresh()
  }

  @objc private func checkConfiguration() { saveTarget() }
  @objc private func installConfiguration() { launchConfiguration("install") }
  @objc private func restoreConfiguration() { launchConfiguration("restore") }
  private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
  private func launchConfiguration(_ action: String) {
    do {
      try saveProfile()
      guard let profile = profile, let executable = Bundle.main.executableURL else {
        throw configurationError(
          localized("找不到应用程序或显示器配置。", "The application or display profile could not be found."))
      }
      let tool = executable.deletingLastPathComponent().appendingPathComponent("ConfigTool")
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("HiDPIHelper")
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      let profileURL = support.appendingPathComponent("\(profile.modelKey).json")
      try JSONEncoder().encode(profile).write(to: profileURL, options: .atomic)
      let script = support.appendingPathComponent("\(action)-\(profile.modelKey).command")
      let body =
        localized(
          "#!/bin/zsh\nset -eu\necho '显示器配置操作需要管理员验证，输入密码时不会显示字符。'\nsudo \(shellQuote(tool.path)) \(action) \(shellQuote(profileURL.path))\necho '完成后请返回应用检查配置。安装或恢复后需重启。'\nread '?按回车关闭…'\n",
          "#!/bin/zsh\nset -eu\necho 'Administrator authentication is required. Password characters will not appear.'\nsudo \(shellQuote(tool.path)) \(action) \(shellQuote(profileURL.path))\necho 'Return to the app to check the configuration. Restart after installing or restoring.'\nread '?Press Return to close…'\n"
        )
      try body.write(to: script, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
      guard NSWorkspace.shared.open(script) else {
        throw configurationError(
          localized(
            "无法打开安装脚本，请检查终端应用关联。",
            "Could not open the configuration script. Check the application associated with terminal scripts."
          ))
      }
      configLabel.stringValue = localized(
        "请在终端完成管理员验证，然后重启并检查配置。",
        "Complete administrator authentication in Terminal, then restart and check the configuration."
      )
    } catch { refresh(error.localizedDescription) }
  }

  func applicationWillTerminate(_ notification: Notification) { if previous != nil { restore() } }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    show()
    return true
  }
}

if CommandLine.arguments.contains("--diagnose") {
  for display in DisplayController.connected() {
    guard let current = CGDisplayCopyDisplayMode(display.id) else { continue }
    print(
      "\(display.name): \(current.width)×\(current.height), " + localized("渲染", "Rendered")
        + " \(current.pixelWidth)×\(current.pixelHeight), \(current.refreshRate)Hz"
    )
    print(
      localized("可识别原生模式：", "Identifiable native mode: ")
        + "\(DisplayController.native(display.id) != nil)")
  }
} else {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.delegate = delegate
  application.setActivationPolicy(.regular)
  application.run()
}
