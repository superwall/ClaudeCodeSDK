//
//  ExecutableType.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 6/17/25.
//

import Foundation

/// Type of JavaScript runtime executable
public enum ExecutableType: String, Codable, Sendable {
  case bun = "bun"
  case deno = "deno"
  case node = "node"
}
