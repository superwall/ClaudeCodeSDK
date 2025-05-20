//
//  ClaudeCodeError.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

public enum ClaudeCodeError: Error {
  case executionFailed(String)
  case invalidOutput(String)
  case jsonParsingError(Error)
  case cancelled
  case notInstalled
  
  var localizedDescription: String {
    switch self {
    case .notInstalled:
      return "Claude Code is not installed. Please install with 'npm install -g @anthropic/claude-code'"
    case .executionFailed(let message):
      return "Execution failed: \(message)"
    case .invalidOutput(let message):
      return "Invalid output: \(message)"
    case .jsonParsingError(let error):
      return "JSON parsing error: \(error.localizedDescription)"
    case .cancelled:
      return "Operation cancelled"
    }
  }
}
