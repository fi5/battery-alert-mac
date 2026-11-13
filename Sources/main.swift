import AppKit
import Carbon
import SwiftUI
import IOKit.ps
import ServiceManagement
import UserNotifications

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

func readBattery() -> BatterySnapshot? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for source in sources {
        guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = data[kIOPSCurrentCapacityKey] as? Int,
              let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
        return BatterySnapshot(percent: min(100, max(0, current * 100 / maximum)),
                               onBattery: data[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue)
    }
    return nil
}

final class BatteryModel: ObservableObject {
    @Published var battery: BatterySnapshot?
    @Published var threshold: Int {
        didSet {
            defaults.set(threshold, forKey: "threshold")
            policy.reset()
            defaults.set(false, forKey: "hasNotified")
            evaluate()
        }
    }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); evaluate() } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            onVisibilityChanged?()
        }
    }
    @Published var authorization: UNAuthorizationStatus = .notDetermined
    @Published var loginEnabled = false
    @Published var message = ""
    @Published var testing = false
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var policy: AlertPolicy
    private var delivering = false
    var onBatteryChanged: (() -> Void)?
    var onVisibilityChanged: (() -> Void)?
    var onTestScheduled: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["threshold": 15, "enabled": true, "sound": true, "showMenuBarIcon": true])
        threshold = min(50, max(5, defaults.integer(forKey: "threshold")))
        enabled = defaults.bool(forKey: "enabled")
        sound = defaults.bool(forKey: "sound")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        policy = AlertPolicy(hasNotified: defaults.bool(forKey: "hasNotified"))
    }

    func refresh() {
        battery = readBattery()
        loginEnabled = SMAppService.mainApp.status == .enabled
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorization = settings.authorizationStatus
                self.evaluate()
            }
        }
        onBatteryChanged?()
    }

    private func evaluate() {
        guard let battery = battery else { return }
        let shouldSend = policy.shouldNotify(battery, threshold: threshold, enabled: enabled)
        defaults.set(policy.hasNotified, forKey: "hasNotified")
        guard shouldSend, !delivering,
              authorization == .authorized || authorization == .provisional else { return }
        delivering = true
        let body = String(format: L("Battery is at %d%%. Connect your Mac to power soon."), battery.percent)
        let configuredThreshold = threshold
        send(body: body, test: false) { success in
            self.delivering = false
            if success, self.threshold == configuredThreshold, self.enabled,
               let latest = self.battery, latest.onBattery, latest.percent <= self.threshold {
                self.policy.markDelivered()
                self.defaults.set(true, forKey: "hasNotified")
            }
        }
    }

    func requestPermission(then completion: (() -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error = error { self.message = error.localizedDescription }
                else if !granted { self.message = L("Allow notifications in System Settings to receive battery alerts.") }
                self.authorization = granted ? .authorized : .denied
                self.refresh()
                if granted { completion?() }
            }
        }
    }

    func testNotification() {
        guard !testing else { return }
        testing = true
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorization = settings.authorizationStatus
                if settings.authorizationStatus == .denied {
                    self.testing = false
                    self.message = L("Allow notifications in System Settings to receive battery alerts.")
                    self.openNotificationSettings()
                    return
                }
                if settings.authorizationStatus == .notDetermined {
                    self.testing = false
                    self.requestPermission { self.testNotification() }
                    return
                }
                guard settings.alertSetting == .enabled, settings.alertStyle != .none else {
                    self.testing = false
                    self.message = L("Choose Banners or Alerts in notification settings to display the test.")
                    self.openNotificationSettings()
                    return
                }
                let percent = self.battery?.percent ?? self.threshold
                self.send(body: String(format: L("Test notification · Battery is at %d%%. Your alert threshold is unchanged."), percent), test: true) { success in
                    self.message = success ? L("Test scheduled. Look for a banner in 2 seconds.") : L("Could not send the notification. Please check notification settings.")
                    if success { self.onTestScheduled?() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 2.5 : 0)) {
                        self.testing = false
                    }
                }
            }
        }
    }

    private func send(body: String, test: Bool, completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = L("Battery Low")
        content.body = body
        if sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass")) }
        // A unique test ID prevents Notification Center from silently updating an existing banner.
        let identifier = test ? "test-\(UUID().uuidString)" : "battery-low"
        let trigger = test ? UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false) : nil
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
            DispatchQueue.main.async {
                if let error = error { self.message = error.localizedDescription }
                completion(error == nil)
            }
        }
    }

    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                message = L("Allow LowBatt in System Settings → General → Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { message = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
}

struct SettingsView: View {
    @ObservedObject var model: BatteryModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
                    .resizable().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("LowBatt")).font(.headline)
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            Toggle(L("Low battery alerts"), isOn: $model.enabled)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Notify at"))
                    Spacer()
                    Text("\(model.threshold)%").font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(model.threshold) }, set: { model.threshold = Int($0) }), in: 5...50, step: 1)
                    .disabled(!model.enabled)
                HStack { Text("5%"); Spacer(); Text("50%") }.font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L("Play a sound"), isOn: $model.sound)
            Toggle(L("Launch at login"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            VStack(alignment: .leading, spacing: 5) {
                Toggle(L("Show menu bar icon"), isOn: $model.showMenuBarIcon)
                if !model.showMenuBarIcon {
                    Text(L("Open LowBatt from Applications to show settings."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.authorization != .authorized && model.authorization != .provisional {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Notifications are not enabled"), systemImage: "bell.slash").foregroundStyle(.orange)
                    Button(model.authorization == .denied ? L("Open notification settings") : L("Allow notifications")) {
                        if model.authorization == .denied { model.openNotificationSettings() }
                        else { model.requestPermission() }
                    }
                }.font(.callout)
            }
            HStack {
                Button(L("Send test notification")) { model.testNotification() }.disabled(model.testing)
                Spacer()
                Button { model.openNotificationSettings() } label: { Image(systemName: "gearshape") }
                    .help(L("Open notification settings"))
            }
            if !model.message.isEmpty {
                Text(model.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text(L("Once per discharge. Runs locally.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(18).frame(width: 330)
        .onAppear { model.refresh() }
    }

    private var status: String {
        guard let battery = model.battery else { return L("No internal battery detected") }
        return "\(battery.percent)% · " + (battery.onBattery ? L("On battery") : L("Connected to power"))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = BatteryModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Avoid running two monitors if the app is opened more than once.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        UNUserNotificationCenter.current().delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        model.onBatteryChanged = { [weak self] in self?.updateIcon() }
        model.onTestScheduled = { [weak self] in
            self?.popover.performClose(nil)
            NSApp.hide(nil)
        }
        statusItem.isVisible = model.showMenuBarIcon
        model.onVisibilityChanged = { [weak self] in
            guard let self = self else { return }
            self.popover.performClose(nil)
            self.settingsWindow?.orderOut(nil)
            self.statusItem.isVisible = self.model.showMenuBarIcon
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().model.refresh()
        }, context)?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.model.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        model.refresh()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if firstLaunch || !launchedAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showSettings() }
        }
    }

    @objc private func wake() { model.refresh() }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            settingsWindow?.orderOut(nil)
            model.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showSettings() {
        if model.showMenuBarIcon {
            if !popover.isShown { togglePopover() }
        } else {
            showSettingsWindow()
        }
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = L("LowBatt")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.level = .floating
            window.center()
            settingsWindow = window
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func updateIcon() {
        let name = model.battery?.onBattery == false ? "battery.100.bolt" : "battery.25"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: L("LowBatt"))
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = model.battery.map { "\(L("LowBatt")) · \($0.percent)%" } ?? L("LowBatt")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
