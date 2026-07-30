public protocol SelectionMonitoring: Sendable {
    @MainActor func start()
    @MainActor func stop()
}
