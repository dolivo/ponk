import BackgroundTasks
import Compression
import CryptoKit
import Foundation
import Network
import Observation
import UserNotifications

/// Stahuje denní data, která připravuje GitHub Actions (vydání „data“ v repozitáři),
/// a vyměňuje je v telefonu. Počítač už není potřeba.
@MainActor
@Observable
final class DataStore {
    static let shared = DataStore()
    static let refreshTaskID = "cz.ponk.app.refresh"
    static let defaultRepo = "dolivo/ponk"

    let engine: LocalEngine
    private(set) var hasData = false
    private(set) var running = false
    private(set) var phase = ""
    private(set) var done = 0
    private(set) var total = 0
    private(set) var message = ""
    /// Kdy GitHub data připravil.
    private(set) var generatedAt: Date?

    private let dir: URL
    private var dataURL: URL { dir.appendingPathComponent("ponk-data.sqlite") }

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ponk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        engine = LocalEngine(dataPath: dir.appendingPathComponent("ponk-data.sqlite").path,
                             userPath: dir.appendingPathComponent("ponk-user.sqlite").path)
        if let s = UserDefaults.standard.string(forKey: "data_generated_at") { generatedAt = Self.iso.date(from: s) }
    }

    var repo: String {
        let r = UserDefaults.standard.string(forKey: "repo")?.trimmingCharacters(in: .whitespaces) ?? ""
        return r.isEmpty ? Self.defaultRepo : r
    }

    private var base: URL { URL(string: "https://github.com/\(repo)/releases/download/data/")! }

    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    var status: SyncStatus {
        SyncStatus(running: running, phase: phase, done: done, total: total, started: nil, message: message)
    }

    /// Data jsou starší než dva dny (např. GitHub úloha neproběhla nebo telefon dlouho nebyl online).
    var isStale: Bool { generatedAt.map { Date().timeIntervalSince($0) > 48 * 3600 } ?? false }

    func start() async {
        do { try await engine.open() } catch { message = error.localizedDescription }
        hasData = await engine.hasData
        PonkAPI.shared.offlineSince = isStale ? generatedAt : nil
    }

    // MARK: - aktualizace

    private struct Status: Decodable {
        let schema: Int
        let generated_at: String
        let files: [String: FileInfo]
        struct FileInfo: Decodable { let size: Int; let sha256: String }
    }

    /// - Parameter force: stáhnout i na mobilních datech a i když nejsou novější.
    @discardableResult
    func update(force: Bool) async -> Bool {
        guard !running else { return false }
        running = true
        phase = "Zjišťuji, jestli jsou nová data"
        done = 0; total = 0; message = ""
        defer { running = false; phase = "" }
        do {
            let (sdata, _) = try await URLSession.shared.data(from: base.appendingPathComponent("status.json"))
            let status = try JSONDecoder().decode(Status.self, from: sdata)
            guard status.schema <= 4 else {
                message = "Data jsou pro novější verzi aplikace. Aktualizuj Ponk."
                return false
            }
            let remote = Self.iso.date(from: status.generated_at)
            if !force, hasData, let remote, let local = generatedAt, remote <= local {
                message = "Data jsou aktuální."
                return false
            }
            if !force, !(await Self.isOnWiFi()), UserDefaults.standard.object(forKey: "auto_wifi") as? Bool ?? true {
                message = "Nová data čekají na Wi-Fi."
                return false
            }
            // xz je menší; kdyby ho systém neuměl rozbalit, použije se deflate
            var lastError: Error?
            for (name, algorithm) in [("ponk-mobile.sqlite.xz", Algorithm.lzma), ("ponk-mobile.sqlite.deflate", Algorithm.zlib)] {
                guard let info = status.files[name] else { continue }
                do {
                    try await install(name: name, info: info, algorithm: algorithm)
                    lastError = nil
                    break
                } catch {
                    lastError = error
                }
            }
            if let lastError { throw lastError }
            generatedAt = remote
            UserDefaults.standard.set(status.generated_at, forKey: "data_generated_at")
            PonkAPI.shared.offlineSince = nil
            message = "Data aktualizována."
            await notifyWatchedDrops()
            await notifyWatchedRestocks()
            return true
        } catch {
            message = "Data se nepodařilo stáhnout: \(error.localizedDescription)"
            PonkAPI.shared.offlineSince = isStale ? generatedAt : nil
            return false
        }
    }

    private func install(name: String, info: Status.FileInfo, algorithm: Algorithm) async throws {
        phase = "Stahuji data (\(info.size / 1_000_000) MB)"
        total = info.size
        let (tmp, response) = try await URLSession.shared.download(from: base.appendingPathComponent(name))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        done = info.size
        phase = "Ověřuji a rozbaluji"
        let newURL = dir.appendingPathComponent("ponk-data.new.sqlite")
        let tmpPath = tmp.path, newPath = newURL.path, sha = info.sha256
        try await Task.detached(priority: .userInitiated) {
            let packed = try Data(contentsOf: URL(fileURLWithPath: tmpPath), options: .mappedIfSafe)
            let digest = SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined()
            guard digest == sha else { throw URLError(.cannotDecodeContentData) }
            try Self.decompress(packed, algorithm: algorithm, to: URL(fileURLWithPath: newPath))
            try LocalEngine.prepareDownloaded(path: newPath)
        }.value
        phase = "Připravuji databázi"
        await engine.closeData()
        if FileManager.default.fileExists(atPath: dataURL.path) {
            _ = try FileManager.default.replaceItemAt(dataURL, withItemAt: newURL)
        } else {
            try FileManager.default.moveItem(at: newURL, to: dataURL)
        }
        try await engine.open()
        hasData = await engine.hasData
    }

    nonisolated private static func decompress(_ packed: Data, algorithm: Algorithm, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        let filter = try OutputFilter(.decompress, using: algorithm, bufferCapacity: 1 << 20) { chunk in
            if let chunk { out.write(chunk) }
        }
        var offset = 0
        let step = 1 << 20
        while offset < packed.count {
            let end = min(offset + step, packed.count)
            try filter.write(packed.subdata(in: offset..<end))
            offset = end
        }
        try filter.finalize()
    }

    nonisolated private static func isOnWiFi() async -> Bool {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                cont.resume(returning: path.status == .satisfied && !path.isExpensive)
            }
            monitor.start(queue: DispatchQueue(label: "ponk.net"))
        }
    }

    // MARK: - upozornění a běh na pozadí

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyWatchedRestocks() async {
        guard let names = try? await engine.newWatchedRestocks(), !names.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = names.count == 1 ? "Znovu skladem: \(names[0])" : "Znovu skladem \(names.count) hlídaných produktů"
        content.body = names.count == 1 ? "Je na tvé prodejně nebo v e-shopu." : names.prefix(4).joined(separator: "\n")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func notifyWatchedDrops() async {
        guard let drops = try? await engine.newWatchedDrops(), !drops.isEmpty else { return }
        let content = UNMutableNotificationContent()
        if drops.count == 1, let d = drops.first {
            content.title = "Zlevněno: \(d.name)"
            content.body = "Teď \(money(d.price)) Kč (hlídáš od \(money(d.was)) Kč)."
        } else {
            content.title = "Zlevnilo \(drops.count) hlídaných produktů"
            content.body = drops.prefix(3).map { "\($0.name): \(money($0.price)) Kč" }.joined(separator: "\n")
        }
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Naplánuje další kontrolu na pozadí (iOS rozhodne, kdy přesně proběhne).
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        var next = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: Date()) ?? Date()
        if next < Date() { next = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? next }
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }

    func backgroundRefresh() async {
        Self.scheduleBackgroundRefresh()
        if !hasData { await start() }
        await update(force: false)
    }
}
