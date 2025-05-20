//
//  SessionInfo.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

/// Information about a Claude Code session
public struct SessionInfo: Codable {
  public let sessionId: String
  public let createdAt: Date
  public let lastUpdatedAt: Date
  public let title: String?
}
