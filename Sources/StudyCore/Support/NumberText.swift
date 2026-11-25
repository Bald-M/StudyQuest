import Foundation

/// 把 Double 显示成文本。直接 `Int(x)` 在数值越界或非有限时会崩溃（过关线、满分都可能被外部改成任意数），一律走这里。
public enum NumberText {
    /// 四舍五入成整数文本；越界或非有限时原样输出。
    public static func whole(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(rounded) < 1e15 ? String(Int(rounded)) : String(value)
    }

    /// 分数：整数不带小数，否则保留一位小数。
    public static func score(_ value: Double) -> String {
        value == value.rounded() ? whole(value) : String(format: "%.1f", value)
    }
}
