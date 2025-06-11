//
//  Created by ktiays on 2025/6/11.
//  Copyright (c) 2025 ktiays. All rights reserved.
// 

import SwiftUI
import ObjcRuntimeClassDump

struct ContentView: View {
    var body: some View {
        ZStack {
            
        }
        .task {
            let temporaryDirectory = NSTemporaryDirectory()
            objc_dump_class(UIView.self, temporaryDirectory)
            print("Dumped UIView class to: \(temporaryDirectory)")
        }
    }
}

#Preview {
    ContentView()
}
