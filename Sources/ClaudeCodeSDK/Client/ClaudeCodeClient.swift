//
//  ClaudeCodeClient.swift
//  ClaudeCodeSDK
//
@preconcurrency import Combine
import Foundation
import os.log

/// Concrete implementation of ClaudeCodeSDK that uses the Claude Code CLI
public final class ClaudeCodeClient: ClaudeCode, @unchecked Sendable {
  private var task: Process?
  private var cancellables = Set<AnyCancellable>()
  private var logger: Logger?
  private let decoder = JSONDecoder()
  
  /// Configuration for the client - can be updated at any time
  public var configuration: ClaudeCodeConfiguration
  
  public init(configuration: ClaudeCodeConfiguration = .default) {
    self.configuration = configuration
    
    if configuration.enableDebugLogging {
      self.logger = Logger(subsystem: "com.yourcompany.ClaudeCodeClient", category: "ClaudeCode")
      logger?.info("Initializing Claude Code client")
    }
    
    decoder.keyDecodingStrategy = .convertFromSnakeCase
  }
  
  /// Convenience initializer for backward compatibility
  public convenience init(workingDirectory: String = "", debug: Bool = false) {
    var config = ClaudeCodeConfiguration.default
    config.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
    config.enableDebugLogging = debug
    self.init(configuration: config)
  }
  // MARK: - Protocol Implementation
  
  private func configuredProcess(for command: String) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", command]
    
    if let workingDirectory = configuration.workingDirectory {
      process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }
    
    var env = ProcessInfo.processInfo.environment
    
    // Add additional paths to PATH
    if !configuration.additionalPaths.isEmpty {
      let additionalPathString = configuration.additionalPaths.joined(separator: ":")
      if let currentPath = env["PATH"] {
        env["PATH"] = "\(currentPath):\(additionalPathString)"
      } else {
        env["PATH"] = "\(additionalPathString):/bin"
      }
    }
    
    // Apply custom environment variables
    for (key, value) in configuration.environment {
      env[key] = value
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
    let suffix = configuration.commandSuffix.map { " \($0)" } ?? ""
    let commandString = "\(configuration.command)\(suffix) \(argsString)"
    
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat,
      stdinContent: stdinContent,
      abortController: opts.abortController,
      timeout: opts.timeout
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
    
    // Do NOT append the prompt as a quoted argument!
    let suffix = configuration.commandSuffix.map { " \($0)" } ?? ""
    let argsString = args.joined(separator: " ")
    let commandString = "\(configuration.command)\(suffix) \(argsString)"
    
    // Always send the prompt via stdin
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat,
      stdinContent: prompt,
      abortController: opts.abortController,
      timeout: opts.timeout
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
    
    // Construct the full command (no prompt appended!)
    let suffix = configuration.commandSuffix.map { " \($0)" } ?? ""
    let argsString = args.joined(separator: " ")
    let commandString = "\(configuration.command)\(suffix) \(argsString)"
    
    // Pass prompt via stdin (or nil if not provided)
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat,
      stdinContent: prompt,
      abortController: opts.abortController,
      timeout: opts.timeout
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
    
    // Build the command without the prompt
    let suffix = configuration.commandSuffix.map { " \($0)" } ?? ""
    let argsString = args.joined(separator: " ")
    let commandString = "\(configuration.command)\(suffix) \(argsString)"
    
    // Use stdin for prompt
    return try await executeClaudeCommand(
      command: commandString,
      outputFormat: outputFormat,
      stdinContent: prompt,
      abortController: opts.abortController,
      timeout: opts.timeout
    )
  }
  
  public func listSessions() async throws -> [SessionInfo] {
    let suffix = configuration.commandSuffix.map { " \($0)" } ?? ""
    let commandString = "\(configuration.command)\(suffix) logs --output-format json"
    
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
      
      logger?.debug("Received session list output: \(output.prefix(10000))...")
      
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
  
  public func validateCommand(_ command: String) async throws -> Bool {
    // Use 'which' command to check if the command exists in PATH
    let checkCommand = "which \(command)"
    
    logger?.info("Validating command: \(command)")
    
    let process = configuredProcess(for: checkCommand)
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    do {
      try process.run()
      process.waitUntilExit()
      
      // 'which' returns 0 if command is found, non-zero otherwise
      let isValid = process.terminationStatus == 0
      
      if isValid {
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
          logger?.info("Command '\(command)' found at: \(path)")
        }
      } else {
        logger?.warning("Command '\(command)' not found in PATH")
        
        // Log current PATH for debugging
        if configuration.enableDebugLogging {
          let pathCheckCommand = "echo $PATH"
          let pathProcess = configuredProcess(for: pathCheckCommand)
          let pathPipe = Pipe()
          pathProcess.standardOutput = pathPipe
          
          try pathProcess.run()
          pathProcess.waitUntilExit()
          
          let pathData = pathPipe.fileHandleForReading.readDataToEndOfFile()
          if let currentPath = String(data: pathData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            logger?.debug("Current PATH: \(currentPath)")
          }
        }
      }
      
      return isValid
    } catch {
      logger?.error("Error validating command '\(command)': \(error.localizedDescription)")
      throw ClaudeCodeError.executionFailed("Failed to validate command: \(error.localizedDescription)")
    }
  }
  
