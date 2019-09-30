//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import XCTest
@testable import BerkananSDK

final class BerkananSDKTests: XCTestCase {
  
  func testPublicBroadcastMessagePDU() {
    _testPublicBroadcastMessagePDU(
      with: "Hello, World!",
      expectedData: Data(base64Encoded: "4xJILZRewxHlHrTCXfXdlqed5wT4pSS4BKbp3jB7WOM5Ze81T6MvB50ShVi88jPylHg9UnNy8nUUwvOLclIUAQ==")!
    )
    _testPublicBroadcastMessagePDU(
      with: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
      expectedData: Data(base64Encoded: "NZC9ThVAEIULLQyNN1ZEmxMSOrwFBQ9ANARDZWJjN+7OvUyyf3d3hlD4AvTEZ7CwpKXwBSyNrYWtFQ/ALBe6nZ2ZM+d8OwvevPnx4vPJx+8n+/9v/l39Wrx8vbuz+Pb2z9Hfr6fXt79PD+9+HtOr5x/qedm7fXZWO2dIG5YRa6odQxSUWQ8QahkclNU6KEqTEaSswUm8OTj6Alhs5BqhnJsvSwkSJVpRmCLRF5cH61aakWldCJRkY7TEJwUXya6NLPNx4SXlA2xMBkod2i2CL7kHUVKpBZYS5VC3ynNIhsxLD5LSfBhMbjy7p7oN4Kd0iXdTkkwZ0s2dbLNKQefW+ZxL5O7B/eOiJmt+jt2OJwWPwQiS0hMhD2RY2VpIUaYhNOpeWF/i/WXgpmwTozOoIRAHnwvWJJLODU/RepXIZVKcpPxosNRo5kZdrSQIIfLgPru5pmmDJiBxHOORq+XlPQ==")!
    )
  }
  
  private func _testPublicBroadcastMessagePDU(
    with text: String,
    expectedData: Data
  ) {
    do {
      let user = User.with {
        $0.uuid = UUID(uuidString: "962DD836-E17C-4994-BDD6-4932F4C14261")
        $0.name = "John"
      }
      let message = PublicBroadcastMessage.with {
        $0.uuid = UUID(uuidString: "65711BAC-085A-4752-A847-25EEB4E589CE")
        $0.timeToLive = 15
        $0.sourceUser = user
        $0.text = text
      }
      let pdu = try message.pdu()
      XCTAssertEqual(pdu, expectedData)
    } catch {
      XCTFail(error.localizedDescription)
    }
  }
  
  static var allTests = [
    ("testPublicBroadcastMessagePDU", testPublicBroadcastMessagePDU),
  ]
}
