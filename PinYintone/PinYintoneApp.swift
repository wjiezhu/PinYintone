//
//  PinYintoneApp.swift
//  PinYintone
//
//  Created by zhouo on 18/5/2026.
//

import SwiftUI
import CoreData

@main
struct PinYintoneApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
