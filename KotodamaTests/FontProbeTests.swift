//
//  FontProbeTests.swift
//  KotodamaTests
//
//  Created by Kyle Zhao on 2026-10-06.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Testing
import UIKit
@testable import Kotodama

struct FontProbeTests {
    /// Writes the installed CJK-capable families to /tmp/koto-fonts.txt so the spirit font choice is grounded.
    @MainActor @Test func dumpsInstalledCJKFonts() {
        let keywords = ["Hiragino", "PingFang", "Songti", "Kaiti", "Xingkai", "Heiti", "Yuanti", "Weibei", "Baoli", "Libian", "Wawati", "Hannotate", "HanziPen", "Mincho", "Gothic"]
        var lines: [String] = []
        for family in UIFont.familyNames.sorted() where keywords.contains(where: { family.localizedCaseInsensitiveContains($0) }) {
            lines.append("\(family): \(UIFont.fontNames(forFamilyName: family).joined(separator: ", "))")
        }
        lines.append("resolved: \(SpiritFont.firstAvailable() ?? "none")")
        try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/koto-fonts.txt"), atomically: true, encoding: .utf8)
        #expect(!lines.isEmpty)
    }
}
