#if os(macOS)
@testable import ScoutCore
import ScoutProtocol
import Testing

struct MacMemoryReaderTests {
    @Test("Memory in use is Activity Monitor's Memory Used, and cache its Cached Files")
    func captured() {
        // Arrange: a 16 GB Mac with 16 KB pages, as `vm_stat` showed it, with 4.7 GB of swap used of 6.
        let counts = MacMemoryCounts(
            pageSize: 16_384,
            totalBytes: 17_179_869_184,
            wiredPages: 164_690,
            compressedPages: 258_538,
            internalPages: 311_827,
            externalPages: 244_252,
            purgeablePages: 3_990,
            swapIns: 0,
            swapOuts: 0,
            swapTotalBytes: 6_442_450_944,
            swapUsedBytes: 5_035_130_880
        )

        // Act
        let figures = counts.figures(swapping: nil)

        // Assert: App Memory (311,827 less 3,990 purgeable), Wired and Compressed make 731,065 pages in
        // use. Cached Files are the file pages and the purgeable ones, 248,242 pages.
        #expect(figures.totalBytes == 17_179_869_184)
        #expect(figures.availableBytes == 17_179_869_184 - 731_065 * 16_384)
        #expect(figures.cacheBytes == 248_242 * 16_384)
        #expect(figures.swapTotalBytes == 6_442_450_944)
        #expect(figures.swapUsedBytes == 5_035_130_880)
    }
}
#endif
