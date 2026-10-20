import AppKit
import CoreGraphics
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let contentWidth: CGFloat = 412
  private let cardPadding: CGFloat = 18
  private var window: NSWindow!
  private var root: NSStackView!
  private var statusItem: NSStatusItem!
  private var displayPicker: NSPopUpButton!
  private var displayNameLabel: NSTextField!
  private var modeLabel: NSTextField!
  private var hiDPISwitch: NSSwitch!
  private var setupButton: NSButton!
  private var confirmCard: NSView!
  private var confirmLabel: NSTextField!
  private var advancedButton: NSButton!
  private var advancedCard: NSView!
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
  private var confirmationDeadline = Date()
  private var debounce: DispatchWorkItem?
  private let preferences = UserDefaults.standard

  func applicationDidFinishLaunching(_ notification: Notification) {
    preferences.register(defaults: ["automatic": false, "useHiDPI": true, "showAdvanced": false])
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
    fitWindow(animated: false)
    window.center()
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

  // MARK: - 界面

  private func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: contentWidth + 48, height: 360),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "HiDPI Helper"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    let background = NSView()
    installWindowBackground(background)

    root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 14
    root.translatesAutoresizingMaskIntoConstraints = false
    root.addArrangedSubview(header())
    addFullWidth(heroCard())
    confirmCard = confirmationCard()
    addFullWidth(confirmCard)
    advancedButton = NSButton(
      title: localized("高级", "Advanced"), target: self, action: #selector(toggleAdvanced))
    advancedButton.isBordered = false
    advancedButton.imagePosition = .imageTrailing
    advancedButton.font = .systemFont(ofSize: 13, weight: .medium)
    advancedButton.contentTintColor = .secondaryLabelColor
    root.addArrangedSubview(advancedButton)
    root.setCustomSpacing(8, after: advancedButton)
    advancedCard = advancedSettingsCard()
    addFullWidth(advancedCard)
    let github = NSButton(
      title: "GitHub · jxlabx/HiDPIHelper", target: self, action: #selector(openGitHub))
    github.isBordered = false
    github.contentTintColor = .tertiaryLabelColor
    github.font = .systemFont(ofSize: 11)
    root.addArrangedSubview(github)
    root.setCustomSpacing(18, after: advancedCard)
    github.centerXAnchor.constraint(equalTo: root.centerXAnchor).isActive = true

    background.addSubview(root)
    NSLayoutConstraint.activate([
      root.widthAnchor.constraint(equalToConstant: contentWidth),
      root.centerXAnchor.constraint(equalTo: background.centerXAnchor),
      root.topAnchor.constraint(equalTo: background.topAnchor, constant: 40),
    ])
    advancedCard.isHidden = !preferences.bool(forKey: "showAdvanced")
    updateAdvancedButton()
    window.initialFirstResponder = hiDPISwitch
  }

  // macOS 26 起整个窗口是一块 Liquid Glass，折射后方的桌面与窗口；更早系统使用半透明材质。
  private func installWindowBackground(_ background: NSView) {
    window.isOpaque = false
    window.backgroundColor = .clear
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 16
        glass.contentView = background
        window.contentView = glass
        background.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          background.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
          background.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
          background.topAnchor.constraint(equalTo: glass.topAnchor),
          background.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        return
      }
    #endif
    let material = NSVisualEffectView()
    material.material = .underWindowBackground
    material.blendingMode = .behindWindow
    material.state = .active
    window.contentView = material
    pin(background, in: material)
  }

  private func header() -> NSView {
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let title = NSTextField(labelWithString: "HiDPI Helper")
    title.font = .systemFont(ofSize: 20, weight: .semibold)
    let subtitle = NSTextField(
      labelWithString: localized("让外接显示器的文字大小刚刚好", "Text at just the right size"))
    subtitle.textColor = .secondaryLabelColor
    let text = NSStackView(views: [title, subtitle])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    return row([icon, text], spacing: 12)
  }

  private func heroCard() -> NSView {
    let symbol = NSImageView(
      image: NSImage(systemSymbolName: "display", accessibilityDescription: nil) ?? NSImage())
    symbol.symbolConfiguration = .init(pointSize: 24, weight: .regular)
    symbol.contentTintColor = .secondaryLabelColor
    symbol.widthAnchor.constraint(equalToConstant: 32).isActive = true
    displayNameLabel = NSTextField(labelWithString: "")
    displayNameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    displayNameLabel.lineBreakMode = .byTruncatingTail
    displayPicker = NSPopUpButton()
    displayPicker.target = self
    displayPicker.action = #selector(selectDisplay)
    displayPicker.isHidden = true
    modeLabel = NSTextField(labelWithString: "")
    modeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    modeLabel.textColor = .secondaryLabelColor
    let info = NSStackView(views: [displayNameLabel, displayPicker, modeLabel])
    info.orientation = .vertical
    info.alignment = .leading
    info.spacing = 3
    let top = row([symbol, info], spacing: 12)

    // 设置项式布局：标题与说明左对齐，开关贴齐卡片右侧内边距。
    let title = NSTextField(labelWithString: localized("开启 HiDPI", "Use HiDPI"))
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    statusLabel = wrappingLabel(size: 12)
    statusLabel.preferredMaxLayoutWidth = contentWidth - cardPadding * 2 - 64
    let text = NSStackView(views: [title, statusLabel])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3
    text.translatesAutoresizingMaskIntoConstraints = false
    hiDPISwitch = NSSwitch()
    hiDPISwitch.target = self
    hiDPISwitch.action = #selector(toggleHiDPI)
    hiDPISwitch.setAccessibilityLabel(localized("开启 HiDPI", "Use HiDPI"))
    hiDPISwitch.translatesAutoresizingMaskIntoConstraints = false
    let toggle = NSView()
    toggle.addSubview(text)
    toggle.addSubview(hiDPISwitch)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: toggle.leadingAnchor),
      text.topAnchor.constraint(equalTo: toggle.topAnchor),
      text.bottomAnchor.constraint(equalTo: toggle.bottomAnchor),
      text.trailingAnchor.constraint(lessThanOrEqualTo: hiDPISwitch.leadingAnchor, constant: -16),
      hiDPISwitch.trailingAnchor.constraint(equalTo: toggle.trailingAnchor),
      hiDPISwitch.centerYAnchor.constraint(equalTo: text.centerYAnchor),
    ])

    setupButton = button(
      localized("创建 HiDPI 配置…", "Create HiDPI Configuration…"), #selector(installConfiguration),
      prominent: true)
    let stack = NSStackView(views: [top, divider(), toggle, setupButton])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    toggle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    return sectionCard(stack, radius: 24)
  }

  private func confirmationCard() -> NSView {
    let icon = NSImageView(
      image: NSImage(systemSymbolName: "timer", accessibilityDescription: nil) ?? NSImage())
    icon.contentTintColor = .systemOrange
    confirmLabel = NSTextField(labelWithString: "")
    confirmLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    confirmLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let revert = button(localized("还原", "Revert"), #selector(revertChange))
    let keep = button(localized("保留", "Keep"), #selector(confirm), prominent: true)
    keep.keyEquivalent = "\r"
    let content = row([icon, confirmLabel, spacer, revert, keep], spacing: 8)
    let card = sectionCard(content, radius: 20, padding: 12, tint: .systemOrange.withAlphaComponent(0.12))
    card.isHidden = true
    return card
  }

  private func advancedSettingsCard() -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10

    stack.addArrangedSubview(sectionTitle(localized("目标桌面尺寸", "Target Desktop Size")))
    widthField = NSTextField(string: "2048")
    heightField = NSTextField(string: "1152")
    for field in [widthField!, heightField!] {
      field.alignment = .center
      field.bezelStyle = .roundedBezel
      field.widthAnchor.constraint(equalToConstant: 72).isActive = true
    }
    let save = button(localized("保存", "Save"), #selector(saveTarget))
    let reload = button(localized("刷新显示器", "Refresh Displays"), #selector(reload))
    stack.addArrangedSubview(
      row([widthField, NSTextField(labelWithString: "×"), heightField, save, reload], spacing: 8))
    editControls = [displayPicker, widthField, heightField, save, reload]

    stack.addArrangedSubview(divider())
    stack.addArrangedSubview(sectionTitle(localized("启动与恢复", "Startup & Restoration")))
    automaticButton = NSButton(
      checkboxWithTitle: localized(
        "登录、唤醒及重新连接后恢复已保留的模式", "Restore at login, wake, and reconnect"),
      target: self, action: #selector(toggleAutomatic))
    loginButton = NSButton(
      checkboxWithTitle: localized("登录时启动", "Launch at Login"), target: self,
      action: #selector(toggleLogin))
    stack.addArrangedSubview(automaticButton)
    stack.addArrangedSubview(loginButton)

    stack.addArrangedSubview(divider())
    stack.addArrangedSubview(sectionTitle(localized("显示器配置", "Display Configuration")))
    configLabel = wrappingLabel(size: 12)
    stack.addArrangedSubview(configLabel)
    stack.addArrangedSubview(
      row(
        [
          button(localized("检查", "Check"), #selector(checkConfiguration)),
          button(localized("创建 / 修复…", "Create / Repair…"), #selector(installConfiguration)),
          button(localized("恢复安装前…", "Restore Previous…"), #selector(restoreConfiguration)),
        ], spacing: 8))
    let hint = wrappingLabel(size: 11)
    hint.textColor = .tertiaryLabelColor
    hint.stringValue = localized(
      "开启 HiDPI 后需在 15 秒内保留，否则自动还原。配置安装需要管理员验证并重启。关闭窗口后仍在菜单栏运行。",
      "Keep a new mode within 15 seconds, or it is reverted. Installing a configuration requires administrator authentication and a restart. The app stays in the menu bar when the window is closed."
    )
    stack.addArrangedSubview(hint)
    return sectionCard(stack, radius: 22)
  }

  // 玻璃窗口内的分组只用轻填充，避免玻璃叠玻璃。
  private func sectionCard(
    _ content: NSView, radius: CGFloat, padding: CGFloat? = nil, tint: NSColor? = nil
  ) -> NSView {
    let inner = NSView()
    pin(content, in: inner, inset: padding ?? cardPadding)
    let box = NSBox()
    box.boxType = .custom
    // 较实的填充加细描边，在窗口获得焦点、玻璃变亮时仍能区分分组。
    box.borderWidth = 1
    box.borderColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? .white.withAlphaComponent(0.1) : .black.withAlphaComponent(0.08)
    }
    box.cornerRadius = radius
    box.fillColor =
      tint
      ?? NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          ? .white.withAlphaComponent(0.14) : .white.withAlphaComponent(0.82)
      }
    box.contentViewMargins = .zero
    box.contentView = inner
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.08)
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = 6
    box.shadow = shadow
    return box
  }

  private func pin(_ view: NSView, in parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    if view.superview !== parent { parent.addSubview(view) }
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
  }

  private func addFullWidth(_ view: NSView) {
    root.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
  }

  private func wrappingLabel(size: CGFloat) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.font = .systemFont(ofSize: size)
    label.textColor = .secondaryLabelColor
    label.preferredMaxLayoutWidth = contentWidth - cardPadding * 2
    return label
  }

  private func sectionTitle(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func divider() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.widthAnchor.constraint(equalToConstant: contentWidth - cardPadding * 2).isActive = true
    return box
  }

  private func button(_ title: String, _ action: Selector, prominent: Bool = false) -> NSButton {
    let control = NSButton(title: title, target: self, action: action)
    control.bezelStyle = .rounded
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        control.bezelStyle = .glass
        if prominent { control.tintProminence = .primary }
        return control
      }
    #endif
    if prominent { control.bezelColor = .controlAccentColor }
    return control
  }

  private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
  }

  // 按内容高度调整窗口，保持顶部位置不变。
  private func fitWindow(animated: Bool) {
    guard let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    let height = root.fittingSize.height + 40 + 20
    guard abs(content.frame.height - height) > 0.5 else { return }
    var frame = window.frameRect(
      forContentRect: NSRect(x: 0, y: 0, width: contentWidth + 48, height: height))
    frame.origin.x = window.frame.minX
    frame.origin.y = window.frame.maxY - frame.height
    window.setFrame(frame, display: true, animate: animated && window.isVisible)
  }

  private func updateAdvancedButton() {
    advancedButton.image = NSImage(
      systemSymbolName: advancedCard.isHidden ? "chevron.right" : "chevron.down",
      accessibilityDescription: nil)
  }

  @objc private func toggleAdvanced() {
    advancedCard.isHidden.toggle()
    preferences.set(!advancedCard.isHidden, forKey: "showAdvanced")
    updateAdvancedButton()
    fitWindow(animated: true)
  }

  @objc private func openGitHub() {
    NSWorkspace.shared.open(URL(string: "https://github.com/jxlabx/HiDPIHelper")!)
  }

  // MARK: - 显示器与配置

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

  // 根据当前选择与输入生成目标，不写入偏好。
  private func candidateProfile() -> DisplayProfile? {
    guard let display = selectedDisplay, let width = Int(widthField.stringValue),
      let height = Int(heightField.stringValue)
    else { return nil }
    let candidate = DisplayProfile(
      vendorID: display.vendorID, productID: display.productID, serialNumber: display.serialNumber,
      width: width, height: height)
    return (try? candidate.validate()) != nil ? candidate : nil
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
    displayPicker.isHidden = displays.count < 2
    displayNameLabel.isHidden = displays.count >= 2

    let display = selectedDisplay
    let current = display.flatMap { CGDisplayCopyDisplayMode($0.id) }
    let target = candidateProfile()
    let active = current.flatMap { mode in target.map { DisplayController.matches(mode, profile: $0) } } ?? false
    let available = display.flatMap { display in
      target.map { DisplayController.target(display.id, profile: $0) != nil }
    } ?? false
    hiDPISwitch.state = active ? .on : .off
    hiDPISwitch.isEnabled = display != nil && target != nil && previous == nil

    if let display = display, let current = current {
      displayNameLabel.stringValue = display.name
      modeLabel.stringValue =
        "\(current.width) × \(current.height) · "
        + (current.pixelWidth > current.width
          ? "HiDPI \(current.pixelWidth) × \(current.pixelHeight)"
          : localized("标准分辨率", "Standard resolution"))
    } else {
      displayNameLabel.stringValue = localized("未检测到外接显示器", "No external display")
      modeLabel.stringValue = localized("连接显示器后自动识别", "Connect a display to get started")
    }

    let size = target.map { "\($0.width) × \($0.height)" } ?? ""
    setupButton.isHidden = display == nil || target == nil || active || available
    if let message = message {
      statusLabel.stringValue = message
    } else if display == nil {
      statusLabel.stringValue = localized(
        "HiDPI Helper 会在显示器连接后自动恢复已保留的模式。",
        "HiDPI Helper restores the kept mode when a display connects.")
    } else if target == nil {
      statusLabel.stringValue = localized(
        "请在“高级”中输入有效的目标尺寸。", "Enter a valid target size under Advanced.")
    } else if active {
      statusLabel.stringValue = localized(
        "HiDPI 已开启，桌面 \(size) 以 2 倍精度渲染。",
        "HiDPI is on. The \(size) desktop is rendered at 2× precision.")
    } else if available {
      statusLabel.stringValue = localized(
        "打开开关，以 \(size) HiDPI 显示更清晰的文字。",
        "Turn on to use \(size) HiDPI for sharper text.")
    } else {
      statusLabel.stringValue = localized(
        "系统尚未提供 \(size) HiDPI 模式。创建配置并重启后即可开启。",
        "macOS does not offer \(size) HiDPI yet. Create a configuration and restart to turn it on.")
    }

    confirmCard.isHidden = previous == nil
    updateConfirmLabel()
    if let profile = profile, display?.matches(profile) == true {
      configLabel.stringValue = configurationStatus(profile, display: display)
    } else {
      configLabel.stringValue = localized(
        "先保存目标尺寸，再检查或创建该显示器的配置。",
        "Save the target size before checking or creating this display’s configuration.")
    }
    if window.isVisible { fitWindow(animated: true) }
  }

  private func updateConfirmLabel() {
    let seconds = max(0, Int(confirmationDeadline.timeIntervalSinceNow.rounded(.up)))
    confirmLabel.stringValue = localized(
      "保留新的显示模式？\(seconds) 秒后还原", "Keep this display mode? Reverting in \(seconds)s")
  }

  @objc private func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    refresh()
  }
  @objc private func quit() { NSApp.terminate(nil) }
  @objc private func toggleHiDPI() { change(hiDPI: hiDPISwitch.state == .on) }
  @objc private func revertChange() { restore() }

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
              "目标 HiDPI 模式尚不可用，请创建配置并重启后再试。",
              "The target HiDPI mode is unavailable. Create a configuration, restart, and try again."
            )
            : localized(
              "系统没有提供可识别的原生模式。", "The system did not provide an identifiable native mode."))
      }
      if DisplayController.same(old, target) {
        keep(hiDPI: hiDPI)
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
      confirmationDeadline = Date().addingTimeInterval(15)
      confirmationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
        [weak self] _ in
        guard let self = self else { return }
        if self.confirmationDeadline.timeIntervalSinceNow <= 0 { self.restore() } else {
          self.updateConfirmLabel()
        }
      }
      refresh()
      NSApp.requestUserAttention(.informationalRequest)
    } catch { refresh(error.localizedDescription) }
  }

  // 主开关代表“保持 HiDPI”：保留后同时决定是否自动恢复。
  private func keep(hiDPI: Bool) {
    preferences.set(hiDPI, forKey: "useHiDPI")
    preferences.set(hiDPI, forKey: "automatic")
  }

  @objc private func confirm() {
    guard previous != nil else { return }
    confirmationTimer?.invalidate()
    confirmationTimer = nil
    previous = nil
    keep(hiDPI: pendingHiDPI)
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
      // 未自动恢复时也同步开关状态，反映外部的模式变化。
      if previous == nil { refresh() }
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

  private func configurationStatus(_ profile: DisplayProfile, display: ConnectedDisplay?) -> String {
    let fileStatus = DisplayConfiguration(profile: profile).check()
    guard let display = display else { return fileStatus }
    let available = DisplayController.target(display.id, profile: profile) != nil
    let active = CGDisplayCopyDisplayMode(display.id).map {
      DisplayController.matches($0, profile: profile)
    } ?? false
    let modeStatus = active
      ? localized("目标 HiDPI 已启用。", "The target HiDPI mode is active.")
      : available
        ? localized("目标 HiDPI 可用，尚未启用。", "The target HiDPI mode is available but inactive.")
        : localized(
          "系统未提供目标 HiDPI；文件存在不代表模式已加载。",
          "The target HiDPI mode is unavailable; a file on disk does not mean it is loaded.")
    return fileStatus + "\n" + modeStatus
  }

  @objc private func checkConfiguration() {
    // 检查不保存输入，也不改变自动恢复偏好。
    refresh()
  }
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
      // 提示显示在主卡片，收起高级选项时也能看到下一步。
      refresh(
        localized(
          "请在终端完成管理员验证，然后重启并检查配置。",
          "Complete administrator authentication in Terminal, then restart and check the configuration."
        ))
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
  let displays = DisplayController.connected()
  guard !displays.isEmpty else {
    fputs("未读取到外接显示器。请在当前图形登录会话中运行；受限环境无法证明显示器未连接。\n", stderr)
    exit(1)
  }
  let preferences = UserDefaults.standard
  let saved = preferences.data(forKey: "profile").flatMap {
    try? JSONDecoder().decode(DisplayProfile.self, from: $0)
  }
  print("自动恢复：\(preferences.bool(forKey: "automatic"))，登录项状态：\(SMAppService.mainApp.status.rawValue)")
  for display in displays {
    guard let current = CGDisplayCopyDisplayMode(display.id) else { continue }
    print("\(display.name): \(current.width)×\(current.height)，渲染 \(current.pixelWidth)×\(current.pixelHeight)，\(current.refreshRate)Hz")
    print("显示器标识：\(String(display.vendorID, radix: 16))-\(String(display.productID, radix: 16))")
    if let profile = saved, display.matches(profile) {
      print(DisplayConfiguration(profile: profile).check())
      print("目标 HiDPI 可用：\(DisplayController.target(display.id, profile: profile) != nil)，已启用：\(DisplayController.matches(current, profile: profile))")
    }
  }
} else {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.delegate = delegate
  application.setActivationPolicy(.regular)
  application.run()
}
