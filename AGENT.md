# Claude Code SDK Agent Migration Guide

This document provides a comprehensive guide for migrating between versions of the Claude Code SDK for Swift. It is formatted to be easily parsed by LLMs while remaining human-readable.

## Version History & Migration Instructions

### Version: Post-Improvements (June 18, 2025) - Commit: a8abf5a

<migration-guide version="post-improvements" date="2025-06-18" commit="a8abf5a">

<summary>
Major improvements to SDK functionality including enhanced error handling, MCP support, rate limiting, and retry policies.
</summary>

<breaking-changes>
  <change category="options-structure">
    <before>
      ```swift
      let options = ClaudeCodeOptions(printMode: true)
      options.maxTurns = 5
      ```
    </before>
    <after>
      ```swift
      let options = ClaudeCodeOptions()  // printMode is now internal
      options.maxTurns = 5
      ```
    </after>
    <reason>printMode is now managed internally and always set to true for SDK operations</reason>
  </change>
</breaking-changes>

<new-features>
  <feature name="MCP-Server-Support">
    <description>Added full Model Context Protocol (MCP) server support</description>
    <usage>
      ```swift
      // Configure MCP servers programmatically
      options.mcpServers = [
          "XcodeBuildMCP": .stdio(McpStdioServerConfig(
              command: "npx",
              args: ["-y", "xcodebuildmcp@latest"]
          )),
          "filesystem": .stdio(McpStdioServerConfig(
              command: "npx",
              args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/projects"],
              env: ["ALLOWED_PATHS": "/Users/me/projects"]
          ))
      ]
      
      // Alternative: File-based configuration
      options.mcpConfigPath = "/path/to/mcp-config.json"
      ```
    </usage>
  </feature>

  <feature name="Enhanced-Error-Handling">
    <description>Comprehensive error handling with detailed error types and recovery options</description>
    <usage>
      ```swift
      do {
          let result = try await client.runSinglePrompt(prompt: "Create API")
      } catch let error as ClaudeCodeError {
          if error.isRetryable {
              // Error can be retried
              if let delay = error.suggestedRetryDelay {
                  // Wait and retry
                  print("Retrying after \(delay) seconds")
              }
          } else if error.isRateLimitError {
              print("Rate limited")
          } else if error.isTimeoutError {
              print("Request timed out")
          } else if error.isPermissionError {
              print("Permission denied")
          }
          
          // Access specific error types
          switch error {
          case .rateLimitExceeded(let retryAfter):
              print("Rate limited. Retry after: \(retryAfter ?? Date())")
          case .timeout:
              print("Operation timed out")
          case .networkError(let underlyingError):
              print("Network error: \(underlyingError)")
          default:
              print("Other error: \(error)")
          }
      }
      ```
    </usage>
  </feature>

  <feature name="Abort-Controller">
    <description>Added support for cancelling operations</description>
    <usage>
      ```swift
      let abortController = AbortController()
      options.abortController = abortController
      
      // Later, to cancel:
      abortController.abort()
      ```
    </usage>
  </feature>

  <feature name="Additional-CLI-Options">
    <description>New options for enhanced control</description>
    <additions>
      <option name="timeout" type="TimeInterval">
        <description>Custom timeout for command execution (Swift SDK enhancement)</description>
        <example>options.timeout = 300 // 5 minutes</example>
      </option>
      
      <option name="verbose" type="Bool">
        <description>Enable verbose logging (CLI option)</description>
        <example>options.verbose = true</example>
      </option>
      
      <option name="permissionPromptToolName" type="String">
        <description>Tool for handling permission prompts in non-interactive mode</description>
        <example>options.permissionPromptToolName = "mcp__auth__prompt"</example>
      </option>
      
      <option name="continue" type="Bool">
        <description>Continue the most recent conversation</description>
        <example>options.continue = true</example>
      </option>
      
      <option name="resume" type="String">
        <description>Resume a conversation by session ID</description>
        <example>options.resume = "550e8400-e29b-41d4-a716-446655440000"</example>
      </option>
    </additions>
  </feature>

  <feature name="Rate-Limiting">
    <description>Rate limiting support via wrapper class</description>
    <usage>
      ```swift
      // Create a rate-limited client
      let rateLimitedClient = RateLimitedClaudeCode(
          wrapped: client,
          requestsPerMinute: 10,
          burstCapacity: 3 // Allow 3 requests in burst
      )
      
      // All requests are automatically rate-limited
      let result = try await rateLimitedClient.runSinglePrompt(
          prompt: "Task",
          outputFormat: .json,
          options: nil
      )
      ```
    </usage>
  </feature>
  
  <feature name="Retry-Logic">
    <description>Built-in retry support with exponential backoff via extension methods</description>
    <usage>
      ```swift
      // Simple retry with default policy
      let result = try await client.runSinglePromptWithRetry(
          prompt: "Generate code",
          outputFormat: .json,
          retryPolicy: .default // 3 attempts with exponential backoff
      )
      
      // Custom retry policy
      let conservativePolicy = RetryPolicy(
          maxAttempts: 5,
          initialDelay: 5.0,
          maxDelay: 300.0,
          backoffMultiplier: 2.0,
          useJitter: true
      )
      
      let result = try await client.runSinglePromptWithRetry(
          prompt: "Complex analysis",
          outputFormat: .json,
          retryPolicy: conservativePolicy
      )
      ```
    </usage>
  </feature>

  <feature name="Session-Management">
    <description>Enhanced session tracking and continuation</description>
    <usage>
      ```swift
      // Resume a previous session
      let result = try await client.runStreamingPrompt(
          prompt: "Continue working on the API",
          options: options
      ) { message in
          if let sessionId = message.sessionId {
              // Save for later resumption
              UserDefaults.standard.set(sessionId, forKey: "lastSession")
          }
      }
      ```
    </usage>
  </feature>
