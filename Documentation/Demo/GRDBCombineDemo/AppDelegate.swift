import UIKit
import Combine
import GRDB

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Setup the Current world
        let dbPool = try! setupDatabase(application)
        Current = World(database: { dbPool })
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: - Database
    
    private func setupDatabase(_ application: UIApplication) throws -> DatabasePool {
        let databaseURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("db.sqlite")
        let dbPool = try AppDatabase.openDatabase(atPath: databaseURL.path)
        
        // Be a nice iOS citizen, and don't consume too much memory
        // See https://github.com/groue/GRDB.swift/blob/master/README.md#memory-management
        dbPool.setupMemoryManagement(in: application)
        
        return dbPool
    }

    // MARK: - IBActions
    
    @IBAction func deletePlayers() {
        try! Current.players().deleteAll()
    }
    
    @IBAction func refreshPlayers() {
        try! Current.players().refresh()
    }
    
    @IBAction func stressTest() {
        Current.players().stressTest()
    }
}

/// Convenience of view controllers
let playerEditionToolbarItems = [
    UIBarButtonItem(barButtonSystemItem: .trash, target: nil, action: #selector(AppDelegate.deletePlayers)),
    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
    UIBarButtonItem(barButtonSystemItem: .refresh, target: nil, action: #selector(AppDelegate.refreshPlayers)),
    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
    UIBarButtonItem(title: "💣", style: .plain, target: nil, action: #selector(AppDelegate.stressTest)),
]
