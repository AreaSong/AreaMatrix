import Foundation

private final class ObservabilityCatalogBundleToken: NSObject {}

private struct ObservabilityCatalogVersionHeader: Decodable {
    let schemaVersion: UInt64

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
    }
}

private struct ObservabilityCatalogDocument: Decodable {
    let schemaVersion: UInt64
    let actions: [ObservabilityCatalog.Action]
    let components: [ObservabilityCatalog.Component]
    let expectedFlows: [ObservabilityCatalog.ExpectedFlow]
}

struct ObservabilityCatalog: Equatable {
    struct Action: Decodable, Equatable {
        let id: String
        let group: String
    }

    struct Component: Decodable, Equatable {
        let id: String
        let owner: String
        let role: String
        let symbol: String
        let authority: String
    }

    struct ExpectedFlowSelector: Decodable, Equatable {
        let actionGroup: String?
        let actionID: String?
        let componentID: String
        let phase: String?
    }

    struct ExpectedFlowStep: Decodable, Equatable {
        let id: String
        let required: Bool
        let matchAny: [ExpectedFlowSelector]
    }

    struct ExpectedFlow: Decodable, Equatable {
        let id: String
        let entryActionIDs: [String]
        let steps: [ExpectedFlowStep]
    }

    let schemaVersion: UInt64
    let actions: [Action]
    let components: [Component]
    let expectedFlows: [ExpectedFlow]
    private let actionIDs: Set<String>
    private let componentIDs: Set<String>

    static func loadBundled(bundle: Bundle? = nil) -> Result<Self, ObservabilityCatalogError> {
        let bundle = bundle ?? Bundle(for: ObservabilityCatalogBundleToken.self)
        guard let url = bundle.url(forResource: "observability_catalog", withExtension: "json") else {
            return .failure(.resourceMissing)
        }
        do {
            return try .success(decode(Data(contentsOf: url)))
        } catch let error as ObservabilityCatalogError {
            return .failure(error)
        } catch {
            return .failure(.invalidDocument)
        }
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let version: ObservabilityCatalogVersionHeader
        do {
            version = try decoder.decode(ObservabilityCatalogVersionHeader.self, from: data)
        } catch {
            throw ObservabilityCatalogError.invalidDocument
        }
        guard version.schemaVersion == 1 else {
            throw ObservabilityCatalogError.unsupportedSchema
        }
        let document: ObservabilityCatalogDocument
        do {
            document = try decoder.decode(ObservabilityCatalogDocument.self, from: data)
        } catch {
            throw ObservabilityCatalogError.invalidDocument
        }
        return try validated(document)
    }

    func containsAction(_ id: String) -> Bool {
        actionIDs.contains(id)
    }

    func containsComponent(_ id: String) -> Bool {
        componentIDs.contains(id)
    }

    func action(for id: String) -> Action? {
        actions.first { $0.id == id }
    }

    func group(forActionID id: String) -> String? {
        action(for: id)?.group
    }
}

enum ObservabilityCatalogError: Error, Equatable {
    case invalidDocument
    case resourceMissing
    case unsupportedSchema
}

private extension ObservabilityCatalog {
    static func validated(_ document: ObservabilityCatalogDocument) throws -> Self {
        let actionIDs = try validatedActions(document.actions)
        let componentIDs = try validatedComponents(document.components)
        let groups = Set(document.actions.map(\.group))
        try validateFlows(
            document.expectedFlows,
            actionIDs: actionIDs,
            componentIDs: componentIDs,
            actionGroups: groups
        )
        return Self(
            schemaVersion: document.schemaVersion,
            actions: document.actions,
            components: document.components,
            expectedFlows: document.expectedFlows,
            actionIDs: actionIDs,
            componentIDs: componentIDs
        )
    }

    static func validatedActions(_ actions: [Action]) throws -> Set<String> {
        let ids = actions.map(\.id)
        guard strictlySorted(ids),
              actions.allSatisfy({ validID($0.id) && validID($0.group) })
        else { throw ObservabilityCatalogError.invalidDocument }
        return Set(ids)
    }

    static func validatedComponents(_ components: [Component]) throws -> Set<String> {
        let ids = components.map(\.id)
        guard strictlySorted(ids) else { throw ObservabilityCatalogError.invalidDocument }
        for component in components {
            guard validID(component.id),
                  validID(component.owner),
                  validID(component.role),
                  component.id.hasPrefix("\(component.owner)."),
                  validSymbol(component.symbol),
                  validAuthority(component.authority)
            else { throw ObservabilityCatalogError.invalidDocument }
        }
        return Set(ids)
    }

    static func validateFlows(
        _ flows: [ExpectedFlow],
        actionIDs: Set<String>,
        componentIDs: Set<String>,
        actionGroups: Set<String>
    ) throws {
        guard strictlySorted(flows.map(\.id)) else {
            throw ObservabilityCatalogError.invalidDocument
        }
        var claimedEntryActions = Set<String>()
        for flow in flows {
            try validateFlow(
                flow,
                actionIDs: actionIDs,
                componentIDs: componentIDs,
                actionGroups: actionGroups,
                claimedEntryActions: &claimedEntryActions
            )
        }
    }

