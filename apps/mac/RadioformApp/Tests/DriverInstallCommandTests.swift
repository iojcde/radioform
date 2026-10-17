import Foundation
import AppKit

@main
struct DriverInstallCommandTests {
    static func main() throws {
        let paths = [
            "/Applications/Radioform.app/Contents/Resources/RadioformDriver.driver",
            "/tmp/a'b\"c\\d/Radioform.app",
            "/tmp/$(id); `id` & \"quoted\"/Radioform.app",
            "/tmp/new\nline\rcarriage\ttab/Radioform.app",
            "/tmp/한글 🎵/Radioform.app",
            "/tmp/\" & character id 39 & \"; id; #/Radioform.app"
        ]
        for path in paths {
            var error: NSDictionary?
            let literal = NSAppleScript(source: "return " + DriverInstallCommand.appleScriptString(path))!
            let result = literal.executeAndReturnError(&error)
            precondition(error == nil, "AppleScript literal failed: \(String(describing: error))")
            precondition(result.stringValue == path, "AppleScript altered the path")

            let shell = Process()
            let output = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", "/usr/bin/printf '%s' " + DriverInstallCommand.shellArgument(path)]
            shell.standardOutput = output
            try shell.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            // Foundation/macOS can canonically decompose Unicode process arguments.
            precondition(shell.terminationStatus == 0 && String(data: data, encoding: .utf8) == path,
                         "Shell altered the path")

            let command = "/usr/bin/printf '%s' " + DriverInstallCommand.shellArgument(path) + " | /usr/bin/base64"
            let roundTrip = NSAppleScript(source: "do shell script " + DriverInstallCommand.appleScriptString(command))!
            let encoded = roundTrip.executeAndReturnError(&error).stringValue ?? ""
            precondition(error == nil, "Shell/AppleScript round trip failed")
            let compact = encoded.components(separatedBy: .whitespacesAndNewlines).joined()
            let decoded = Data(base64Encoded: compact).flatMap { String(data: $0, encoding: .utf8) }
            precondition(decoded == path, "Combined AppleScript and shell encoding altered the path")

            // Compile the real privileged commands; never execute them in tests.
            let install = NSAppleScript(source: DriverInstallCommand.install(
                source: path, destination: "/Library/Audio/Plug-Ins/HAL", driverName: "RadioformDriver.driver"
            ))!
            precondition(install.compileAndReturnError(&error), "Invalid install script: \(String(describing: error))")
            let uninstall = NSAppleScript(source: DriverInstallCommand.uninstall(path: path))!
            precondition(uninstall.compileAndReturnError(&error), "Invalid uninstall script")
        }
        print("Installer quoting and AppleScript compilation passed for \(paths.count) adversarial paths")
    }
}
