import AppKit

enum AppRelaunchService {
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        // Flush UserDefaults before termination to prevent restart loop (research pitfall 4)
        UserDefaults.standard.synchronize()
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
