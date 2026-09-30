import ApplicationServices

/// Thin wrappers over the Accessibility C API. AX frames use global coordinates with the origin at
/// the top-left of the primary screen and y growing downward (see `Geometry.cocoa`).
public enum AX {
    public static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    /// One round trip for several attributes; missing ones come back as nil.
    public static func multi(_ element: AXUIElement, _ attributes: [String]) -> [AnyObject?] {
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray,
                                                         AXCopyMultipleAttributeOptions(rawValue: 0), &out)
        guard err == .success, let values = out as? [AnyObject], values.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return values.map { v in
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { return nil }
            return v
        }
    }

    public static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let list = copy(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return list.compactMap(self.element)
    }

    public static func rect(_ position: AnyObject?, _ size: AnyObject?) -> CGRect? {
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    public static func setPosition(_ element: AXUIElement, _ origin: CGPoint) {
        var p = origin
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }
}

/// The attributes of one element that the toolbar probe cares about, fetched in a single call.
public struct AXNode {
    static let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                             kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
    public let element: AXUIElement
    public let role: String
    public let subrole: String
    public let frame: CGRect?
    public let text: String

    public init?(_ element: AXUIElement) {
        let v = AX.multi(element, Self.attributes)
        guard let role = v[0] as? String else { return nil }
        self.element = element
        self.role = role
        subrole = (v[1] as? String) ?? ""
        frame = AX.rect(v[2], v[3])
        text = [v[4], v[5], v[6]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
}
