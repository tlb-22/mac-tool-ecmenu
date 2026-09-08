/**
 限定原生宽度输入框的整数文本编辑行为。
 区分编辑中允许的临时文本与提交时有效的正整数。
 */

import AppKit
import Foundation

/// 使用系统数字格式化能力，并在编辑阶段只接受正整数。
final class PositiveIntegerFormatter: Formatter {
    /// 负责最终数值显示的系统格式化器。
    private let numberFormatter: NumberFormatter

    /// 构造不使用小数和分组符号的正整数格式化器。
    override init() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: ImageCompressionWidthRules.minimum)
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        numberFormatter = formatter
        super.init()
    }

    /// 不支持从归档恢复格式化器。
    required init?(coder: NSCoder) {
        nil
    }

    /// 使用系统数字格式化器生成字段显示文本。
    override func string(for obj: Any?) -> String? {
        numberFormatter.string(for: obj)
    }

    /// 在提交时把有效正整数转换为 `NSNumber`。
    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard let value = Self.positiveInteger(from: string) else {
            error?.pointee = String(
                localized: "imageCompression.validation.positiveInteger",
                defaultValue: "Enter a positive integer.",
                comment: "Input validation message for the target-width field"
            ) as NSString
            return false
        }

        obj?.pointee = NSNumber(value: value)
        return true
    }

    /// 允许暂时清空字段，其他中间输入必须已经是有效正整数。
    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard !partialString.isEmpty else {
            return true
        }
        guard Self.positiveInteger(from: partialString) != nil else {
            error?.pointee = String(
                localized: "imageCompression.validation.positiveInteger",
                defaultValue: "Enter a positive integer.",
                comment: "Input validation message for the target-width field"
            ) as NSString
            return false
        }
        return true
    }

    /// 解析只由十进制数字组成且未发生 `Int` 溢出的正整数。
    private static func positiveInteger(from string: String) -> Int? {
        guard
            !string.isEmpty,
            string.rangeOfCharacter(
                from: CharacterSet.decimalDigits.inverted
            ) == nil,
            let value = Int(string),
            ImageCompressionWidthRules.validated(value) != nil
        else {
            return nil
        }
        return value
    }
}
