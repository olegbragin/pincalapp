
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
        // Unbuffered stdout, before anything can print.
        //
        // Swift's `print` to a pipe is block-buffered, so redirected output (`> log`,
        // CI, a nohup capture) showed *nothing* until the process exited: on a real run
        // the entire preamble — including "Resetting AutoTest simulators..." and
        // "Reset complete" — was invisible for the whole hour-long test run and only
        // appeared at the end. For a tool whose entire claim is "the simulators were
        // erased, and here is proof", the proof showing up an hour late is the same
        // class of bug as not doing the erase at all.
        setvbuf(stdout, nil, _IONBF, 0)

        var profile = "iphone"
        var parallelWorkers = 1
        var shouldReset = true
        var checkOnly = false
        var printConfigOnly = false

        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let flag = args.removeFirst()
            switch flag {
            case "--profile", "-p":
                guard let value = args.first else { fail("Missing value for \(flag)") }
                args.removeFirst()
                guard ["iphone", "ipad", "all"].contains(value) else {
                    fail("Unsupported profile '\(value)'. Use 'iphone', 'ipad' or 'all'.")
                }
                profile = value
            case "--parallel-workers":
                // A flag rather than a constant because the right number is a property of the
                // machine, not of this file: four clones of an iPad Pro is a different ask of a
                // Mac than four clones of an iPhone, and the answer has to come from a measured
                // run rather than from a number someone guessed.
                //
                // Defaults to 1, which is serial — one destination, no clones.
                //
                // Deliberately not a measured optimum, because no reliable measurement exists:
                // the same one-worker configuration has been observed at both 27s and 106s on a
                // host whose `uptime` swung between 5 and 113 with nothing booted. An early sample
                // suggested four workers was ~2.5x slower than one, and a later one-worker run was
                // slower than any four-worker run, so that comparison was measuring the machine.
                // One is the conservative default and the configuration that was green most
                // often; raising it is opt-in, and the honest way to choose a number is to
                // interleave configurations on an idle host and watch `uptime` while doing it.
                guard let value = args.first else { fail("Missing value for \(flag)") }
                args.removeFirst()
                guard let count = Int(value), count > 0 else {
                    fail("\(flag) expects a positive integer, got '\(value)'.")
                }
                parallelWorkers = count
            case "--skip-reset":
                shouldReset = false
            case "--check":
                checkOnly = true
            case "--print-config", "-c":
                printConfigOnly = true
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

        if checkOnly {
            for (profile, simulator) in autoTestSimulators {
                let udid = udids[profile] ?? "?"
                print("\(profile): \(simulator.name) → \(udid)")
            }
            print("Preflight OK.")
            exit(0)
        }

        guard let runDirectory else {
            fail(
                """
                Could not find a '.mobilebuildmcp/config.yaml' in \(FileManager.default.currentDirectoryPath) \
                or any parent directory.

                The tool was renamed from xcodebuildmcp to MobileBuildMCP — the *config
                directory* is '.mobilebuildmcp', not '.xcodebuildmcp' — and this runner used
                to look for the old one, so it found nothing and silently skipped the config
                sync. Run it from inside the project so the config is on the path above it.
                """
            )
        }

        let configURL = runDirectory.appendingPathComponent(".mobilebuildmcp/config.yaml")
        let defaults: SessionDefaults
        do {
            defaults = try readSessionDefaults(at: configURL)
        } catch {
            fail("Could not read \(configURL.path): \(error)")
        }

        // 'all' means *both*, one after another, rather than a third kind of device.
        //
        // AGENTS.md is explicit that an iPhone-only green run has never exercised the
        // calendar-switch guarantees: a phone pops the calendar view away, while an iPad replaces
        // the detail column in place, so `testSwitchingCalendarEndsAMultiselectSession` is green on
        // one and red on the other for the same code. The two profiles check different things, so
        // neither substitutes for the other and a single-profile default quietly drops half the
        // suite.
        let profiles = profile == "all" ? autoTestSimulators.map(\.profile) : [profile]

        let workspace = defaults.workspacePath.map {
            resolvedWorkspace($0, in: runDirectory).path
        } ?? runDirectory.appendingPathComponent("pincalapp/PinCalApp.xcworkspace").path
        let scheme = defaults.scheme ?? "PinCalApp"
        guard FileManager.default.fileExists(atPath: workspace) else {
            fail("Workspace not found at \(workspace) (from \(defaults.workspacePath ?? "the default path") ??).")
        }
        print("Workspace: \(workspace)")
        print("Scheme:    \(scheme)")

        if printConfigOnly {
            // Still has to do the sync. The per-profile sync moved into the run loop so each
            // profile points the config at its own device, and leaving it out of this branch would
            // make `--print-config` announce a synchronisation that never happened — the same
            // "the run looks clean but nothing was done" failure this tool already got rewritten
            // once for.
            for target in profiles {
                do {
                    try syncProfileConfig(profile: target, with: udids, in: runDirectory)
                } catch {
                    fail("Could not point the config at the '\(target)' profile: \(error)")
                }
            }
            print("Config synchronised at \(runDirectory.path) for: \(profiles.joined(separator: ", "))")
            exit(0)
        }

        if shouldReset {
            // A shutdown/erase pass, retried.
            //
            // Neither step is atomic with respect to CoreSimulator's own state machine.
            // `shutdown` returns before the device is down, `list` reports it as Shutdown
            // before it will accept an `erase`, and a single pass therefore fails often
            // enough to matter — and the old code ignored that failure, so runs were
            // quietly starting on a non-reset simulator. Three passes, and only then fatal.
            print("Resetting AutoTest simulators...")
            let targets = autoTestSimulators.compactMap { udids[$0.profile] }
            for attempt in 1...4 {
                // From the second pass on, shut *everything* down first.
                //
                // Per-device shutdown was not enough. `simctl erase` kept refusing with
                // *"current state: Booted"* on devices that `simctl list` already reported as
                // Shutdown — including on simulators created seconds earlier, so it is not
                // leftover state on the device. Something else in CoreSimulator is holding a
                // device up, and only a fleet-wide shutdown clears it.
                //
                // Deliberately a *fallback* rather than the first thing that happens: it shuts
                // down every simulator on the machine, including any the developer has open,
                // and that is not this tool's business unless the polite route has failed
                // twice. Prints what it is about to do, because a runner that silently stops
                // someone's other simulators is its own kind of surprising.
                if attempt >= 3 {
                    print("Attempt \(attempt): shutting down all simulators before erasing.")
                    _ = run(["xcrun", "simctl", "shutdown", "all"], expectingSuccess: false)
                    Thread.sleep(forTimeInterval: 15)
                }

                var pending: [String] = []
                for target in targets {
                    if isBooted(target) {
                        _ = run(["xcrun", "simctl", "shutdown", target], expectingSuccess: false)
                        _ = waitUntilShutdown(target, timeout: 60)
                    }
                    // A beat to settle, because `list` can say "Shutdown" for a device that
                    // has not finished shutting down and `erase` will still call it Booted.
                    Thread.sleep(forTimeInterval: 2)

                    let status = run(["xcrun", "simctl", "erase", target], expectingSuccess: false)
                    if status != 0 {
                        pending.append(target)
                    }
                }
                if pending.isEmpty {
                    print("Reset complete (attempt \(attempt)).")
                    break
                }
                print("Attempt \(attempt): erase still refused for \(pending.count) device(s); retrying.")
                if attempt == 3 {
                    fail(
                        """
                        Could not erase \(pending.joined(separator: ", ")) after 4 attempts, \
                        including a fleet-wide `simctl shutdown all`. \
                        Refusing to run: a "full reset" that did not happen is worse than no \
                        reset, because the run still looks clean.
                        """
                    )
                }
            }
        }

        // Profiles run strictly one after another, and each one may spread its own targets
        // across clones.
        //
        // Sequential between profiles is a requirement, not a nicety. Each profile erases and
        // then drives its own simulator, cloning it up to `--parallel-workers` times; two
        // profiles at once would be every clone of both devices at the same time, and they
        // would also be rewriting the same `.mobilebuildmcp/config.yaml` under each other, since
        // the config carries a single `sessionDefaults:` block.
        //
        // A failing profile does not stop the next one. Running both is the point — the iPad half
        // is the only thing that checks the calendar-switch guarantees — so exiting on the first
        // failure would report the iPhone outcome and hide the iPad one.
        var failures: [String] = []
        for currentProfile in profiles {
            guard let udid = udids[currentProfile] else {
                failures.append("\(currentProfile) (no simulator resolved)")
                continue
            }

            do {
                try syncProfileConfig(profile: currentProfile, with: udids, in: runDirectory)
            } catch {
                fail("Could not point the config at the '\(currentProfile)' profile: \(error)")
            }

            print("Running tests using the '\(currentProfile)' profile (\(udid)), \(parallelWorkers) at a time...")
            // The simulator is named explicitly rather than through a defaults profile. The
            // installed CLI has no `--profile` flag, and config.yaml carries a flat
            // `sessionDefaults:` with no `sessionDefaultsProfiles:` section, so a profile
            // selector is not something this can ask for. The id is the thing that actually
            // picks a device, and passing it directly cannot drift from the resolved UDID the
            // way a name or a profile key can.
            // The command is `mobilebuildmcp`, not `xcodebuildmcp`. The tool was renamed and
            // both binaries are on PATH — the old name still resolves, to the previous release —
            // so a runner still calling `xcodebuildmcp` keeps working while quietly running a
            // version behind, which is exactly the kind of drift that reads as "the runner is
            // flaky". Verified: `mobilebuildmcp` 2.7.1, `xcodebuildmcp` 2.7.0.
            //
            // Parallel, capped at `parallelWorkers`. Repeated `--extra-args=<value>`, one entry
            // per xcodebuild argument: a JSON array is *not* accepted, the CLI reads the value as
            // a single string and reports `Unknown build action '["-parallel-testing-enabled","NO"]'`,
            // which is how the old serial flag could have silently stopped reaching xcodebuild.
            //
            // The target-level half of this lives in `PinCalApp.xctestplan`: every unit target is
            // marked `parallelizable`, and without that this flag only buys concurrency between
            // destinations that have nothing to put on them. `PinCalAppUITests` is deliberately
            // left unmarked — Xcode will not distribute UI tests, since they drive one app against
            // one device — so they run serially alongside the parallel unit targets rather than
            // being excluded.
            //
            // The flag used to be `NO`, because parallel runs produced a hard main-actor contention
            // crash that poisoned 136 tests including previously-green ones. That was never a
            // coupling problem: Swift Testing already ran every suite concurrently inside the
            // process (nothing in this repo carries `.serialized`), so `-parallel-testing-enabled`
            // only ever added *cross-destination* concurrency. The crash was four clones
            // oversubscribing one Mac and the wall-clock assertions missing their deadlines —
            // `waitForWrites(1, timeout: .milliseconds(300))` and friends. Those are being made
            // load-independent; this flag is on again so that work can be measured rather than
            // assumed.
            let status = run(
                [
                    "mobilebuildmcp", "simulator", "test",
                    "--workspace-path", workspace,
                    "--scheme", scheme,
                    "--simulator-id", udid,
                    "--extra-args=-parallel-testing-enabled",
                    "--extra-args=YES",
                    "--extra-args=-maximum-parallel-testing-workers",
                    "--extra-args=\(parallelWorkers)",
                ],
                expectingSuccess: false
            )
            if status != 0 {
                failures.append("\(currentProfile) (exit \(status))")
            }
        }

        if failures.isEmpty {
            print("All profiles passed.")
            exit(0)
        }
        fail("Failed: \(failures.joined(separator: ", "))")
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

    /// Whether a device is currently booted.
    private static func isBooted(_ udid: String) -> Bool {
        let (status, output) = runCapturingOutput(["xcrun", "simctl", "list", "--json", "devices"])
        guard status == 0,
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: Any]
        else { return false }
        for (_, devices) in byRuntime {
            guard let devices = devices as? [[String: Any]] else { continue }
            for device in devices where (device["udid"] as? String) == udid {
                return (device["state"] as? String) == "Booted"
            }
        }
        return false
    }

    /// Polls until a device reports itself shut down.
    private static func waitUntilShutdown(_ udid: String, timeout: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if !isBooted(udid) {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
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

    // MARK: - Config

    /// The `sessionDefaults:` block, flattened.
    ///
    /// Read rather than assumed. The CLI resolves its own session defaults relative to
    /// wherever it decides the project root is, and a relative `workspacePath` in here
    /// ("pincalapp/PinCalApp.xcworkspace") does not survive that — `simulator test` came
    /// back with *"scheme is required. Either projectPath or workspacePath is required"*
    /// even though both are plainly present. So the runner hands the CLI what it needs
    /// explicitly, resolved against the directory the config was found in, and the config
    /// write is only for the benefit of an interactive session.
    private struct SessionDefaults {
        var workspacePath: String?
        var scheme: String?
        var simulatorName: String?
        var simulatorId: String?
    }

    private static func readSessionDefaults(at configURL: URL) throws -> SessionDefaults {
        let content = try String(contentsOf: configURL, encoding: .utf8)
        var defaults = SessionDefaults()
        var inDefaults = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "sessionDefaults:" {
                inDefaults = true
                continue
            }
            if inDefaults, !trimmed.isEmpty, !line.hasPrefix(" ") {
                inDefaults = false
            }
            guard inDefaults else { continue }

            if let value = value(of: "workspacePath", in: trimmed) {
                defaults.workspacePath = value
            }
            if let value = value(of: "scheme", in: trimmed) {
                defaults.scheme = value
            }
            if let value = value(of: "simulatorName", in: trimmed) {
                defaults.simulatorName = value
            }
            if let value = value(of: "simulatorId", in: trimmed) {
                defaults.simulatorId = value
            }
        }

        guard defaults.workspacePath != nil || defaults.scheme != nil else {
            throw RunnerError.noSessionDefaults(configURL.path)
        }
        return defaults
    }

    private static func value(of key: String, in trimmedLine: String) -> String? {
        let prefix = "\(key):"
        guard trimmedLine.hasPrefix(prefix) else { return nil }
        let value = String(trimmedLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Points the config's `sessionDefaults` at one profile's simulator.
    ///
    /// The file has a single `sessionDefaults:` block and no `sessionDefaultsProfiles:`
    /// section, so "the profile" is expressed by rewriting the simulator name and id in
    /// place. That keeps an interactive session pointed at the same device the run used,
    /// which is the main reason to bother with the file at all now that the test invocation
    /// passes everything explicitly.
    private static func syncProfileConfig(
        profile: String,
        with udids: [String: String],
        in runDirectory: URL
    ) throws {
        guard let udid = udids[profile],
              let simulator = autoTestSimulators.first(where: { $0.profile == profile })?.simulator
        else { return }

        let configURL = runDirectory.appendingPathComponent(".mobilebuildmcp/config.yaml")
        let content = try String(contentsOf: configURL, encoding: .utf8)

        var lines = content.components(separatedBy: .newlines)
        var inDefaults = false
        var changed = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "sessionDefaults:" {
                inDefaults = true
                continue
            }
            if inDefaults, !trimmed.isEmpty, !lines[index].hasPrefix(" ") {
                inDefaults = false
            }
            guard inDefaults else { continue }

            if trimmed.hasPrefix("simulatorName:") {
                let replacement = "  simulatorName: \(simulator.name)"
                if lines[index] != replacement {
                    lines[index] = replacement
                    changed = true
                }
            } else if trimmed.hasPrefix("simulatorId:") {
                let replacement = "  simulatorId: \(udid)"
                if lines[index] != replacement {
                    lines[index] = replacement
                    changed = true
                }
            }
        }

        if changed {
            try lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
            print("Updated \(configURL.lastPathComponent): \(simulator.name) -> \(udid)")
        } else {
            print("\(configURL.lastPathComponent) already points at \(simulator.name) - no change.")
        }
    }

    /// The absolute workspace path, resolving a relative one against `runDirectory`.
    private static func resolvedWorkspace(_ configured: String, in runDirectory: URL) -> URL {
        if configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured)
        }
        return runDirectory.appendingPathComponent(configured).standardizedFileURL
    }

    // MARK: - Process helpers

    private static var runDirectory: URL? {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var directory = current
        while true {
            let configURL = directory.appendingPathComponent(".mobilebuildmcp/config.yaml")
            if FileManager.default.fileExists(atPath: configURL.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory {
                break
            }
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
        if expectingSuccess, status != 0 {
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
            case let .creationFailed(name):
                return "Failed to create simulator '\(name)' on any available iOS runtime."
            case .noRuntimeFound:
                return "No available iOS runtimes found (xcrun simctl list runtimes)."
            }
        }
    }

    private enum RunnerError: LocalizedError, CustomStringConvertible {
        case noSessionDefaults(String)

        var description: String {
            switch self {
            case let .noSessionDefaults(path):
                return "No 'sessionDefaults:' block in \(path), so there is nothing to point at a profile."
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
              --profile, -p <iphone|ipad|all>
                                            Test profile (simulator) to use. 'all' runs both,
                                            one after the other. Default: iphone.
              --parallel-workers <n>        Simulator clones a profile's run may use at once.
                                            1 (the default) is serial; raise it to trade wall
                                            clock for concurrency.
              --skip-reset                  Do not erase the AutoTest simulators before testing.
              --check                       Resolve/create the AutoTest simulators and exit
                                            without touching the config or running tests.
              --print-config, -c            Sync the config to the chosen profile and exit
                                            without running tests.
              --help, -h                    Show this help text.

            Missing -AutoTest simulators are created on the newest available iOS runtime before
            testing. Both are shut down and erased before every run by default, and a failure
            to do either is fatal rather than ignored — a "full reset" that silently did not
            happen is worse than none, because the run still looks clean.

            Each profile runs its test targets across up to --parallel-workers clones of its own
            simulator, one destination by default. Profiles never overlap: they share one machine
            and one config file, so a failing profile still lets the next one run — the iPad half
            is the only thing that checks the calendar-switch guarantees, so stopping at the
            first failure would report the iPhone outcome and hide the iPad one.

            The chosen profile is written into .mobilebuildmcp/config.yaml, which is what the
            CLI reads, and the simulator is also passed to the CLI by id. The id is the
            authoritative part: a name or a config entry can drift, a resolved UDID cannot.
            """
        )
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
