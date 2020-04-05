//
//  PlayerEditingView.swift
//  GRDBDemo-SwiftUI
//
//  Created by Toby Brennan on 5/4/20.
//  Copyright © 2020 Github-ApptekStudios. All rights reserved.
//

import SwiftUI
import GRDBCombine

struct PlayerEditingView: View {
	@ObservedObject
	var player: DatabaseEditable<Player>
	
	@Environment(\.presentationMode) var presentation
	
	var scoreAsString: Binding<String> {
		Binding(get: {
			return "\(self.player.score)"
		}) { (newValue) in
			if let int = Int(newValue) {
				self.player.score = int
			}
		}
	}
	
    var body: some View {
		NavigationView {
			Form {
				HStack {
					Text("Player name").layoutPriority(1)
					Spacer()
					TextField("Player name", text: $player.name)
						.multilineTextAlignment(.trailing)
				}
				HStack {
					Text("Player score").layoutPriority(1)
					Spacer()
					TextField("Player score", text: scoreAsString)
						.multilineTextAlignment(.trailing)
				}
				Button(action: {
					do {
						try self.player.commitChanges()
						self.presentation.wrappedValue.dismiss()
					}
					catch {
						// Do something if unable to save (eg. notify user)
					}
					
				}) {
					Text("Apply Changes")
				}
			}
			.textFieldStyle(RoundedBorderTextFieldStyle())
			.navigationBarTitle("Edit player")
		}
    }
}

struct PlayerEditingView_Previews: PreviewProvider {
    static var previews: some View {
		PlayerEditingView(player: .init(database: AppDatabase.shared.db, value: Player(name: "Test player", score: 99)))
    }
}

import GRDB
