import Foundation

private struct AutoTestSimulator {
    let name: String
    let deviceTypeIdentifier: String
}

private let autoTestSimulators: [(profile: String, simulator: AutoTestSimulator)] = [
    (
        "iphone",
        AutoTestSimulator(
            name: "iPhone 17 Pro - AutoTest",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
        )
    ),
    (
        "ipad",
        AutoTestSimulator(
            name: "iPad Pro 13-inch (M5) (16GB) - AutoTest",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-16GB"
        )
    ),
]

@main
struct AutoTestRunner {
    static func main() {
        var profile = "iphone"
        var shouldReset = true
        var checkOnly = false

        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--profile", "-p":
                guard let value = args.first else { fail("Missing value for \(flag)") }
                args.removeFirst()
                guard value == "iphone" || value == "ipad" else {
                    fail("Unsupported profile '\(value)'. Use 'iphone' or 'ipad'.")
                }
                profile = value
            case "--skip-reset":
                shouldReset = false
            case "--check":
                checkOnly = true
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                fail("Unknown argument '\(flag)'. Use --help for usage.")
            }
        }

        let udids: [String: String]
        do {
            udids = try resolveSimulatorUDIDs()
        } catch {
            fail("Could not ensure the AutoTest simulators exist: \(error)")
        }

        do {
            try syncProfileConfig(with: udids)
        } catch {
            fail("Could not update .xcodebuildmcp/config.yaml: \(error)")
        }

        if checkOnly {
            for (profile, simulator) in autoTestSimulators {
                let udid = udids[profile] ?? "?"
                print("\(profile): \(simulator.name) → \(udid)")
            }
            print("Preflight OK.")
            exit(0)
        }

        if shouldReset {
            let targets = autoTestSimulators.compactMap { udids[$0.profile] }
            print("Erasing AutoTest simulators...")
            _ = run(["xcrun", "simctl", "erase"] + targets, expectingSuccess: false)
        }

        print("Running tests using the '\(profile)' profile...")
        let status = run(["xcodebuildmcp", "simulator", "test", "--profile", profile], expectingSuccess: true)
        exit(status)
    }

    // MARK: - Simulator resolution & creation

    private static func resolveSimulatorUDIDs() throws -> [String: String] {
        var available = availableSimulators()
        var resolved: [String: String] = [:]

        for (profile, simulator) in autoTestSimulators {
            if let udid = available[simulator.name] {
                resolved[profile] = udid
                continue
            }

            print("Simulator '\(simulator.name)' not found. Creating it...")
            guard let udid = try createSimulator(simulator) else {
                throw SimulatorError.creationFailed(simulator.name)
            }
            available[simulator.name] = udid
            resolved[profile] = udid
        }
        return resolved
    }

    private static func availableSimulators() -> [String: String] {
        let (status, output) = runCapturingOutput(["xcrun", "simctl", "list", "--json", "devices"])
        guard status == 0,
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: Any]
        else {
            return [:]
        }

        var result: [String: String] = [:]
        for (_, devices) in byRuntime {
            guard let devices = devices as? [[String: Any]] else { continue }
            for device in devices {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String,
                      (device["isAvailable"] as? Bool) == true
                else {
                    continue
                }
                result[name] = udid
            }
        }
        return result
    }

    private static func createSimulator(_ simulator: AutoTestSimulator) throws -> String? {
        let runtimes = availableRuntimes()
        guard !runtimes.isEmpty else {
            throw SimulatorError.noRuntimeFound
        }

        for runtime in runtimes {
            let (status, output) = runCapturingOutput(
                ["xcrun", "simctl", "create", simulator.name, simulator.deviceTypeIdentifier, runtime]
            )
            if status == 0 {
                let udid = output.trimmingCharacters(in: .whitespacesAndNewlines)
                print("Created \(simulator.name) (\(udid)) on \(runtime).")
                return udid.isEmpty ? nil : udid
            }
        }
        return nil
    }

    private static func availableRuntimes() -> [String] {
        let (status, output) = runCapturingOutput(["xcrun", "simctl", "list", "--json", "runtimes"])
        guard status == 0,
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["runtimes"] as? [[String: Any]]
        else {
            return []
        }

        return runtimes
            .compactMap { runtime -> (name: String, identifier: String)? in
                guard let name = runtime["name"] as? String,
                      let identifier = runtime["identifier"] as? String,
                      name.hasPrefix("iOS "),
                      (runtime["isAvailable"] as? Bool) == true
                else {
                    return nil
                }
                return (name, identifier)
            }
            .sorted { $0.name.compare($1.name, options: .numeric) == .orderedDescending }
            .map(\.identifier)
    }

    // MARK: - Config sync

    private static func syncProfileConfig(with udids: [String: String]) throws {
        guard let workspaceRoot = runDirectory else { return }
        let configURL = workspaceRoot.appendingPathComponent(".xcodebuildmcp/config.yaml")
        let content = try String(contentsOf: configURL, encoding: .utf8)

        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inProfiles = false
        var currentProfile: String?
        var changed = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "sessionDefaultsProfiles:" {
                inProfiles = true
                continue
            }
            guard inProfiles else { continue }

            if line.hasPrefix("  ") && !line.hasPrefix("    ") && trimmed.hasSuffix(":") {
                currentProfile = String(trimmed.dropLast())
                continue
            }

            guard let profile = currentProfile, let udid = udids[profile] else { continue }
            guard let simulator = autoTestSimulators.first(where: { $0.profile == profile })?.simulator else { continue }

            if trimmed.hasPrefix("simulatorName:") {
                let replacement = "    simulatorName: \(simulator.name)"
                if line != replacement {
                    lines[index] = replacement
                    changed = true
                }
            } else if trimmed.hasPrefix("simulatorId:") {
                let replacement = "    simulatorId: \(udid)"
                if line != replacement {
                    lines[index] = replacement
                    changed = true
                }
            }
        }

        if changed {
            try lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
            print("Updated .xcodebuildmcp/config.yaml simulator references.")
        }
    }

    // MARK: - Process helpers

    private static var runDirectory: URL? {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var directory = current
        while true {
            let configURL = directory.appendingPathComponent(".xcodebuildmcp/config.yaml")
            if FileManager.default.fileExists(atPath: configURL.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    private static func run(_ arguments: [String], expectingSuccess: Bool) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = runDirectory
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            fail("Failed to launch \(arguments[0]): \(error)")
        }
        process.waitUntilExit()

        let status = process.terminationStatus
        if expectingSuccess && status != 0 {
            fail("\(arguments.first ?? "Command") failed with exit code \(status).")
        }
        return status
    }

    private static func runCapturingOutput(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = runDirectory
        process.standardError = FileHandle.standardError

        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return (1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - Errors & help

    private enum SimulatorError: LocalizedError, CustomStringConvertible {
        case creationFailed(String)
        case noRuntimeFound

        var description: String {
            switch self {
            case .creationFailed(let name):
                return "Failed to create simulator '\(name)' on any available iOS runtime."
            case .noRuntimeFound:
                return "No available iOS runtimes found (xcrun simctl list runtimes)."
            }
        }
    }

    private static func printHelp() {
        print(
            """
            PinCal test runner — runs the suite on the -AutoTest simulators.

            Usage:
              AutoTestRunner [options]

            Options:
              --profile, -p <iphone|ipad>   Test profile (simulator) to use. Default: iphone.
              --skip-reset                  Do not erase the AutoTest simulators before testing.
              --check                       Resolve/create the AutoTest simulators, sync the
                                            config, and exit without running tests.
              --help, -h                    Show this help text.

            Missing -AutoTest simulators are created on the newest available iOS runtime before
            testing. The AutoTest simulators are erased before every run by default.
            """
        )
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}