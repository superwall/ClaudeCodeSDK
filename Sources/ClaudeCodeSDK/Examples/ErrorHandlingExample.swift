//
//  ErrorHandlingExample.swift
//  ClaudeCodeSDK
//
//  Example demonstrating error handling, retry logic, and rate limiting
//

import Foundation
import ClaudeCodeSDK

// MARK: - Basic Error Handling

func basicErrorHandling() async throws {
    let client = ClaudeCodeClient()
    
    do {
        let result = try await client.runSinglePrompt(
            prompt: "Write a hello world function",
            outputFormat: .json,
            options: nil
        )
        print("Success: \(result)")
    } catch let error as ClaudeCodeError {
        switch error {
        case .notInstalled:
            print("Please install Claude Code first")
        case .timeout(let duration):
            print("Request timed out after \(duration) seconds")
        case .rateLimitExceeded(let retryAfter):
            print("Rate limited. Retry after: \(retryAfter ?? 60) seconds")
        case .permissionDenied(let message):
            print("Permission denied: \(message)")
        default:
            print("Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Timeout Example

func timeoutExample() async throws {
    let client = ClaudeCodeClient()
    
    var options = ClaudeCodeOptions()
    options.timeout = 30 // 30 second timeout
    
    do {
        let result = try await client.runSinglePrompt(
            prompt: "Analyze this large codebase...",
            outputFormat: .json,
            options: options
        )
        print("Completed: \(result)")
    } catch ClaudeCodeError.timeout(let duration) {
        print("Operation timed out after \(duration) seconds")
    }
}

// MARK: - Retry Logic Example

func retryExample() async {
    let client = ClaudeCodeClient()
    
    // Use default retry policy (3 attempts with exponential backoff)
    do {
        let result = try await client.runSinglePromptWithRetry(
            prompt: "Generate a REST API",
            outputFormat: .json,
            retryPolicy: .default
        )
        print("Success after retries: \(result)")
    } catch {
        print("Failed after all retry attempts: \(error)")
    }
    
    // Use conservative retry policy for rate-limited operations
    do {
        let result = try await client.runSinglePromptWithRetry(
            prompt: "Complex analysis task",
            outputFormat: .json,
            retryPolicy: .conservative
        )
        print("Success with conservative retry: \(result)")
    } catch {
        print("Failed with conservative retry: \(error)")
    }
}

// MARK: - Rate Limiting Example

func rateLimitingExample() async {
    let baseClient = ClaudeCodeClient()
    
    // Wrap with rate limiter - 10 requests per minute
    let rateLimitedClient = RateLimitedClaudeCode(
        wrapped: baseClient,
        requestsPerMinute: 10,
        burstCapacity: 3 // Allow 3 requests in burst
    )
    
    // Make multiple requests - they will be rate limited
    for i in 1...15 {
        do {
            print("Making request \(i)...")
            let result = try await rateLimitedClient.runSinglePrompt(
                prompt: "Quick task \(i)",
                outputFormat: .text,
                options: nil
            )
            print("Request \(i) completed")
        } catch {
            print("Request \(i) failed: \(error)")
        }
    }
}

// MARK: - Combined Example with Smart Error Handling

func smartErrorHandling() async throws {
    let client = ClaudeCodeClient()
    var options = ClaudeCodeOptions()
    options.timeout = 60
    
    var attempts = 0
    let maxAttempts = 3
    
    while attempts < maxAttempts {
        attempts += 1
        
        do {
            let result = try await client.runSinglePrompt(
                prompt: "Complex task",
                outputFormat: .json,
                options: options
            )
            print("Success: \(result)")
            break // Success, exit loop
            
        } catch let error as ClaudeCodeError {
            print("Attempt \(attempts) failed: \(error.localizedDescription)")
            
            // Check if error is retryable
            if error.isRetryable && attempts < maxAttempts {
                if let delay = error.suggestedRetryDelay {
                    print("Waiting \(delay) seconds before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } else {
                // Non-retryable error or max attempts reached
                print("Giving up after \(attempts) attempts")
                throw error
            }
        }
    }
}

// MARK: - Abort Controller Example

func abortExample() async {
    let client = ClaudeCodeClient()
    
    var options = ClaudeCodeOptions()
    let abortController = AbortController()
    options.abortController = abortController
    
    // Start a long-running task
    Task {
        do {
            let result = try await client.runSinglePrompt(
                prompt: "Very long running task...",
                outputFormat: .streamJson,
                options: options
            )
            print("Task completed: \(result)")
        } catch ClaudeCodeError.cancelled {
            print("Task was cancelled")
        }
    }
    
    // Cancel after 5 seconds
    Task {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        print("Aborting task...")
        abortController.abort()
    }
}
