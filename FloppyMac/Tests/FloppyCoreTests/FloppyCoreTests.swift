import Foundation
import Testing
@testable import FloppyCore

@Test func approvalURLContainsExpectedParameters() throws {
    let url = FloppyAPIClient.approvalURL(siteURL: URL(string: "https://example.com")!, state: "abc", deviceName: "Studio Mac")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.absoluteString.hasPrefix("https://example.com/wp-admin/admin.php"))
    #expect(items["page"] == "floppy")
    #expect(items["floppy-device-approval"] == "1")
    #expect(items["state"] == "abc")
    #expect(items["callback"] == "floppy://device-approved")
}

@Test func applicationPasswordURLContainsExpectedParameters() throws {
    let url = FloppyAPIClient.applicationPasswordAuthorizationURL(
        siteURL: URL(string: "https://example.com")!,
        authorizationURL: URL(string: "https://example.com/wp-admin/authorize-application.php")!,
        state: "abc",
        deviceName: "Studio Mac"
    )
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.absoluteString.hasPrefix("https://example.com/wp-admin/authorize-application.php"))
    #expect(items["app_name"] == "Floppy for Mac - Studio Mac")
    #expect(items["success_url"] == "floppy://wordpress-authorized?state=abc")
    #expect(items["reject_url"] == "floppy://wordpress-rejected?state=abc")
}

@Test func parsesApplicationPasswordCallback() throws {
    let url = URL(string: "floppy://wordpress-authorized?state=abc&site_url=https%3A%2F%2Fexample.com&user_login=admin&password=abcdEFGH1234")!
    let credential = try FloppyAPIClient.parseApplicationPasswordCallback(url)

    #expect(credential.siteURL.absoluteString == "https://example.com")
    #expect(credential.userLogin == "admin")
    #expect(credential.password == "abcdEFGH1234")
    #expect(credential.state == "abc")
    #expect(credential.basicAuthorizationHeader.hasPrefix("Basic "))
}

@Test func rejectsDuplicateCallbackParameters() throws {
    let url = URL(string: "floppy://wordpress-authorized?state=abc&state=def&site_url=https%3A%2F%2Fexample.com&user_login=admin&password=abcd")!

    do {
        _ = try FloppyAPIClient.parseApplicationPasswordCallback(url)
        Issue.record("Expected duplicate state parameter to be rejected.")
    } catch FloppyAPIError.duplicateCallbackParameter(let name) {
        #expect(name == "state")
    } catch {
        Issue.record("Expected duplicate parameter error, got \(error).")
    }
}

@Test func parsesApprovalCallback() throws {
    let url = URL(string: "floppy://device-approved?site=https%3A%2F%2Fexample.com&device_uuid=dev-1&token=flp_secret&scope=files%3Aread%2Cfiles%3Awrite%2Csync&state=abc")!
    let approval = try FloppyAPIClient.parseApprovalCallback(url)

    #expect(approval.siteURL.absoluteString == "https://example.com")
    #expect(approval.deviceUUID == "dev-1")
    #expect(approval.token == "flp_secret")
    #expect(approval.scope == "files:read,files:write,sync")
    #expect(approval.state == "abc")
}

@Test func decodesItem() throws {
    let json = """
    {
      "kind": "file",
      "id": 12,
      "uuid": "file-uuid",
      "attachment_id": 44,
      "owner_id": 1,
      "parent_id": 0,
      "name": "hello.txt",
      "mime_type": "text/plain",
      "size_bytes": 5,
      "content_hash": "abc",
      "content_version": "cv",
      "metadata_version": "mv",
      "status": "active",
      "visibility": "private",
      "download_url": "https://example.com/wp-json/floppy/v1/files/12/download",
      "created_at_gmt": "2026-05-22 00:00:00",
      "updated_at_gmt": "2026-05-22 00:00:00"
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder.floppy.decode(FloppyItem.self, from: json)
    #expect(item.kind == .file)
    #expect(item.name == "hello.txt")
    #expect(item.downloadURL?.path.contains("/floppy/v1/files/12/download") == true)
}