</new-features>

<api-changes>
  <change name="Streaming-Output">
    <description>Minor improvements to streaming, no breaking changes</description>
    <internal-changes>
      - ResponseChunk now uses specific UserMessage and AssistantMessage types instead of generic Message
      - Streaming handler enhanced with timeout and AbortController support
      - Improved error handling during streaming
    </internal-changes>
    <public-api>
      - No changes to public streaming API
      - Still returns .stream(AnyPublisher&lt;ResponseChunk, Error&gt;)
      - Same chunk types emitted (initSystem, user, assistant, result)
    </public-api>
  </change>

  <change name="ClaudeCodeOptions-Properties">
    <added>
      - abortController: AbortController?
      - timeout: TimeInterval?
      - mcpServers: [String: McpServerConfiguration]?
      - mcpConfigPath: String?
      - permissionPromptToolName: String?
      - continue: Bool?
      - resume: String?
      - verbose: Bool
    </added>
    <modified>
      - printMode: Now internal (was public)
    </modified>
  </change>

  <change name="New-Types">
    <added>
      - AbortController: For cancellation support
      - McpServerConfiguration: For MCP server setup
      - ApiKeySource: Enum for API key sources
      - ConfigScope: Enum for configuration scopes
      - PermissionMode: Enum for permission modes
      - RateLimiter: For rate limiting logic
      - RetryPolicy: For retry configuration
    </added>
  </change>

  <change name="Error-Handling">
    <added>
      ClaudeCodeError enum cases:
      - notInstalled
      - invalidConfiguration(String)
      - executionFailed(String)
      - timeout
      - cancelled
      - rateLimitExceeded(retryAfter: Date?)
      - networkError(Error)
      - permissionDenied(String)
      
      Convenience properties:
      - isRateLimitError: Bool
      - isTimeoutError: Bool
      - isRetryable: Bool
      - isInstallationError: Bool
      - isPermissionError: Bool
      - suggestedRetryDelay: TimeInterval?
    </added>
  </change>
</api-changes>

