//
//  main.swift
//  GenerateObjectBox
//
//  Regenerates `generated/EntityInfo-CorePersistence.generated.swift` and
//  `generated/model-CorePersistence.json` after an entity changes.
//
//  Run it through the **GenerateObjectBox scheme** — that is the only supported way, and
//  AGENTS.md says so. Not a SwiftPM executable target (there is none, and `swift run
//  GenerateObjectBox` cannot work); the scheme runs this file as a standalone script.
//
//  Why it invokes the generator binary directly instead of `swift package plugin`:
//
//  That route does not work against the pinned ObjectBox, and it fails *quietly*, which is the
//  dangerous part. `swift package plugin objectbox-generator` exits **0** whether the generator
//  succeeded or not, so the old version of this file printed "Done." after the plugin had in
//  fact rejected every argument it was given:
//
//      Unknown Arguments: --allow-writing-to-package-directory --allow-network-connections all
//      🛑 The plugin execution failed with reason: 1 and status: 1
//      Done.
//
//  Nothing was regenerated and the tool claimed success. Splitting the permission flags with `--`
//  so SwiftPM consumes them does not rescue it either — the plugin then fails to see `--target`
//  and reports "Multiple targets found" instead.
//
//  So this runs the `Sourcery` binary the plugin would have run, with the same arguments the
//  plugin constructs. That path works, and — more importantly — a failure here is now a non-zero
//  exit, which is the whole point of the rewrite.
//

import Foundation

/// Resolved from this file's own location rather than the working directory.
///
/// The scheme's pre-action runs with the working directory set to the project root, which has no
/// `Package.swift` — that was the first thing to break, and it broke the same way: exit 0, and a
/// message that looked like success.
let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // GenerateObjectBox
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // CorePersistence

let targetName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "CorePersistence"

let sourcesDirectory = packageDirectory
    .appendingPathComponent("Sources")
    .appendingPathComponent(targetName)

let generatedDirectory = sourcesDirectory.appendingPathComponent("generated")

/// The generator binary, as fetched into the build directory by the ObjectBox package.
///
/// Not a stable path in the way an SDK path is, so its absence is reported rather than worked
/// around: without it the run cannot be trusted, and quietly producing nothing is the failure mode
/// this file exists to eliminate.
let generator = packageDirectory
    .appendingPathComponent(".build")
    .appendingPathComponent("artifacts")
    .appendingPathComponent("objectbox-swift-spm")
    .appendingPathComponent("ObjectBoxGenerator")
    .appendingPathComponent("Contents")
    .appendingPathComponent("MacOS")
    .appendingPathComponent("Sourcery")

guard FileManager.default.isExecutableFile(atPath: generator.path) else {
    FileHandle.standardError.write(
        Data(
            """
            Cannot find the ObjectBox generator at:
              \(generator.path)

            Resolve the package first so the generator artifact is fetched:
              swift package --package-path \(packageDirectory.path) resolve

            """.utf8
        )
    )
    exit(2)
}

print("Generating ObjectBox code for \(targetName)...")

/// The arguments `GeneratorCommand.runGenerator` builds. Kept in step with that file: it passes the
/// target's own path as `--sources`, names the model and output files explicitly, and disables the
/// cache so a stale template run cannot masquerade as a regeneration.
let process = Process()
process.executableURL = generator
process.arguments = [
    "--sources", sourcesDirectory.path,
    "--model-json", generatedDirectory.appendingPathComponent("model-\(targetName).json").path,
    "--output", generatedDirectory.appendingPathComponent("EntityInfo-\(targetName).generated.swift").path,
    "--disableCache",
    // No telemetry to ObjectBox on a machine that is not asking for it.
    "--no-statistics",
]
// Matches the plugin: sourcekit in-process, which the generator needs to typecheck the sources
// rather than parse them as text.
process.environment = ProcessInfo.processInfo.environment.merging(
    ["IN_PROCESS_SOURCEKIT": "1"]
) { _, new in new }

let outPipe = Pipe()
let errPipe = Pipe()
process.standardOutput = outPipe
process.standardError = errPipe

do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("Could not start the generator: \(error)\n".utf8))
    exit(2)
}

process.waitUntilExit()

let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

if !out.isEmpty {
    print(out)
}

if !err.isEmpty {
    print(err)
}

// Propagate the real status, and say plainly which way it went. A codegen run that reported
// success while regenerating nothing is how stale entity info reaches a commit.
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("Generator exited with status \(process.terminationStatus)\n".utf8))
    exit(process.terminationStatus)
}

print("Done.")
