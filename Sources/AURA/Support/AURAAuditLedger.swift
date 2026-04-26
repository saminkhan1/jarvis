import Foundation

final class AURAAuditLedger {
    static let shared = AURAAuditLedger()

    private let queue = DispatchQueue(label: "com.wexprolabs.aura.audit-ledger")
    private let fileManager = FileManager.default
    private let maxBytes = 5_000_000
    private let retainedArchives = 3

    let ledgerURL: URL

    private init() {
        ledgerURL = Self.defaultLedgerURL()
    }

    static func defaultLedgerURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["AURA_AUDIT_LEDGER_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: false)
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseURL
            .appendingPathComponent("AURA", isDirectory: true)
            .appendingPathComponent("audit", isDirectory: true)
            .appendingPathComponent("aura-audit.jsonl", isDirectory: false)
    }

    func record(
        event: String,
        category: String,
        severity: String,
        auditKind: String,
        traceID: String?,
        spanID: String?,
        parentSpanID: String?,
        fields: [AURATelemetry.Field]
    ) {
        var payload: [String: Any] = [
            "schema_version": AURATelemetry.schemaVersion,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "event": event,
            "category": category,
            "severity": severity,
            "audit_kind": auditKind,
            "app_session_id": AURATelemetry.appSessionID,
            "process_id": Int(AURATelemetry.processID)
        ]

        if let traceID {
            payload["trace_id"] = traceID
        }

        if let spanID {
            payload["span_id"] = spanID
        }

        if let parentSpanID {
            payload["parent_span_id"] = parentSpanID
        }

        for field in fields {
            payload[field.key] = field.value
        }

        queue.async { [ledgerURL, maxBytes, retainedArchives, fileManager] in
            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return
            }

            do {
                try fileManager.createDirectory(
                    at: ledgerURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Self.rotateIfNeeded(
                    ledgerURL: ledgerURL,
                    maxBytes: maxBytes,
                    retainedArchives: retainedArchives,
                    fileManager: fileManager
                )

                if !fileManager.fileExists(atPath: ledgerURL.path) {
                    fileManager.createFile(atPath: ledgerURL.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: ledgerURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data("\n".utf8))
            } catch {
                return
            }
        }
    }

    private static func rotateIfNeeded(
        ledgerURL: URL,
        maxBytes: Int,
        retainedArchives: Int,
        fileManager: FileManager
    ) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: ledgerURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue >= maxBytes else {
            return
        }

        let oldestURL = archiveURL(for: ledgerURL, index: retainedArchives)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try fileManager.removeItem(at: oldestURL)
        }

        if retainedArchives >= 2 {
            for index in stride(from: retainedArchives - 1, through: 1, by: -1) {
                let source = archiveURL(for: ledgerURL, index: index)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = archiveURL(for: ledgerURL, index: index + 1)
                try fileManager.moveItem(at: source, to: destination)
            }
        }

        let firstArchiveURL = archiveURL(for: ledgerURL, index: 1)
        try fileManager.moveItem(at: ledgerURL, to: firstArchiveURL)
    }

    private static func archiveURL(for ledgerURL: URL, index: Int) -> URL {
        ledgerURL.deletingLastPathComponent()
            .appendingPathComponent("\(ledgerURL.lastPathComponent).\(index)", isDirectory: false)
    }
}
