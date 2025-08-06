//
//  ContentView.swift
//  Swift6
//
//  Created by Keigo Nakagawa on 2025/07/30.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Button("#file, #filePath") {
                print(#file)     // Swift6/ContentView.swift（プロジェクトルートからの相対パス
                print(#filePath) // /Users/k5/develop/Swift6/Swift6/ContentView.swift（絶対パス
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
