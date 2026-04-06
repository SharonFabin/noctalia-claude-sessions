import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property int editPollInterval: cfg.pollInterval ?? defaults.pollInterval ?? 2

  spacing: Style.marginL

  NSlider {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.poll-interval.label")
    description: pluginApi?.tr("settings.poll-interval.desc")
    from: 1
    to: 10
    stepSize: 1
    value: root.editPollInterval
    onValueChanged: root.editPollInterval = value
  }

  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.pollInterval = root.editPollInterval
    pluginApi.saveSettings()
  }
}
