import Combine
import SwiftUI

// Native menu commands share navigation with the bundled WebKit interface.
enum SidebarSelection: String {
  case wallpaper, workshop, pixiv, display, settings
}

enum SettingsSection: String, CaseIterable {
  case performance, general, appearance, displays, library, storage, about
}

@MainActor
final class ControlPanelNavigation: ObservableObject {
  @Published var selection: SidebarSelection?
  @Published var targetDisplayID = "primary"
  var isImporting = false
  @Published private(set) var settingsSection = SettingsSection.performance
  @Published private(set) var settingsSectionToken: UInt64 = 0

  init(selection: SidebarSelection? = .wallpaper) { self.selection = selection }

  func revealSettingsSection(_ section: SettingsSection) {
    settingsSection = section
    settingsSectionToken &+= 1
  }
}

struct ControlPanelView: View {
  let store: BridgeStore
  @ObservedObject var navigation: ControlPanelNavigation
  let workshop: WorkshopStore
  let pixiv: PixivStore
  let updater: AppUpdateStore

  init(
    store: BridgeStore, navigation: ControlPanelNavigation, workshop: WorkshopStore,
    pixiv: PixivStore, updater: AppUpdateStore
  ) {
    self.store = store
    self.navigation = navigation
    self.workshop = workshop
    self.pixiv = pixiv
    self.updater = updater
  }

  var body: some View {
    WebControlPanel(
      store: store, navigation: navigation, workshop: workshop, pixiv: pixiv, updater: updater)
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      // The page owns the title-bar strip; the window only keeps the traffic lights there.
      .ignoresSafeArea()
  }
}
