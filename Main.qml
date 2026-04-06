import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  property int activeCount: 0
  property int idleCount: 0
  property int waitingCount: 0
  property int errorCount: 0
  property int totalCount: 0
  property var sessions: []

  readonly property string scriptPath: pluginApi ? pluginApi.pluginDir + "/scripts/scan-sessions.sh" : ""
  // cctop poller — runs as a child of Quickshell, dies and restarts with it
  property string pollerPath: ""
  Process {
    id: pollerFinder
    command: ["bash", "-c", "find ~/.claude/plugins -name cctop-poller.py -print -quit 2>/dev/null"]
    running: true
    stdout: SplitParser {
      onRead: data => {
        var path = data.trim()
        if (path) {
          root.pollerPath = path
          Logger.i("ClaudeSessions", "Found cctop poller: " + path)
        }
      }
    }
  }
  Process {
    id: pollerProc
    command: ["python3", root.pollerPath]
    running: root.pollerPath !== ""
  }

  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    running: root.scriptPath !== ""
    triggeredOnStart: true
    onTriggered: {
      scanner.running = true
    }
  }

  Process {
    id: scanner
    command: ["bash", root.scriptPath]
    running: false
    stdout: SplitParser {
      onRead: data => {
        try {
          var result = JSON.parse(data)
          root.activeCount = result.active || 0
          root.idleCount = result.idle || 0
          root.waitingCount = result.waiting || 0
          root.errorCount = result.error || 0
          root.totalCount = result.total || 0
          root.sessions = result.sessions || []
        } catch(e) {
          Logger.e("ClaudeSessions", "Parse error: " + e)
        }
      }
    }
  }

  IpcHandler {
    target: "plugin:claude-sessions"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(screen => {
          pluginApi.togglePanel(screen);
        });
      }
    }
  }

  Component.onCompleted: {
    Logger.i("ClaudeSessions", "Plugin loaded, poller started")
  }
}
