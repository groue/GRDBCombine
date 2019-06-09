import SwiftUI
import GRDBCombine

struct HallOfFameView: View {
    @EnvironmentObject var viewModel: HallOfFameViewModel
    
    var body: some View {
        VStack {
            NavigationView {
                List(viewModel.bestPlayers.identified(by: \.id)) {
                    PlayerRow(player: $0)
                    }
                    .navigationBarTitle(Text(viewModel.title))
            }
            Spacer()
            HStack {
                Button(
                    action: { Players.deletePlayers() },
                    label: { Text("Delete All") })
                Spacer()
                Button(
                    action: { Players.refreshPlayers() },
                    label: { Text("Refresh") })
                }
                .padding()
        }
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
