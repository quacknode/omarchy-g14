import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.quacknode.g14"
  ipcTarget: "io.github.quacknode.g14"

  readonly property color ink: Commons.Color.foreground
  readonly property color dim: Qt.rgba(ink.r, ink.g, ink.b, 0.62)
  readonly property color faint: Qt.rgba(ink.r, ink.g, ink.b, 0.42)
  readonly property var modes: [
    { key: "Quiet", label: "Silent" },
    { key: "Balanced", label: "Balanced" },
    { key: "Performance", label: "Turbo" }
  ]
  readonly property var fanOrder: ["cpu", "gpu", "mid"]
  readonly property bool curvesOn: !!(curveEnabled.cpu && curveEnabled.gpu && curveEnabled.mid)
  readonly property string hint: "Drag a point, or draw across the chart. The hardware keeps eight points. M4 opens this panel."

  property string profile: ""
  property string liveProfile: ""
  property string acProfile: ""
  property string batteryProfile: ""
  property string fan: "cpu"
  property string leds: "med"
  property string gpuMode: "hybrid"
  property string errorText: ""
  property var curves: ({ cpu: [], gpu: [], mid: [] })
  property var curveEnabled: ({ cpu: false, gpu: false, mid: false })
  property var limits: ({})
  property var rpms: [0, 0, 0]
  property var pending: null
  property int cpu: 0
  property int igpu: 0
  property int gpuTemp: -1
  property int boost: 1
  property int ac: 1
  property int charge: 80
  property bool reboot: false
  property bool loaded: false
  property bool autostart: true

  function fileOf(name) {
    var base = Qt.resolvedUrl(name).toString()
    if (base.indexOf("file://") === 0) base = base.substring(7)
    return decodeURIComponent(base)
  }

  function run(args) {
    if (actionProc.running) {
      pending = args
      return
    }
    actionProc.command = ["python3", fileOf("g14.py")].concat(args)
    actionProc.running = true
  }

  function pump() {
    if (!pending) return
    var next = pending
    pending = null
    Qt.callLater(function() { run(next) })
  }

  function refreshStats() {
    if (statsProc.running) return
    statsProc.command = opened ? [fileOf("g14-stats.sh"), "--gpu"] : [fileOf("g14-stats.sh")]
    statsProc.running = true
  }

  function limitValue(key) {
    var row = limits[key]
    return row && row.value !== undefined ? Number(row.value) : 0
  }

  function rpmFor(which) {
    var index = fanOrder.indexOf(which)
    if (index < 0 || !rpms || rpms.length <= index) return 0
    return rpms[index]
  }

  function tempFor(which) {
    var gpu = gpuTemp >= 0 ? gpuTemp : igpu
    if (which === "gpu") return gpu
    if (which === "mid") return Math.max(cpu, gpu)
    return cpu
  }

  function series(which) {
    return curves[which] || []
  }

  function ghostsFor(which) {
    var out = []
    for (var i = 0; i < fanOrder.length; i++) {
      if (fanOrder[i] === which) continue
      var row = series(fanOrder[i])
      if (row.length) out.push(row)
    }
    return out
  }

  function modeName(name) {
    for (var i = 0; i < modes.length; i++) if (modes[i].key === name) return modes[i].label
    return name || "—"
  }

  function use(mode) {
    if (!mode || (mode === profile && mode === liveProfile)) return
    liveProfile = mode
    run(["use", mode])
  }

  function pickSource(which, mode) {
    var onThisSource = (which === "ac") === (ac === 1)
    if (onThisSource) use(mode)
    else run(["remember", which, mode])
  }

  function commitCurve(which, pts) {
    if (!pts || pts.length !== 8) return
    if (Model.same(series(which), pts)) return
    var next = { cpu: series("cpu"), gpu: series("gpu"), mid: series("mid") }
    next[which] = pts
    curves = next
    run(["apply", profile, which, Model.formatData(pts)])
  }

  function commitCpu(which, value) {
    var spl = limitValue("spl")
    var sppt = limitValue("sppt")
    var fppt = limitValue("fppt")
    if (which === "spl") spl = value
    else if (which === "sppt") sppt = value
    else fppt = value
    if (which === "spl") {
      if (sppt < spl) sppt = spl
      if (fppt < sppt) fppt = sppt
    } else if (which === "sppt") {
      if (spl > sppt) spl = sppt
      if (fppt < sppt) fppt = sppt
    } else {
      if (sppt > fppt) sppt = fppt
      if (spl > sppt) spl = sppt
    }
    run(["limits", profile, "spl", String(spl), "sppt", String(sppt), "fppt", String(fppt)])
  }

  function stepFan(direction) {
    var index = fanOrder.indexOf(fan)
    if (index < 0) index = 0
    var next = index + (direction > 0 ? 1 : -1)
    fan = fanOrder[(next + fanOrder.length) % fanOrder.length]
  }

  function ingestStats(raw) {
    var msg = parse(raw)
    if (!msg || !msg.ok) return
    cpu = Number(msg.cpu) || 0
    igpu = Number(msg.igpu) || 0
    gpuTemp = msg.gpu === null || msg.gpu === undefined ? -1 : Number(msg.gpu)
    if (msg.fans && msg.fans.length === 3) rpms = msg.fans
    boost = Number(msg.boost) ? 1 : 0
    ac = Number(msg.ac) ? 1 : 0
    if (msg.profile) liveProfile = msg.profile
    if (loaded && msg.profile && msg.profile !== profile && !actionProc.running && !pending)
      run(["snapshot"])
  }

  function ingest(raw) {
    var msg = parse(raw)
    if (!msg) return
    if (!msg.ok) {
      errorText = msg.error || "That didn't apply"
      return
    }
    errorText = msg.note || ""
    applySnapshot(msg)
  }

  function parse(raw) {
    var text = String(raw || "").trim()
    if (!text) return null
    try { return JSON.parse(text) }
    catch (error) {
      console.warn("io.github.quacknode.g14", text)
      return null
    }
  }

  function applySnapshot(msg) {
    if (msg.profile) {
      profile = msg.profile
      liveProfile = msg.profile
    }
    if (msg.acProfile) acProfile = msg.acProfile
    if (msg.batteryProfile) batteryProfile = msg.batteryProfile
    if (msg.ac !== undefined) ac = Number(msg.ac) ? 1 : 0
    if (msg.limits) limits = msg.limits
    if (msg.charge !== undefined) charge = Number(msg.charge)
    if (msg.leds) leds = String(msg.leds)
    if (msg.boost !== undefined) boost = Number(msg.boost) ? 1 : 0
    if (msg.gpuMode) gpuMode = String(msg.gpuMode)
    reboot = msg.reboot === true
    if (msg.autostart !== undefined) autostart = msg.autostart === true
    var block = msg.curves ? msg.curves[profile] : null
    if (block && !chart.editing) {
      var next = {}
      var flags = {}
      for (var i = 0; i < fanOrder.length; i++) {
        var name = fanOrder[i]
        var raw = block[name]
        next[name] = raw ? Model.fromRaw(raw.temp, raw.pwm) : []
        flags[name] = !!(raw && raw.enabled)
      }
      curves = next
      curveEnabled = flags
    }
    loaded = true
  }

  Component.onCompleted: {
    refreshStats()
    run(["snapshot"])
  }

  onOpenedChanged: if (opened) refreshStats()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    interval: root.opened ? 2000 : 20000
    running: true
    repeat: true
    onTriggered: root.refreshStats()
  }

  Process {
    id: statsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingestStats(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
    onExited: root.pump()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB85\uDE85"
    slotSize: Style.bar.iconSlot
    fontSize: Style.bar.iconFont
    tooltipText: "G14  " + (root.liveProfile ? root.modeName(root.liveProfile) : "…")
      + "  ·  " + root.cpu + "°  ·  "
      + root.rpms[0] + " / " + root.rpms[1] + " / " + root.rpms[2]
    onPressed: root.toggle()
  }

  component PowerLimit: Column {
    id: limit
    property string title: ""
    property string unit: "W"
    property int from: 0
    property int to: 100
    property int number: 0
    signal commit(int value)
    spacing: Style.space(2)

    Item {
      width: limit.width
      height: Math.max(titleText.implicitHeight, valueText.implicitHeight)
      Text {
        id: titleText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: limit.title
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: limit.number + (limit.unit !== "" ? " " + limit.unit : "")
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      width: limit.width
      bar: root.bar
      minimum: limit.from
      maximum: Math.max(limit.from + 1, limit.to)
      step: 1
      integer: true
      value: limit.number
      onReleased: function(v) {
        var next = Math.round(v)
        if (next !== limit.number) limit.commit(next)
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.stepFan(dx) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          Column {
            width: parent.width
            spacing: Style.space(3)
            Item {
              width: parent.width
              height: titleText.implicitHeight
              Text {
                id: titleText
                anchors.left: parent.left
                text: "Zephyrus G14"
                color: root.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.baseline: titleText.baseline
                text: root.modeName(root.liveProfile)
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
            Text {
              width: parent.width
              text: "CPU " + root.cpu + "°    iGPU " + root.igpu + "°    GPU "
                + (root.gpuTemp >= 0 ? root.gpuTemp + "°" : "—")
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: modeRow
            readonly property real slot: Math.max(1, (width - spacing * 2) / 3)
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.modes
              delegate: Button {
                required property var modelData
                width: modeRow.slot
                text: modelData.label
                selected: modelData.key === root.liveProfile
                onClicked: root.use(modelData.key)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              id: acRow
              readonly property real slot: Math.max(1, (width - Style.space(92) - spacing * 3) / 3)
              width: parent.width
              spacing: Style.space(6)
              Text {
                width: Style.space(92)
                text: "Plugged in"
                color: root.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: root.modes
                delegate: Button {
                  required property var modelData
                  width: acRow.slot
                  text: modelData.label
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
                  selected: modelData.key === root.acProfile
                  onClicked: root.pickSource("ac", modelData.key)
                }
              }
            }

            Row {
              id: batteryRow
              readonly property real slot: Math.max(1, (width - Style.space(92) - spacing * 3) / 3)
              width: parent.width
              spacing: Style.space(6)
              Text {
                width: Style.space(92)
                text: "On battery"
                color: root.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: root.modes
                delegate: Button {
                  required property var modelData
                  width: batteryRow.slot
                  text: modelData.label
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(3)
                  selected: modelData.key === root.batteryProfile
                  onClicked: root.pickSource("battery", modelData.key)
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.ink }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "Fans"; foreground: root.ink }

            Row {
              id: fanRow
              readonly property real slot: Math.max(1, (width - spacing * 2) / 3)
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [
                  { key: "cpu", label: "CPU" },
                  { key: "gpu", label: "GPU" },
                  { key: "mid", label: "Mid" }
                ]
                delegate: Button {
                  required property var modelData
                  width: fanRow.slot
                  text: modelData.label + "  " + root.rpmFor(modelData.key)
                  selected: modelData.key === root.fan
                  onClicked: root.fan = modelData.key
                }
              }
            }

            Curve {
              id: chart
              width: parent.width
              height: Style.space(176)
              ink: root.ink
              points: root.series(root.fan)
              ghosts: root.ghostsFor(root.fan)
              liveTemp: root.tempFor(root.fan)
              rpmFull: root.fan === "gpu" ? 6800 : root.fan === "mid" ? 8100 : 6900
              onCommitted: function(pts) { root.commitCurve(root.fan, pts) }
            }

            Text {
              width: parent.width
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              text: {
                var pts = root.series(root.fan)
                var temp = root.tempFor(root.fan)
                if (!pts.length) return "Reading the curve stored for " + root.modeName(root.profile) + "…"
                if (chart.hoverIndex >= 0) return chart.pointText(chart.hoverIndex)
                var duty = Model.percent(Model.dutyAt(pts, temp))
                var line = Math.round(temp) + "° commands " + duty
                  + "% on the " + root.modeName(root.profile) + " curve"
                var rpm = root.rpmFor(root.fan)
                if (root.curvesOn && duty === 0 && rpm >= 1200)
                  line += ". Firmware is overriding this fan at " + rpm + " rpm"
                return line
              }
            }

            Toggle {
              width: parent.width
              label: "Use these curves"
              description: root.curvesOn
                ? "Running while " + root.modeName(root.profile) + " is the active mode."
                : "Saved for " + root.modeName(root.profile) + ". The BIOS curve is still running."
              checked: root.curvesOn
              foreground: root.ink
              onClicked: {
                var next = !root.curvesOn
                root.curveEnabled = { cpu: next, gpu: next, mid: next }
                root.run(["enable", root.profile, next ? "true" : "false"])
              }
            }

            Button {
              text: "Reset " + root.modeName(root.profile) + " curves"
              onClicked: root.run(["default", root.profile])
            }
          }

          PanelSeparator { width: parent.width; foreground: root.ink }

          Column {
            width: parent.width
            spacing: Style.space(8)
            PanelSectionHeader {
              text: "Power  ·  " + root.modeName(root.profile)
              foreground: root.ink
            }
            PowerLimit {
              width: parent.width
              title: "CPU sustained"
              from: root.limitBound("spl", "min", 15)
              to: root.limitBound("spl", "max", 80)
              number: root.limitValue("spl")
              onCommit: function(v) { root.commitCpu("spl", v) }
            }
            PowerLimit {
              width: parent.width
              title: "CPU boost"
              from: root.limitBound("sppt", "min", 25)
              to: root.limitBound("sppt", "max", 80)
              number: root.limitValue("sppt")
              onCommit: function(v) { root.commitCpu("sppt", v) }
            }
            PowerLimit {
              width: parent.width
              title: "CPU spike"
              from: root.limitBound("fppt", "min", 35)
              to: root.limitBound("fppt", "max", 80)
              number: root.limitValue("fppt")
              onCommit: function(v) { root.commitCpu("fppt", v) }
            }
            PowerLimit {
              width: parent.width
              title: "GPU power"
              from: root.limitBound("tgp", "min", 55)
              to: root.limitBound("tgp", "max", 65)
              number: root.limitValue("tgp")
              onCommit: function(v) { root.run(["limits", root.profile, "tgp", String(v)]) }
            }
            PowerLimit {
              width: parent.width
              title: "GPU dynamic boost"
              from: root.limitBound("gboost", "min", 5)
              to: root.limitBound("gboost", "max", 25)
              number: root.limitValue("gboost")
              onCommit: function(v) { root.run(["limits", root.profile, "gboost", String(v)]) }
            }
            PowerLimit {
              width: parent.width
              title: "GPU temperature limit"
              unit: "°"
              from: root.limitBound("gtemp", "min", 75)
              to: root.limitBound("gtemp", "max", 87)
              number: root.limitValue("gtemp")
              onCommit: function(v) { root.run(["limits", root.profile, "gtemp", String(v)]) }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.ink }

          Column {
            width: parent.width
            spacing: Style.space(8)
            PanelSectionHeader { text: "Machine"; foreground: root.ink }

            PowerLimit {
              width: parent.width
              title: "Charge limit"
              unit: "%"
              from: 20
              to: 100
              number: root.charge
              onCommit: function(v) { root.run(["battery", String(v)]) }
            }

            Row {
              id: chargeRow
              readonly property real slot: Math.max(1, (width - spacing * 2) / 3)
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: ["60", "80", "100"]
                delegate: Button {
                  required property string modelData
                  width: chargeRow.slot
                  text: modelData + "%"
                  selected: Number(modelData) === root.charge
                  onClicked: root.run(["battery", modelData])
                }
              }
            }

            Text {
              text: "Keyboard"
              color: root.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              id: ledRow
              readonly property real slot: Math.max(1, (width - spacing * 3) / 4)
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [
                  { key: "off", label: "Off" },
                  { key: "low", label: "Low" },
                  { key: "med", label: "Med" },
                  { key: "high", label: "High" }
                ]
                delegate: Button {
                  required property var modelData
                  width: ledRow.slot
                  text: modelData.label
                  selected: modelData.key === root.leds
                  onClicked: root.run(["leds", modelData.key])
                }
              }
            }

            Toggle {
              width: parent.width
              label: "CPU boost"
              description: "Lets the 8945HS clock above its base speed."
              checked: root.boost === 1
              foreground: root.ink
              onClicked: root.run(["boost", root.boost === 1 ? "0" : "1"])
            }

            Text {
              text: "GPU mode"
              color: root.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              id: gpuRow
              readonly property real slot: Math.max(1, (width - spacing * 2) / 3)
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [
                  { key: "hybrid", label: "Hybrid" },
                  { key: "eco", label: "Eco" },
                  { key: "ultimate", label: "Ultimate" }
                ]
                delegate: Button {
                  required property var modelData
                  width: gpuRow.slot
                  text: modelData.label
                  selected: modelData.key === root.gpuMode
                  onClicked: root.run(["gpu", modelData.key])
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Eco turns the 4070 off. Ultimate hands the display to it. Both wait for a reboot."
              color: root.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            PanelSeparator { width: parent.width; foreground: root.ink }

            Toggle {
              width: parent.width
              label: "Start with the desktop"
              description: "Reapplies your curves and power limits when you log in. The fan icon stays on the bar either way."
              checked: root.autostart
              foreground: root.ink
              onClicked: {
                root.autostart = !root.autostart
                root.run(["autostart", root.autostart ? "true" : "false"])
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.reboot
              ? "A GPU mode change is waiting for a reboot."
              : (root.errorText !== "" ? root.errorText : root.hint)
            color: root.errorText !== "" || root.reboot ? root.ink : root.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Rectangle {
        visible: flick.contentHeight > flick.height + 1
        width: Style.space(2)
        radius: width
        color: root.faint
        anchors.right: parent.right
        y: flick.contentHeight > flick.height
          ? flick.contentY * (flick.height - height) / (flick.contentHeight - flick.height)
          : 0
        height: Math.max(Style.space(24), flick.height * flick.height / Math.max(1, flick.contentHeight))
      }
    }
  }

  function limitBound(key, edge, fallback) {
    var row = limits[key]
    if (!row || row[edge] === undefined) return fallback
    return Number(row[edge])
  }
}
