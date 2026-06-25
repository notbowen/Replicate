//
//  ReplicateApp.swift
//  Replicate
//
//  Created by Hu Bowen on 24/6/26.
//

import SwiftUI

@main
struct ReplicateApp: App {
    @StateObject private var model = ReplicateAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSystemImage)
                .task {
                    model.start()
                }
        }
        .menuBarExtraStyle(.menu)

        Window("Replicate", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
