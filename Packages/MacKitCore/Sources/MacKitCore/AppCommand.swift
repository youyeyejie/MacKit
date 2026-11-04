import Foundation

enum AppCommand: Equatable {
    case clean, wallpaper

    init?(url: URL) {
        guard url.scheme?.lowercased() == "mackit", ["clean", "wallpaper"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        self = url.host?.lowercased() == "wallpaper" ? .wallpaper : .clean
    }
}
