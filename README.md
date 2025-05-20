# ClaudeCodeSDK

[Beta] A Swift SDK for seamlessly integrating Claude Code into your iOS and macOS applications. Interact with Anthropic's Claude Code programmatically for AI-powered coding assistance.

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

### Customization Options

Fine-tune Claude Code's behavior:

```swift
var options = ClaudeCodeOptions()
options.verbose = true
options.maxTurns = 5
options.systemPrompt = "You are a senior backend engineer specializing in Swift."
options.appendSystemPrompt = "After writing code, add comprehensive comments."

let result = try await client.runSinglePrompt(
    prompt: "Create a REST API in Swift",
    outputFormat: .text,
    options: options
)
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

* **`ClaudeCode`**: Protocol defining the interface
* **`ClaudeCodeClient`**: Concrete implementation that runs Claude Code CLI as a subprocess
* **`ClaudeCodeOptions`**: Configuration options for Claude Code execution
* **`ClaudeCodeOutputFormat`**: Output format options (text, JSON, streaming JSON)
* **`ClaudeCodeResult`**: Result types returned by the SDK
* **`ResponseChunk`**: Individual chunks in streaming responses

## License

ClaudeCodeSDK is available under the MIT license. See the `LICENSE` file for more info.

## Documentation

This is not an offical Anthropic SDK, For more information about Claude Code and its capabilities, visit the [Anthropic Documentation](https://docs.anthropic.com/en/docs/claude-code/sdk).
