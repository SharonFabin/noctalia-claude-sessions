import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var sessions: mainInstance ? mainInstance.sessions : []
  property string searchQuery: ""
  readonly property var filteredSessions: {
    var list = searchQuery
      ? sessions.filter(function(s) {
          var q = searchQuery.toLowerCase()
          return (s.name && s.name.toLowerCase().indexOf(q) !== -1) ||
                 (s.tmux_session && s.tmux_session.toLowerCase().indexOf(q) !== -1)
        })
      : [].concat(sessions)
    list.sort(function(a, b) {
      return (b.last_activity || "").localeCompare(a.last_activity || "")
    })
    return list
  }
  readonly property bool panelReady: pluginApi !== null && mainInstance !== null && mainInstance !== undefined

  property int selectedIndex: 0

  property real contentPreferredWidth: panelReady ? 420 * Style.uiScaleRatio : 0
  property real contentPreferredHeight: panelReady ? Math.max(200, Math.min(500, 80 + sessions.length * 72)) * Style.uiScaleRatio : 0

  anchors.fill: parent

  onVisibleChanged: {
    if (visible) {
      searchInput.text = ""
      root.searchQuery = ""
      root.selectedIndex = 0
      searchInput.forceActiveFocus()
    }
  }

  readonly property string focusScript: pluginApi ? pluginApi.pluginDir + "/scripts/focus-session.sh" : ""

  function focusSession(pid, tmuxSession, tmuxWindow) {
    if (!root.focusScript || !pid) return
    focusProc.command = ["bash", root.focusScript, pid.toString(), tmuxSession || "", tmuxWindow || ""]
    focusProc.running = true
    if (pluginApi) pluginApi.closePanel(null)
  }

  function ensureVisible() {
    var item = sessionRepeater.itemAt(selectedIndex)
    if (!item || !sessionFlickable) return
    var itemTop = item.y
    var itemBottom = itemTop + item.height
    if (itemTop < sessionFlickable.contentY)
      sessionFlickable.contentY = itemTop
    else if (itemBottom > sessionFlickable.contentY + sessionFlickable.height)
      sessionFlickable.contentY = itemBottom - sessionFlickable.height
  }

  function selectCurrent() {
    if (filteredSessions.length === 0) return
    var idx = Math.min(selectedIndex, filteredSessions.length - 1)
    var s = filteredSessions[idx]
    if (s) focusSession(s.pid, s.tmux_session, s.tmux_window)
  }

  Process {
    id: focusProc
    running: false
  }

  function statusColor(status) {
    if (!status) return Color.mOnSurfaceVariant
    if (status.startsWith("thinking") || status.startsWith("tool:") || status === "started")
      return Color.mPrimary
    if (status === "resumed")
      return Color.mOnSurfaceVariant
    if (status.startsWith("awaiting_") || status === "idle:needs_input")
      return Color.mError
    if (status.startsWith("error:"))
      return Color.mError
    return Color.mOnSurfaceVariant
  }

  function statusIcon(status) {
    if (!status) return "circle"
    if (status.startsWith("tool:")) return "hammer"
    if (status === "thinking") return "brain"
    if (status === "started") return "player-play"
    if (status === "resumed") return "clock"
    if (status.startsWith("awaiting_permission")) return "lock"
    if (status.startsWith("awaiting_") || status === "idle:needs_input") return "bell"
    if (status.startsWith("error:")) return "alert-triangle"
    if (status === "idle" || status === "idle:awaiting_plan") return "clock"
    return "circle"
  }

  function statusLabel(status) {
    if (!status) return pluginApi?.tr("status.unknown") ?? "unknown"
    if (status.startsWith("tool:")) return status.substring(5)
    if (status === "idle:awaiting_plan") return pluginApi?.tr("status.planning") ?? "planning"
    if (status === "idle:needs_input") return pluginApi?.tr("status.needs-input") ?? "needs input"
    if (status === "awaiting_permission") return pluginApi?.tr("status.needs-permission") ?? "needs permission"
    if (status === "awaiting_input") return pluginApi?.tr("status.needs-input") ?? "needs input"
    if (status === "awaiting_mcp_input") return pluginApi?.tr("status.mcp-input") ?? "MCP input"
    if (status.startsWith("error:")) return pluginApi?.tr("status.error") ?? "error"
    return status
  }

  function cwdShort(cwd) {
    if (!cwd) return ""
    var parts = cwd.split("/")
    if (parts.length <= 2) return cwd
    return "~/" + parts.slice(-2).join("/")
  }

  function timeAgo(isoStr) {
    if (!isoStr) return ""
    var then = new Date(isoStr)
    var now = new Date()
    var diffSec = Math.floor((now - then) / 1000)
    if (diffSec < 60) return pluginApi?.tr("time.seconds", { n: diffSec }) ?? (diffSec + "s ago")
    if (diffSec < 3600) return pluginApi?.tr("time.minutes", { n: Math.floor(diffSec / 60) }) ?? (Math.floor(diffSec / 60) + "m ago")
    return pluginApi?.tr("time.hours", { n: Math.floor(diffSec / 3600) }) ?? (Math.floor(diffSec / 3600) + "h ago")
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"
    visible: panelReady

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginL

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: "sparkles"
          pointSize: Style.fontSizeL
          color: Color.mPrimary
        }

        NText {
          text: pluginApi?.tr("panel.title") ?? "Claude Sessions"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NText {
          text: sessions.length.toString()
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }
      }

      // Search
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: searchInput.implicitHeight + Style.marginS * 2
        radius: Style.radiusM
        color: searchInput.activeFocus ? Color.mSurface : Color.mSurfaceVariant
        border.color: searchInput.activeFocus ? Color.mPrimary : "transparent"
        border.width: searchInput.activeFocus ? 1 : 0
        visible: sessions.length > 1

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginS

          NIcon {
            icon: "search"
            color: searchInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
          }

          TextInput {
            id: searchInput
            Layout.fillWidth: true
            color: Color.mOnSurface
            font.pointSize: Style.fontSizeM
            clip: true
            onTextChanged: {
              root.searchQuery = text
              root.selectedIndex = 0
            }

            Keys.onPressed: (event) => {
              if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) {
                root.selectedIndex = Math.min(root.selectedIndex + 1, root.filteredSessions.length - 1)
                root.ensureVisible()
                event.accepted = true
              } else if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) {
                root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                root.ensureVisible()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.selectedIndex = Math.min(root.selectedIndex + 1, root.filteredSessions.length - 1)
                root.ensureVisible()
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                root.ensureVisible()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.selectCurrent()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (pluginApi) pluginApi.closePanel(null)
                event.accepted = true
              }
            }

            NText {
              anchors.fill: parent
              text: pluginApi?.tr("panel.search") ?? "Search sessions..."
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              visible: !searchInput.text
              opacity: 0.5
            }
          }
        }
      }

      // Session list
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
          id: sessionFlickable
          anchors.fill: parent
          anchors.margins: Style.marginS
          contentHeight: sessionColumn.implicitHeight
          clip: true

          ColumnLayout {
            id: sessionColumn
            width: parent.width
            spacing: Style.marginS

            // Empty state
            NText {
              visible: filteredSessions.length === 0
              text: searchQuery
                ? (pluginApi?.tr("panel.no-match") ?? "No matching sessions")
                : (pluginApi?.tr("panel.empty") ?? "No active sessions")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: Style.marginL
            }

            Repeater {
              id: sessionRepeater
              model: filteredSessions

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: sessionRow.implicitHeight + Style.marginM * 2
                radius: Style.radiusM
                color: {
                  if (index === root.selectedIndex) return Qt.alpha(Color.mPrimary, 0.1)
                  if (sessionMouse.containsMouse) return Color.mHover
                  return "transparent"
                }
                border.color: index === root.selectedIndex ? Qt.alpha(Color.mPrimary, 0.3) : "transparent"
                border.width: index === root.selectedIndex ? 1 : 0

                ColumnLayout {
                  id: sessionRow
                  anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: Style.marginS
                  }
                  spacing: 2

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                      icon: statusIcon(modelData.status)
                      color: statusColor(modelData.status)
                      pointSize: Style.fontSizeM
                    }

                    NText {
                      text: statusLabel(modelData.status)
                      color: statusColor(modelData.status)
                      pointSize: Style.fontSizeM
                      font.weight: Style.fontWeightMedium
                    }

                    Item { Layout.fillWidth: true }

                    NText {
                      text: timeAgo(modelData.last_activity)
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeS
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NText {
                      visible: !!modelData.name
                      text: modelData.name || ""
                      color: Color.mOnSurface
                      pointSize: Style.fontSizeS
                      font.weight: Style.fontWeightMedium
                    }

                    NText {
                      visible: !!modelData.tmux_session
                      text: modelData.tmux_session ? ("@ " + modelData.tmux_session) : ""
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeS
                      opacity: 0.7
                    }

                    NText {
                      text: cwdShort(modelData.cwd)
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeS
                      elide: Text.ElideMiddle
                      Layout.fillWidth: true
                    }
                  }

                  NText {
                    visible: modelData.context !== undefined && modelData.context !== ""
                    text: modelData.context || ""
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    opacity: 0.7
                  }
                }

                MouseArea {
                  id: sessionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.focusSession(modelData.pid, modelData.tmux_session, modelData.tmux_window)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
