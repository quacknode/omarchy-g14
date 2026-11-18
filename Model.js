.pragma library

function clamp(value, lo, hi) {
  var n = Number(value)
  if (!isFinite(n)) n = lo
  if (n < lo) return lo
  if (n > hi) return hi
  return n
}

function clone(points) {
  var out = []
  if (!points) return out
  for (var i = 0; i < points.length; i++) {
    out.push({ t: Number(points[i].t), p: Number(points[i].p) })
  }
  return out
}

function enforce(points) {
  var pts = clone(points)
  for (var i = 1; i < pts.length; i++) {
    if (pts[i].t < pts[i - 1].t) pts[i].t = pts[i - 1].t
    if (pts[i].p < pts[i - 1].p) pts[i].p = pts[i - 1].p
  }
  return pts
}

function dropBefore(pts, index) {
  for (var k = index - 1; k >= 0; k--) {
    if (pts[k].p > pts[k + 1].p) pts[k].p = pts[k + 1].p
  }
}

function setPoint(points, index, temp, pwm) {
  var pts = clone(points)
  if (index < 0 || index >= pts.length) return pts
  var minT = index === 0 ? 20 : pts[index - 1].t
  var maxT = index === pts.length - 1 ? 100 : pts[index + 1].t
  pts[index].t = Math.round(clamp(temp, minT, maxT))
  pts[index].p = Math.round(clamp(pwm, 0, 255))
  dropBefore(pts, index)
  return enforce(pts)
}

function stroke(points, t0, p0, t1, p1) {
  var pts = clone(points)
  if (!pts.length) return pts
  var lo = Math.min(t0, t1)
  var hi = Math.max(t0, t1)
  var pLo = t0 <= t1 ? p0 : p1
  var pHi = t0 <= t1 ? p1 : p0
  function desired(t) {
    if (hi - lo < 0.5) return pLo
    return pLo + (pHi - pLo) * ((t - lo) / (hi - lo))
  }
  var touched = -1
  for (var i = 0; i < pts.length; i++) {
    if (pts[i].t < lo - 0.01 || pts[i].t > hi + 0.01) continue
    pts[i].p = Math.round(clamp(desired(pts[i].t), 0, 255))
    if (touched < 0) touched = i
  }
  if (touched < 0) {
    var mid = (lo + hi) / 2
    var best = 0
    var bestD = 1e9
    for (var j = 0; j < pts.length; j++) {
      var d = Math.abs(pts[j].t - mid)
      if (d < bestD) {
        bestD = d
        best = j
      }
    }
    pts[best].p = Math.round(clamp(desired(mid), 0, 255))
    touched = best
  }
  dropBefore(pts, touched)
  return enforce(pts)
}

function dutyAt(points, temp) {
  if (!points || !points.length) return 0
  var t = Number(temp)
  if (t <= points[0].t) return points[0].p
  var last = points.length - 1
  if (t >= points[last].t) return points[last].p
  for (var i = 0; i < last; i++) {
    if (t > points[i + 1].t) continue
    var span = points[i + 1].t - points[i].t
    var u = span <= 0 ? 0 : (t - points[i].t) / span
    return points[i].p + (points[i + 1].p - points[i].p) * u
  }
  return points[last].p
}

function percent(pwm) {
  return Math.round(clamp(pwm, 0, 255) * 100 / 255)
}

function formatData(points) {
  var parts = []
  var pts = enforce(points)
  for (var i = 0; i < pts.length; i++) {
    parts.push(Math.round(pts[i].t) + "c:" + Math.round(pts[i].p))
  }
  return parts.join(",")
}

function same(a, b) {
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (Math.round(a[i].t) !== Math.round(b[i].t)) return false
    if (Math.round(a[i].p) !== Math.round(b[i].p)) return false
  }
  return true
}

function fromRaw(temp, pwm) {
  var out = []
  var n = Math.min(temp ? temp.length : 0, pwm ? pwm.length : 0)
  for (var i = 0; i < n; i++) out.push({ t: Number(temp[i]), p: Number(pwm[i]) })
  return out
}
