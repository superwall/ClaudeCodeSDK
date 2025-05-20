//
//  ChatMessageRow.swift
//  ClaudeCodeSDKExample
//
//  Created by James Rochabrun on 5/20/25.
//

import Foundation
import SwiftUI

struct MessageRow: View {
  
  let message: ChatMessage
  
  var body: some View {
    HStack {
      if message.role == .user {
        Spacer()
        Text(message.content)
          .padding(10)
          .background(Color.blue)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      } else {
        VStack(alignment: .leading) {
          Text(message.content.isEmpty ? "..." : message.content)
            .padding(10)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          
          if !message.isComplete {
            ProgressView()
              .padding(.leading, 10)
          }
        }
        Spacer()
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
  }
}
