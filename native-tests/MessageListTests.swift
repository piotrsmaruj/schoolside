import Foundation

@main
struct MessageListTests {
    static func main() {
        filtersUseUnreadAndAvailableAttachmentMetadata()
        searchCombinesWithFilterAndKeepsOriginalItems()
        selectionNeverDefaultsToFirstVisibleMessage()
        orderingUsesDateThenTimeWithStableTies()
        print("Swift messages: filters, search, attachment metadata, explicit selection and ordering passed")
    }

    static let messages = [
        SchoolItem(id: "read", title: "Spotkanie rodziców", subtitle: "Anna Nowak",
                   body: "Krótki podgląd", date: "2026-10-27", unread: false),
        SchoolItem(id: "unread", title: "Wycieczka", subtitle: "Jan Kowalski",
                   body: "Spotkanie pod szkołą", date: "2026-10-28", unread: true),
        SchoolItem(id: "flag", title: "Zgoda", date: "2026-10-26", unread: true, hasAttachments: true),
        SchoolItem(id: "files", title: "Plan", date: "2026-10-25",
                   attachments: [SchoolAttachment(id: "a", name: "Regulamin.pdf")]),
        SchoolItem(id: "false-flag", title: "Dokument", date: "2026-10-24",
                   attachments: [SchoolAttachment(id: "b", name: "Instrukcja.pdf")], hasAttachments: false),
    ]

    static func filtersUseUnreadAndAvailableAttachmentMetadata() {
        assert(SchoolMessageList(messages, filter: .unread).items.map(\.id) == ["unread", "flag"],
               "Unread filter must exclude read messages without marking visible messages read")
        assert(SchoolMessageList(messages, filter: .attachments).items.map(\.id) == ["flag", "files", "false-flag"],
               "A preview flag or known attachments must qualify, including legacy items without a flag")
        assert(SchoolMessageList(messages).items.count == 5)
    }

    static func searchCombinesWithFilterAndKeepsOriginalItems() {
        let before = messages
        assert(SchoolMessageList(messages, search: "  SPOTKANIE\n").items.map(\.id) == ["unread", "read"])
        assert(SchoolMessageList(messages, filter: .unread, search: "Nowak").items.isEmpty)
        assert(SchoolMessageList(messages, search: "NOWAK").items.map(\.id) == ["read"])
        assert(SchoolMessageList(messages, filter: .attachments, search: "regulamin").items.map(\.id) == ["files"])
        assert(SchoolMessageList(messages, search: " \n").items.count == 5)
        assert(messages == before, "Browsing and search must preserve previews and unread state")
    }

    static func selectionNeverDefaultsToFirstVisibleMessage() {
        assert(SchoolMessageList(messages).selectedID == nil,
               "Entering messages must not select or open the first message")
        assert(SchoolMessageList(messages, filter: .unread).selectedID == nil)
        assert(SchoolMessageList(messages, selectedID: "read").selectedID == "read")
        assert(SchoolMessageList(messages, filter: .unread, selectedID: "read").selectedID == nil,
               "A hidden selected message must not highlight a different visible message")
        assert(SchoolMessageList(messages, search: "missing", selectedID: "unread").selectedID == nil)
        assert(SchoolMessageList([], selectedID: "missing").selectedID == nil)
    }

    static func orderingUsesDateThenTimeWithStableTies() {
        let input = [
            SchoolItem(id: "first-tie", title: "Pierwsza", date: "2026-10-28", time: "08:00"),
            SchoolItem(id: "unknown", title: "Bez daty"),
            SchoolItem(id: "later", title: "Późniejsza", date: "2026-10-28", time: "10:00"),
            SchoolItem(id: "second-tie", title: "Druga", date: "2026-10-28", time: "08:00"),
            SchoolItem(id: "older", title: "Starsza", date: "2026-10-27", time: "12:00"),
        ]
        assert(SchoolMessageList(input).items.map(\.id) == ["later", "first-tie", "second-tie", "older", "unknown"])
    }
}
