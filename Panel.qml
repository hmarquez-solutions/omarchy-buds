import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.hmarquez-solutions.buds"
  ipcTarget: "buds"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", true) === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barIconColor: buds.hasBuds ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Say nothing extra once a section already explains the state.
  readonly property bool guidanceVisible: !buds.hasBuds && !buds.schemaUnsupported

  property int phraseIndex: 0

  readonly property int lowBatteryPercent: 20
  readonly property int phraseIntervalMs: 2800

  // Ten, matching the stock panels.
  readonly property var activePhrases: [
    "Galaxy brain engaged",
    "Bixby was not invited",
    "Blades out",
    "Cancelling the noise",
    "One UI, zero phones",
    "Ambient and aware",
    "Charged and paired",
    "Wearable, wearing",
    "Seamless enough",
    "Buds up"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property bool modesVisible: buds.hasBuds && buds.availableModes.length > 0
  readonly property bool ambientVisible: buds.hasBuds && buds.can("ambient_volume") && buds.noiseMode === "ambient"
  readonly property bool conversationVisible: buds.hasBuds && buds.can("conversation_detect")
  readonly property bool oneBudVisible: buds.hasBuds && buds.can("one_bud_anc")
  readonly property bool touchVisible: buds.hasBuds && buds.can("touch_lock")
  readonly property bool eqVisible: buds.hasBuds && buds.can("equalizer")
  readonly property bool findVisible: buds.hasBuds && buds.can("find")
  readonly property bool togglesVisible: conversationVisible || oneBudVisible || touchVisible
  readonly property bool valuesVisible: eqVisible || findVisible

  // Rebuilt whenever a section appears, so j and k never land on a hidden control.
  readonly property var cursorRows: {
    var rows = []
    if (!buds.hasBuds) return rows
    for (var i = 0; i < buds.availableModes.length; i++) rows.push("mode:" + buds.availableModes[i])
    if (ambientVisible) rows.push("ambient")
    if (conversationVisible) rows.push("conversation")
    if (oneBudVisible) rows.push("onebud")
    if (touchVisible) rows.push("touch")
    if (eqVisible) rows.push("eq")
    if (findVisible) rows.push("find")
    return rows
  }

  readonly property string cursorRow: cursorRows.length === 0
    ? ""
    : cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) {
    return cursorActive && cursorRow === name
  }

  function moveCursor(dy) {
    cursorActive = true
    if (cursorRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
  }

  function nudgeCursor(dx) {
    if (cursorRow === "ambient") buds.setAmbientVolume(buds.ambientVolume + dx)
  }

  function activateCursor() {
    var name = cursorRow
    if (name.indexOf("mode:") === 0) buds.setNoiseMode(name.substring(5))
    else if (name === "conversation") buds.setConversationDetect(!buds.conversationDetect)
    else if (name === "onebud") buds.setOneBudAnc(!buds.oneBudAnc)
    else if (name === "touch") buds.setTouchLocked(!buds.touchLocked)
    else if (name === "eq") buds.cycleEqPreset()
    else if (name === "find") buds.toggleFinding()
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
  }

  visible: !hideWhenDisconnected || buds.hasBuds
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    buds.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: buds
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { buds.refresh(); return "ok" }
    function noise(): string { buds.cycleNoiseMode(); return "ok" }
    function status(): string { return buds.hasBuds ? Model.noiseModeName(buds.noiseMode) : "disconnected" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        BudsIcon {
          anchors.centerIn: parent
          // A pair of buds is wider than it is tall, so it takes a size above the stock 12 to carry the row.
          iconSize: Style.space(13)
          color: root.barIconColor
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) buds.cycleNoiseMode()
      else if (buttonCode === Qt.MiddleButton) buds.setTouchLocked(!buds.touchLocked)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.nudgeCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") buds.refresh()
        else if (!buds.hasBuds) return
        // The mode keys need no capability check of their own: setNoiseMode drops a mode this device does not have.
        else if (Model.NOISE_KEYS[key] !== undefined) buds.setNoiseMode(Model.NOISE_KEYS[key])
        else if (key === "c") buds.setConversationDetect(!buds.conversationDetect)
        else if (key === "b") buds.setOneBudAnc(!buds.oneBudAnc)
        else if (key === "l") buds.setTouchLocked(!buds.touchLocked)
        else if (key === "e") buds.cycleEqPreset()
        else if (key === "f") buds.toggleFinding()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: buds.modelName !== "" ? buds.modelName : (buds.deviceName !== "" ? buds.deviceName : "Galaxy Buds")
            meta: buds.hasBuds ? root.heroPhraseText
              : buds.schemaUnsupported ? "Unsupported status schema"
              : buds.daemonReachable ? "Not connected"
              : "omarchy-buds is not running"
            detail: buds.hasBuds && buds.deviceName !== "" && buds.deviceName !== buds.modelName ? buds.deviceName : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: buds.hasBuds ? 1.0 : 0.5
            iconComponent: Component {
              BudsIcon {
                iconSize: Style.font.displayLarge
                color: buds.hasBuds ? root.foreground : root.dim
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            // A command failure gets its own field, or the next status read wipes it unread.
            visible: buds.actionStatus !== "" || (buds.lastError !== "" && buds.daemonReachable)
            width: parent.width
            text: buds.actionStatus !== "" ? buds.actionStatus : buds.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: buds.hasBattery
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "BATTERY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              BudRow { width: parent.width; label: "Left"; level: buds.leftBud.level; charging: buds.leftBud.charging; meta: Model.budMeta(buds.leftBud) }
              BudRow { width: parent.width; label: "Right"; level: buds.rightBud.level; charging: buds.rightBud.charging; meta: Model.budMeta(buds.rightBud) }
              BudRow { width: parent.width; label: "Case"; level: buds.caseBattery.level; charging: buds.caseBattery.charging; meta: Model.caseMeta(buds.caseBattery) }
            }
          }

          PanelSeparator {
            visible: buds.hasBattery && root.modesVisible
            foreground: root.foreground
          }

          Column {
            visible: root.modesVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "NOISE CONTROL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: buds.availableModes
                ModeRow {
                  required property var modelData
                  width: parent.width
                  mode: modelData
                }
              }
            }

            SliderRow {
              visible: root.ambientVisible
              width: parent.width
            }
          }

          PanelSeparator {
            visible: root.togglesVisible
            foreground: root.foreground
          }

          Column {
            visible: root.togglesVisible
            width: parent.width
            spacing: Style.space(6)

            ToggleRow {
              visible: root.conversationVisible
              width: parent.width
              rowName: "conversation"
              label: "Voice detect"
              caption: "Switch to Ambient sound when you start talking"
              checked: buds.conversationDetect
              onToggled: buds.setConversationDetect(!buds.conversationDetect)
            }

            ToggleRow {
              visible: root.oneBudVisible
              width: parent.width
              rowName: "onebud"
              label: "One-bud noise controls"
              caption: "Keep noise controls on with one bud in"
              checked: buds.oneBudAnc
              onToggled: buds.setOneBudAnc(!buds.oneBudAnc)
            }

            ToggleRow {
              visible: root.touchVisible
              width: parent.width
              rowName: "touch"
              label: "Touch lock"
              caption: "Ignore taps and pinches on the buds"
              checked: buds.touchLocked
              onToggled: buds.setTouchLocked(!buds.touchLocked)
            }
          }

          PanelSeparator {
            visible: root.valuesVisible
            foreground: root.foreground
          }

          Column {
            visible: root.valuesVisible
            width: parent.width
            spacing: Style.space(6)

            ValueRow {
              visible: root.eqVisible
              width: parent.width
              rowName: "eq"
              label: "Equalizer"
              value: Model.eqName(buds.eqPreset)
              onActivated: buds.cycleEqPreset()
            }

            ValueRow {
              visible: root.findVisible
              width: parent.width
              rowName: "find"
              label: "Find my buds"
              value: buds.finding ? "Ringing… click to stop" : "Ring"
              onActivated: buds.toggleFinding()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.guidanceVisible
            width: parent.width
            text: buds.daemonReachable
              ? "Connect your Galaxy Buds to see battery and noise controls."
              : "Start the omarchy-buds daemon to see battery and noise controls."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: root.phraseIntervalMs
    running: root.opened && buds.hasBuds
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component BudRow: Item {
    id: budRow
    property string label: ""
    property int level: Model.LEVEL_UNKNOWN
    property bool charging: false
    property string meta: ""

    readonly property bool low: level !== Model.LEVEL_UNKNOWN && level <= root.lowBatteryPercent && !charging

    implicitHeight: budLayout.implicitHeight

    RowLayout {
      id: budLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: budRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Math.max(Style.space(44), implicitWidth + Style.space(10))
      }

      Rectangle {
        id: meterTrack
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)

        Rectangle {
          width: meterTrack.width * Model.levelFraction(budRow.level)
          height: parent.height
          radius: parent.radius
          color: budRow.low ? root.urgent : root.foreground
        }
      }

      Text {
        textFormat: Text.PlainText
        text: Model.levelText(budRow.level)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(38)
      }

      Text {
        textFormat: Text.PlainText
        text: budRow.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.preferredWidth: Style.space(56)
      }
    }
  }

  component ModeRow: CursorSurface {
    id: modeRow
    property string mode: ""

    readonly property string rowName: "mode:" + mode
    readonly property bool selected: buds.noiseMode === mode

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: modeLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(modeRow.rowName)
      onClicked: buds.setNoiseMode(modeRow.mode)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        id: modeLabel
        Layout.fillWidth: true
        text: Model.noiseModeName(modeRow.mode)
        color: root.foreground
        opacity: modeRow.selected ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        text: Model.GLYPH_CHECK
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: modeRow.selected ? 1.0 : 0.0
      }
    }
  }

  component ToggleRow: CursorSurface {
    id: toggleRow
    property string rowName: ""
    property string label: ""
    property string caption: ""
    property bool checked: false

    signal toggled()

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: toggleContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(toggleRow.rowName)
      onClicked: toggleRow.toggled()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: toggleContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: toggleRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: toggleRow.caption
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        Layout.alignment: Qt.AlignVCenter
        checked: toggleRow.checked
        busy: buds.busy
        hasCursor: toggleRow.hasCursor
        foreground: root.foreground
        onToggled: toggleRow.toggled()
      }
    }
  }

  component ValueRow: CursorSurface {
    id: valueRow
    property string rowName: ""
    property string label: ""
    property string value: ""

    signal activated()

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: valueLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(valueRow.rowName)
      onClicked: valueRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        id: valueLabel
        Layout.fillWidth: true
        text: valueRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: valueRow.value
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  component SliderRow: Item {
    id: sliderRow
    implicitHeight: sliderColumn.implicitHeight

    Column {
      id: sliderColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: "Ambient volume"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
          height: 1
        }

        Text {
          textFormat: Text.PlainText
          text: (buds.ambientVolume + 1) + " / " + (buds.ambientVolumeMax + 1)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: buds.ambientVolumeMax
        step: 1
        integer: true
        tickCount: buds.ambientVolumeMax + 1
        value: buds.ambientVolume
        onReleased: function (v) { buds.setAmbientVolume(v) }
      }
    }
  }
}
