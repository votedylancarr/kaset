import CoreGraphics
import Foundation
import Testing
@testable import Kaset

struct StoryboardSeekPreviewTests {
    /// Four levels, like a real watch-page spec: 48, 80, 160 and 320 px wide.
    private static let spec = [
        "https://i.ytimg.com/sb/vid/storyboard3_L$L/$N.jpg?sqp=test",
        "48#27#100#10#10#0#default#rsREDACTED",
        "80#45#244#10#10#10000#M$M#rsREDACTED",
        "160#90#244#5#5#10000#M$M#rsREDACTED",
        "320#180#244#3#3#10000#M$M#rsREDACTED",
    ].joined(separator: "|")

    @Test("The preview uses the smallest level that is at least 160 px wide")
    func previewLevelPrefersSharpButLight() {
        #expect(StoryboardSheet.previewLevel(in: Self.spec) == 2)
    }

    @Test("A spec with only small levels falls back to the largest one")
    func previewLevelFallsBackToLargest() {
        let spec = "https://i.ytimg.com/sb/v/L$L/$N.jpg|48#27#100#10#10#0#default#s|80#45#100#10#10#0#M$M#s"
        #expect(StoryboardSheet.previewLevel(in: spec) == 1)
    }

    @Test("A spec without levels has no preview level")
    func previewLevelNilWithoutLevels() {
        #expect(StoryboardSheet.previewLevel(in: "https://i.ytimg.com/sb/v") == nil)
    }

    @Test("Frames follow the level's interval when it has one")
    func frameIndexUsesInterval() throws {
        let sheet = try #require(StoryboardSheet(spec: Self.spec, level: 2, maxSheets: 60))

        #expect(sheet.frameIndex(atFraction: 0.5, duration: 600) == 30)
        #expect(sheet.frameIndex(atFraction: 0, duration: 600) == 0)
        #expect(sheet.frameIndex(atFraction: 1, duration: 600) == 60)
        // Never past the last frame, however long the reported duration.
        #expect(sheet.frameIndex(atFraction: 1, duration: 5000) == 243)
    }

    @Test("Level 0 spreads its frames evenly over the whole video")
    func frameIndexSpreadsEvenlyWithoutInterval() throws {
        let sheet = try #require(StoryboardSheet(spec: Self.spec, level: 0))

        #expect(sheet.frameIndex(atFraction: 0.5, duration: 600) == 50)
        #expect(sheet.frameIndex(atFraction: 1, duration: 600) == 99)
    }

    @Test("Out-of-range and non-finite positions stay inside the sheet")
    func frameIndexClamps() throws {
        let sheet = try #require(StoryboardSheet(spec: Self.spec, level: 2, maxSheets: 60))

        #expect(sheet.frameIndex(atFraction: -3, duration: 600) == 0)
        #expect(sheet.frameIndex(atFraction: 9, duration: 600) == 60)
        #expect(sheet.frameIndex(atFraction: .nan, duration: 600) == 0)
    }

    @Test("A frame maps to its sheet and crop rect from the fetched sheet's size")
    func locationOfFrame() throws {
        let sheet = try #require(StoryboardSheet(spec: Self.spec, level: 2, maxSheets: 60))
        // 5×5 grid of 160×90 cells → an 800×450 sheet; frame 30 is cell 5 of sheet 1.
        let located = try #require(sheet.location(ofFrame: 30, pixelWidth: 800, height: 450))

        #expect(located.sheet == 1)
        #expect(located.rect == CGRect(x: 0, y: 90, width: 160, height: 90))
        #expect(sheet.sheetIndex(ofFrame: 30) == 1)
        #expect(sheet.location(ofFrame: 244, pixelWidth: 800, height: 450) == nil)
        #expect(sheet.location(ofFrame: -1, pixelWidth: 800, height: 450) == nil)
    }

    @Test("Sheet URLs are limited to YouTube image hosts")
    func rejectsForeignHosts() {
        let spec = "https://example.com/sb/$L/$N.jpg|160#90#25#5#5#10000#M$M#s"
        #expect(StoryboardSheet(spec: spec, level: 0) == nil)
    }

    @Test("Ambient color sampling still reads level 0")
    func defaultLevelIsZero() throws {
        let sheet = try #require(StoryboardSheet(spec: Self.spec))

        #expect(sheet.frameCount == 100)
        #expect(sheet.intervalMilliseconds == 0)
    }
}
