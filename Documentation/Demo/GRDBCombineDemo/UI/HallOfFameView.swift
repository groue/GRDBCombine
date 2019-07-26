import SwiftUI

struct HallOfFameView: View {
    @ObjectBinding var viewModel: HallOfFameViewModel
    
    var body: some View {
        VStack {
            list
            toolbar
        }
        .navigationBarTitle(Text(viewModel.title))
    }
    
    var list: some View {
        List(viewModel.bestPlayers, id: \.id) {
            PlayerRow(player: $0)
        }
    }
    
    var toolbar: some View {
        HStack {
            Button(
                action: { try! Current.players().deleteAll() },
                label: { Image(systemName: "trash")})
            Spacer()
            Button(
                action: { try! Current.players().refresh() },
                label: { Image(systemName: "arrow.clockwise")})
            Spacer()
            Button(
                action: { Current.players().stressTest() },
                label: { Text("💣") })
        }
        .padding()
    }
}

struct PlayerRow: View {
    var player: Player
    
    var body: some View {
        HStack {
            Text(player.name)
            Spacer()
            Text("\(player.score)")
        }
    }
}
