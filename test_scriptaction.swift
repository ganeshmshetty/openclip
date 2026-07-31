import Foundation

func test() async throws {
    let stdOutPipe = Pipe()
    let stdErrPipe = Pipe()
    let stdInPipe = Pipe()
    let text = "Hello"
    let process = Process()
    
    try process.run()
    
    let writeTask = Task.detached {
        if let textData = text.data(using: .utf8) {
            try stdInPipe.fileHandleForWriting.write(contentsOf: textData)
        }
        try stdInPipe.fileHandleForWriting.close()
    }
    
    let readOutTask = Task.detached {
        try stdOutPipe.fileHandleForReading.readToEnd()
    }
    
    let readErrTask = Task.detached {
        try stdErrPipe.fileHandleForReading.readToEnd()
    }
    
    let outDataOpt = try await readOutTask.value
    let errDataOpt = try await readErrTask.value
    _ = try await writeTask.value
    
    process.waitUntilExit()
}
