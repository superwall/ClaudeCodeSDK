//
//  ClaudeCodeClient.swift
//  ClaudeCodeSDK
//
import Foundation
import Combine
import OSLog
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

// MARK: ‑ Helpers

/// Wrapper representing the captured output of a subprocess.
private struct ProcessCapture {
  let stdout: String
  let stderr: String
  let exitCode: Int32
}

/// Modern async wrapper using swift-subprocess.
private func runProcess(
  executable: String,
  arguments: [String],
  environment: [String: String],
  workingDirectory: String?,
  stdin: String?
) async throws -> ProcessCapture {
  
  // Convert working directory to FilePath if provided
  let workingDir: FilePath? = workingDirectory.map { FilePath($0) }
  
  // Execute subprocess with correct API - handle input conditionally to avoid type inference issues
  let result: CollectedResult<StringOutput<UTF8>, StringOutput<UTF8>>
  
  if let inputString = stdin {
    result = try await run(
      .name(executable),
      arguments: Arguments(arguments),
      environment: .inherit.updating(environment),
      workingDirectory: workingDir,
      input: .string(inputString),
      output: .string,
      error: .string
    )
  } else {
    result = try await run(
      .name(executable),
      arguments: Arguments(arguments),
      environment: .inherit.updating(environment),
      workingDirectory: workingDir,
      input: .none,
      output: .string,
      error: .string
    )
  }
  
  // Extract exit code from TerminationStatus enum
  let exitCode: Int32
  switch result.terminationStatus {
  case .exited(let code):
    exitCode = Int32(code)
  case .unhandledException(let code):
    exitCode = Int32(code)
  }
  
  return ProcessCapture(
    stdout: result.standardOutput ?? "",
    stderr: result.standardError ?? "",
    exitCode: exitCode
  )
}

// MARK: ‑ Convenience

