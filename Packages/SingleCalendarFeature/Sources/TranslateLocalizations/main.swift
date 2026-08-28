import Foundation

let apiURL = ProcessInfo.processInfo.environment["LIBRETRANSLATE_URL"]
    ?? "https://libretranslate.com/translate"
let apiKey = ProcessInfo.processInfo.environment["LIBRETRANSLATE_API_KEY"]

let targetLanguages: [String]
if CommandLine.arguments.count > 1 {
    targetLanguages = Array(CommandLine.arguments.dropFirst())
} else {
    targetLanguages = ["ru"]
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

func findXcstrings(in directory: URL) -> [URL] {
    var files: [URL] = []
    if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator {
            if url.pathExtension == "xcstrings" && url.path.contains("Resources") {
                files.append(url)
            }
        }
    }
    return files
}

func translate(text: String, to lang: String) -> String? {
    guard let url = URL(string: apiURL) else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 15

    var body: [String: Any] = ["q": text, "source": "en", "target": lang, "format": "text"]
    if let key = apiKey, !key.isEmpty {
        body["api_key"] = key
    }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let sem = DispatchSemaphore(value: 0)
    var result: String?
    URLSession.shared.dataTask(with: req) { data, response, _ in
        defer { sem.signal() }
        guard let data = data,
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["translatedText"] as? String else { return }
        result = t
    }.resume()
    _ = sem.wait(timeout: .now() + 20)
    return result
}

func translateFile(at url: URL) throws {
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var strings = json["strings"] as! [String: Any]
    var count = 0

    for key in strings.keys {
        guard var entry = strings[key] as? [String: Any] else { continue }
        guard var localizations = entry["localizations"] as? [String: Any] else { continue }
        guard let enEntry = localizations["en"] as? [String: Any],
              let su = enEntry["stringUnit"] as? [String: Any],
              let enValue = su["value"] as? String,
              !enValue.isEmpty,
              enValue != "%@" && enValue != "%lld" else { continue }

        var needsTranslation: [String] = []
        for lang in targetLanguages {
            if let existing = localizations[lang] as? [String: Any],
               let s = existing["stringUnit"] as? [String: Any],
               let state = s["state"] as? String,
               state == "translated" || state == "new" { continue }
            needsTranslation.append(lang)
        }
        guard !needsTranslation.isEmpty else { continue }

        for lang in needsTranslation {
            if let translated = translate(text: enValue, to: lang) {
                localizations[lang] = [
                    "stringUnit": ["state": "translated", "value": translated]
                ]
                count += 1
                print("  \(key) → \(lang): \(translated)")
            } else {
                print("  \(key) → \(lang): FAILED")
            }
        }
        entry["localizations"] = localizations
        strings[key] = entry
    }

    var output = json
    output["strings"] = strings
    let outData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try outData.write(to: url)
    print("Saved \(count) translations to \(url.lastPathComponent)")
}

print("API: \(apiURL)")
print("Languages: \(targetLanguages.joined(separator: ", "))")
let files = findXcstrings(in: cwd)
guard !files.isEmpty else { print("No .xcstrings files found"); exit(1) }
for f in files {
    print("Translating: \(f.lastPathComponent)")
    try translateFile(at: f)
}
