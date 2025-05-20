//
//  ClaudeCodeClient.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//
@preconcurrency import Combine
import Foundation
import os.log

/// Concrete implementation of ClaudeCodeSDK that uses the Claude Code CLI
public class ClaudeCodeClient: ClaudeCode {
  private var task: Process?
  private var cancellables = Set<AnyCancellable>()
  private var logger: Logger?
  private let decoder = JSONDecoder()
  private var currentWorkingDirectory: String = ""
  
  public init(workingDirectory: String = "", debug: Bool = false) {
    self.currentWorkingDirectory = workingDirectory
    
    if debug {
      self.logger = Logger(subsystem: "com.yourcompany.ClaudeCodeClient", category: "ClaudeCode")
      logger?.info("Initializing Claude Code client")
    }
    
    decoder.keyDecodingStrategy = .convertFromSnakeCase
  }
  // MARK: - Protocol Implementation
  
  private func configuredProcess(for command: String) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    
    if !currentWorkingDirectory.isEmpty {
      process.currentDirectoryURL = URL(fileURLWithPath: currentWorkingDirectory)
    }
    
    var env = ProcessInfo.processInfo.environment
    if let currentPath = env["PATH"] {
      env["PATH"] = "\(currentPath):/usr/local/bin:/opt/homebrew/bin:/usr/bin"
    } else {
      env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    }
    process.environment = env
    
