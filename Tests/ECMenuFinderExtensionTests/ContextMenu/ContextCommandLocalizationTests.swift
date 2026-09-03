import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证 Finder Extension 产物中的命令名称中英文资源。
@MainActor
final class ContextCommandLocalizationTests: XCTestCase {
    /// 七个共享 descriptor 必须能在 Extension bundle 内解析为两种产品文案。
    func testCommandTitlesInEnglishAndSimplifiedChinese() {
        let bundle = Bundle(for: FinderSync.self)
        let expectations: [(
            resource: LocalizedStringResource,
            english: String,
            simplifiedChinese: String
        )] = [
            (
                CreateNewTextFileCommand.descriptor.title,
                "New TXT File",
                "新建 TXT"
            ),
            (CopyPathCommand.descriptor.title, "Copy Path", "拷贝路径"),
            (HideItemsCommand.descriptor.title, "Hide Items", "隐藏项目"),
            (ShowItemsCommand.descriptor.title, "Show Items", "显示项目"),
            (
                CompressImagesCommand.descriptor.title,
                "Compress Images",
                "压缩图片"
            ),
            (
                OpenInVSCodeCommand.descriptor.title,
                "Open in Visual Studio Code",
                "进入 Visual Studio Code"
            ),
            (
                OpenInITerm2Command.descriptor.title,
                "Open in iTerm2",
                "进入 iTerm2"
            ),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                localized(
                    expectation.resource,
                    in: bundle,
                    language: Locale.Language(languageCode: "en")
                ),
                expectation.english
            )
            XCTAssertEqual(
                localized(
                    expectation.resource,
                    in: bundle,
                    language: Locale.Language(
                        languageCode: "zh",
                        script: "Hans"
                    )
                ),
                expectation.simplifiedChinese
            )
        }
    }

    /// 使用指定产物 bundle 和语言解析 descriptor 携带的资源键。
    private func localized(
        _ resource: LocalizedStringResource,
        in bundle: Bundle,
        language: Locale.Language
    ) -> String {
        bundle.localizedString(
            forKey: resource.key,
            value: nil,
            table: resource.table,
            localizations: [language]
        )
    }
}