<migration-steps>
  <step number="1">
    <title>Update Option Initialization</title>
    <description>Remove printMode parameter from ClaudeCodeOptions initialization</description>
    <code-change>
      <from>let options = ClaudeCodeOptions(printMode: true)</from>
      <to>let options = ClaudeCodeOptions()</to>
    </code-change>
  </step>

  <step number="2">
    <title>Add Error Handling</title>
    <description>Update error handling to handle new error types</description>
    <example>
      ```swift
      do {
          let result = try await client.runSinglePrompt(prompt: prompt)
      } catch let error as ClaudeCodeError {
          // Use convenience properties
          if error.isRetryable {
              if let delay = error.suggestedRetryDelay {
                  print("Retry after \(delay) seconds")
              }
          }
          
          // Or handle specific cases
          switch error {
          case .rateLimitExceeded(let retryAfter):
              print("Rate limited. Retry after: \(retryAfter ?? Date())")
          case .cancelled:
              print("Operation cancelled")
          case .timeout:
              print("Operation timed out")
          default:
              print("Error: \(error)")
          }
      }
      ```
    </example>
  </step>

  <step number="3">
    <title>Optional: Add MCP Support</title>
    <description>If using MCP tools, configure MCP servers</description>
    <example>
      ```swift
      // Option 1: Direct configuration
      options.mcpServers = [
          "filesystem": .stdio(McpStdioServerConfig(
              command: "npx",
              args: ["-y", "@modelcontextprotocol/server-filesystem"],
              env: ["ALLOWED_PATHS": "/Users/me/projects"]
          ))
      ]
      
      // Option 2: File-based configuration
      options.mcpConfigPath = Bundle.main.path(forResource: "mcp-config", ofType: "json")
      ```
    </example>
  </step>

  <step number="4">
    <title>Optional: Configure Timeouts</title>
    <description>Set custom timeouts if needed</description>
    <example>
      ```swift
      options.timeout = 600 // 10 minutes for long operations
      ```
    </example>
  </step>
  
  <step number="5">
    <title>Optional: Add Retry Support</title>
    <description>Use retry methods for resilient operations</description>
    <example>
      ```swift
      // Use the WithRetry methods
      let result = try await client.runSinglePromptWithRetry(
          prompt: "Generate code",
          outputFormat: .json,
          retryPolicy: .default
      )
      ```
    </example>
  </step>
  
  <step number="6">
    <title>Optional: Add Rate Limiting</title>
    <description>Wrap client with rate limiter for API protection</description>
    <example>
      ```swift
      let rateLimitedClient = RateLimitedClaudeCode(
          wrapped: client,
          requestsPerMinute: 10
      )
      ```
    </example>
  </step>
</migration-steps>

<testing-checklist>
  <item>Verify existing code works without printMode parameter</item>
  <item>Test error handling for rate limit scenarios</item>
  <item>If using MCP, verify server configurations</item>
  <item>Test cancellation with AbortController if implemented</item>
  <item>Verify session continuation works with resume/continue options</item>
</testing-checklist>

</migration-guide>

## Best Practices

<best-practices>
  <practice name="Error-Handling">
    Always implement comprehensive error handling, especially for rate limits and network errors.
  </practice>
  
  <practice name="Session-Management">
    Save session IDs when using streaming APIs to allow conversation continuation.
  </practice>
  
  <practice name="MCP-Configuration">
    Use file-based MCP configuration for production deployments to avoid hardcoding credentials.
  </practice>
  
  <practice name="Timeouts">
    Set appropriate timeouts based on expected operation duration. Default is 2 minutes.
  </practice>
</best-practices>

## Troubleshooting

<troubleshooting>
  <issue name="Rate-Limit-Errors">
    <symptom>Frequent ClaudeCodeError.rateLimitError</symptom>
    <solution>The SDK handles retry automatically. Ensure you're not making parallel requests.</solution>
  </issue>
  
  <issue name="MCP-Connection-Failed">
    <symptom>MCP tools not available</symptom>
    <solution>
      1. Verify MCP server command/URL is correct
      2. Check environment variables are set
      3. Ensure required npm packages are installed
    </solution>
  </issue>
  
  <issue name="Timeout-Errors">
    <symptom>Operations timing out</symptom>
    <solution>Increase timeout: options.timeout = 600 // 10 minutes</solution>
  </issue>
</troubleshooting>

---

*This document is maintained for LLM consumption and human reference. Update after each merge to main.*