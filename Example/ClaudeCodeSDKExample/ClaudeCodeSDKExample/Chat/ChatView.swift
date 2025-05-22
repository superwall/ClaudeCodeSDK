//
//  ChatView.swift
//  ClaudeCodeSDKExample
//
//  Created by James Rochabrun on 5/20/25.
//

import ClaudeCodeSDK
import Foundation
import SwiftUI

struct ChatView: View {

  @State var viewModel = ChatViewModel(claudeClient: ClaudeCodeClient(debug: true))
  @State private var messageText: String = ""
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    VStack {

      // Chat messages list
      ScrollViewReader { scrollView in
        List {
          ForEach(viewModel.messages) { message in
            MessageRow(message: message)
              .id(message.id)
          }
        }
        .onChange(of: viewModel.messages) { _, newMessages in
          // Scroll to bottom when new messages are added
          if let lastMessage = viewModel.messages.last {
            withAnimation {
              scrollView.scrollTo(lastMessage.id, anchor: .bottom)
            }
          }
        }
      }
      .listStyle(PlainListStyle())

      // Error message if present
      if let error = viewModel.error {
        Text(error.localizedDescription)
          .foregroundColor(.red)
          .padding()
      }

      // Input area
      HStack {
        TextField("Type a message...", text: $messageText)
          .padding(10)
          .cornerRadius(20)
          .focused($isTextFieldFocused)
          .onSubmit {
            sendMessage()
          }
          .submitLabel(.send)

        if viewModel.isLoading {
          Button(action: {
            viewModel.cancelRequest()
          }) {
            Image(systemName: "stop.fill")
              .foregroundColor(.red)
          }
          .padding(10)
        } else {
          Button(action: {
            sendMessage()
          }) {
            Image(systemName: "arrow.up.circle.fill")
              .foregroundColor(.blue)
              .font(.title2)
          }
          .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding()
    }
    .navigationTitle("Claude Code Chat")
  }

  private func sendMessage() {
    let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    viewModel.sendMessage(text)
    messageText = ""
  }
}