private extension String {
  /// Returns a shell‑escaped / quoted version for logging purposes.
  var shellEscaped: String {
    // Simple rule: wrap in double quotes & escape internal quotes
    "\"" + self.replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

private extension ClaudeCodeOutputFormat {
  /// `claude` expects   --output-format <value>
  var cliTokens: [String] {
    switch self {
    case .text:       return ["--output-format", "text"]
    case .json:       return ["--output-format", "json"]
    case .streamJson: return ["--output-format", "stream-json"]
    }
  }
}

// MARK: ‑ Concrete SDK client

public final class ClaudeCodeClient: ClaudeCode {
  
  // MARK: Stored
  
  private let decoder = JSONDecoder()
  private let logger  = Logger(subsystem: "com.yourcompany.ClaudeCodeClient", category: "ClaudeCode")
  private let workingDirectory: String?
  private var cancellables = Set<AnyCancellable>()
  
  // MARK: Init
  
  public init(workingDirectory: String = "/Users/jamesrochabrun/Desktop/git/ClaudeCodeSDK", debug: Bool = false) {
    self.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    if debug { logger.debug("Initialised ClaudeCodeClient (wd: \(self.workingDirectory ?? "<inherit>"))") }
  }
  
  // MARK: Helper
  
  private func configuredEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let defaultPath = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    if let existing = env["PATH"] {
      env["PATH"] = existing + ":" + defaultPath
    } else {
      env["PATH"] = defaultPath
    }
    return env
  }
  
  @inline(__always)
  private func ensureSuccess(_ capture: ProcessCapture) throws {
    guard capture.exitCode == 0 else {
      throw ClaudeCodeError.executionFailed(capture.stderr)
    }
  }
  
  // MARK: ‑ Public API (ClaudeCode)
  
  public func runWithStdin(
    stdinContent: String,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    let cmd = try makeCommand(additional: options, outputFormat: outputFormat)
    return try await executeClaude(arguments: cmd, outputFormat: outputFormat, stdin: stdinContent)
  }
  
  public func runSinglePrompt(
    prompt: String,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    let cmd = try makeCommand(additional: options, outputFormat: outputFormat, trailing: prompt)
    return try await executeClaude(arguments: cmd, outputFormat: outputFormat)
  }
  
  public func continueConversation(
    prompt: String?,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var cmd = try makeCommand(additional: options, outputFormat: outputFormat)
    cmd.append("--continue")
    if let p = prompt, !p.isEmpty { cmd.append(p) }
    return try await executeClaude(arguments: cmd, outputFormat: outputFormat)
  }
  
  public func resumeConversation(
    sessionId: String,
    prompt: String?,
    outputFormat: ClaudeCodeOutputFormat,
    options: ClaudeCodeOptions?
  ) async throws -> ClaudeCodeResult {
    var cmd = try makeCommand(additional: options, outputFormat: outputFormat)
    cmd.append(contentsOf: ["--resume", sessionId])
    if let p = prompt, !p.isEmpty { cmd.append(p) }
    return try await executeClaude(arguments: cmd, outputFormat: outputFormat)
  }
  
  public func listSessions() async throws -> [SessionInfo] {
    let capture = try await runProcess(
      executable: "claude",
      arguments: ["logs", "--output-format", "json"],
      environment: configuredEnvironment(),
      workingDirectory: workingDirectory,
      stdin: nil
    )
    
    try ensureSuccess(capture)
    
    guard let data = capture.stdout.data(using: .utf8) else {
      throw ClaudeCodeError.invalidOutput("Unable to UTF‑8 decode logs output")
    }
    do {
      return try decoder.decode([SessionInfo].self, from: data)
    } catch {
      throw ClaudeCodeError.jsonParsingError(error)
    }
  }
  
  public func cancel() {
    // Note: swift-subprocess runs are awaited, so cancellation would be handled
    // by canceling the enclosing Task that calls these methods
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()
  }
  
  // MARK: ‑ Internals
  
  /// Builds the base command array, inserting options & output‑format.
  private func makeCommand(additional options: ClaudeCodeOptions?, outputFormat: ClaudeCodeOutputFormat, trailing: String? = nil) throws -> [String] {
    var opts = options ?? ClaudeCodeOptions()
    opts.printMode = true
    if outputFormat == .streamJson { opts.verbose = true }
    
    var cmd = opts.toCommandArgs()
    cmd.append(contentsOf: outputFormat.cliTokens)   // <<‑ split token & value
    if let t = trailing, !t.isEmpty { cmd.append(t) }
    return cmd
  }
  
  private func executeClaude(
    arguments: [String],
    outputFormat: ClaudeCodeOutputFormat,
    stdin: String? = nil
  ) async throws -> ClaudeCodeResult {
    
    // —‑‑ Smart‑quoted log output ‑‑‑—
    let displayArgs = arguments.enumerated().map { idx, arg -> String in
      // Always quote the *last* token (prompt) so even "hi" gets wrapped.
      if idx == arguments.count - 1 {
        return arg.shellEscaped
      }
      // Quote only if needed for others (spaces or quotes)
      if arg.contains(where: { $0.isWhitespace || $0 == "\"" }) {
        return arg.shellEscaped
      }
      return arg
    }
    logger.info("Executing: claude \(displayArgs.joined(separator: " "))")
    
    let capture = try await runProcess(
      executable: "claude",
      arguments: arguments,
      environment: configuredEnvironment(),
      workingDirectory: workingDirectory,
      stdin: stdin
    )
    
    try ensureSuccess(capture)
    
    switch outputFormat {
    case .text:
      return .text(capture.stdout)
      
    case .json:
      guard let data = capture.stdout.data(using: .utf8) else {
        throw ClaudeCodeError.invalidOutput("Unable to UTF‑8 decode output")
      }
      do {
        return .json(try decoder.decode(ResultMessage.self, from: data))
      } catch {
        throw ClaudeCodeError.jsonParsingError(error)
      }
      
    case .streamJson:
      return try streamChunks(from: capture.stdout)
    }
  }
  
  // MARK: Stream‑JSON support → collect & replay
  
  private func streamChunks(from raw: String) throws -> ClaudeCodeResult {
    let lines = raw.split(separator: "\n")
    let chunks: [ResponseChunk] = try lines.compactMap { line in
      guard !line.isEmpty else { return nil }
      let data = Data(line.utf8)
      return try decodeChunk(from: data)
    }
    return .stream(Publishers.Sequence(sequence: chunks).eraseToAnyPublisher())
  }
  
  private func decodeChunk(from data: Data) throws -> ResponseChunk {
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let type = json?["type"] as? String else {
      throw ClaudeCodeError.invalidOutput("Missing `type` field in stream‑JSON")
    }
    
    switch type {
    case "system":   return .initSystem(try decoder.decode(InitSystemMessage.self, from: data))
    case "user":     return .user(try decoder.decode(UserMessage.self, from: data))
    case "assistant":return .assistant(try decoder.decode(AssistantMessage.self, from: data))
    case "result":   return .result(try decoder.decode(ResultMessage.self, from: data))
    default:          throw ClaudeCodeError.invalidOutput("Unknown stream‑JSON type \(type)")
    }
  }
}
