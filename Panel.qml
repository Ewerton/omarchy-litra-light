import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar button + popup for the Litra light: whether a webcam turns it on, how
// bright and how warm it is, and which cameras count. The settings live in
// ~/.config/litra-light/config.json, written through bin/litra-light-ctl; the
// watcher that drives the light (started by Service.qml) reads that same file.
Panel {
  id: root
  moduleName: "ewer.litra-light"
  ipcTarget: "ewer.litra-light"

  readonly property string ctl: Qt.resolvedUrl("bin/litra-light-ctl").toString().replace("file://", "")
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/litra-light/config.json"
  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/litra-light/state"

  property bool triggerEnabled: true
  property int brightness: 20
  property int temperature: 6000
  property var disabledCameras: []
  property var cameras: []
  property bool lightOn: false
  property var queue: []

  readonly property string statusText: !triggerEnabled ? strings.t("status.disabled")
    : lightOn ? strings.t("status.on") : strings.t("status.off")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function applyConfig(raw) {
    var cfg = {}
    try { cfg = JSON.parse(raw) || {} } catch (e) {}
    triggerEnabled = cfg.enabled !== false
    brightness = Math.max(1, Math.min(100, Math.round(Number(cfg.brightness) || 20)))
    temperature = Math.max(2700, Math.min(6500, Math.round(Number(cfg.temperature) || 6000)))
    disabledCameras = Array.isArray(cfg.disabledCameras) ? cfg.disabledCameras : []
  }

  function refreshCameras() {
    camerasProc.running = false
    camerasProc.running = true
  }

  // Writes go through a queue so quick successive changes never overlap.
  function runCtl(args) {
    // A newer value for the same setting replaces one still waiting, so a drag
    // never builds a backlog of stale writes.
    if (args[0] === "set") queue = queue.filter(function(q) { return !(q[0] === "set" && q[1] === args[1]) })
    queue.push(args)
    drain()
  }

  function drain() {
    if (writer.running || queue.length === 0) return
    writer.command = [ctl].concat(queue.shift())
    writer.running = true
  }

  function setTriggerEnabled(value) {
    triggerEnabled = value
    runCtl(["set", "enabled", value ? "true" : "false"])
  }

  function setBrightness(value) {
    brightness = value
    runCtl(["set", "brightness", String(value)])
  }

  function setTemperature(value) {
    temperature = value
    runCtl(["set", "temperature", String(value)])
  }

  function cameraAllowed(id) { return disabledCameras.indexOf(id) < 0 }

  function setCameraAllowed(id, allowed) {
    var next = disabledCameras.filter(function(c) { return c !== id })
    if (!allowed) next.push(id)
    disabledCameras = next
    runCtl(["camera", id, allowed ? "on" : "off"])
  }

  onOpenedChanged: if (opened) refreshCameras()
  Component.onCompleted: refreshCameras()

  Process { id: writer; onExited: root.drain() }

  Process {
    id: camerasProc
    command: [root.ctl, "cameras"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          root.cameras = Array.isArray(list) ? list : []
        } catch (e) { root.cameras = [] }
      }
    }
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.lightOn = ["on", "manual"].indexOf(text().trim()) >= 0
    onLoadFailed: root.lightOn = false
  }

  // The bar sizes the widget from these; without them the button collapses.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-lightbulb_o; lit with the bar's active color while the light is on.
    text: ""
    tooltipText: ""
    active: root.opened || root.lightOn
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: ""
            color: root.bar.foreground
            opacity: root.lightOn ? 1 : 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Button {
            id: lightNow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.lightOn ? strings.t("light.off") : strings.t("light.on")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: root.lightOn
            onClicked: root.runCtl(["light", "toggle"])
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: lightNow.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: strings.t("title")
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.statusText.toUpperCase()
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Camera trigger ----------
        Toggle {
          width: parent.width
          label: strings.t("trigger.label")
          description: strings.t("trigger.description")
          checked: root.triggerEnabled
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.setTriggerEnabled(!root.triggerEnabled)
        }

        // ---------- Brightness ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: brightnessHeader.implicitHeight

            PanelSectionHeader {
              id: brightnessHeader
              text: strings.t("brightness")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
            }

            Text {
              textFormat: Text.PlainText
              text: Commons.I18n.formatNumber(Math.round(brightnessSlider.liveValue), 0) + "%"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.right: parent.right
              anchors.verticalCenter: brightnessHeader.verticalCenter
            }
          }

          PanelSlider {
            id: brightnessSlider
            width: parent.width
            bar: root.bar
            minimum: 1
            maximum: 100
            step: 5
            integer: true
            value: root.brightness
            // Send values while dragging (throttled) so the light follows live.
            onMoved: function(v) { brightnessDrag.pending = Math.round(v); brightnessDrag.start() }
            onReleased: function(v) { brightnessDrag.stop(); root.setBrightness(Math.round(v)) }

            Timer {
              id: brightnessDrag
              property int pending: 0
              interval: 200
              onTriggered: root.setBrightness(pending)
            }
          }
        }

        // ---------- Color temperature ----------
        // The slider counts in hundreds of kelvin: the light takes multiples of 100.
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: temperatureHeader.implicitHeight

            PanelSectionHeader {
              id: temperatureHeader
              text: strings.t("temperature")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
            }

            Text {
              textFormat: Text.PlainText
              text: Commons.I18n.formatNumber(Math.round(temperatureSlider.liveValue) * 100, 0) + " K"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.right: parent.right
              anchors.verticalCenter: temperatureHeader.verticalCenter
            }
          }

          PanelSlider {
            id: temperatureSlider
            width: parent.width
            bar: root.bar
            minimum: 27
            maximum: 65
            step: 1
            integer: true
            value: root.temperature / 100
            onMoved: function(v) { temperatureDrag.pending = Math.round(v) * 100; temperatureDrag.start() }
            onReleased: function(v) { temperatureDrag.stop(); root.setTemperature(Math.round(v) * 100) }

            Timer {
              id: temperatureDrag
              property int pending: 0
              interval: 200
              onTriggered: root.setTemperature(pending)
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Cameras ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: strings.t("cameras")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.cameras.length === 0
            textFormat: Text.PlainText
            text: strings.t("cameras.none")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.cameras

            Toggle {
              required property var modelData
              width: column.width
              label: modelData.name
              description: modelData.node
              checked: root.cameraAllowed(modelData.id)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.setCameraAllowed(modelData.id, !checked)
            }
          }
        }
      }
    }
  }
}
