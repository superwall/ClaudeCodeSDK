//
//  ClaudeCodeOptions.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

// MARK: - ClaudeCodeOptions

/// Configuration options for Claude Code execution
public struct ClaudeCodeOptions {
  /// Run in non-interactive mode (--print/-p flag)
  /// This should be true for all SDK operations
  public var printMode: Bool = true
  
  /// Enable verbose logging
  public var verbose: Bool = false
  
  /// Maximum number of turns allowed (for non-interactive mode)
  public var maxTurns: Int?
  
  /// List of tools allowed for Claude to use
  public var allowedTools: [String]?
  
  /// List of tools denied for Claude to use
  public var disallowedTools: [String]?
  
  /// Tool for handling permission prompts in non-interactive mode
  public var permissionPromptTool: String?
  
  /// Custom system prompt
  public var systemPrompt: String?
  
  /// Text to append to system prompt
  public var appendSystemPrompt: String?
  
  /// Path to MCP configuration file
  public var mcpConfigPath: String?
  
  /// Working directory for file operations
  public var workingDirectory: String?
  
  public init(printMode: Bool = true) {
    self.printMode = printMode
  }
  
  /// Convert options to command line arguments
  internal func toCommandArgs() -> [String] {
    var args: [String] = []
    
    // Add print mode flag for non-interactive mode
    if printMode {
      args.append("-p")
    }
    
    if verbose {
      args.append("--verbose")
    }
    
    if let maxTurns = maxTurns {
      args.append("--max-turns")
      args.append("\(maxTurns)")
    }
    
    if let allowedTools = allowedTools, !allowedTools.isEmpty {
      args.append("--allowedTools")
      args.append(allowedTools.joined(separator: ","))
    }
    
    if let disallowedTools = disallowedTools, !disallowedTools.isEmpty {
      args.append("--disallowedTools")
      args.append(disallowedTools.joined(separator: ","))
    }
    
    if let permissionPromptTool = permissionPromptTool {
      args.append("--permission-prompt-tool")
      args.append(permissionPromptTool)
    }
    
    if let systemPrompt = systemPrompt {
      args.append("--system-prompt")
      args.append(systemPrompt)
    }
    
    if let appendSystemPrompt = appendSystemPrompt {
      args.append("--append-system-prompt")
      args.append(appendSystemPrompt)
    }
    
    if let mcpConfigPath = mcpConfigPath {
      args.append("--mcp-config")
      args.append(mcpConfigPath)
    }
    
    return args
  }
}
