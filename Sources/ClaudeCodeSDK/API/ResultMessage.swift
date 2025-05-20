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
}
