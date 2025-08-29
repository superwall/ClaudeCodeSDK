//
//  ClaudeSessionModels.swift
//  ClaudeCodeSDK
//
//  Created by Assistant on 8/18/2025.
//

import Foundation

/// Represents a stored Claude session from the native CLI storage
public struct ClaudeStoredSession: Identifiable, Codable {
  public let id: String
  public let projectPath: String
  public let createdAt: Date
  public let lastAccessedAt: Date
  public var summary: String?
  public var gitBranch: String?
  public var messages: [ClaudeStoredMessage]
  
  public init(
    id: String,
    projectPath: String,
    createdAt: Date = Date(),
    lastAccessedAt: Date = Date(),
    summary: String? = nil,
    gitBranch: String? = nil,
    messages: [ClaudeStoredMessage] = []
  ) {
    self.id = id
    self.projectPath = projectPath
    self.createdAt = createdAt
    self.lastAccessedAt = lastAccessedAt
    self.summary = summary
    self.gitBranch = gitBranch
    self.messages = messages
  }
}

/// Represents a message in a Claude session
public struct ClaudeStoredMessage: Identifiable, Codable {
  public let id: String // UUID from the jsonl file
  public let parentId: String?
  public let sessionId: String
  public let role: MessageRole
  public let content: String
  public let contentArray: [[String: Any]]? // Store structured content array for assistant messages
  public let timestamp: Date
  public let cwd: String?
  public let version: String?
  
  public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
  }
  
  public init(
    id: String,
    parentId: String? = nil,
    sessionId: String,
    role: MessageRole,
    content: String,
    contentArray: [[String: Any]]? = nil,
    timestamp: Date,
    cwd: String? = nil,
    version: String? = nil
  ) {
    self.id = id
    self.parentId = parentId
    self.sessionId = sessionId
    self.role = role
    self.content = content
    self.contentArray = contentArray
    self.timestamp = timestamp
    self.cwd = cwd
    self.version = version
  }
  
  // Custom coding to handle [String: Any]
  enum CodingKeys: String, CodingKey {
    case id, parentId, sessionId, role, content, contentArray, timestamp, cwd, version
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
    sessionId = try container.decode(String.self, forKey: .sessionId)
    role = try container.decode(MessageRole.self, forKey: .role)
    content = try container.decode(String.self, forKey: .content)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    version = try container.decodeIfPresent(String.self, forKey: .version)
    
    // Decode contentArray as JSONValue array
    if let jsonArray = try? container.decode([[String: JSONValue]].self, forKey: .contentArray) {
      contentArray = jsonArray.map { dict in
        dict.mapValues { $0.anyValue }
      }
    } else {
      contentArray = nil
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(parentId, forKey: .parentId)
    try container.encode(sessionId, forKey: .sessionId)
    try container.encode(role, forKey: .role)
    try container.encode(content, forKey: .content)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encodeIfPresent(cwd, forKey: .cwd)
    try container.encodeIfPresent(version, forKey: .version)
    // Note: contentArray encoding would require converting back to JSONValue
  }
}

/// Raw JSON structure from Claude's .jsonl files
internal struct ClaudeJSONLEntry: Codable {
  let type: String
  let uuid: String?
  let parentUuid: String?
  let sessionId: String?
  let timestamp: String?
  let cwd: String?
  let version: String?
  let gitBranch: String?
  let message: MessageContent?
  let summary: String?
  let leafUuid: String?
  let requestId: String?
  
  struct MessageContent: Codable {
    let role: String?
    let content: MessageContentValue?
  }
  
  enum MessageContentValue: Codable {
    case string(String)
    case array([ContentItem])
    
    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let stringValue = try? container.decode(String.self) {
        self = .string(stringValue)
      } else if let arrayValue = try? container.decode([ContentItem].self) {
        self = .array(arrayValue)
      } else {
        throw DecodingError.typeMismatch(
          MessageContentValue.self,
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Expected String or [ContentItem]"
          )
        )
      }
    }
    
    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .string(let value):
        try container.encode(value)
      case .array(let items):
        try container.encode(items)
      }
    }
    
    var textContent: String {
      switch self {
      case .string(let str):
        return str
      case .array(let items):
        return items.compactMap { $0.textContent }.joined(separator: "\n")
      }
    }
  }
  
  struct ContentItem: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: Any]?
    let tool_use_id: String?
    let content: [[String: Any]]?
    let is_error: Bool?
    let thinking: String?
    let signature: String?
    
    var textContent: String? {
      if type == "text" {
        return text
      }
      return nil
    }
    
    enum CodingKeys: String, CodingKey {
      case type, text, id, name, input
      case tool_use_id = "tool_use_id"
      case content
      case is_error = "is_error"
      case thinking, signature
    }
    
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      type = try container.decode(String.self, forKey: .type)
      text = try container.decodeIfPresent(String.self, forKey: .text)
      id = try container.decodeIfPresent(String.self, forKey: .id)
      name = try container.decodeIfPresent(String.self, forKey: .name)
      tool_use_id = try container.decodeIfPresent(String.self, forKey: .tool_use_id)
      is_error = try container.decodeIfPresent(Bool.self, forKey: .is_error)
      thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
      signature = try container.decodeIfPresent(String.self, forKey: .signature)
      
      // Decode input as Any
      if let inputValue = try? container.decode([String: JSONValue].self, forKey: .input) {
        input = inputValue.mapValues { $0.anyValue }
      } else {
        input = nil
      }
      
      // Decode content array
      if let contentValue = try? container.decode([[String: JSONValue]].self, forKey: .content) {
        content = contentValue.map { dict in
          dict.mapValues { $0.anyValue }
        }
      } else {
        content = nil
      }
    }
    
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(type, forKey: .type)
      try container.encodeIfPresent(text, forKey: .text)
      try container.encodeIfPresent(id, forKey: .id)
      try container.encodeIfPresent(name, forKey: .name)
      try container.encodeIfPresent(tool_use_id, forKey: .tool_use_id)
      try container.encodeIfPresent(is_error, forKey: .is_error)
      try container.encodeIfPresent(thinking, forKey: .thinking)
      try container.encodeIfPresent(signature, forKey: .signature)
      // Note: input and content encoding would require JSONValue conversion
    }
  }
}

// Helper for decoding arbitrary JSON
enum JSONValue: Codable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([JSONValue])
  case dictionary([String: JSONValue])
  case null
  
  var anyValue: Any {
    switch self {
    case .string(let s): return s
    case .int(let i): return i
    case .double(let d): return d
    case .bool(let b): return b
    case .array(let a): return a.map { $0.anyValue }
    case .dictionary(let d): return d.mapValues { $0.anyValue }
    case .null: return NSNull()
    }
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let str = try? container.decode(String.self) {
      self = .string(str)
    } else if let int = try? container.decode(Int.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let dict = try? container.decode([String: JSONValue].self) {
      self = .dictionary(dict)
    } else if container.decodeNil() {
      self = .null
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
    }
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .bool(let b): try container.encode(b)
    case .array(let a): try container.encode(a)
    case .dictionary(let d): try container.encode(d)
    case .null: try container.encodeNil()
    }
  }
}