import Foundation

enum DriverInstallCommand {
    static func shellArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Shell quoting and AppleScript string encoding are separate layers.
    // Encode the complete command only after every shell argument is quoted.
    static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"" + escaped + "\""
    }

    static func install(source: String, destination: String, driverName: String) -> String {
        let target = shellArgument(destination + "/" + driverName)
        let command = "/bin/cp -R \(shellArgument(source)) \(shellArgument(destination + "/")) && "
            + "/usr/sbin/chown -R root:wheel \(target) && "
            + "/bin/chmod -R 755 \(target) && /usr/bin/killall coreaudiod"
        return "do shell script \(appleScriptString(command)) with administrator privileges"
    }

    static func uninstall(path: String) -> String {
        "do shell script \(appleScriptString("/bin/rm -rf " + shellArgument(path))) with administrator privileges"
    }
}
