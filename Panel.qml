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
  // Chip under the cursor on the two chip rows; h and l walk it, enter applies it.
  property int modeIndex: 0
  property int eqIndex: 0

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", true) === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Say nothing extra once a section already explains the state.
  readonly property bool guidanceVisible: !buds.hasBuds && !buds.schemaUnsupported

  property int phraseIndex: 0

  readonly property int lowBatteryPercent: 20
  readonly property int phraseIntervalMs: 2800

  readonly property bool lowBattery: buds.hasBuds && Model.anyBudLow(buds.leftBud, buds.rightBud, lowBatteryPercent)
  // Dim while nothing is connected, the bar's urgent tone once a bud runs low; the mark itself never changes.
  readonly property color barIconColor: !buds.hasBuds ? Qt.darker(barForeground, 1.55)
    : lowBattery ? urgent
    : barForeground

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
  readonly property bool eqVisible: buds.hasBuds && buds.can("equalizer") && buds.eqPresets.length > 0
  readonly property bool findVisible: buds.hasBuds && buds.can("find")
  readonly property bool togglesVisible: conversationVisible || oneBudVisible || touchVisible

  readonly property var modeOptions: Model.chipOptions(buds.availableModes, Model.noiseModeShort)
  readonly property var eqOptions: Model.chipOptions(buds.eqPresets, Model.eqShort)

  // Rebuilt whenever a section appears, so j and k never land on a hidden control.
  readonly property var cursorRows: {
    var rows = []
    if (!buds.hasBuds) return rows
    if (findVisible) rows.push("find")
    if (modesVisible) rows.push("modes")
    if (ambientVisible) rows.push("ambient")
    if (conversationVisible) rows.push("conversation")
    if (oneBudVisible) rows.push("onebud")
    if (touchVisible) rows.push("touch")
    if (eqVisible) rows.push("eq")
    return rows
  }

  readonly property string cursorRow: cursorRows.length === 0
    ? ""
    : cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) {
    return cursorActive && cursorRow === name
  }

  // Land on the chip that is already selected, so enter without h or l changes nothing.
  function syncChipCursor() {
    if (cursorRow === "modes") modeIndex = Model.indexOrFirst(buds.availableModes, buds.noiseMode)
    else if (cursorRow === "eq") eqIndex = Model.indexOrFirst(buds.eqPresets, buds.eqPreset)
  }

  function moveCursor(dy) {
    cursorActive = true
    if (cursorRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
    syncChipCursor()
  }

  function nudgeCursor(dx) {
    if (cursorRow === "ambient") buds.setAmbientVolume(buds.ambientVolume + dx)
    else if (cursorRow === "modes") modeIndex = Math.max(0, Math.min(modeOptions.length - 1, modeIndex + dx))
    else if (cursorRow === "eq") eqIndex = Math.max(0, Math.min(eqOptions.length - 1, eqIndex + dx))
  }

  function activateCursor() {
    var name = cursorRow
    if (name === "find") buds.toggleFinding()
    else if (name === "modes" && modeIndex < buds.availableModes.length) buds.setNoiseMode(buds.availableModes[modeIndex])
    else if (name === "conversation") buds.setConversationDetect(!buds.conversationDetect)
    else if (name === "onebud") buds.setOneBudAnc(!buds.oneBudAnc)
    else if (name === "touch") buds.setTouchLocked(!buds.touchLocked)
    else if (name === "eq" && eqIndex < buds.eqPresets.length) buds.setEqPreset(buds.eqPresets[eqIndex])
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
    modeIndex = Model.indexOrFirst(buds.availableModes, buds.noiseMode)
    eqIndex = Model.indexOrFirst(buds.eqPresets, buds.eqPreset)
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
          // The pair is wider than tall, so it takes the whole canvas width to match the glyphs' height.
          iconSize: Style.bar.iconCanvas
          strokeWidth: 1.2
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

  // The current mode and the ringer share the hero's trailing slot, so the two
  // sit on one centreline at one height instead of the pill riding the title row.
  Component {
    id: heroControls

    Row {
      spacing: Style.space(8)

      BorderSurface {
        visible: buds.noiseMode !== ""
        implicitWidth: modeText.implicitWidth + Style.space(14)
        implicitHeight: findBell.visible ? findBell.height : modeText.implicitHeight + Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
        radius: Style.cornerRadius

        Text {
          id: modeText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: Model.noiseModeShort(buds.noiseMode)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      PanelActionButton {
        id: findBell
        visible: root.findVisible
        anchors.verticalCenter: parent.verticalCenter
        iconText: buds.finding ? "󰂟" : "󰂚"
        tooltipText: buds.finding ? "Stop ringing" : "Ring the buds"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.iconLarge
        bordered: true
        hasCursor: root.rowHasCursor("find")
        onClicked: buds.toggleFinding()
        onHovered: function (h) { if (h) root.focusRow("find") }
      }
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
        if (!root.cursorActive) { root.cursorActive = true; root.syncChipCursor(); return }
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
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: buds.hasBuds ? 1.0 : 0.5
            iconComponent: Component {
              BudsIcon {
                iconSize: Style.space(38)
                strokeWidth: 1.5
                fillOpacity: 0.08
                color: buds.hasBuds ? root.foreground : root.dim
              }
            }
            trailingControl: buds.hasBuds ? heroControls : null
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

            ChipRow {
              width: parent.width
              rowName: "modes"
              options: root.modeOptions
              value: buds.noiseMode
              cursorIndex: root.modeIndex
              onPicked: function (v) { buds.setNoiseMode(v) }
              onCursorMoved: function (i) { root.modeIndex = i }
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
              caption: "Ambient Sound while you talk"
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
            visible: root.eqVisible
            foreground: root.foreground
          }

          Column {
            visible: root.eqVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "EQUALIZER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ChipRow {
              width: parent.width
              rowName: "eq"
              options: root.eqOptions
              value: buds.eqPreset
              cursorIndex: root.eqIndex
              onPicked: function (v) { buds.setEqPreset(v) }
              onCursorMoved: function (i) { root.eqIndex = i }
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

          Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: Model.levelText(budRow.level)
        color: budRow.low ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(38)
      }

      Row {
        spacing: Style.space(4)
        Layout.preferredWidth: Style.space(70)

        Text {
          textFormat: Text.PlainText
          visible: budRow.charging
          text: "󱐋"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: budRow.meta
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  // Pick one of N as a row of bordered chips, the way the power panel offers its profiles.
  // Every chip is its own cursor target; the row it sits in is one j/k stop.
  //
  // Sizing: equal cells when the longest label allows it, otherwise each chip
  // keeps its natural width and the spare room is shared out, and only when
  // even that does not fit does the Flow wrap.
  component ChipRow: Flow {
    id: chips
    property string rowName: ""
    property var options: []
    property string value: ""
    property int cursorIndex: 0

    signal picked(string value)
    signal cursorMoved(int index)

    spacing: Style.space(6)

    property real naturalTotal: 0
    property real naturalMax: 0
    readonly property int count: options ? options.length : 0
    readonly property real spare: width - spacing * Math.max(0, count - 1) - naturalTotal
    readonly property real cellWidth: count > 0 ? Math.floor((width - spacing * (count - 1)) / count) : 0

    function measure() {
      var total = 0
      var widest = 0
      for (var i = 0; i < children.length; i++) {
        var c = children[i]
        if (!c || c.chipNatural === undefined) continue
        total += c.chipNatural
        widest = Math.max(widest, c.chipNatural)
      }
      naturalTotal = total
      naturalMax = widest
    }

    function chipWidth(natural) {
      if (count === 0) return natural
      if (naturalMax <= cellWidth) return cellWidth
      if (spare >= 0) return natural + spare / count
      return natural
    }

    Repeater {
      model: chips.options
      onItemRemoved: Qt.callLater(chips.measure)

      Button {
        required property var modelData
        required property int index
        readonly property real chipNatural: implicitWidth
        onChipNaturalChanged: chips.measure()
        Component.onCompleted: chips.measure()

        text: modelData.label
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        // A touch tighter than a stock button, so six equalizer presets share one line.
        horizontalPadding: Style.space(8)
        verticalPadding: Style.spacing.controlPaddingY + Style.space(1)
        bordered: true
        active: modelData.value === chips.value
        hasCursor: root.rowHasCursor(chips.rowName) && chips.cursorIndex === index
        width: chips.chipWidth(implicitWidth)
        onClicked: chips.picked(modelData.value)
        onHovered: function (h) {
          if (!h) return
          root.focusRow(chips.rowName)
          chips.cursorMoved(index)
        }
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

  // The ambient slider is a cursor stop too, so h and l have somewhere visible to act.
  component SliderRow: CursorSurface {
    id: sliderRow
    hasCursor: root.rowHasCursor("ambient")
    foreground: root.foreground
    implicitHeight: sliderColumn.implicitHeight + Style.space(10)

    // A HoverHandler rather than a MouseArea, so the slider underneath keeps its drag.
    HoverHandler {
      onHoveredChanged: if (hovered) root.focusRow("ambient")
    }

    Column {
      id: sliderColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

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
