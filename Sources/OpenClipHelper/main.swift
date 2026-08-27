import Foundation
import Core

let delegate = AXHelperService.shared
let listener = NSXPCListener(machServiceName: AXHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Keep daemon run loop active
RunLoop.main.run()
