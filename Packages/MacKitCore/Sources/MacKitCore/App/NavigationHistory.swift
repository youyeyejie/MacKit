struct NavigationHistory<Page: Equatable> {
    private(set) var current: Page
    private var previous: [Page] = []
    private var upcoming: [Page] = []
    var canGoBack: Bool { !previous.isEmpty }
    var canGoForward: Bool { !upcoming.isEmpty }
    init(current: Page) { self.current = current }
    mutating func visit(_ page: Page) {
        guard page != current else { return }
        previous.append(current)
        if previous.count > 100 { previous.removeFirst() }
        current = page
        upcoming.removeAll()
    }
    mutating func back() -> Page? {
        guard let page = previous.popLast() else { return nil }
        upcoming.append(current)
        current = page
        return page
    }
    mutating func forward() -> Page? {
        guard let page = upcoming.popLast() else { return nil }
        previous.append(current)
        current = page
        return page
    }
}
