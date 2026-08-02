// SelectionCoordinator.swift
// OpenClip
//
// Coordinates selection monitoring events and text retrieval results, publishing unified selection context updates.
import Foundation
import Combine

/// Deep module unifying selection monitoring, AX text retrieval fallbacks, and app filtering behind a clean seam.
@MainActor
public final class SelectionCoordinator: ObservableObject, Sendable {
    @Published public private(set) var currentSelection: SelectionContext?
    public var onSelection: ((SelectionContext) -> Void)?
    
    private var monitor: any SelectionMonitoring
    
    public init(monitor: any SelectionMonitoring) {
        self.monitor = monitor
        self.monitor.onSelection = { [weak self] context in
            self?.currentSelection = context
            self?.onSelection?(context)
        }
    }
    
    public func start() {
        monitor.start()
    }
    
    public func stop() {
        monitor.stop()
    }
}
