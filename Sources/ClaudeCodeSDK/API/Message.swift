//
//  Message.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation
import SwiftAnthropic

public struct Message: Decodable {
  public let type: String
  public let message: MessageResponse
  public let sessionId: String
}
