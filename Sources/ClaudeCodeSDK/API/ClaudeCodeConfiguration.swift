//
//  ClaudeCodeConfiguration.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

/// Configuration for ClaudeCodeClient
public struct ClaudeCodeConfiguration {
  /// The command to execute (default: "claude")
  public var command: String
  
  /// The working directory for command execution
  public var workingDirectory: String?
  
  /// Additional environment variables
  public var environment: [String: String]
  
  /// Enable debug logging
  public var enableDebugLogging: Bool
  
  /// Additional paths to add to PATH environment variable
  public var additionalPaths: [String]
  
  /// Optional suffix to append after the command (e.g., "--" for "airchat --")
  public var commandSuffix: String?
  
  /// Default configuration
  public static var `default`: ClaudeCodeConfiguration {
    ClaudeCodeConfiguration(
      command: "claude",
      workingDirectory: nil,
      environment: [:],
      enableDebugLogging: false,
      additionalPaths: ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"],
      commandSuffix: nil
    )
  }
  
  public init(
    command: String = "claude",
    workingDirectory: String? = nil,
    environment: [String: String] = [:],
    enableDebugLogging: Bool = false,
    additionalPaths: [String] = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"],
    commandSuffix: String? = nil
  ) {
    self.command = command
    self.workingDirectory = workingDirectory
    self.environment = environment
    self.enableDebugLogging = enableDebugLogging
    self.additionalPaths = additionalPaths
    self.commandSuffix = commandSuffix
  }
}
