import CoreText
import Foundation

enum FontRegistrar {
    private(set) static var fontName = "KFGQPCHafsSmart-Regular"
    private static var isRegistered = false
    static func register() throws {
        guard !isRegistered else { return }
        let url = try BundleResources.requiredURL("HafsSmart_08", extension: "ttf")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let font = CTFontCreateWithName("KFGQPCHafsSmart-Regular" as CFString, 18, nil)
        fontName = CTFontCopyPostScriptName(font) as String
        isRegistered = true
    }
}
