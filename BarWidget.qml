import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property int activeCount: mainInstance ? mainInstance.activeCount : 0
  readonly property int idleCount: mainInstance ? mainInstance.idleCount : 0
  readonly property int waitingCount: mainInstance ? mainInstance.waitingCount : 0
  readonly property int errorCount: mainInstance ? mainInstance.errorCount : 0
  readonly property int totalCount: mainInstance ? mainInstance.totalCount : 0

  readonly property string screenName: screen?.name ?? ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  readonly property real contentWidth: {
    if (isVertical) return capsuleHeight
    return contentRow.implicitWidth + Style.marginM * 2
  }
  readonly property real contentHeight: capsuleHeight

  implicitWidth: isVertical ? capsuleHeight : contentWidth
  implicitHeight: isVertical ? contentHeight : capsuleHeight

  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    radius: Style.radiusL
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS
      layoutDirection: Qt.LeftToRight

      NIcon {
        icon: "sparkles"
        applyUiScale: false
        color: {
          if (root.waitingCount > 0) return Color.mError
          if (root.activeCount > 0) return Color.mPrimary
          return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
        }
      }

      // Active count
      RowLayout {
        visible: !root.isVertical && root.activeCount > 0
        spacing: 2
        NText {
          text: "\u25CF"
          color: Color.mPrimary
          pointSize: root.barFontSize * 0.8
        }
        NText {
          text: root.activeCount.toString()
          color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
          pointSize: root.barFontSize
          family: Settings.data.ui.fontFixed
        }
      }

      // Idle count
      RowLayout {
        visible: !root.isVertical && root.idleCount > 0
        spacing: 2
        NText {
          text: "\u25CB"
          color: Color.mOnSurfaceVariant
          pointSize: root.barFontSize * 0.8
        }
        NText {
          text: root.idleCount.toString()
          color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
          pointSize: root.barFontSize
          family: Settings.data.ui.fontFixed
        }
      }

      // Waiting count
      RowLayout {
        visible: !root.isVertical && root.waitingCount > 0
        spacing: 2
        NText {
          text: "\u25C6"
          color: Color.mError
          pointSize: root.barFontSize * 0.8
        }
        NText {
          text: root.waitingCount.toString()
          color: Color.mError
          pointSize: root.barFontSize
          family: Settings.data.ui.fontFixed
        }
      }

      // Error count
      RowLayout {
        visible: !root.isVertical && root.errorCount > 0
        spacing: 2
        NText {
          text: "\u2716"
          color: Color.mError
          pointSize: root.barFontSize * 0.8
        }
        NText {
          text: root.errorCount.toString()
          color: Color.mError
          pointSize: root.barFontSize
          family: Settings.data.ui.fontFixed
        }
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu
    model: [
      { "label": pluginApi?.tr("menu.settings"), "action": "settings", "icon": "settings" }
    ]
    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest)
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onEntered: {
      var parts = []
      if (root.activeCount > 0)
        parts.push(pluginApi?.tr("widget.tooltip.active", { count: root.activeCount }))
      if (root.idleCount > 0)
        parts.push(pluginApi?.tr("widget.tooltip.idle", { count: root.idleCount }))
      if (root.waitingCount > 0)
        parts.push(pluginApi?.tr("widget.tooltip.waiting", { count: root.waitingCount }))
      if (root.errorCount > 0)
        parts.push(pluginApi?.tr("widget.tooltip.error", { count: root.errorCount }))
      if (parts.length === 0)
        parts.push(pluginApi?.tr("widget.tooltip.none"))
      var tip = pluginApi?.tr("widget.tooltip.prefix") + ": " + parts.join(", ")
      TooltipService.show(root, tip, BarService.getTooltipDirection())
    }
    onExited: TooltipService.hide()

    onClicked: (mouse) => {
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) pluginApi.togglePanel(root.screen, root)
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }
  }
}
