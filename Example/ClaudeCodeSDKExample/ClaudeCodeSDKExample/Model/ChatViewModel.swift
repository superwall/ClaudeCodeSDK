//
//  ChatViewModel.swift
//  ClaudeCodeSDKExample
//
//  Created by James Rochabrun on 5/20/25.
//

import Combine
import ClaudeCodeSDK
import Foundation
import os.log

@Observable
public class ChatViewModel {
  
  private let claudeClient: ClaudeCode
  private let logger = Logger(subsystem: "com.yourcompany.ClaudeChat", category: "ChatViewModel")
  private var cancellables = Set<AnyCancellable>()
  private var currentSessionId: String?
  private var currentMessageId: UUID?
  
  // MARK: - Published Properties
  
  /// All messages in the conversation
  var messages: [ChatMessage] = []
  
  /// Loading state
  public var isLoading: Bool = false
  
  /// Error state
  public var error: Error?
  
  
  // MARK: - Initialization
  
  public init(claudeClient: ClaudeCode) {
    self.claudeClient = claudeClient
  }
  
  // MARK: - Public Methods
  
  /// Sends a new message to Claude
  /// - Parameter text: The message text to send
  public func sendMessage(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    
    // Add user message to the list
    let userMessage = ChatMessage(role: .user, content: text)
    messages.append(userMessage)
    
    // Clear any previous errors
    error = nil
    
    // Add a placeholder for assistant's response
    let assistantId = UUID()
    currentMessageId = assistantId
    
    let placeholderMessage = ChatMessage(
      id: assistantId,
      role: .assistant,
      content: "",
      isComplete: false
    )
    messages.append(placeholderMessage)
    
    // Set loading state
    isLoading = true
    
    // Determine if we need to continue or start a new conversation
    Task {
      do {
        if let sessionId = currentSessionId {
          try await continueConversation(sessionId: sessionId, prompt: text, messageId: assistantId)
        } else {
          try await startNewConversation(prompt: text, messageId: assistantId)
        }
      } catch {
        await MainActor.run {
          self.handleError(error)
        }
      }
    }
  }
  
  /// Clears the conversation history and starts a new session
  public func clearConversation() {
    messages = []
    currentSessionId = nil
    currentMessageId = nil
    error = nil
  }
  
  /// Cancels any ongoing requests
  public func cancelRequest() {
    claudeClient.cancel()
    isLoading = false
  }
  
  // MARK: - Private Methods
  
  private func startNewConversation(prompt: String, messageId: UUID) async throws {
    var options = ClaudeCodeOptions()
    options.verbose = true
    
    let result = try await claudeClient.runSinglePrompt(
      prompt: prompt,
      outputFormat: .streamJson,
      options: options
    )
    
    await processStreamResult(result, messageId: messageId)
  }
  
  private func continueConversation(sessionId: String, prompt: String, messageId: UUID) async throws {
    var options = ClaudeCodeOptions()
    options.verbose = true
    
    let result = try await claudeClient.resumeConversation(
      sessionId: sessionId,
      prompt: prompt,
      outputFormat: .streamJson,
      options: options
    )
    
    await processStreamResult(result, messageId: messageId)
  }
  
  private func processStreamResult(_ result: ClaudeCodeResult, messageId: UUID) async {
    switch result {
    case .stream(let publisher):
      var contentBuffer = ""
      
      await withCheckedContinuation { continuation in
        publisher
          .receive(on: DispatchQueue.main)
          .sink(
            receiveCompletion: { [weak self] completion in
              guard let self = self else { return }
              
              switch completion {
              case .finished:
                // Ensure message is marked as complete
                self.updateAssistantMessage(messageId: messageId, content: contentBuffer, isComplete: true)
                self.isLoading = false
              case .failure(let error):
                self.handleError(error)
              }
              
              continuation.resume()
            },
            receiveValue: { [weak self] chunk in
              guard let self = self else { return }
              
              switch chunk {
              case .initSystem(let initMessage):
                self.currentSessionId = initMessage.sessionId
                logger.debug("Started session: \(initMessage.sessionId)")
                
              case .assistant(let message):
                // Handle different content types
                for content in message.message.content {
                  switch content {
                  case .text(let textContent, _):
                    contentBuffer = textContent
                    self.updateAssistantMessage(messageId: messageId, content: contentBuffer, isComplete: false)
                    
                  case .toolUse(let toolUse):
                    let toolInput = toolUse.input["query"]?.stringValue ?? toolUse.input["prompt"]?.stringValue ?? "Unknown"
                    let toolMessage = "TOOL USE: Searching for information about: \(toolInput)."
                    contentBuffer = toolMessage
                    self.updateAssistantMessage(messageId: messageId, content: toolMessage, isComplete: false)
                    
                  default:
                    break
                  }
                }
                
                if contentBuffer.isEmpty {
                  logger.error("No processable content found in assistant message")
                }
                
              case .result(let resultMessage):
                // Save the session ID for continuations
                self.currentSessionId = resultMessage.sessionId
                logger.info("Completed response for session: \(resultMessage.sessionId)")
                
                // Ensure we have the final content in case we missed it
                if let finalContent = resultMessage.result, !finalContent.isEmpty {
                  contentBuffer = finalContent
                  self.updateAssistantMessage(messageId: messageId, content: finalContent, isComplete: true)
                }
                
              default:
                break
              }
            }
          )
          .store(in: &self.cancellables)
      }
      
    default:
      await MainActor.run {
        logger.error("Expected stream result but got a different format")
        error = NSError(domain: "ChatViewModel", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        isLoading = false
      }
    }
  }
  
  private func updateAssistantMessage(messageId: UUID, content: String, isComplete: Bool) {
    if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
      let updatedMessage = ChatMessage(
        id: messageId,
        role: .assistant,
        content: content,
        isComplete: isComplete
      )
      self.messages[index] = updatedMessage
    } else {
      logger.error("⚠️ Message with ID \(messageId) not found in messages array")
    }
  }
  
  private func handleError(_ error: Error) {
    logger.error("Error: \(error.localizedDescription)")
    self.error = error
    self.isLoading = false
    
    // Remove incomplete assistant message if there was an error
    if let currentMessageId = currentMessageId,
       let index = messages.firstIndex(where: { $0.id == currentMessageId && !$0.isComplete }) {
      messages.remove(at: index)
    }
  }
}
