import QtQuick
import Quickshell.Io

// Keeps bin/litra-light-watcher running for as long as the plugin is enabled, so
// the light follows the camera whether or not the widget is on the bar.
Item {
  id: root

  // Injected by omarchy-shell (the service loader).
  property var shell: null
  property var manifest: null

  Process {
    id: watcher
    running: true
    command: [Qt.resolvedUrl("bin/litra-light-watcher").toString().replace("file://", "")]
    // Restart if it ever exits; the watcher only stops on a real failure.
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: watcher.running = true
  }
}
