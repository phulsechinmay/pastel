import Foundation

@main
struct TextWorkBudgetSmoke {
    static func main() {
        let huge = String(repeating: "func process(input_value: Int) { return input_value }\n", count: 200_000)
        let originalBytes = huge.utf8.count
        let start = ContinuousClock.now
        let preview = TextWorkBudget.cardPreview(huge)
        let sample = TextWorkBudget.codeSample(huge)
        let elapsed = start.duration(to: .now)

        precondition(preview.utf8.count <= TextWorkBudget.cardPreviewBytes)
        precondition(preview.split(separator: "\n", omittingEmptySubsequences: false).count <= TextWorkBudget.cardPreviewLines)
        precondition(sample.utf8.count <= TextWorkBudget.codeSampleBytes)
        precondition(sample.split(separator: "\n", omittingEmptySubsequences: false).count <= TextWorkBudget.codeSampleLines)
        precondition(huge.utf8.count == originalBytes)
        precondition(huge.hasPrefix(preview))

        let unicode = "ab😀é文c"
        precondition(TextWorkBudget.prefix(unicode, maxUTF8Bytes: 5, maxLines: 10) == "ab")
        precondition(TextWorkBudget.prefix(unicode, maxUTF8Bytes: 6, maxLines: 10) == "ab😀")
        precondition(TextWorkBudget.prefix("one\ntwo\nthree", maxUTF8Bytes: 100, maxLines: 2) == "one\ntwo")
        precondition(TextWorkBudget.prefix("anything", maxUTF8Bytes: 0, maxLines: 10).isEmpty)

        print("Processed \(originalBytes) input bytes into \(preview.utf8.count) preview bytes and \(sample.utf8.count) sample bytes in \(elapsed)")
    }
}
