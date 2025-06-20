# ClaudeCodeSDK

[Beta] A Swift SDK for seamlessly integrating Claude Code into your iOS and macOS applications. Interact with Anthropic's Claude Code programmatically for AI-powered coding assistance.

## ✨ What's New

* **Enhanced Error Handling** - Detailed error types with retry hints and classification
* **Built-in Retry Logic** - Automatic retry with exponential backoff for transient failures
* **Rate Limiting** - Token bucket rate limiter to respect API limits
* **Timeout Support** - Configurable timeouts for all operations
* **Cancellation** - AbortController support for canceling long-running operations
* **New Configuration Options** - Model selection, permission modes, executable configuration, and more

## Overview

ClaudeCodeSDK allows you to integrate Claude Code's capabilities directly into your Swift applications. The SDK provides a simple interface to run Claude Code as a subprocess, enabling multi-turn conversations, custom system prompts, and various output formats.

## Requirements

* **Platforms:** iOS 15+ or macOS 13+
* **Swift Version:** Swift 6.0+
* **Dependencies:** Claude Code CLI installed (`npm install -g @anthropic/claude-code`)

## 🚀 Installation

### Swift Package Manager

Add the package dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/jamesrochabrun/ClaudeCodeSDK", from: "1.0.0")
]
```

Or add it directly in Xcode:
1. File > Add Package Dependencies...
2. Enter: `https://github.com/jamesrochabrun/ClaudeCodeSDK`

## Basic Usage

Import the SDK and create a client:

```swift
import ClaudeCodeSDK

// Initialize the client
let client = ClaudeCodeClient(debug: true)

// Run a simple prompt
Task {
    do {
        let result = try await client.runSinglePrompt(
            prompt: "Write a function to calculate Fibonacci numbers",
            outputFormat: .text,
            options: nil
        )
        
        switch result {
        case .text(let content):
            print("Response: \(content)")
        default:
            break
        }
    } catch {
        print("Error: \(error)")
    }
}
```

## Key Features

### Different Output Formats

Choose from three output formats depending on your needs:

```swift
// Get plain text
let textResult = try await client.runSinglePrompt(
    prompt: "Write a sorting algorithm",
    outputFormat: .text,
    options: nil
)

// Get JSON with metadata
let jsonResult = try await client.runSinglePrompt(
    prompt: "Explain big O notation",
    outputFormat: .json,
    options: nil
)

// Stream responses as they arrive
let streamResult = try await client.runSinglePrompt(
    prompt: "Create a React component",
    outputFormat: .streamJson,
    options: nil
)
```

#### Processing Streams

```swift
if case .stream(let publisher) = streamResult {
    publisher.sink(
        receiveCompletion: { completion in
            // Handle completion
        },
        receiveValue: { chunk in
            // Process each chunk as it arrives
        }
    )
    .store(in: &cancellables)
}
```

### Multi-turn Conversations

Maintain context across multiple interactions:

```swift
// Continue the most recent conversation
let continuationResult = try await client.continueConversation(
    prompt: "Now refactor this for better performance",
    outputFormat: .text,
    options: nil
)

// Resume a specific session
let resumeResult = try await client.resumeConversation(
    sessionId: "550e8400-e29b-41d4-a716-446655440000",
    prompt: "Add error handling",
    outputFormat: .text,
    options: nil
)
```

### Configuration

Configure the client's runtime behavior:

```swift
// Create a custom configuration
var configuration = ClaudeCodeConfiguration(
    command: "claude",                    // Command to execute (default: "claude")
    workingDirectory: "/path/to/project", // Set working directory
    environment: ["API_KEY": "value"],    // Additional environment variables
    enableDebugLogging: true,             // Enable debug logs
    additionalPaths: ["/custom/bin"]      // Additional PATH directories
)

// Initialize client with custom configuration
let client = ClaudeCodeClient(configuration: configuration)

// Or modify configuration at runtime
client.configuration.enableDebugLogging = false
client.configuration.workingDirectory = "/new/path"
```

### Customization Options

Fine-tune Claude Code's behavior with comprehensive options:

```swift
var options = ClaudeCodeOptions()
options.verbose = true
options.maxTurns = 5
options.systemPrompt = "You are a senior backend engineer specializing in Swift."
options.appendSystemPrompt = "After writing code, add comprehensive comments."
options.timeout = 300 // 5 minute timeout
options.model = "claude-3-sonnet-20240229"
options.permissionMode = .acceptEdits
options.maxThinkingTokens = 10000

// Tool configuration
options.allowedTools = ["Read", "Write", "Bash"]
options.disallowedTools = ["Delete"]

let result = try await client.runSinglePrompt(
    prompt: "Create a REST API in Swift",
    outputFormat: .text,
    options: options
)
```

### MCP Configuration

The Model Context Protocol (MCP) allows you to extend Claude Code with additional tools and resources from external servers. ClaudeCodeSDK provides full support for MCP integration.

#### Using MCP with Configuration File

