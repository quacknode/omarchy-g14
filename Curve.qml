import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var points: []
  property var shown: []
  property var ghosts: []
  property real liveTemp: -1
  property color ink: Commons.Color.foreground
  property bool adjusting: false
  property int rpmFull: 6900
  property int hoverIndex: -1
  readonly property bool editing: pointer.pressed

  signal committed(var points)

  onPointsChanged: if (!adjusting) shown = Model.clone(points)
  Component.onCompleted: shown = Model.clone(points)

  readonly property real leftPad: Style.space(36)
  readonly property real rightPad: Style.space(10)
  readonly property real topPad: Style.space(10)
  readonly property real bottomPad: Style.space(18)
  readonly property real tMin: 20
  readonly property real tMax: 100

  function xFor(temp) {
    var span = Math.max(1, width - leftPad - rightPad)
    return leftPad + (Model.clamp(temp, tMin, tMax) - tMin) / (tMax - tMin) * span
  }

  function yFor(pwm) {
    var span = Math.max(1, height - topPad - bottomPad)
    return topPad + (1 - Model.clamp(pwm, 0, 255) / 255) * span
  }

  function tempAt(x) {
    var span = Math.max(1, width - leftPad - rightPad)
    return tMin + Model.clamp(x - leftPad, 0, span) / span * (tMax - tMin)
  }

  function pwmAt(y) {
    var span = Math.max(1, height - topPad - bottomPad)
    return (1 - Model.clamp(y - topPad, 0, span) / span) * 255
  }

  function pointText(index) {
    var series = shown || []
    if (index < 0 || index >= series.length) return ""
    var pt = series[index]
    var pct = Model.percent(pt.p)
    var rpm = Math.round(pct / 100 * rpmFull)
    return Math.round(pt.t) + "°    " + pct + "%    " + rpm + " rpm"
  }

  function hit(x, y) {
    var best = -1
    var reach = Style.space(28)
    var bestD = reach * reach
    var series = shown || []
    for (var i = 0; i < series.length; i++) {
      var dx = x - xFor(series[i].t)
      var dy = y - yFor(series[i].p)
      var d = dx * dx + dy * dy
      if (d <= bestD) {
        bestD = d
        best = i
      }
    }
    return best
  }

  function paintLine(ctx, series, alpha, widthPx) {
    if (!series || series.length < 2) return
    ctx.beginPath()
    ctx.moveTo(xFor(series[0].t), yFor(series[0].p))
    for (var i = 1; i < series.length; i++) ctx.lineTo(xFor(series[i].t), yFor(series[i].p))
    ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, alpha)
    ctx.lineWidth = widthPx
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.stroke()
  }

  onRpmFullChanged: canvas.requestPaint()
  onHoverIndexChanged: canvas.requestPaint()
  onShownChanged: canvas.requestPaint()
  onGhostsChanged: canvas.requestPaint()
  onLiveTempChanged: canvas.requestPaint()
  onInkChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.font = Style.font.caption + "px \"" + Style.font.family + "\""
      ctx.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
      ctx.textAlign = "right"
      ctx.textBaseline = "middle"
      var full = Math.max(1, root.rpmFull)
      var rpmMarks = [0]
      var rpmStep = 1000
      var rpm = rpmStep
      while (rpm < full) {
        rpmMarks.push(rpm)
        rpm += rpmStep
      }
      rpmMarks.push(full)
      for (var i = rpmMarks.length - 2; i >= 0; i--) {
        var gap = root.yFor(rpmMarks[i] / full * 255) - root.yFor(rpmMarks[i + 1] / full * 255)
        if (gap < Style.space(12)) rpmMarks.splice(i, 1)
      }
      for (var m = 0; m < rpmMarks.length; m++) {
        var y = root.yFor(rpmMarks[m] / full * 255)
        ctx.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(root.leftPad, y)
        ctx.lineTo(width - root.rightPad, y)
        ctx.stroke()
        ctx.fillText(String(rpmMarks[m]), root.leftPad - Style.space(4), y)
      }
      ctx.textAlign = "center"
      ctx.textBaseline = "top"
      for (var temp = root.tMin; temp <= root.tMax; temp += 5) {
        ctx.fillText(String(temp), root.xFor(temp), height - root.bottomPad + Style.space(3))
      }

      var ghosts = root.ghosts || []
      for (var g = 0; g < ghosts.length; g++) root.paintLine(ctx, ghosts[g], 0.18, 1)

      var pts = root.shown || []
      if (pts.length >= 2) {
        ctx.beginPath()
        ctx.moveTo(root.xFor(pts[0].t), root.yFor(pts[0].p))
        for (var i = 1; i < pts.length; i++) ctx.lineTo(root.xFor(pts[i].t), root.yFor(pts[i].p))
        ctx.lineTo(root.xFor(pts[pts.length - 1].t), root.yFor(0))
        ctx.lineTo(root.xFor(pts[0].t), root.yFor(0))
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.07)
        ctx.fill()
        root.paintLine(ctx, pts, 0.95, Math.max(1.5, Style.space(2)))
        for (var h = 0; h < pts.length; h++) {
          ctx.beginPath()
          var dot = h === root.hoverIndex ? Style.space(7) : Style.space(4)
          ctx.arc(root.xFor(pts[h].t), root.yFor(pts[h].p), dot, 0, Math.PI * 2)
          ctx.fillStyle = root.ink
          ctx.fill()
        }
      }

      if (root.liveTemp >= root.tMin && root.liveTemp <= root.tMax) {
        var x = root.xFor(root.liveTemp)
        ctx.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
        ctx.lineWidth = 1
        ctx.setLineDash([Style.space(3), Style.space(3)])
        ctx.beginPath()
        ctx.moveTo(x, root.topPad)
        ctx.lineTo(x, height - root.bottomPad)
        ctx.stroke()
        ctx.setLineDash([])
      }
    }
  }

  MouseArea {
    id: pointer
    z: 3
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.CrossCursor

    function noteHover() {
      if (!containsMouse || (pressed && drag >= 0)) return
      root.hoverIndex = root.hit(mouseX, mouseY)
    }

    onMouseXChanged: noteHover()
    onMouseYChanged: noteHover()
    onExited: if (!pressed) root.hoverIndex = -1

    HoverHandler {
      onHoveredChanged: if (!hovered && !pointer.pressed) root.hoverIndex = -1
      onPointChanged: {
        if (pointer.pressed && pointer.drag >= 0) return
        root.hoverIndex = root.hit(point.position.x, point.position.y)
      }
    }
    property int drag: -1
    property real lastT: 0
    property real lastP: 0

    onPressed: function(mouse) {
      root.adjusting = true
      var index = root.hit(mouse.x, mouse.y)
      lastT = root.tempAt(mouse.x)
      lastP = root.pwmAt(mouse.y)
      if (index >= 0) {
        drag = index
        root.shown = Model.setPoint(root.shown, index, lastT, lastP)
      } else {
        drag = -2
        root.shown = Model.stroke(root.shown, lastT, lastP, lastT, lastP)
      }
    }

    onPositionChanged: function(mouse) {
      if (!pressed || drag === -1) return
      var t = root.tempAt(mouse.x)
      var p = root.pwmAt(mouse.y)
      if (drag >= 0) {
        root.shown = Model.setPoint(root.shown, drag, t, p)
        root.hoverIndex = drag
      } else {
        root.shown = Model.stroke(root.shown, lastT, lastP, t, p)
        root.hoverIndex = root.hit(mouse.x, mouse.y)
      }
      lastT = t
      lastP = p
    }

    onReleased: function(mouse) {
      if (root.shown && root.shown.length) root.committed(Model.clone(root.shown))
      drag = -1
      root.adjusting = false
    }

    onCanceled: {
      drag = -1
      root.adjusting = false
      root.shown = Model.clone(root.points)
    }
  }
}
