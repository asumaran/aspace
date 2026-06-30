import Foundation
import Testing
@testable import DisplayKit

@Suite struct DisplayModeMatcherTests {

    private func mode(_ pw: Int, _ ph: Int, px: Int, py: Int, hz: Double = 60, safe: Bool = true) -> DisplayMode {
        DisplayMode(pointWidth: pw, pointHeight: ph, pixelWidth: px, pixelHeight: py, refreshHz: hz, isSafe: safe)
    }

    private let target = AspaceConfig.ModeSpec(pointWidth: 2560, pointHeight: 1440)

    @Test func prefersHiDPIOverOneToOne() {
        let oneToOne = mode(2560, 1440, px: 2560, py: 1440)        // scale 1.0
        let hidpi    = mode(2560, 1440, px: 5120, py: 2880)        // scale 2.0
        let best = DisplayModeMatcher.best(for: target, in: [oneToOne, hidpi])
        #expect(best == hidpi)
    }

    @Test func prefersHigherRefreshAmongHiDPI() {
        let hz30 = mode(2560, 1440, px: 5120, py: 2880, hz: 30)
        let hz60 = mode(2560, 1440, px: 5120, py: 2880, hz: 60)
        let best = DisplayModeMatcher.best(for: target, in: [hz30, hz60])
        #expect(best == hz60)
    }

    @Test func prefersSafeWhenScaleAndRefreshTie() {
        let unsafe = mode(2560, 1440, px: 5120, py: 2880, hz: 60, safe: false)
        let safe   = mode(2560, 1440, px: 5120, py: 2880, hz: 60, safe: true)
        let best = DisplayModeMatcher.best(for: target, in: [unsafe, safe])
        #expect(best == safe)
    }

    @Test func returnsNilWhenNoPointSizeMatches() {
        let other = mode(3200, 1800, px: 6400, py: 3600)
        #expect(DisplayModeMatcher.best(for: target, in: [other]) == nil)
    }

    @Test func picksBestFromRealisticStudioDisplayList() {
        // Mirrors the inspector output for the Studio Display at 2560x1440.
        let modes = [
            mode(3200, 1800, px: 6400, py: 3600),
            mode(2560, 1440, px: 5120, py: 2880, hz: 60, safe: true),  // <- expected
            mode(2560, 1440, px: 2560, py: 1440, hz: 60, safe: true),
            mode(2560, 1440, px: 2560, py: 1440, hz: 60, safe: false),
            mode(1920, 1080, px: 3840, py: 2160),
        ]
        let best = DisplayModeMatcher.best(for: target, in: modes)
        #expect(best?.pixelWidth == 5120 && best?.pixelHeight == 2880)
        #expect(best?.isHiDPI == true)
    }
}

@Suite struct ModeSpecTests {

    @Test func parsesPlainString() throws {
        let spec = try AspaceConfig.ModeSpec(string: "2560x1440")
        #expect(spec.pointWidth == 2560)
        #expect(spec.pointHeight == 1440)
    }

    @Test func parsesUppercaseAndWhitespace() throws {
        let spec = try AspaceConfig.ModeSpec(string: " 3200X1800 ")
        #expect(spec.pointWidth == 3200)
        #expect(spec.pointHeight == 1800)
    }

    @Test func rejectsMalformedStrings() {
        for bad in ["2560", "2560x", "x1440", "axb", "2560x1440x60", "0x1440", ""] {
            #expect(throws: AspaceConfig.ModeSpec.ParseError.self) {
                _ = try AspaceConfig.ModeSpec(string: bad)
            }
        }
    }

    @Test func decodesFromJSONString() throws {
        let json = #""2560x1440""#.data(using: .utf8)!
        let spec = try JSONDecoder().decode(AspaceConfig.ModeSpec.self, from: json)
        #expect(spec == AspaceConfig.ModeSpec(pointWidth: 2560, pointHeight: 1440))
    }

    @Test func encodesAsJSONString() throws {
        let spec = AspaceConfig.ModeSpec(pointWidth: 3200, pointHeight: 1800)
        let data = try JSONEncoder().encode(spec)
        #expect(String(data: data, encoding: .utf8) == #""3200x1800""#)
    }

    @Test func configRoundtripPreservesResolutions() throws {
        let original = AspaceConfig(
            profiles: ["desk": .init(disable: ["TV"], main: "STUDIO")],
            resolutions: [
                "cozy":     ["STUDIO": .init(pointWidth: 2560, pointHeight: 1440)],
                "spacious": ["STUDIO": .init(pointWidth: 3200, pointHeight: 1800)],
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AspaceConfig.self, from: data)
        #expect(decoded.resolutions["cozy"]?["STUDIO"] == .init(pointWidth: 2560, pointHeight: 1440))
        #expect(decoded.resolutions["spacious"]?["STUDIO"] == .init(pointWidth: 3200, pointHeight: 1800))
    }

    @Test func configWithoutResolutionsDecodesToEmpty() throws {
        let json = #"{ "profiles": { "desk": { "disable": ["A"] } } }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(AspaceConfig.self, from: json)
        #expect(config.resolutions.isEmpty)
    }
}