    logger?.info("Configured process with command: \(command)")
    return process
  }
  
  public func runWithStdin(
    stdinContent: String,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var opts = options ?? ClaudeCodeOptions()
    
    // Ensure print mode and verbose for stream-json
    opts.printMode = true
    if outputFormat == .streamJson {
      opts.verbose = true
    }
    
    let args = opts.toCommandArgs()
    let argsString = args.joined(separator: " ")
    let commandString = "claude \(argsString)"
    
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat,
      stdinContent: stdinContent
    )
  }
  
  public func runSinglePrompt(
    prompt: String,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var opts = options ?? ClaudeCodeOptions()
    
    // Ensure print mode and verbose for stream-json
    opts.printMode = true
    if outputFormat == .streamJson {
      opts.verbose = true
    }
    
    var args = opts.toCommandArgs()
    args.append(outputFormat.commandArgument)
    
    // Properly escape the prompt for shell
    let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
    
    // Construct the full command
    var commandString = "claude \(args.joined(separator: " "))"
    
    // Add the prompt if not empty
    if !prompt.isEmpty {
      commandString += " \"\(escapedPrompt)\""
    }
    
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat
    )
  }
  
  public func continueConversation(
    prompt: String?,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var opts = options ?? ClaudeCodeOptions()
    
    // Ensure print mode and verbose for stream-json
    opts.printMode = true
    if outputFormat == .streamJson {
      opts.verbose = true
    }
    
    var args = opts.toCommandArgs()
    args.append("--continue")
    args.append(outputFormat.commandArgument)
    
    // Construct the full command
    var commandString = "claude \(args.joined(separator: " "))"
    
    // Add the prompt if provided
    if let prompt = prompt, !prompt.isEmpty {
      let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
      commandString += " \"\(escapedPrompt)\""
    }
    
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat
    )
  }
  
  public func resumeConversation(
    sessionId: String,
    prompt: String?,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var opts = options ?? ClaudeCodeOptions()
    
    // Ensure print mode and verbose for stream-json
    opts.printMode = true
    if outputFormat == .streamJson {
      opts.verbose = true
    }
    
    var args = opts.toCommandArgs()
    args.append("--resume")
    args.append(sessionId)
    args.append(outputFormat.commandArgument)
    
    // Construct the full command
    var commandString = "claude \(args.joined(separator: " "))"
    
    // Add the prompt if provided
    if let prompt = prompt, !prompt.isEmpty {
      let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
      commandString += " \"\(escapedPrompt)\""
    }
    
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat
    )
  }
  
  public func listSessions() async throws -> [SessionInfo] {
    let commandString = "claude logs --output-format json"
    
    let process = configuredProcess(for: commandString)
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    do {
      try process.run()
      process.waitUntilExit()
      
      if process.terminationStatus != 0 {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        logger?.error("Failed to list sessions: \(errorString)")
        throw ClaudeCodeError.executionFailed(errorString)
      }
      
      let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: outputData, encoding: .utf8) else {
        throw ClaudeCodeError.invalidOutput("Could not decode output as UTF-8")
      }
      
      logger?.debug("Received session list output: \(output.prefix(100))...")
      
      do {
        let sessions = try decoder.decode([SessionInfo].self, from: outputData)
        logger?.info("Successfully retrieved \(sessions.count) sessions")
        return sessions
      } catch {
        logger?.error("JSON parsing error when decoding sessions: \(error)")
        throw ClaudeCodeError.jsonParsingError(error)
      }
    } catch {
      logger?.error("Error listing sessions: \(error.localizedDescription)")
      throw error
    }
  }
  
  public func cancel() {
    task?.terminate()
    task = nil
    
    for cancellable in cancellables {
      cancellable.cancel()
    }
    cancellables.removeAll()
  }
  
  private func executeClaudeCommand(
    command: String,
    outputFormat: ClaudeCodeOutputFormat,
    stdinContent: String? = nil
  ) async throws -> ClaudeCodeResult {
    logger?.info("Executing command: \(command)")
    
    let process = configuredProcess(for: command)
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    // Set up stdin if content provided
    if let stdinContent = stdinContent {
      let stdinPipe = Pipe()
      process.standardInput = stdinPipe
      
      if let data = stdinContent.data(using: .utf8) {
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        stdinPipe.fileHandleForWriting.closeFile()
      }
    }
    
    // Store for cancellation
    self.task = process
    
    do {
      // Handle stream-json differently
      if outputFormat == .streamJson {
        return try await handleStreamJsonOutput(process: process, outputPipe: outputPipe, errorPipe: errorPipe)
      } else {
        // For text and json formats, run synchronously
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
          let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
          let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
          
          if errorString.contains("No such file or directory") ||
              errorString.contains("command not found") {
            logger?.error("Claude command not found: \(errorString)")
            throw ClaudeCodeError.notInstalled
          } else {
            logger?.error("Process failed with error: \(errorString)")
            throw ClaudeCodeError.executionFailed(errorString)
          }
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
          throw ClaudeCodeError.invalidOutput("Could not decode output as UTF-8")
        }
        
        logger?.debug("Received output: \(output.prefix(100))...")
        
        switch outputFormat {
        case .text:
          return .text(output)
        case .json:
          do {
            guard let data = output.data(using: .utf8) else {
              throw ClaudeCodeError.invalidOutput("Could not convert output to data")
            }
            
            let resultMessage = try decoder.decode(ResultMessage.self, from: data)
            return .json(resultMessage)
          } catch {
            logger?.error("JSON parsing error: \(error)")
            throw ClaudeCodeError.jsonParsingError(error)
          }
        default:
          throw ClaudeCodeError.invalidOutput("Unexpected output format")
        }
      }
    } catch let error as ClaudeCodeError {
      throw error
    } catch {
      logger?.error("Error executing command: \(error.localizedDescription)")
      throw ClaudeCodeError.executionFailed(error.localizedDescription)
    }
  }
  
  // MARK: - Stream JSON Output Handling
  
  private func handleStreamJsonOutput(
    process: Process,
    outputPipe: Pipe,
    errorPipe: Pipe
  ) async throws -> ClaudeCodeResult {
    // Create a publisher for streaming JSON
    let subject = PassthroughSubject<ResponseChunk, Error>()
    let publisher = subject.eraseToAnyPublisher()
    
    // Create a stream buffer
    let streamBuffer = StreamBuffer()
    
    // Capture values to avoid capturing self in @Sendable closures
    let decoder = self.decoder
    let logger = self.logger
    
    // Configure handlers for readability
    outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      guard !data.isEmpty else {
        // End of file
        fileHandle.readabilityHandler = nil
        Task {
          // Process any remaining data
          if !(await streamBuffer.isEmpty()) {
            if let outputString = await streamBuffer.getString() {
              ClaudeCodeClient.processJsonLine(
                outputString,
                subject: subject,
                decoder: decoder,
                logger: logger
              )
            }
          }
          subject.send(completion: .finished)
        }
        return
      }
      
      Task {
        // Append to buffer
        await streamBuffer.append(data)
        
        // Parse the data as JSON line by line
        guard let outputString = await streamBuffer.getString() else { return }
        
        // Split by newlines
        let lines = outputString.components(separatedBy: .newlines)
        
        // Process all complete lines except the last one (which may be incomplete)
        if lines.count > 1 {
          // Reset buffer to only contain the potentially incomplete last line
          if !lines.last!.isEmpty {
            if let lastLineData = lines.last!.data(using: .utf8) {
              await streamBuffer.set(lastLineData)
            }
          } else {
            await streamBuffer.set(Data())
          }
          
          // Process all complete lines
          for i in 0..<lines.count-1 where !lines[i].isEmpty {
            ClaudeCodeClient.processJsonLine(
              lines[i],
              subject: subject,
              decoder: decoder,
              logger: logger
            )
          }
        }
      }
    }
    
    // Configure handler for termination
    process.terminationHandler = { process in
      Task {
        // Process any remaining data
        if !(await streamBuffer.isEmpty()) {
          if let outputString = await streamBuffer.getString() {
            ClaudeCodeClient.processJsonLine(
              outputString,
              subject: subject,
              decoder: decoder,
              logger: logger
            )
          }
        }
        
        if process.terminationStatus != 0 {
          let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
          if let errorString = String(data: errorData, encoding: .utf8) {
            logger?.error("Process terminated with error: \(errorString)")
            
            if errorString.contains("No such file or directory") ||
                errorString.contains("command not found") {
              subject.send(completion: .failure(ClaudeCodeError.notInstalled))
            } else {
              subject.send(completion: .failure(ClaudeCodeError.executionFailed(errorString)))
            }
          } else {
            subject.send(completion: .failure(ClaudeCodeError.executionFailed("Unknown error")))
          }
        } else {
          // Clean completion if not already completed
          subject.send(completion: .finished)
        }
        
        // Clean up
        outputPipe.fileHandleForReading.readabilityHandler = nil
      }
    }
    
    // Start the process
    do {
      try process.run()
      self.task = process
    } catch {
      logger?.error("Failed to start process: \(error.localizedDescription)")
      
      if (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 2 {
        // No such file or directory
        throw ClaudeCodeError.notInstalled
      }
      throw error
    }
    
    // Return the publisher
    return .stream(publisher)
  }
  
  // MARK: - Stream Buffer
  
  actor StreamBuffer {
    private var buffer = Data()
    
    func append(_ data: Data) {
      buffer.append(data)
    }
    
    func getAndClear() -> Data {
      let current = buffer
      buffer = Data()
      return current
    }
    
    func set(_ data: Data) {
      buffer = data
    }
    
    func isEmpty() -> Bool {
      return buffer.isEmpty
    }
    
    func getString() -> String? {
      return String(data: buffer, encoding: .utf8)
    }
  }
  
  // MARK: - JSON Processing
  
  // Make processJsonLine a static method to avoid capturing self
  private static func processJsonLine(
    _ line: String,
    subject: PassthroughSubject<ResponseChunk, Error>,
    decoder: JSONDecoder,
    logger: Logger?
  ) {
    guard !line.isEmpty else { return }
    
    logger?.debug("Processing JSON line: \(line.prefix(100))...")
    
    guard let lineData = line.data(using: .utf8) else {
      logger?.error("Could not convert line to data: \(line.prefix(50))...")
      return
    }
    
    // Fix the warning by separating the throwing part
    let jsonObject: Any
    do {
      // This is the throwing call
      jsonObject = try JSONSerialization.jsonObject(with: lineData)
    } catch {
      logger?.error("Error parsing JSON data: \(error)")
      return
    }
    
    // Then do the optional cast separately
    guard let json = jsonObject as? [String: Any],
          let typeString = json["type"] as? String else {
      logger?.error("Invalid JSON structure or missing 'type' field")
      return
    }
    
    do {
      switch typeString {
      case "system":
        processSystemMessage(
          json: json,
          lineData: lineData,
          subject: subject,
          decoder: decoder,
          logger: logger
        )
        
      case "user":
        let userMessage = try decoder.decode(UserMessage.self, from: lineData)
        logger?.debug("Received user message for session: \(userMessage.sessionId)")
        subject.send(.user(userMessage))
        
      case "assistant":
        let assistantMessage = try decoder.decode(AssistantMessage.self, from: lineData)
        logger?.debug("STREAMING CHUNK RECEIVED")
        
        // Process the content array directly
        for content in assistantMessage.message.content {
          switch content {
          case .text(let textContent, _):
            logger?.debug("CHUNK CONTENT: \(textContent)")
            logger?.debug("CONTENT LENGTH: \(textContent.count)")
          case .toolUse(let toolUse):
            logger?.debug("TOOL USE: \(toolUse.name)")
          case .toolResult(let toolResult):
            logger?.debug("TOOL RESULT: \(toolResult.content), Error: \(toolResult.isError ?? false)")
          case .thinking(let thinking):
            logger?.debug("THINKING: \(thinking.thinking.prefix(50))...")
          case .serverToolUse(let serverToolUse):
            logger?.debug("SERVER TOOL USE: \(serverToolUse.name)")
          case .webSearchToolResult(let searchResult):
            logger?.debug("WEB SEARCH RESULT: \(searchResult.content.count) results")
          }
        }
        
        logger?.debug("Received assistant message for session: \(assistantMessage.sessionId)")
        subject.send(.assistant(assistantMessage))
        
      case "result":
        let resultMessage = try decoder.decode(ResultMessage.self, from: lineData)
        logger?.info("Received result message: cost=\(resultMessage.costUsd), turns=\(resultMessage.numTurns)")
        subject.send(.result(resultMessage))
        
      default:
        logger?.warning("Unknown message type: \(typeString)")
      }
    } catch {
      // This catch block is now reachable since we have throwing calls in the do block
      handleJsonProcessingError(error: error, lineData: lineData, logger: logger)
    }
  }
  
  // Make processSystemMessage static
  private static func processSystemMessage(
    json: [String: Any],
    lineData: Data,
    subject: PassthroughSubject<ResponseChunk, Error>,
    decoder: JSONDecoder,
    logger: Logger?
  ) {
    guard let subtypeString = json["subtype"] as? String else {
      logger?.warning("System message missing subtype")
      return
    }
    
    do {
      if subtypeString == "init" {
        let initMessage = try decoder.decode(InitSystemMessage.self, from: lineData)
        logger?.info("Received init message with session ID: \(initMessage.sessionId)")
        subject.send(.initSystem(initMessage))
      } else {
        let resultMessage = try decoder.decode(ResultMessage.self, from: lineData)
        logger?.info("Received result message: cost=\(resultMessage.costUsd), turns=\(resultMessage.numTurns)")
        subject.send(.result(resultMessage))
      }
    } catch {
      logger?.error("Error decoding system message: \(error)")
    }
  }
  
  // Make handleJsonProcessingError static
  private static func handleJsonProcessingError(
    error: Error,
    lineData: Data,
    logger: Logger?
  ) {
    logger?.error("Error parsing JSON: \(error.localizedDescription)")
    
    if let decodingError = error as? DecodingError {
      switch decodingError {
      case .keyNotFound(let key, let context):
        logger?.error("Missing key: \(key.stringValue), path: \(context.codingPath.map { $0.stringValue })")
        
        // Debug JSON structure
        if let jsonObject = try? JSONSerialization.jsonObject(with: lineData),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
          logger?.error("JSON structure: \(prettyString)")
        }
        
      case .typeMismatch(let type, let context):
        logger?.error("Type mismatch: expected \(type), path: \(context.codingPath.map { $0.stringValue })")
        
      default:
        logger?.error("Other decoding error: \(decodingError)")
      }
    }
    
    if let lineString = String(data: lineData, encoding: .utf8) {
      logger?.error("Error on line: \(lineString.prefix(200))...")
    }
    logger?.error("Error details: \(error)")
  }
}
