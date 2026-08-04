// RelevanceProviding.swift
// OpenClip
//
// Opt-in capability protocol that lets an action declare whether it is useful for a given
// selection, used to smart-filter sub-action menus. Actions that don't conform always show.
import Foundation

/// Declares whether an action is worth showing for a given selection's text, consumed by the
/// popup's registry-driven sub-menu: a sub-action is listed only when it is relevant (or doesn't
/// conform, in which case it always shows). Synchronous and cheap by design — it runs once per
/// sub-action per menu open, so no I/O or parsing belongs here.
public protocol RelevanceProviding: Action {
    func isRelevant(for text: String) -> Bool
}