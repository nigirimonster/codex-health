import Cocoa
import Darwin
import Foundation
import IOKit

private typealias IOHIDEventSystemClient = CFTypeRef
private typealias IOHIDServiceClient = CFTypeRef
private typealias IOHIDEvent = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreateWithType")
private func IOHIDEventSystemClientCreateWithType(
    _ allocator: CFAllocator?,
    _ type: Int32,
    _ attributes: CFDictionary?
) -> IOHIDEventSystemClient

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(
    _ client: IOHIDEventSystemClient,
    _ matching: CFDictionary
)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClient) -> CFArray

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClient,
    _ type: Int64,
    _ matching: CFDictionary?,
    _ options: UInt32
) -> IOHIDEvent?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(
    _ service: IOHIDServiceClient,
    _ key: CFString
) -> CFTypeRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEvent, _ field: Int32) -> Double

struct AuthFile: Decodable {
    struct Tokens: Decodable {
        let access_token: String?
    }

    let tokens: Tokens?
}

struct UsageResponse: Decodable {
    struct RateLimit: Decodable {
        let allowed: Bool
        let limit_reached: Bool
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Decodable {
        let used_percent: Double
        let limit_window_seconds: Int?
        let reset_after_seconds: Int?
        let reset_at: TimeInterval?
    }

    struct Credits: Decodable {
        let has_credits: Bool?
        let unlimited: Bool?
        let balance: String?
    }

    let plan_type: String?
    let rate_limit: RateLimit?
    let credits: Credits?
}

struct LocalUsage {
    let todayTokens: Int64
    let weekTokens: Int64
    let totalTokens: Int64
}

struct MeterState {
    var primaryUsedPercent: Double?
    var secondaryUsedPercent: Double?
    var primaryResetText: String?
    var secondaryResetText: String?
    var primaryResetMenuText: String?
    var secondaryResetMenuText: String?
    var statusText: String
    var creditText: String?
    var localUsage: LocalUsage?
    var updatedAt: Date
    var errorText: String?

    static let loading = MeterState(
        primaryUsedPercent: nil,
        secondaryUsedPercent: nil,
        primaryResetText: nil,
        secondaryResetText: nil,
        primaryResetMenuText: nil,
        secondaryResetMenuText: nil,
        statusText: "Loading",
        creditText: nil,
        localUsage: nil,
        updatedAt: Date(),
        errorText: nil
    )
}

enum HealthLevel {
    case green
    case yellow
    case red
    case unknown

    var label: String {
        switch self {
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .unknown: return "Unknown"
        }
    }

    var color: NSColor {
        switch self {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }
}

struct TemperatureReading {
    enum Source {
        case hidSensor(String)
        case thermalState

        var label: String {
            switch self {
            case .hidSensor(let name):
                return "Exact sensor: \(name)"
            case .thermalState:
                return "Fallback: macOS thermal state"
            }
        }
    }

    let celsius: Double?
    let thermalState: ProcessInfo.ThermalState
    let source: Source

    var level: HealthLevel {
        if let celsius {
            if celsius >= 85 { return .red }
            if celsius >= 70 { return .yellow }
            return .green
        }

        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious, .critical: return .red
        @unknown default: return .unknown
        }
    }

    var menuBarText: String {
        if let celsius {
            return "\(Int(celsius.rounded()))C"
        }

        switch thermalState {
        case .nominal: return "OK"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Crit"
        @unknown default: return "--"
        }
    }

    var detailText: String {
        if let celsius {
            return String(format: "%.1f C", celsius)
        }

        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var showsThrottleWarning: Bool {
        switch thermalState {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        @unknown default:
            return false
        }
    }

    var toolbarText: String {
        let base = menuBarText
        return showsThrottleWarning ? "\(base) !" : base
    }

    var warningLevel: HealthLevel {
        showsThrottleWarning ? .red : level
    }
}

struct MemoryReading {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let activeBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let reclaimableBytes: UInt64
    let freeBytes: UInt64

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    var level: HealthLevel {
        if usedPercent >= 85 { return .red }
        if usedPercent >= 70 { return .yellow }
        return .green
    }
}

struct HealthState {
    let temperature: TemperatureReading
    let memory: MemoryReading?
    let updatedAt: Date
    let errorText: String?