Create a JSON configuration file with your MCP servers:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/path/to/allowed/files"
      ]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "your-github-token"
      }
    }
  }
}
```

Use the configuration in your Swift code:

```swift
var options = ClaudeCodeOptions()
options.mcpConfigPath = "/path/to/mcp-config.json"

// MCP tools are automatically added with the format: mcp__serverName__toolName
// The SDK will automatically allow tools like:
// - mcp__filesystem__read_file
// - mcp__filesystem__list_directory
// - mcp__github__*

let result = try await client.runSinglePrompt(
    prompt: "List all files in the project",
    outputFormat: .text,
    options: options
)
```

#### Programmatic MCP Configuration

You can also configure MCP servers programmatically:

```swift
var options = ClaudeCodeOptions()

// Define MCP servers in code
options.mcpServers = [
    "XcodeBuildMCP": .stdio(McpStdioServerConfig(
        command: "npx",
        args: ["-y", "xcodebuildmcp@latest"]
    )),
    "filesystem": .stdio(McpStdioServerConfig(
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/projects"]
    ))
]

// The SDK creates a temporary configuration file automatically
let result = try await client.runSinglePrompt(
    prompt: "Build the iOS app",
    outputFormat: .streamJson,
    options: options
)
```

#### MCP Tool Naming Convention

MCP tools follow a specific naming pattern: `mcp__<serverName>__<toolName>`

```swift
// Explicitly allow specific MCP tools
options.allowedTools = [
    "mcp__filesystem__read_file",
    "mcp__filesystem__write_file",
    "mcp__github__search_repositories"
]

// Or use wildcards to allow all tools from a server
options.allowedTools = ["mcp__filesystem__*", "mcp__github__*"]
```

#### Using MCP with Permission Prompts

For non-interactive mode with MCP servers that require permissions:

```swift
var options = ClaudeCodeOptions()
options.mcpConfigPath = "/path/to/mcp-config.json"
options.permissionMode = .auto
options.permissionPromptToolName = "mcp__permissions__approve"
```

### Error Handling & Resilience

The SDK provides robust error handling with detailed error types and recovery options:

```swift
// Enhanced error handling
do {
    let result = try await client.runSinglePrompt(
        prompt: "Complex task",
        outputFormat: .json,
        options: options
    )
} catch let error as ClaudeCodeError {
    if error.isRetryable {
        // Error can be retried
        if let delay = error.suggestedRetryDelay {
            // Wait and retry
        }
    } else if error.isRateLimitError {
        print("Rate limited")
    } else if error.isTimeoutError {
        print("Request timed out")
    } else if error.isPermissionError {
        print("Permission denied")
    }
}
```

### Retry Logic

Built-in retry support with exponential backoff:

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

### Rate Limiting

Protect against API rate limits with built-in rate limiting:

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

### Cancellation Support

Cancel long-running operations with AbortController:

```swift
var options = ClaudeCodeOptions()
let abortController = AbortController()
options.abortController = abortController

// Start operation
Task {
    let result = try await client.runSinglePrompt(
        prompt: "Long running task",
        outputFormat: .streamJson,
        options: options
    )
}

// Cancel when needed
abortController.abort()
```

## Example Project

The repository includes a complete example project demonstrating how to integrate and use the SDK in a real application. You can find it in the `Example/ClaudeCodeSDKExample` directory.

The example showcases:

* Creating a chat interface with Claude
* Handling streaming responses
* Managing conversation sessions
* Displaying loading states
* Error handling

### Running the Example

1. Clone the repository
2. Open `Example/ClaudeCodeSDKExample/ClaudeCodeSDKExample.xcodeproj`
3. Build and run

## Architecture

The SDK is built with a protocol-based architecture for maximum flexibility:

### Core Components
* **`ClaudeCode`**: Protocol defining the interface
* **`ClaudeCodeClient`**: Concrete implementation that runs Claude Code CLI as a subprocess
* **`ClaudeCodeOptions`**: Configuration options for Claude Code execution
* **`ClaudeCodeOutputFormat`**: Output format options (text, JSON, streaming JSON)
* **`ClaudeCodeResult`**: Result types returned by the SDK
* **`ResponseChunk`**: Individual chunks in streaming responses

### Type System
* **`ApiKeySource`**: Source of API key (user/project/org/temporary)
* **`ConfigScope`**: Configuration scope levels (local/user/project)
* **`PermissionMode`**: Permission handling modes (default/acceptEdits/bypassPermissions/plan)
* **`McpServerConfig`**: MCP server configurations (stdio/sse)

### Error Handling
* **`ClaudeCodeError`**: Comprehensive error types with retry hints
* **`RetryPolicy`**: Configurable retry strategies
* **`RetryHandler`**: Automatic retry with exponential backoff

### Utilities
* **`RateLimiter`**: Token bucket rate limiting
* **`AbortController`**: Cancellation support
* **`RateLimitedClaudeCode`**: Rate-limited wrapper

## License

ClaudeCodeSDK is available under the MIT license. See the `LICENSE` file for more info.

## Documentation

This is not an offical Anthropic SDK, For more information about Claude Code and its capabilities, visit the [Anthropic Documentation](https://docs.anthropic.com/en/docs/claude-code/sdk).
