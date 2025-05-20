//
//  ChatMessage.swift
//  ClaudeCodeSDKExample
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

public struct ChatMessage: Identifiable, Equatable {
  public var id: UUID
  public var role: MessageRole
  public var content: String
  public var timestamp: Date
  public var isComplete: Bool
  
  public init(
    id: UUID = UUID(),
    role: MessageRole,
    content: String,
    timestamp: Date = Date(),
    isComplete: Bool = true
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.timestamp = timestamp
    self.isComplete = isComplete
  }
  
  public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
    return lhs.content == rhs.content && lhs.id == rhs.id && lhs.isComplete == rhs.isComplete
  }
}

/// Message role types
public enum MessageRole: String {
  case user
  case assistant
  case system
}