    static func validateFlow(
        _ flow: ExpectedFlow,
        actionIDs: Set<String>,
        componentIDs: Set<String>,
        actionGroups: Set<String>,
        claimedEntryActions: inout Set<String>
    ) throws {
        guard validID(flow.id),
              strictlySorted(flow.entryActionIDs),
              !flow.steps.isEmpty,
              flow.steps.contains(where: \.required)
        else { throw ObservabilityCatalogError.invalidDocument }
        for actionID in flow.entryActionIDs {
            guard actionIDs.contains(actionID), claimedEntryActions.insert(actionID).inserted else {
                throw ObservabilityCatalogError.invalidDocument
            }
        }
        var stepIDs = Set<String>()
        for step in flow.steps {
            guard validID(step.id),
                  stepIDs.insert(step.id).inserted,
                  !step.matchAny.isEmpty
            else { throw ObservabilityCatalogError.invalidDocument }
            try validateSelectors(
                step.matchAny,
                actionIDs: actionIDs,
                componentIDs: componentIDs,
                actionGroups: actionGroups
            )
        }
    }

    static func validateSelectors(
        _ selectors: [ExpectedFlowSelector],
        actionIDs: Set<String>,
        componentIDs: Set<String>,
        actionGroups: Set<String>
    ) throws {
        var identities = Set<String>()
        for selector in selectors {
            let actionIdentity: String
            switch (selector.actionID, selector.actionGroup) {
            case let (.some(actionID), .none) where actionIDs.contains(actionID):
                actionIdentity = "action:\(actionID)"
            case let (.none, .some(group)) where actionGroups.contains(group):
                actionIdentity = "group:\(group)"
            default:
                throw ObservabilityCatalogError.invalidDocument
            }
            guard componentIDs.contains(selector.componentID),
                  selector.phase.map(validID) ?? true,
                  identities.insert(
                      "\(actionIdentity)|\(selector.componentID)|\(selector.phase ?? "*")"
                  ).inserted
            else { throw ObservabilityCatalogError.invalidDocument }
        }
    }

    static func strictlySorted(_ values: [String]) -> Bool {
        !values.isEmpty && zip(values, values.dropFirst()).allSatisfy { $0.0 < $0.1 }
    }

    static func validID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 128, bytes[0].isASCIILowercase else { return false }
        var previousWasSeparator = false
        for byte in bytes {
            if byte.isASCIILowercase || byte.isASCIIDigit {
                previousWasSeparator = false
            } else if byte.isCatalogSeparator, !previousWasSeparator {
                previousWasSeparator = true
            } else {
                return false
            }
        }
        return !previousWasSeparator
    }

    static func validSymbol(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }

    static func validAuthority(_ value: String) -> Bool {
        let segments = value.split(separator: "/", omittingEmptySubsequences: false)
        return value.hasPrefix("docs/")
            && value.hasSuffix(".md")
            && value.utf8.count <= 256
            && !value.contains("\\")
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

extension ObservabilityCatalog.Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, group
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
    }
}

extension ObservabilityCatalog.Component {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, owner, role, symbol, authority
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(String.self, forKey: .owner)
        role = try container.decode(String.self, forKey: .role)
        symbol = try container.decode(String.self, forKey: .symbol)
        authority = try container.decode(String.self, forKey: .authority)
    }
}

extension ObservabilityCatalog.ExpectedFlow {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case entryActionIDs = "entry_action_ids"
        case steps
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        entryActionIDs = try container.decode([String].self, forKey: .entryActionIDs)
        steps = try container.decode([ObservabilityCatalog.ExpectedFlowStep].self, forKey: .steps)
    }
}

extension ObservabilityCatalog.ExpectedFlowStep {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, required
        case matchAny = "match_any"
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        required = try container.decode(Bool.self, forKey: .required)
        matchAny = try container.decode([ObservabilityCatalog.ExpectedFlowSelector].self, forKey: .matchAny)
    }
}

extension ObservabilityCatalog.ExpectedFlowSelector {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionGroup = "action_group"
        case actionID = "action_id"
        case componentID = "component_id"
        case phase
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionGroup = try container.decodeIfPresent(String.self, forKey: .actionGroup)
        actionID = try container.decodeIfPresent(String.self, forKey: .actionID)
        componentID = try container.decode(String.self, forKey: .componentID)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
    }
}

private extension ObservabilityCatalogDocument {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actions, components
        case expectedFlows = "expected_flows"
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.all)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(UInt64.self, forKey: .schemaVersion)
        actions = try container.decode([ObservabilityCatalog.Action].self, forKey: .actions)
        components = try container.decode([ObservabilityCatalog.Component].self, forKey: .components)
        expectedFlows = try container.decode(
            [ObservabilityCatalog.ExpectedFlow].self,
            forKey: .expectedFlows
        )
    }
}

private struct ObservabilityCatalogCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

private extension Decoder {
    func rejectUnknownKeys(allowed: Set<String>) throws {
        let container = try container(keyedBy: ObservabilityCatalogCodingKey.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Unknown observability catalog keys: \(unknown.sorted())"
            ))
        }
    }
}

private extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var all: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

private extension UInt8 {
    var isASCIILowercase: Bool {
        (97 ... 122).contains(self)
    }

    var isASCIIDigit: Bool {
        (48 ... 57).contains(self)
    }

    var isCatalogSeparator: Bool {
        self == 46 || self == 45 || self == 95
    }
}
