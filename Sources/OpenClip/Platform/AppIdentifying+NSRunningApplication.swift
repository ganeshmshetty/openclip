// AppIdentifying+NSRunningApplication.swift
// OpenClip
//
// Extends NSRunningApplication to conform to the AppIdentifying protocol for macOS process tracking.
import AppKit
import Core

extension NSRunningApplication: @retroactive AppIdentifying {}
