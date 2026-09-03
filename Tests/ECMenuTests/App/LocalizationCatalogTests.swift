import Foundation
import XCTest
@testable import ECMenu

/// 验证两个产品 Bundle 的本地化资源完整且共享命令文案一致。
final class LocalizationCatalogTests: XCTestCase {
    private let requiredLanguages = ["en", "zh-Hans"]

    /// 每个产品文案必须同时提供英文源文案和简体中文翻译。
    func testEveryProductStringHasBothSupportedLanguages() throws {
        for catalogURL in catalogURLs {
            let catalog = try loadCatalog(at: catalogURL)
            XCTAssertEqual(catalog.sourceLanguage, "en", catalogURL.path)
            XCTAssertFalse(catalog.strings.isEmpty, catalogURL.path)

            for (key, entry) in catalog.strings {
                for language in requiredLanguages {
                    let unit = try XCTUnwrap(
                        entry.localizations[language]?.stringUnit,
                        "\(catalogURL.lastPathComponent): \(key) lacks \(language)"
                    )
                    XCTAssertEqual(unit.state, "translated", key)
                    XCTAssertFalse(
                        unit.value.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty,
                        "\(catalogURL.lastPathComponent): \(key) is empty in \(language)"
                    )
                }
            }
        }
    }

    /// 两个 Bundle 重复携带的七个命令名称必须保持完全一致。
    func testCommandTranslationsMatchAcrossProductBundles() throws {
        let applicationCatalog = try loadCatalog(at: catalogURLs[0])
        let extensionCatalog = try loadCatalog(at: catalogURLs[1])
        let commandKeys = [
            "command.newTextFile",
            "command.copyPath",
            "command.hideItems",
            "command.showItems",
            "command.compressImages",
            "command.openInVisualStudioCode",
            "command.openInITerm2",
        ]

        for key in commandKeys {
            XCTAssertEqual(
                applicationCatalog.strings[key]?.localizations,
                extensionCatalog.strings[key]?.localizations,
                key
            )
        }
    }

    /// 主应用产物必须实际编译并携带两种语言，而不只保留源 Catalog。
    @MainActor
    func testApplicationBundleContainsBothSupportedLanguages() {
        let applicationBundle = Bundle(for: AppDelegate.self)

        for language in requiredLanguages {
            XCTAssertNotNil(
                applicationBundle.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                ),
                language
            )
        }
    }

    /// 从测试源码位置稳定定位仓库中的两个产品 Catalog。
    private var catalogURLs: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return [
            root.appendingPathComponent("ECMenu/Localizable.xcstrings"),
            root.appendingPathComponent(
                "ECMenuFinderExtension/Localizable.xcstrings"
            ),
        ]
    }

    private func loadCatalog(at url: URL) throws -> StringCatalog {
        try JSONDecoder().decode(
            StringCatalog.self,
            from: Data(contentsOf: url)
        )
    }
}

private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringCatalogLocalization]
}

private struct StringCatalogLocalization: Decodable, Equatable {
    let stringUnit: StringCatalogUnit
}

private struct StringCatalogUnit: Decodable, Equatable {
    let state: String
    let value: String
}
