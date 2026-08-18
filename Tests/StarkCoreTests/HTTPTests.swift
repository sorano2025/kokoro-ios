import Foundation
import Testing
@testable import StarkCore

@Test func parsesRequestLineHeadersAndBody() throws {
  let raw = "POST /api/products?dry=1 HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer abc\r\nContent-Length: 13\r\n\r\n{\"name\":\"x\"}!"
  let parsed = try #require(HTTPRequest.parse(Data(raw.utf8)))
  #expect(parsed.request.method == "POST")
  #expect(parsed.request.path == "/api/products")
  #expect(parsed.request.query["dry"] == "1")
  #expect(parsed.request.header("authorization") == "Bearer abc")
  #expect(parsed.request.body.count == 13)
}

@Test func returnsNilWhileBodyIsIncomplete() {
  let raw = "POST /x HTTP/1.1\r\nContent-Length: 40\r\n\r\nshort"
  #expect(HTTPRequest.parse(Data(raw.utf8)) == nil)
}

@Test func routerMatchesParametersAndReportsMethodMismatch() async {
  var router = Router()
  router.add("POST", "/api/queue/:id/approve") { _, parameters in
    .text(parameters["id"] ?? "none")
  }
  let matched = await router.handle(HTTPRequest(method: "POST", path: "/api/queue/abc123/approve"))
  guard case .data(let body) = matched.body else { Issue.record("expected data body"); return }
  #expect(String(decoding: body, as: UTF8.self) == "abc123")

  let wrongMethod = await router.handle(HTTPRequest(method: "GET", path: "/api/queue/abc123/approve"))
  #expect(wrongMethod.status == 405)

  let missing = await router.handle(HTTPRequest(method: "GET", path: "/nope"))
  #expect(missing.status == 404)
}

@Test func jsonPathReadsNestedValuesAndEscapes() {
  let object = try! JSONSerialization.jsonObject(with: Data(#"{"data":{"items":[{"id":7,"who":{"name":"ada"}}]}}"#.utf8))
  #expect(JSONPath.string(at: "data.items.0.id", in: object) == "7")
  #expect(JSONPath.string(at: "data.items.0.who.name", in: object) == "ada")
  #expect(JSONPath.string(at: "data.missing.name", in: object) == nil)
  #expect(JSONPath.escape("say \"hi\"\n") == #"say \"hi\"\n"#)
}

@Test func stripsMastodonHTML() {
  let html = "<p>hey <a href=\"https://x\">link</a><br>second &amp; line</p>"
  #expect(MastodonConnector.plainText(fromHTML: html) == "hey link\nsecond & line")
}
