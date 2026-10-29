import Foundation

public enum FeatureID: String, CaseIterable, Sendable {
    case cleaning, finderCut, windowSwitcher, dockEnhancement
}

@MainActor
public protocol FeatureModule: AnyObject {
    var id: FeatureID { get }
    func stop()
}
