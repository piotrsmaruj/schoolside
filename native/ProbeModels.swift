import Foundation

struct LoginInput: Codable, Sendable {
    let login: String
    let password: String

    init(login: String, password: String) {
        self.login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    static func isValid(login: String, password: String) -> Bool {
        let value = login.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !password.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

enum ModuleStatus: String, Decodable, Sendable {
    case available, empty, unavailable, error
    case notChecked = "not_checked"
}

struct ModuleCheck: Decodable, Identifiable, Sendable {
    let id: String
    let status: ModuleStatus
    let count: Int?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case id, status, count
        case errorCode = "error_code"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        status = try values.decode(ModuleStatus.self, forKey: .status)
        count = try values.decodeIfPresent(Int.self, forKey: .count)
        errorCode = try values.decodeIfPresent(String.self, forKey: .errorCode)
        let hasData = status == .available || status == .empty
        if (count ?? 0) < 0 || (hasData && count == nil) {
            throw DecodingError.dataCorruptedError(forKey: .count, in: values,
                                                   debugDescription: "Invalid record count")
        }
    }

    var title: String {
        switch id {
        case "timetable": "Plan lekcji · bieżący tydzień"
        case "grades": "Oceny"
        case "messages": "Wiadomości · próbka ostatnich wpisów"
        case "agenda": "Terminarz"
        case "attendance": "Frekwencja"
        case "announcements": "Ogłoszenia"
        case "homework": "Zadania domowe"
        default: "Moduł"
        }
    }

    var detail: String {
        switch status {
        case .available: "Dostępny · wpisów: \(count ?? 0)"
        case .empty: "Dostępny · brak wpisów"
        case .unavailable: "Brak dostępu lub moduł jeszcze nieudostępniony"
        case .notChecked: "Nie sprawdzono"
        case .error: ProbeCopy.error(errorCode)
        }
    }
}

struct ProbeReport: Decodable, Sendable {
    let authenticated: Bool
    let sessionReused: Bool?
    let sessionErrorCode: String?
    let errorCode: String?
    let modules: [ModuleCheck]
    let diagnosticCode: String?

    enum CodingKeys: String, CodingKey {
        case authenticated, modules
        case protocolVersion = "protocol_version"
        case sessionReused = "session_reused"
        case sessionErrorCode = "session_error_code"
        case errorCode = "error_code"
        case diagnosticCode = "diagnostic_code"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .protocolVersion) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .protocolVersion, in: values,
                                                   debugDescription: "Incompatible protocol")
        }
        authenticated = try values.decode(Bool.self, forKey: .authenticated)
        sessionReused = try values.decodeIfPresent(Bool.self, forKey: .sessionReused)
        sessionErrorCode = try values.decodeIfPresent(String.self, forKey: .sessionErrorCode)
        errorCode = try values.decodeIfPresent(String.self, forKey: .errorCode)
        diagnosticCode = try values.decodeIfPresent(String.self, forKey: .diagnosticCode)
        modules = try values.decode([ModuleCheck].self, forKey: .modules)
    }

    var hasIssues: Bool {
        errorCode != nil || sessionReused == false || modules.contains {
            $0.status == .error || $0.status == .unavailable
        }
    }
}

enum ProbeCopy {
    static func diagnostic(_ code: String?) -> String? {
        switch code {
        case "login.redirect_missing": "Etap logowania: Librus nie zwrócił przekierowania."
        case "login.response_not_json": "Etap logowania: formularz odpowiedział w innym formacie."
        case "login.redirect_limit": "Etap logowania: przekroczono limit przekierowań."
        case "login.cookie_missing": "Etap logowania: Librus nie utworzył sesji."
        case "identity.missing": "Etap profilu: odpowiedź ma nierozpoznany format."
        default: nil
        }
    }

    static func error(_ code: String?) -> String {
        switch code {
        case "invalid_input": "Wpisz numeryczny login rodzica i hasło."
        case "auth_failed": "Librus odrzucił login lub hasło. Sprawdź dane."
        case "captcha_required": "Librus wymaga CAPTCHA. Zaloguj się najpierw przez jego stronę."
        case "account_action_required": "Dokończ wymagane czynności na stronie Librusa."
        case "session_expired": "Librus odrzucił sesję. Spróbuj ponownie później."
        case "connection_error": "Nie udało się połączyć z Librusem. Sprawdź połączenie z internetem."
        case "rate_limited": "Librus ograniczył liczbę zapytań. Odczekaj przed kolejną próbą."
        case "maintenance": "Librus ma przerwę techniczną. Spróbuj później."
        case "invalid_response": "Librus zwrócił nierozpoznaną odpowiedź."
        case "access_denied": "Konto nie ma dostępu do tego modułu."
        case "timed_out": "Librus odpowiada zbyt długo. Spróbuj później."
        default: "Test nie mógł zostać ukończony."
        }
    }
}