    static let loading = HealthState(
        temperature: TemperatureReading(
            celsius: nil,
            thermalState: ProcessInfo.processInfo.thermalState,
            source: .thermalState
        ),
        memory: nil,
        updatedAt: Date(),
        errorText: nil
    )
}

enum UsageError: LocalizedError {
    case missingToken
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No Codex login token"
        case .invalidResponse:
            return "Invalid server response"
        case .httpStatus(let status):
            return "Usage request failed: HTTP \(status)"
        }
    }
}

enum HealthError: LocalizedError {
    case memoryUnavailable(kern_return_t)

    var errorDescription: String? {
        switch self {
        case .memoryUnavailable(let code):
            return "Memory stats unavailable: \(code)"
        }
    }
}

enum LoginItemError: LocalizedError {
    case missingExecutable
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Could not find app executable"
        case .launchctlFailed(let output):
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "Could not update launch-at-login setting" : message
        }
    }
}

enum DisplayMode: String, CaseIterable {
    case both
    case codex
    case health
    case rotate

    var title: String {
        switch self {
        case .both: return "Both"
        case .codex: return "Codex Only"
        case .health: return "Local Health Only"
        case .rotate: return "Rotate"
        }
    }
}

enum IconChoice: String, CaseIterable {
    case none
    case speedometer
    case sparkles
    case cpuFill = "cpu.fill"
    case circleHexagonpathFill = "circle.hexagonpath.fill"
    case hexagon = "hexagon"
    case codex

    var defaultsValue: String { rawValue }

    var menuTitle: String {
        switch self {
        case .none: return "No Icon"
        case .speedometer: return "Speedometer"
        case .sparkles: return "Sparkles"
        case .cpuFill: return "CPU"
        case .circleHexagonpathFill: return "Tokens"
        case .hexagon: return "Hexagon"
        case .codex: return "Codex"
        }
    }
}

final class UsageReader {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var authURL: URL {
        home.appendingPathComponent(".codex/auth.json")
    }

    private var codexStateURL: URL {
        home.appendingPathComponent(".codex/state_5.sqlite")
    }

