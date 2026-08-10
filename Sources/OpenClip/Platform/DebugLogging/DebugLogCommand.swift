// DebugLogCommand.swift
// OpenClip
//
// Parses command-line arguments for the minimal `--dump-logs` CLI surface and formats
// dump lines. Output goes to stdout; the process exits via the AppDelegate glue.
import Foundation

enum DebugLogCommand {
    struct DumpOptions: Equatable {
        var category: String? = nil
        var level: DebugLogLevel? = nil
        var count: Int? = 500
        var collectSeconds: Double = 4

        var filter: DebugLogFilter {
            DebugLogFilter(category: category, level: level, count: count)
        }
    }

    enum Mode: Equatable {
        case none
        case dumpLogs(DumpOptions)
        case showHelp
        case usageError(String)
    }

    static func parse(_ arguments: [String]) -> Mode {
        var sawDump = false
        var options = DumpOptions()
        let args = Array(arguments.dropFirst()) // drop executable path
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--dump-logs" {
                sawDump = true
            } else if arg == "--help" {
                return .showHelp
            } else if let (key, value) = splitFlag(arg) {
                switch key {
                case "category": options.category = value
                case "level":
                    guard let level = DebugLogLevel.allCases.first(where: { $0.displayName == value }) else {
                        return .usageError("Unknown level '\(value)'. Valid: debug, info, notice, error, fault")
                    }
                    options.level = level
                case "count":
                    guard let count = Int(value), count >= 0 else {
                        return .usageError("Invalid count '\(value)'. Expected a non-negative integer")
                    }
                    options.count = count
                case "collect":
                    guard let seconds = Double(value), seconds >= 0 else {
                        return .usageError("Invalid collect '\(value)'. Expected a number of seconds")
                    }
                    options.collectSeconds = seconds
                default:
                    return .usageError("Unknown flag '\(arg)'")
                }
            } else if arg.hasPrefix("--") {
                return .usageError("Unknown flag '\(arg)'")
            }
            // else: ignore non-`--` arguments. Framework/launcher-owned args (e.g. XCTest's
            // `-NSTreatUnknownArgumentsAsOpen`) must not abort a normal app launch.
            index += 1
        }
        return sawDump ? .dumpLogs(options) : .none
    }

    /// Splits `--name=value` into (name, value).
    private static func splitFlag(_ argument: String) -> (String, String)? {
        guard argument.hasPrefix("--") else { return nil }
        let body = argument.dropFirst(2)
        guard let eq = body.firstIndex(of: "=") else { return nil }
        return (String(body[..<eq]), String(body[body.index(after: eq)...]))
    }

    static var usage: String {
        """
        Usage: OpenClip --dump-logs [options]

        Prints recent OpenClip log entries (subsystem com.openclip) from this process
        and exits. Run the app binary directly (not via dev_run.sh).

        Options:
          --category=<name>      Only entries from this Log category (e.g. extensions)
          --level=<level>        Only entries at this severity: debug, info, notice, error, fault
          --count=<N>            Max number of lines (default 500)
          --collect=<seconds>    Collect window before dumping (default 4)
          --help                 Show this help

        Examples:
          OpenClip --dump-logs --category=extensions --level=error
          OpenClip --dump-logs --count=20 --collect=5
        """
    }

    static func formattedLine(_ entry: DebugLogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: entry.date)) \(entry.level.displayName) \(entry.category) \(entry.message)"
    }
}
