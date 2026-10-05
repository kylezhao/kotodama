//
//  SpiritFont.swift
//  Kotodama
//
//  Created by Kyle Zhao on 2026-10-06.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import CoreText
import Foundation
import Observation
import SwiftUI
import UIKit

/// Picks a brush-like CJK face for the floating word spirits. Prefers Apple's cursive 行楷 and
/// regular-script 楷体 faces, which iOS can download on demand, and falls back to the built-in
/// Hiragino Mincho while they are not installed.
@MainActor
@Observable
final class SpiritFont {
    /// Preferred PostScript names, best first.
    static let preferred = ["STXingkai-SC-Light", "STXingkai-SC-Bold", "STKaiti-SC-Regular", "STKaitiSC-Regular", "HiraMinProN-W3", "STSongti-SC-Regular"]
    /// Families to request from the on-demand font catalogue.
    static let downloadable = ["Xingkai SC", "Kaiti SC"]

    private(set) var fontName: String?

    init() {
        fontName = Self.firstAvailable()
        if fontName == nil || !fontName!.hasPrefix("STXingkai") {
            downloadIfNeeded()
        }
    }

    func font(size: CGFloat) -> Font {
        if let fontName { return .custom(fontName, size: size) }
        return .system(size: size, weight: .light, design: .serif)
    }

    static func firstAvailable() -> String? {
        preferred.first { UIFont(name: $0, size: 12) != nil }
    }

    /// Asks CoreText for the downloadable faces. Silent when offline; the fallback face stays in use.
    private func downloadIfNeeded() {
        let descriptors = Self.downloadable.map { family in
            CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        }
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors as CFArray, nil) { [weak self] state, _ in
            if state == .didFinish || state == .didFailWithError {
                Task { @MainActor in
                    self?.fontName = Self.firstAvailable()
                }
            }
            return true
        }
    }
}