  private func executeClaudeCommand(
    command: String,
    outputFormat: ClaudeCodeOutputFormat,
    stdinContent: String? = nil,
    abortController: AbortController? = nil,
    timeout: TimeInterval? = nil
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
    
    // Set up abort controller handling
    if let abortController = abortController {
      abortController.signal.onAbort { [weak self] in
        self?.task?.terminate()
      }
    }
    
    // Set up timeout handling
    var timeoutTask: Task<Void, Never>?
    if let timeout = timeout {
      timeoutTask = Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        if !Task.isCancelled && process.isRunning {
          logger?.warning("Process timed out after \(timeout) seconds")
          process.terminate()
        }
      }
    }
    
    do {
      // Handle stream-json differently
      if outputFormat == .streamJson {
        let result = try await handleStreamJsonOutput(
          process: process,
          outputPipe: outputPipe,
          errorPipe: errorPipe,
          abortController: abortController,
          timeout: timeout
        )
        timeoutTask?.cancel()
        return result
      } else {
        // For text and json formats, run synchronously
        try process.run()
        process.waitUntilExit()
        
        // Cancel timeout task
        timeoutTask?.cancel()
        
        if process.terminationStatus != 0 {
          let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
          let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
          
          // Check if it was a timeout
          if let timeout = timeout,
             errorString.isEmpty && !process.isRunning {
            throw ClaudeCodeError.timeout(timeout)
          }
          
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
    errorPipe: Pipe,
    abortController: AbortController? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> ClaudeCodeResult {
    // Create a publisher for streaming JSON
    let subject = PassthroughSubject<ResponseChunk, Error>()
    let publisher = subject.eraseToAnyPublisher()
    
    // Create a stream buffer
    let streamBuffer = StreamBuffer()
    
    // Capture values to avoid capturing self in @Sendable closures
    let decoder = self.decoder
    let logger = self.logger
    
    // Configure error handler first
    errorPipe.fileHandleForReading.readabilityHandler = { errorHandle in
      let errorData = errorHandle.availableData
      if !errorData.isEmpty {
        if let errorString = String(data: errorData, encoding: .utf8) {
          logger?.error("Claude stderr: \(errorString)")
          print("Claude stderr: \(errorString)")
        }
      }
    }
    
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
      print("Starting stream process...")
      print("Process working dir: \(process.currentDirectoryURL?.path ?? "none")")
      try process.run()
      self.task = process
      print("Stream process started with PID: \(process.processIdentifier)")
    } catch {
      logger?.error("Failed to start process: \(error.localizedDescription)")
      print("Failed to start process: \(error.localizedDescription)")
      
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
    
    print("=== Processing JSON line: \(line.prefix(200))...")
    logger?.debug("Processing JSON line: \(line.prefix(10000))...")
    
    guard let lineData = line.data(using: .utf8) else {
      print("ERROR: Could not convert line to data")
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
            switch toolResult.content {
            case .string(let value):
              logger?.debug("TOOL RESULT: \(value), Error: \(toolResult.isError ?? false)")
            case .items(let items):
              for item in items {
                logger?.debug("TOOL RESULT: \(item.title ?? "No title for tool") response: \(item.text ?? "No text"), Error: \(toolResult.isError ?? false)")
              }
            }
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
        logger?.info("Received result message: cost=\(resultMessage.totalCostUsd), turns=\(resultMessage.numTurns)")
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
        let log = "Received result message: cost=\(resultMessage.totalCostUsd), turns=\(resultMessage.numTurns)"
        logger?.info("\(log)")
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
      logger?.error("Error on line: \(lineString.prefix(10000))...")
    }
    logger?.error("Error details: \(error)")
  }
}
