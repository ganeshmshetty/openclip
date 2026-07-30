public protocol SelectionMonitoring: Sendable {
    @MainActor var onSelection: ((SelectionContext) -> Void)? { get set }
    @MainActor func start()
    @MainActor func stop()
}
