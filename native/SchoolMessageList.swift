import Foundation

enum SchoolMessageFilter: String, CaseIterable, Identifiable {
    case all, unread, attachments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Wszystkie"
        case .unread: "Nieprzeczytane"
        case .attachments: "Z załącznikami"
        }
    }
}

struct SchoolMessageList {
    let items: [SchoolItem]
    let selectedID: String?

    init(_ messages: [SchoolItem], filter: SchoolMessageFilter = .all,
         search: String = "", selectedID: String? = nil) {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        items = messages.enumerated().filter { _, item in
            Self.matches(item, filter: filter) && Self.matches(item, query: query)
        }.sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date > rhs.element.date }
            if lhs.element.time != rhs.element.time { return lhs.element.time > rhs.element.time }
            return lhs.offset < rhs.offset
        }.map(\.element)
        self.selectedID = items.contains { $0.id == selectedID } ? selectedID : nil
    }

    static func hasAttachments(_ item: SchoolItem) -> Bool {
        item.hasAttachments == true || !item.attachments.isEmpty
    }

    private static func matches(_ item: SchoolItem, filter: SchoolMessageFilter) -> Bool {
        switch filter {
        case .all: true
        case .unread: item.unread
        case .attachments: hasAttachments(item)
        }
    }

    private static func matches(_ item: SchoolItem, query: String) -> Bool {
        query.isEmpty || ([item.title, item.subtitle, item.body] + item.attachments.map(\.name))
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
