import Foundation

@main
struct ProbeModelsTests {
    static func main() throws {
        assert(LoginInput.isValid(login: " 1234567 ", password: "🙂 '$\\"))
        for login in ["", "123u", "１２３", "123 45", "abc"] {
            assert(!LoginInput.isValid(login: login, password: "secret"))
        }
        assert(!LoginInput.isValid(login: "123", password: ""))

        let input = LoginInput(login: " 12345 ", password: " żółć '$`\\\n🙂 ")
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(LoginInput.self, from: encoded)
        assert(decoded.login == "12345")
        assert(decoded.password == " żółć '$`\\\n🙂 ")

        let raw = #"{"protocol_version":1,"authenticated":true,"session_reused":true,"modules":[{"id":"grades","status":"available","count":3}]}"#
        let report = try JSONDecoder().decode(ProbeReport.self, from: Data(raw.utf8))
        assert(report.authenticated)
        assert(report.sessionReused == true)
        assert(report.modules.first?.count == 3)
        assert(!report.hasIssues)

        for invalid in [
            #"{"protocol_version":2,"authenticated":true,"modules":[]}"#,
            #"{"protocol_version":1,"authenticated":true,"modules":[{"id":"grades","status":"available","count":-1}]}"#,
            #"{"protocol_version":1,"authenticated":true,"modules":[{"id":"grades","status":"unknown"}]}"#,
            #"{"protocol_version":1,"authenticated":true,"modules":[{"id":"grades","status":"available"}]}"#
        ] {
            do {
                _ = try JSONDecoder().decode(ProbeReport.self, from: Data(invalid.utf8))
                fatalError("Malformed report accepted")
            } catch is DecodingError {
                // Expected: incompatible or invalid payloads cannot become successful results.
            }
        }
        assert(ProbeCopy.error("private secret token") == ProbeCopy.error("internal_error"))
        print("Swift: input, secret transport and report validation passed")
    }
}
