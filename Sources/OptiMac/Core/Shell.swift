import Foundation

/// Lancement de commandes système (sans interface) et des commandes qui demandent
/// le mot de passe administrateur (fenêtre macOS standard).
enum Shell {
    struct Result {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String] = [], timeout: TimeInterval = 120) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        do {
            try p.run()
        } catch {
            return Result(status: -1, out: "", err: error.localizedDescription)
        }
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        p.waitUntilExit()
        timer.cancel()
        group.wait()
        return Result(status: p.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self),
                      err: String(decoding: errData, as: UTF8.self))
    }

    /// Commande shell simple (via /bin/sh -c).
    @discardableResult
    static func sh(_ command: String, timeout: TimeInterval = 120) -> Result {
        run("/bin/sh", ["-c", command], timeout: timeout)
    }

    /// Exécute des commandes avec les droits administrateur : macOS affiche sa fenêtre
    /// de mot de passe habituelle. Une seule demande pour toute la liste.
    @discardableResult
    static func admin(_ commands: [String], prompt: String = "OptiMac a besoin de votre mot de passe pour terminer cette opération.") -> Result {
        guard !commands.isEmpty else { return Result(status: 0, out: "", err: "") }
        let joined = commands.map { "(\($0)) || true" }.joined(separator: "; ")
        let escaped = joined
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let promptEsc = prompt.replacingOccurrences(of: "\"", with: "'")
        let script = "do shell script \"\(escaped)\" with prompt \"\(promptEsc)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script], timeout: 900)
    }

    /// Met un chemin entre guillemets pour /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
