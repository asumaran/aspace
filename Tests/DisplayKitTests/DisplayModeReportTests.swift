import Foundation
import Testing
@testable import DisplayKit

@Suite struct DisplayModeReportTests {

    private func mode(_ pw: Int, _ ph: Int, px: Int, py: Int, hz: Double = 60) -> DisplayMode {
        DisplayMode(pointWidth: pw, pointHeight: ph, pixelWidth: px, pixelHeight: py, refreshHz: hz, isSafe: true)
    }

    @Test func sortsByPointSizeDescending() {
        let sorted = DisplayModeReport.sorted([
            mode(1920, 1080, px: 3840, py: 2160),
            mode(3200, 1800, px: 6400, py: 3600),
            mode(2560, 1440, px: 5120, py: 2880),
        ])
        #expect(sorted.map { $0.pointWidth } == [3200, 2560, 1920])
    }

    @Test func hiDPIVariantSortsAboveOneToOneTwin() {
        let oneToOne = mode(2560, 1440, px: 2560, py: 1440)
        let hidpi    = mode(2560, 1440, px: 5120, py: 2880)
        let sorted = DisplayModeReport.sorted([oneToOne, hidpi])
        #expect(sorted.first == hidpi)
    }

    @Test func higherRefreshSortsFirstWhenSizesTie() {
        let hz30 = mode(2560, 1440, px: 5120, py: 2880, hz: 30)
        let hz60 = mode(2560, 1440, px: 5120, py: 2880, hz: 60)
        let sorted = DisplayModeReport.sorted([hz30, hz60])
        #expect(sorted.first == hz60)
    }

    @Test func emptyInputYieldsEmptyOutput() {
        #expect(DisplayModeReport.sorted([]).isEmpty)
    }
}
