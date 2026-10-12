import Foundation
import Testing
@testable import Genesis

struct AuthUserTests {
    @Test func sessionsSavedBeforeProvidersStillDecode() throws {
        let saved = Data(#"{"id":"AAAAAAAA-0000-0000-0000-000000000001","email":"a@b.co"}"#.utf8)
        let user = try JSONDecoder().decode(AuthUser.self, from: saved)
        #expect(user.providers == nil)
        #expect(!user.usesSignInWithApple)
    }

    @Test func knowsAnAppleAccount() throws {
        let id = UUID()
        let apple = AuthUser(id: id, email: nil, providers: ["email", "apple"])
        let email = AuthUser(id: id, email: "a@b.co", providers: ["email"])
        #expect(apple.usesSignInWithApple)
        #expect(!email.usesSignInWithApple)

        let data = try JSONEncoder().encode(apple)
        let decoded = try JSONDecoder().decode(AuthUser.self, from: data)
        #expect(decoded == apple)
    }
}
