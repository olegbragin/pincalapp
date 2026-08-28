import Foundation

let targetName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "CorePersistence"

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = [
    "package", "plugin", "objectbox-generator",
    "--allow-writing-to-package-directory",
    "--allow-network-connections", "all",
    "--target", targetName
]

let outPipe = Pipe()
let errPipe = Pipe()
process.standardOutput = outPipe
process.standardError = errPipe

print("Generating ObjectBox code for \(targetName)...")

try process.run()
process.waitUntilExit()

let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

if !out.isEmpty { print(out) }
if !err.isEmpty { print(err) }

if process.terminationStatus == 0 {
    print("Done.")
} else {
    print("Generator exited with status \(process.terminationStatus)")
}
