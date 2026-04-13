//
//  texteenuApp.swift
//  texteenu
//
//  Created by Gonzalo Minuto on 4/12/26.
//

import SwiftUI

@main
struct texteenuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: AppViewModel(dependencies: .live()))
        }
    }
}
