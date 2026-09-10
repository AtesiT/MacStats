import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("MacStats")
                .font(.headline)

            Divider()

            Text("Cтатистика")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}

#Preview {
    ContentView()
}
