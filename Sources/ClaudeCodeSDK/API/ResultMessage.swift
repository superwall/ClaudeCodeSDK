//
//  ResultMessage.swift
//  ClaudeCodeSDK
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation

public struct ResultMessage: Codable {
  public let type: String
  public let subtype: String
  public let costUsd: Double
  public let durationMs: Double
  public let durationApiMs: Double
  public let isError: Bool
  public let numTurns: Int
  public let result: String?
  public let sessionId: String
  public let totalCost: Double?
  
  /// Returns a formatted description of the result message with key information
  public func description() -> String {
    let resultText = result ?? "No result available"
    let durationSeconds = durationMs / 1000.0
    let durationApiSeconds = durationApiMs / 1000.0
    
    return """
    Result: \(resultText) \n\n
    Subtype: \(subtype), 
    Cost: $\(String(format: "%.6f", costUsd)),
    Duration: \(String(format: "%.2f", durationSeconds))s, 
    API Duration: \(String(format: "%.2f", durationApiSeconds))s
    Error: \(isError ? "Yes" : "No")
    Number of Turns: \(numTurns)
    Total Cost: $\(String(format: "%.6f", totalCost ?? costUsd))
    """
  }
}
