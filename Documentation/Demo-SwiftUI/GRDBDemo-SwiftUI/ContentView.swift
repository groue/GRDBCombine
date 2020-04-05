//
//  ContentView.swift
//  GRDBDemo-SwiftUI
//
//  Created by Toby Brennan on 5/4/20.
//  Copyright © 2020 Github-ApptekStudios. All rights reserved.
//

import SwiftUI
import GRDB
import GRDBCombine

struct ContentViewModel {
	/// A Hall of Fame
	struct HallOfFame {
		/// Total number of players
		var playerCount: Int = 0
		
		/// The best ones
		var bestPlayers: [Player] = []
	}
	
	/// A publisher that tracks changes in the Hall of Fame
	static func hallOfFameRequest(database: AppDatabase, maxPlayerCount: Int) -> DatabaseRequest<HallOfFame> {
		DatabaseRequest(db: database.db, defaultValue: HallOfFame()) { db -> HallOfFame in
			let playerCount = try Player.fetchCount(db)
			let bestPlayers = try Player
				.limit(maxPlayerCount)
				.orderedByScore()
				.fetchAll(db)
			return HallOfFame(playerCount: playerCount, bestPlayers: bestPlayers)
		}
	}
}

struct ContentView: View {
	@ObservedObject var databaseRequest = ContentViewModel.hallOfFameRequest(database: AppDatabase.shared, maxPlayerCount: 100)

	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				list
				count
				toolbar
			}
			.navigationBarItems(trailing: EditButton())
			.navigationBarTitle(Text("Leaderboard"))
		}
	}
	
	var count: some View {
		Text("\(databaseRequest.result.playerCount) \(databaseRequest.result.playerCount == 1 ? "Player" : "Players") in total")
			.padding()
			.frame(maxWidth: .infinity)
			.background(Color(.secondarySystemBackground))
	}
	
	var list: some View {
		List {
			ForEach(databaseRequest.result.bestPlayers) {
				PlayerRow(player: $0)
			}
			.onDelete { indexSet in
				let toDelete = indexSet.map { self.databaseRequest.result.bestPlayers[$0] }
				
				do {
					//You should probably handle this in your data controller rather than in the view code
					try AppDatabase.shared.db.write { db in
						toDelete.forEach { player in
							do {
								try player.delete(db)
							}
							catch {
								//Catch errors here so that the forEach completes as expected
							}
						}
					}
				}
				catch {
					// Handle any errors if considered important
				}
			}
		}
	}
	
	var toolbar: some View {
		HStack {
			Button(
				action: { try? Players(database: AppDatabase.shared).deleteAll() },
				label: { Image(systemName: "trash")})
			Spacer()
			Button(
				action: { try? Players(database: AppDatabase.shared).refresh() },
				label: { Image(systemName: "arrow.clockwise")})
			Spacer()
			Button(
				action: { Players(database: AppDatabase.shared).stressTest() },
				label: { Text("💣") })
		}
		.padding()
	}
}

struct PlayerRow: View {
	var player: Player
	
	var body: some View {
		NavigationLink(destination: PlayerEditingView(player: DatabaseEditable(database: AppDatabase.shared.db, value: player, autoSave: false))) {
			HStack {
				Text(player.name)
				Spacer()
				Text("\(player.score)")
			}
		}
	}
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
