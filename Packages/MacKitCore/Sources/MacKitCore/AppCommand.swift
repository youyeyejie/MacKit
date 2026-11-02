import Foundation

enum AppCommand: Equatable {
    case clean

    init?(url: URL) {
        guard url.scheme?.lowercased() == "mackit", url.host?.lowercased() == "clean",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        self = .clean
    }
}