    func readLocalUsage() -> LocalUsage? {
        guard FileManager.default.fileExists(atPath: codexStateURL.path) else {
            return nil
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start.timeIntervalSince1970
            ?? (now.timeIntervalSince1970 - 7 * 24 * 60 * 60)

        let query = """
        select
          coalesce(sum(case when updated_at >= \(Int64(startOfDay)) then tokens_used else 0 end), 0),
          coalesce(sum(case when updated_at >= \(Int64(startOfWeek)) then tokens_used else 0 end), 0),
          coalesce(sum(tokens_used), 0)
        from threads;
        """

        guard let output = runSQLite(query: query),
              let firstLine = output.split(separator: "\n", omittingEmptySubsequences: false).first else {
            return nil
        }

        let totals = firstLine.split(separator: "|").map(String.init)
        guard totals.count >= 3,
              let today = Int64(totals[0]),
              let week = Int64(totals[1]),
              let total = Int64(totals[2]) else {
            return nil
        }

        return LocalUsage(todayTokens: today, weekTokens: week, totalTokens: total)
    }

    func fetchUsage(completion: @escaping (Result<UsageResponse, Error>) -> Void) {
        do {
            let token = try readAccessToken()
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/usage")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("en-US", forHTTPHeaderField: "OAI-Language")
            request.setValue("CodexHealthMenu/0.1.0", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(UsageError.invalidResponse))
                    return
                }

                guard (200..<300).contains(http.statusCode), let data else {
                    completion(.failure(UsageError.httpStatus(http.statusCode)))
                    return
                }

                do {
                    completion(.success(try JSONDecoder().decode(UsageResponse.self, from: data)))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private func readAccessToken() throws -> String {
        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(AuthFile.self, from: data)

        guard let token = auth.tokens?.access_token, !token.isEmpty else {
            throw UsageError.missingToken
        }

        return token
    }

    private func runSQLite(query: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [codexStateURL.path, query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

final class TemperatureReader {
    private let temperatureEventType: Int64 = 15
    private let temperatureEventField: Int32 = 15 << 16
    private let sensorUsagePage = 0xff00
    private let sensorUsage = 5

    func read() -> TemperatureReading {
        if let sensor = readHIDTemperature() {
            return TemperatureReading(
                celsius: sensor.celsius,
                thermalState: ProcessInfo.processInfo.thermalState,
                source: .hidSensor(sensor.name)
            )
        }

        return TemperatureReading(
            celsius: nil,
            thermalState: ProcessInfo.processInfo.thermalState,
            source: .thermalState
        )
    }

    private func readHIDTemperature() -> (name: String, celsius: Double)? {
        let matching = [
            "PrimaryUsagePage": sensorUsagePage,
            "PrimaryUsage": sensorUsage
        ] as CFDictionary

        for clientType in [0, 1, 2, 3] as [Int32] {
            let client = IOHIDEventSystemClientCreateWithType(
                kCFAllocatorDefault,
                clientType,
                nil
            )
            IOHIDEventSystemClientSetMatching(client, matching)

            let services = IOHIDEventSystemClientCopyServices(client) as NSArray
            let readings = services.compactMap { service -> (name: String, celsius: Double)? in
                let service = service as CFTypeRef

                guard let event = IOHIDServiceClientCopyEvent(
                    service,
                    temperatureEventType,
                    nil,
                    0
                ) else {
                    return nil
                }

                let celsius = IOHIDEventGetFloatValue(event, temperatureEventField)
                guard celsius.isFinite, celsius > 0, celsius < 130 else {
                    return nil
                }

                return (sensorName(service), celsius)
            }

            if let preferred = preferredSensor(from: readings) {
                return preferred
            }
        }

        return nil
    }

    private func preferredSensor(from readings: [(name: String, celsius: Double)]) -> (name: String, celsius: Double)? {
        guard !readings.isEmpty else {
            return nil
        }

        let preferredNameFragments = ["CPU", "SOC", "SoC", "Die", "PMU", "Thermal"]

        for fragment in preferredNameFragments {
            if let match = readings.first(where: { $0.name.localizedCaseInsensitiveContains(fragment) }) {
                return match
            }
        }

        return readings.max { $0.celsius < $1.celsius }
    }

    private func sensorName(_ service: IOHIDServiceClient) -> String {
        for key in ["Product", "LocationID", "PrimaryUsage"] {
            if let value = IOHIDServiceClientCopyProperty(service, key as CFString) {
                let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return "HID temperature"
    }
}

final class MemoryReader {
    func read() throws -> MemoryReading {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            throw HealthError.memoryUnavailable(result)
        }

        let page = UInt64(pageSize)
        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let free = UInt64(stats.free_count) * page

        return MemoryReading(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            usedBytes: active + wired + compressed,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            reclaimableBytes: inactive + speculative,
            freeBytes: free
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loginItemLabel = "io.github.codexhealthmenu.app"
    private let iconChoiceKey = "statusIconChoice"
    private let displayModeKey = "displayMode"
    private let rotationIntervalKey = "rotationIntervalSeconds"
    private let reader = UsageReader()
    private let temperatureReader = TemperatureReader()
    private let memoryReader = MemoryReader()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var state = MeterState.loading
    private var healthState = HealthState.loading
    private var usageTimer: Timer?
    private var healthTimer: Timer?
    private var rotationTimer: Timer?
    private var rotationShowsCodex = true
    private let usageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateDuplicateInstances()
        configureStatusItem()
        refreshHealth()
        refreshUsage()

        usageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshHealth()
        }
        configureRotationTimer()
    }

    private func terminateDuplicateInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? loginItemLabel

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            if app.processIdentifier != currentPID {
                app.terminate()
            }
        }
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        updateStatusIcon()
        statusItem.menu = menu
        renderMenu()
    }

    @objc private func refreshAll() {
        refreshHealth()
        refreshUsage()
    }

    @objc private func refreshUsage() {
        var next = state
        next.statusText = "Refreshing"
        next.localUsage = reader.readLocalUsage()
        next.updatedAt = Date()
        next.errorText = nil
        state = next
        renderMenu()

        reader.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let usage):
                    self.state = self.makeState(usage: usage, local: self.reader.readLocalUsage())
                case .failure(let error):
                    var failed = self.state
                    failed.errorText = error.localizedDescription
                    failed.statusText = "Offline"
                    failed.updatedAt = Date()
                    failed.localUsage = self.reader.readLocalUsage()
                    self.state = failed
                }

                self.renderMenu()
            }
        }
    }

    @objc private func refreshHealth() {
        let temperature = temperatureReader.read()
        var memory: MemoryReading?
        var errorText: String?

        do {
            memory = try memoryReader.read()
        } catch {
            errorText = error.localizedDescription
        }

        healthState = HealthState(
            temperature: temperature,
            memory: memory,
            updatedAt: Date(),
            errorText: errorText
        )
        renderMenu()
    }

    private func configureRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil

        guard selectedDisplayMode() == .rotate else {
            return
        }

        rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationInterval(), repeats: true) { [weak self] _ in
            guard let self else { return }
            self.rotationShowsCodex.toggle()
            self.renderMenu()
        }
    }

    private func renderMenu() {
        setStatusTitle()
        statusItem.button?.toolTip = tooltipText()

        menu.removeAllItems()
        addHeader("Codex Health")
        addStatusRow("Display", value: selectedDisplayMode().title, level: .unknown)
        if state.errorText == nil {
            addCodexSummaryRow()
        } else {
            addStatusRow("Codex", value: codexMenuSummary(), level: .unknown)
        }
        addStatusRow("Local", value: healthMenuSummary(), level: healthSummaryLevel())

        menu.addItem(.separator())
        addDisplayModeSubmenu()
        addRotationIntervalSubmenu()

        menu.addItem(.separator())
        addHeader("Codex Remaining")
        if let error = state.errorText {
            addDisabled(error)
        } else {
            addDisabled(state.statusText)
            addCodexRemainingRow("Short", remaining: shortRemaining(), reset: state.primaryResetMenuText)
            addCodexRemainingRow("Weekly", remaining: weeklyRemaining(), reset: state.secondaryResetMenuText)
        }

        if let creditText = state.creditText {
            addDisabled(creditText)
        }

        if let local = state.localUsage {
            addDisabled("Tokens today: \(formatTokens(local.todayTokens))")
            addDisabled("Tokens this week: \(formatTokens(local.weekTokens))")
        }

        menu.addItem(.separator())
        addHeader("Local Health")
        addStatusRow("CPU Temperature", value: healthState.temperature.detailText, level: healthState.temperature.level)
        addDisabled("Source: \(shortTemperatureSourceText())")
        if healthState.temperature.showsThrottleWarning {
            addDisabled("Thermal state: performance may be reduced")
        }

        if let memory = healthState.memory {
            addStatusRow("Memory Used", value: "\(Int(memory.usedPercent.rounded()))%", level: memory.level)
            addDisabled("RAM used: \(formatBytes(memory.usedBytes)) of \(formatBytes(memory.totalBytes))")
        } else {
            addStatusRow("Memory Used", value: "--", level: .unknown)
        }

        if let errorText = healthState.errorText {
            addDisabled(errorText)
        }

        menu.addItem(.separator())
        addDisabled("Updated Codex \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
        addAction("Refresh All", #selector(refreshAll))
        addAction("Open Codex Usage Page", #selector(openUsagePage))
        addAction("Open Activity Monitor", #selector(openActivityMonitor))
        addIconSubmenu()
        addCheckAction("Launch at Login", #selector(toggleStartAtLogin), checked: isStartAtLoginEnabled())
        menu.addItem(.separator())
        addAction("Quit", #selector(quit))
    }

    private func setStatusTitle() {
        let text = statusTitleText()
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: attributed.length))

        colorCodexPercentages(in: attributed)
        colorHealthMetrics(in: attributed)

        statusItem.button?.title = text
        statusItem.button?.attributedTitle = attributed
        statusItem.button?.imagePosition = .imageLeading
    }

    private func statusTitleText() -> String {
        switch effectiveDisplayMode() {
        case .both:
            return "\(codexCompactText()) | \(healthState.temperature.toolbarText) | \(memoryCompactText())"
        case .codex:
            return codexCompactText()
        case .health:
            return "\(healthState.temperature.toolbarText) | \(memoryCompactText())"
        case .rotate:
            return codexCompactText()
        }
    }

    private func effectiveDisplayMode() -> DisplayMode {
        let selected = selectedDisplayMode()
        guard selected == .rotate else {
            return selected
        }

        return rotationShowsCodex ? .codex : .health
    }

    private func colorHealthMetrics(in attributed: NSMutableAttributedString) {
        let codexText = codexCompactText()
        let temperatureText = healthState.temperature.toolbarText
        let memoryText = memoryCompactText()
        let memoryLevel = healthState.memory?.level ?? .unknown

        switch effectiveDisplayMode() {
        case .both:
            let temperatureStart = codexText.count + 3
            let memoryStart = temperatureStart + temperatureText.count + 3
            colorRange(start: temperatureStart, length: temperatureText.count, in: attributed, color: healthState.temperature.warningLevel.color)
            colorRange(start: memoryStart, length: memoryText.count, in: attributed, color: memoryLevel.color)
        case .health:
            colorRange(start: 0, length: temperatureText.count, in: attributed, color: healthState.temperature.warningLevel.color)
            colorRange(start: temperatureText.count + 3, length: memoryText.count, in: attributed, color: memoryLevel.color)
        case .codex, .rotate:
            break
        }
    }

    private func colorCodexPercentages(in attributed: NSMutableAttributedString) {
        guard effectiveDisplayMode() == .both || effectiveDisplayMode() == .codex else {
            return
        }

        let shortText = remainingLabel(shortRemaining())
        let weeklyText = remainingLabel(weeklyRemaining())
        var searchStart = 0

        if let shortRange = rangeOf(shortText, in: attributed.string, startingAt: searchStart) {
            colorRange(start: shortRange.location, length: shortRange.length, in: attributed, color: codexPercentLevel(shortRemaining()).color)
            searchStart = shortRange.location + shortRange.length
        }

        if let weeklyRange = rangeOf(weeklyText, in: attributed.string, startingAt: searchStart) {
            colorRange(start: weeklyRange.location, length: weeklyRange.length, in: attributed, color: codexPercentLevel(weeklyRemaining()).color)
        }
    }

    private func rangeOf(_ value: String, in text: String, startingAt start: Int) -> NSRange? {
        let nsText = text as NSString
        guard start >= 0, start < nsText.length else {
            return nil
        }

        let range = nsText.range(of: value, options: [], range: NSRange(location: start, length: nsText.length - start))
        return range.location == NSNotFound ? nil : range
    }

    private func colorRange(start: Int, length: Int, in attributed: NSMutableAttributedString, color: NSColor) {
        guard start >= 0, length > 0, start + length <= attributed.length else {
            return
        }

        attributed.addAttributes([.foregroundColor: color], range: NSRange(location: start, length: length))
    }

    private func codexCompactText() -> String {
        if state.errorText != nil {
            return "--% (--) --% (--)"
        }

        return "\(remainingLabel(shortRemaining())) (\(state.primaryResetText ?? "--")) \(remainingLabel(weeklyRemaining())) (\(state.secondaryResetText ?? "--"))"
    }

    private func memoryCompactText() -> String {
        guard let memory = healthState.memory else {
            return "RAM --%"
        }

        return "RAM \(Int(memory.usedPercent.rounded()))%"
    }

    private func tooltipText() -> String {
        "Codex \(codexMenuSummary()); local \(healthMenuSummary())"
    }

    private func codexMenuSummary() -> String {
        if let error = state.errorText {
            return error
        }

        return "\(remainingLabel(shortRemaining())) short, \(remainingLabel(weeklyRemaining())) weekly"
    }

    private func healthMenuSummary() -> String {
        let memory = healthState.memory.map { "RAM \(Int($0.usedPercent.rounded()))% used" } ?? "RAM --% used"
        return "\(healthState.temperature.detailText), memory \(memory)"
    }

    private func shortTemperatureSourceText() -> String {
        switch healthState.temperature.source {
        case .hidSensor:
            return "Exact sensor"
        case .thermalState:
            return "macOS thermal state"
        }
    }

    private func healthSummaryLevel() -> HealthLevel {
        healthState.temperature.warningLevel
    }

    private func codexLevel() -> HealthLevel {
        guard state.errorText == nil else {
            return .unknown
        }

        let values = [shortRemaining(), weeklyRemaining()].compactMap { $0 }
        guard let lowest = values.min() else {
            return .unknown
        }

        if lowest < 20 { return .red }
        if lowest < 50 { return .yellow }
        return .green
    }

    private func codexPercentLevel(_ value: Double?) -> HealthLevel {
        guard let value else {
            return .unknown
        }

        if value < 20 { return .red }
        if value < 50 { return .yellow }
        return .green
    }

    private func addHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        menu.addItem(item)
    }

    private func addStatusRow(_ title: String, value: String, level: HealthLevel) {
        let text = "\(title): \(value)"
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([.foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: attributed.length))

        let valueRange = (text as NSString).range(of: value)
        if valueRange.location != NSNotFound {
            attributed.addAttributes([
                .foregroundColor: level.color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            ], range: valueRange)
        }

        item.attributedTitle = attributed
        menu.addItem(item)
    }

    private func addCodexSummaryRow() {
        let shortText = remainingLabel(shortRemaining())
        let weeklyText = remainingLabel(weeklyRemaining())
        let text = "Codex: \(shortText) short, \(weeklyText) weekly"
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([.foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: attributed.length))
        colorCodexValue(shortText, in: attributed, startingAt: 0, level: codexPercentLevel(shortRemaining()))
        if let shortRange = rangeOf(shortText, in: attributed.string, startingAt: 0) {
            colorCodexValue(weeklyText, in: attributed, startingAt: shortRange.location + shortRange.length, level: codexPercentLevel(weeklyRemaining()))
        }

        item.attributedTitle = attributed
        menu.addItem(item)
    }

    private func addCodexRemainingRow(_ title: String, remaining: Double?, reset: String?) {
        let percentText = remainingLabel(remaining)
        let text = "\(title): \(percentText) remaining, resets \(reset ?? "--")"
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([.foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: attributed.length))
        colorCodexValue(percentText, in: attributed, startingAt: 0, level: codexPercentLevel(remaining))

        item.attributedTitle = attributed
        menu.addItem(item)
    }

    private func colorCodexValue(_ value: String, in attributed: NSMutableAttributedString, startingAt: Int, level: HealthLevel) {
        guard let range = rangeOf(value, in: attributed.string, startingAt: startingAt) else {
            return
        }

        attributed.addAttributes([
            .foregroundColor: level.color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        ], range: range)
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func addCheckAction(_ title: String, _ action: Selector, checked: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    private func addDisplayModeSubmenu() {
        let parent = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Display")

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == selectedDisplayMode() ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addRotationIntervalSubmenu() {
        let parent = NSMenuItem(title: "Rotation Interval", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Rotation Interval")

        for seconds in [5, 10, 15, 30, 60] {
            let item = NSMenuItem(title: "\(seconds)s", action: #selector(selectRotationInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = Int(rotationInterval()) == seconds ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addIconSubmenu() {
        let parent = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Icon")

        for choice in availableIconChoices() {
            let item = NSMenuItem(title: choice.menuTitle, action: #selector(selectIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.defaultsValue
            item.image = iconImage(for: choice)
            item.state = choice == selectedIconChoice() ? .on : .off
            submenu.addItem(item)
        }

        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: rawValue) else {
            return
        }

        UserDefaults.standard.set(mode.rawValue, forKey: displayModeKey)
        rotationShowsCodex = true
        configureRotationTimer()
        renderMenu()
    }

    @objc private func selectRotationInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else {
            return
        }

        UserDefaults.standard.set(seconds, forKey: rotationIntervalKey)
        configureRotationTimer()
        renderMenu()
    }

    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let choice = IconChoice(rawValue: rawValue) else {
            return
        }

        UserDefaults.standard.set(choice.defaultsValue, forKey: iconChoiceKey)
        updateStatusIcon()
        renderMenu()
    }

    private func selectedDisplayMode() -> DisplayMode {
        if let rawValue = UserDefaults.standard.string(forKey: displayModeKey),
           let mode = DisplayMode(rawValue: rawValue) {
            return mode
        }

        return .both
    }

    private func rotationInterval() -> TimeInterval {
        let saved = UserDefaults.standard.integer(forKey: rotationIntervalKey)
        return TimeInterval(saved == 0 ? 10 : saved)
    }

    private func selectedIconChoice() -> IconChoice {
        if let rawValue = UserDefaults.standard.string(forKey: iconChoiceKey),
           let choice = IconChoice(rawValue: rawValue),
           availableIconChoices().contains(choice) {
            return choice
        }

        return .none
    }

    private func availableIconChoices() -> [IconChoice] {
        let choices: [IconChoice] = [
            .none,
            .speedometer,
            .sparkles,
            .cpuFill,
            .circleHexagonpathFill,
            .hexagon
        ]

        return choices
    }

    private func updateStatusIcon() {
        guard let image = iconImage(for: selectedIconChoice()) else {
            statusItem.button?.image = nil
            return
        }

        image.isTemplate = selectedIconChoice() != .codex
        statusItem.button?.image = image
    }

    private func iconImage(for choice: IconChoice) -> NSImage? {
        switch choice {
        case .none:
            return nil
        case .speedometer:
            return NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Speedometer icon")
        case .sparkles:
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Sparkles icon")
        case .cpuFill:
            return NSImage(systemSymbolName: "cpu.fill", accessibilityDescription: "CPU icon")
        case .circleHexagonpathFill:
            return NSImage(systemSymbolName: "circle.hexagonpath.fill", accessibilityDescription: "Token icon")
        case .hexagon:
            return NSImage(systemSymbolName: "hexagon", accessibilityDescription: "Hexagon icon")
        case .codex:
            return codexIconImage()
        }
    }

    private func codexIconImage() -> NSImage? {
        let paths = [
            "/Applications/Codex.app/Contents/Resources/codexTemplate.png",
            "/Applications/Codex.app/Contents/Resources/codexTemplate@2x.png",
            "/Applications/Codex.app/Contents/Resources/app.icns"
        ]

        for path in paths {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    private func makeState(usage: UsageResponse, local: LocalUsage?) -> MeterState {
        let primaryUsed = usage.rate_limit?.primary_window?.used_percent
        let secondaryUsed = usage.rate_limit?.secondary_window?.used_percent
        let allowed = usage.rate_limit?.allowed ?? true
        let limitReached = usage.rate_limit?.limit_reached ?? false
        let status = limitReached || !allowed ? "Limit reached" : "\(usage.plan_type?.capitalized ?? "Plan") active"

        return MeterState(
            primaryUsedPercent: primaryUsed,
            secondaryUsedPercent: secondaryUsed,
            primaryResetText: resetText(usage.rate_limit?.primary_window),
            secondaryResetText: resetText(usage.rate_limit?.secondary_window),
            primaryResetMenuText: resetMenuText(usage.rate_limit?.primary_window),
            secondaryResetMenuText: resetMenuText(usage.rate_limit?.secondary_window),
            statusText: status,
            creditText: creditText(usage.credits),
            localUsage: local,
            updatedAt: Date(),
            errorText: nil
        )
    }

    private func shortRemaining() -> Double? {
        remainingFromUsed(state.primaryUsedPercent)
    }

    private func weeklyRemaining() -> Double? {
        remainingFromUsed(state.secondaryUsedPercent)
    }

    private func resetText(_ window: UsageResponse.Window?) -> String? {
        guard let seconds = window?.reset_after_seconds else {
            return nil
        }

        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(Int(ceil(Double(seconds) / 60)))m"
        }
        if seconds < 172800 {
            return "\(Int(ceil(Double(seconds) / 3600)))h"
        }
        return "\(Int(ceil(Double(seconds) / 86400)))d"
    }

    private func resetMenuText(_ window: UsageResponse.Window?) -> String? {
        guard let resetAt = window?.reset_at else {
            return resetText(window)
        }

        let date = Date(timeIntervalSince1970: resetAt)
        let time = compactTimeText(date)

        if Calendar.current.isDateInToday(date) {
            return time
        }

        return "\(time) on \(compactDateFormatter.string(from: date))"
    }

    private func compactTimeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.minute], from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = components.minute == 0 ? "ha" : "h:mma"
        return formatter.string(from: date).lowercased()
    }

    private var compactDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter
    }

    private func creditText(_ credits: UsageResponse.Credits?) -> String? {
        guard let credits else {
            return nil
        }

        if credits.unlimited == true {
            return "Credits unlimited"
        }

        if credits.has_credits == true, let balance = credits.balance {
            return "Credits \(balance)"
        }

        return nil
    }

    @objc private func openUsagePage() {
        NSWorkspace.shared.open(usageURL)
    }

    @objc private func openActivityMonitor() {
        let paths = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/Applications/Utilities/Activity Monitor.app"
        ]

        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleStartAtLogin() {
        do {
            if isStartAtLoginEnabled() {
                try disableStartAtLogin()
            } else {
                try enableStartAtLogin()
            }
        } catch {
            var failed = state
            failed.errorText = error.localizedDescription
            state = failed
        }

        renderMenu()
    }

    private func isStartAtLoginEnabled() -> Bool {
        guard let currentExecutable = Bundle.main.executableURL?.path,
              let savedExecutable = launchAgentExecutablePath(),
              savedExecutable == currentExecutable else {
            return false
        }

        return FileManager.default.fileExists(atPath: savedExecutable)
    }

    private func enableStartAtLogin() throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw LoginItemError.missingExecutable
        }

        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: launchAgentLogURL,
            withIntermediateDirectories: true
        )

        try launchAgentPlist(executablePath: executablePath).write(
            to: launchAgentURL,
            atomically: true,
            encoding: .utf8
        )

        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentURL.path])
        try runLaunchctlChecked(arguments: ["bootstrap", "gui/\(getuid())", launchAgentURL.path])
    }

    private func disableStartAtLogin() throws {
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentURL.path])

        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(loginItemLabel).plist")
    }

    private var launchAgentLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CodexHealthMenu")
    }

    private func launchAgentExecutablePath() -> String? {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else {
            return nil
        }

        return arguments.first
    }

    private func launchAgentPlist(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(xmlEscape(loginItemLabel))</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(executablePath))</string>
          </array>
          <key>KeepAlive</key>
          <dict>
            <key>SuccessfulExit</key>
            <false/>
          </dict>
          <key>RunAtLoad</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xmlEscape(launchAgentLogURL.appendingPathComponent("out.log").path))</string>
          <key>StandardErrorPath</key>
          <string>\(xmlEscape(launchAgentLogURL.appendingPathComponent("err.log").path))</string>
        </dict>
        </plist>
        """
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func runLaunchctlChecked(arguments: [String]) throws {
        let result = runLaunchctl(arguments: arguments)
        guard result.exitCode == 0 else {
            throw LoginItemError.launchctlFailed(result.output)
        }
    }

    private func runLaunchctl(arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func remainingLabel(_ value: Double?) -> String {
        guard let value else {
            return "--%"
        }

        return "\(Int(value.rounded()))%"
    }

    private func percentNumber(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "\(Int(value.rounded()))"
    }

    private func remainingFromUsed(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }

        return max(0, min(100, 100 - value))
    }

    private func formatTokens(_ tokens: Int64) -> String {
        let value = Double(tokens)

        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        return "\(tokens)"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 10 {
            return String(format: "%.0f GB", gib)
        }
        return String(format: "%.1f GB", gib)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
