import Foundation

enum BundleResources {
    static func url(_ name: String, extension ext: String? = nil) -> URL? {
        if let direct = Bundle.main.url(forResource: name, withExtension: ext) { return direct }
        let filename = ext.map { "\(name).\($0)" } ?? name
        return Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first { $0.lastPathComponent == filename }
    }

    static func requiredURL(_ name: String, extension ext: String? = nil) throws -> URL {
        guard let url = url(name, extension: ext) else {
            throw ResourceError.missing(ext.map { "\(name).\($0)" } ?? name)
        }
        return url
    }

    enum ResourceError: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self { case .missing(let name): "Missing bundled resource: \(name)" }
        }
    }
}
