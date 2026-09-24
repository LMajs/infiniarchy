.pragma library

// Canvas model: every window is a free item on one infinite plane.
//
// Persisted layout (~/.local/state/infiniarchy/layout.json):
//   windows:   address -> { x, y, w, h, cls, title, seen }   canvas rects
//   viewports: workspaceId -> { x, y }   canvas point shown at a workspace's
//              monitor top-left. A workspace with a viewport is "on the canvas":
//              its windows float at (canvas - viewport) on the real desktop.
//   managed:   address -> { ws, floating }   windows the canvas floated (for `release`)
//   links:     [[addrA, addrB], ...]   attached ("chained") windows move together

var GAP = 40
var ROW_ITEMS = 4
var PRUNE_MS = 14 * 24 * 3600 * 1000

function emptyLayout() {
  return { version: 2, windows: {}, viewports: {}, managed: {}, links: [] }
}

function normalizeLayout(raw) {
  var l = emptyLayout()
  if (raw && typeof raw === "object") {
    if (raw.windows && typeof raw.windows === "object") l.windows = raw.windows
    if (raw.viewports && typeof raw.viewports === "object") l.viewports = raw.viewports
    if (raw.managed && typeof raw.managed === "object") l.managed = raw.managed
    if (Array.isArray(raw.links)) l.links = raw.links.filter(function(k) { return Array.isArray(k) && k.length === 2 })
  }
  return l
}

function cloneLayout(l) {
  return JSON.parse(JSON.stringify(l))
}

function logicalSize(monitor) {
  var scale = Number(monitor.scale) || 1
  var w = Math.round(Number(monitor.width) / scale)
  var h = Math.round(Number(monitor.height) / scale)
  var t = Number(monitor.transform) || 0
  return (t % 2 === 1) ? { w: h, h: w } : { w: w, h: h }
}

function normAddress(value) {
  var s = String(value || "")
  return s.indexOf("0x") === 0 ? s : "0x" + s
}

function intersects(a, b, pad) {
  pad = pad || 0
  return a.x < b.x + b.w + pad && a.x + a.w + pad > b.x && a.y < b.y + b.h + pad && a.y + a.h + pad > b.y
}

function overlapArea(a, b) {
  var w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
  var h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
  return w > 0 && h > 0 ? w * h : 0
}

function freeAt(rect, placed) {
  for (var i = 0; i < placed.length; i++) if (intersects(rect, placed[i], GAP / 2 - 1)) return false
  return true
}

// Free spot for a w×h window, preferring the side of `anchor` (to the right,
// like the reference: new windows line up next to the previous one).
// `within` (optional) is a viewport the result must mostly sit inside.
function place(w, h, placed, anchor, within) {
  if (!placed.length && !within) return { x: 0, y: 0 }
  var cands = []
  function around(r) {
    cands.push({ x: r.x + r.w + GAP, y: r.y })
    cands.push({ x: r.x, y: r.y + r.h + GAP })
    cands.push({ x: r.x - w - GAP, y: r.y })
    cands.push({ x: r.x, y: r.y - h - GAP })
  }
  if (anchor) around(anchor)
  if (within) cands.push({ x: Math.round(within.x + (within.w - w) / 2), y: Math.round(within.y + (within.h - h) / 2) })
  var sorted = placed.slice().sort(function(a, b) { return a.y - b.y || a.x - b.x })
  for (var i = 0; i < sorted.length; i++) around(sorted[i])
  for (var c = 0; c < cands.length; c++) {
    var r = { x: cands[c].x, y: cands[c].y, w: w, h: h }
    if (within && overlapArea(r, within) < w * h * 0.6) continue
    if (freeAt(r, placed)) return cands[c]
  }
  if (within) return { x: Math.round(within.x + (within.w - w) / 2 + 36), y: Math.round(within.y + (within.h - h) / 2 + 36) }
  var b = boundsOf(placed)
  return { x: b.x + b.w + GAP, y: b.y }
}

// Snap a dragged rect to neighbours' edges (aligned or GAP apart).
function snap(rect, others, threshold) {
  var bestX = null, bestDX = threshold, bestY = null, bestDY = threshold
  for (var i = 0; i < others.length; i++) {
    var o = others[i]
    var xs = [o.x, o.x + o.w + GAP, o.x - rect.w - GAP, o.x + o.w - rect.w]
    var ys = [o.y, o.y + o.h + GAP, o.y - rect.h - GAP, o.y + o.h - rect.h]
    var nearY = rect.y < o.y + o.h + threshold * 4 && rect.y + rect.h > o.y - threshold * 4
    var nearX = rect.x < o.x + o.w + threshold * 4 && rect.x + rect.w > o.x - threshold * 4
    for (var a = 0; a < 4; a++) {
      var dx = Math.abs(xs[a] - rect.x)
      if (nearY && dx < bestDX) { bestDX = dx; bestX = xs[a] }
      var dy = Math.abs(ys[a] - rect.y)
      if (nearX && dy < bestDY) { bestDY = dy; bestY = ys[a] }
    }
  }
  return { x: bestX === null ? rect.x : bestX, y: bestY === null ? rect.y : bestY }
}

// snapshot: { clients, workspaces, monitors } from hyprctl -j.
// Returns the canvas items plus an updated layout (new windows placed,
// desktop moves synced back, dead windows re-claimed by class).
function build(snapshot, layoutIn, now, syncDesktop) {
  var layout = cloneLayout(normalizeLayout(layoutIn))
  now = now || Date.now()
  var monitors = snapshot.monitors || []
  var monById = {}, focusedMon = null
  for (var m = 0; m < monitors.length; m++) {
    monById[monitors[m].id] = monitors[m]
    if (monitors[m].focused) focusedMon = monitors[m]
  }
  if (!focusedMon && monitors.length) focusedMon = monitors[0]
  var fallbackMon = focusedMon || { id: -1, name: "", x: 0, y: 0, width: 1920, height: 1080, scale: 1 }
  var fsize = logicalSize(fallbackMon)
  var defaultW = Math.round(fsize.w * 0.6), defaultH = Math.round(fsize.h * 0.62)

  var wsMon = {}
  var rawWs = snapshot.workspaces || []
  for (var i = 0; i < rawWs.length; i++) wsMon[rawWs[i].id] = rawWs[i].monitorID

  var clients = (snapshot.clients || []).filter(function(c) {
    return c && c.mapped !== false && c.hidden !== true && c.workspace && c.workspace.id !== undefined
  })
  clients.sort(function(a, b) {
    return (a.workspace.id - b.workspace.id) || (a.at[0] - b.at[0]) || (a.at[1] - b.at[1])
  })

  var alive = {}
  for (var c0 = 0; c0 < clients.length; c0++) alive[normAddress(clients[c0].address)] = true

  var items = [], fresh = [], rekey = {}
  for (var c = 0; c < clients.length; c++) {
    var cl = clients[c]
    var addr = normAddress(cl.address)
    var wsId = cl.workspace.id
    var mon = monById[cl.monitor !== undefined ? cl.monitor : wsMon[wsId]] || fallbackMon
    var vp = syncDesktop ? layout.viewports[String(wsId)] : null
    var at = cl.at || [0, 0], sz = cl.size || [defaultW, defaultH]
    var entry = layout.windows[addr]
    var item = {
      address: addr,
      title: String(cl.title || ""),
      appClass: String(cl["class"] || cl.initialClass || ""),
      workspaceId: wsId,
      workspaceName: String(cl.workspace.name || wsId),
      special: wsId < 0,
      floating: !!cl.floating,
      fullscreen: Number(cl.fullscreen) > 0,
      pinned: !!cl.pinned,
      focusRank: cl.focusHistoryID === undefined || cl.focusHistoryID === null ? 9999 : Number(cl.focusHistoryID),
      monitorId: mon.id,
      monX: Number(mon.x || 0), monY: Number(mon.y || 0),
      realX: Number(at[0]), realY: Number(at[1]), realW: Number(sz[0]), realH: Number(sz[1]),
      onCanvasWs: !!vp
    }
    item.focused = item.focusRank === 0

    if (vp && item.floating && !item.fullscreen) {
      // The desktop is the source of truth for windows on a canvas workspace.
      item.x = item.realX - item.monX + Number(vp.x)
      item.y = item.realY - item.monY + Number(vp.y)
      item.w = item.realW
      item.h = item.realH
    } else if (entry) {
      item.x = Number(entry.x); item.y = Number(entry.y)
      item.w = Number(entry.w) || defaultW; item.h = Number(entry.h) || defaultH
    } else {
      var claimed = claimDead(layout, alive, item, rekey)
      if (claimed) {
        item.x = claimed.x; item.y = claimed.y; item.w = claimed.w; item.h = claimed.h
      } else {
        // Scale uniformly so the tile keeps the window's proportions.
        var fit = item.floating ? 1 : Math.min(1, defaultW / Math.max(1, item.realW), defaultH / Math.max(1, item.realH))
        item.w = Math.round(item.realW * fit)
        item.h = Math.round(item.realH * fit)
        item.isNew = true
        fresh.push(item)
      }
    }
    // The tile always has the live window's aspect ratio (a tiled window's
    // shape changes with its layout), so the thumbnail fills it with no bars.
    // Width and top-left stay; only the height follows.
    if (item.realW > 0 && item.realH > 0) {
      var h = Math.round(item.w * item.realH / item.realW)
      if (Math.abs(h - item.h) > 1) item.h = h
    }
    items.push(item)
  }

  // Place windows the canvas hasn't seen yet.
  var placed = items.filter(function(it) { return !it.isNew })
  var firstRun = placed.length === 0
  if (firstRun) {
    var x = 0, y = 0, rowH = 0, n = 0
    for (var f = 0; f < fresh.length; f++) {
      if (n === ROW_ITEMS) { x = 0; y += rowH + GAP; rowH = 0; n = 0 }
      fresh[f].x = x; fresh[f].y = y
      x += fresh[f].w + GAP; rowH = Math.max(rowH, fresh[f].h); n++
    }
  } else {
    for (var g = 0; g < fresh.length; g++) {
      var it = fresh[g]
      var anchor = null
      for (var p = 0; p < placed.length; p++) {
        if (!anchor || placed[p].focusRank < anchor.focusRank) anchor = placed[p]
      }
      var spot = place(it.w, it.h, placed, anchor, null)
      it.x = spot.x; it.y = spot.y
      placed.push(it)
    }
  }

  for (var k = 0; k < items.length; k++) {
    var e = items[k]
    layout.windows[e.address] = { x: Math.round(e.x), y: Math.round(e.y), w: Math.round(e.w), h: Math.round(e.h), cls: e.appClass, title: e.title, seen: now }
  }
  for (var a in layout.windows) {
    if (!alive[a] && now - Number(layout.windows[a].seen || 0) > PRUNE_MS) delete layout.windows[a]
  }
  for (var mg in layout.managed) if (!alive[mg]) delete layout.managed[mg]
  // Links follow windows that re-claimed a closed window's spot; links whose
  // windows are gone for good are dropped with them.
  layout.links = layout.links.map(function(k) {
    return [rekey[k[0]] || k[0], rekey[k[1]] || k[1]]
  }).filter(function(k) { return k[0] !== k[1] && layout.windows[k[0]] && layout.windows[k[1]] })

  items.sort(function(a, b) { return Math.round(a.y / 60) - Math.round(b.y / 60) || a.x - b.x })
  var focused = ""
  for (var q = 0; q < items.length; q++) {
    items[q].z = 10000 - Math.min(9999, items[q].focusRank)
    if (items[q].focused) focused = items[q].address
  }

  return {
    items: items,
    layout: layout,
    bounds: boundsOf(items),
    focused: focused,
    activeWs: focusedMon && focusedMon.activeWorkspace ? focusedMon.activeWorkspace.id : 1,
    monitor: focusedMon ? { id: focusedMon.id, x: Number(focusedMon.x), y: Number(focusedMon.y), w: fsize.w, h: fsize.h } : { id: -1, x: 0, y: 0, w: 1920, h: 1080 },
    monitors: monById,
    wsMon: wsMon,
    defaultW: defaultW,
    defaultH: defaultH
  }
}

// Windows closed in a previous session keep their spot: the first new
// window of the same class (same title preferred) takes it over.
function claimDead(layout, alive, item, rekey) {
  var best = null, bestKey = null, bestScore = -1
  for (var key in layout.windows) {
    if (alive[key]) continue
    var e = layout.windows[key]
    if (!e || e.cls !== item.appClass || !item.appClass) continue
    var score = (e.title === item.title ? 2 : 0) + Number(e.seen || 0) / 1e13
    if (score > bestScore) { best = e; bestKey = key; bestScore = score }
  }
  if (!best) return null
  delete layout.windows[bestKey]
  if (rekey) rekey[bestKey] = item.address
  return { x: Number(best.x), y: Number(best.y), w: Number(best.w), h: Number(best.h) }
}

// Two rects sit edge to edge (GAP apart, as snapping leaves them) and share
// enough of that edge to count as attached.
function adjacent(a, b) {
  var tol = 8, minShare = 40
  var shareY = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
  var shareX = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
  if (shareY >= minShare && (Math.abs(a.x + a.w + GAP - b.x) <= tol || Math.abs(b.x + b.w + GAP - a.x) <= tol)) return true
  if (shareX >= minShare && (Math.abs(a.y + a.h + GAP - b.y) <= tol || Math.abs(b.y + b.h + GAP - a.y) <= tol)) return true
  return false
}

function hasLink(links, a, b) {
  for (var i = 0; i < links.length; i++) {
    var k = links[i]
    if ((k[0] === a && k[1] === b) || (k[0] === b && k[1] === a)) return true
  }
  return false
}

// Every window chained to `addr` (including itself).
function groupOf(addr, links) {
  var seen = {}, queue = [addr], out = []
  seen[addr] = true
  while (queue.length) {
    var cur = queue.shift()
    out.push(cur)
    for (var i = 0; i < links.length; i++) {
      var k = links[i], next = k[0] === cur ? k[1] : k[1] === cur ? k[0] : null
      if (next && !seen[next]) { seen[next] = true; queue.push(next) }
    }
  }
  return out
}

// Where a link's chain badge sits: middle of the gap between the two windows.
function linkAnchor(a, b) {
  var horizontal = a.x + a.w <= b.x || b.x + b.w <= a.x
  var vertical = a.y + a.h <= b.y || b.y + b.h <= a.y
  if (horizontal && !vertical) {
    var left = a.x < b.x ? a : b, right = left === a ? b : a
    var y0 = Math.max(a.y, b.y), y1 = Math.min(a.y + a.h, b.y + b.h)
    return { x: (left.x + left.w + right.x) / 2, y: (y0 + y1) / 2, horizontal: true, x0: left.x + left.w, x1: right.x, y0: 0, y1: 0 }
  }
  if (vertical) {
    var top = a.y < b.y ? a : b, bottom = top === a ? b : a
    var x0 = Math.max(a.x, b.x), x1 = Math.min(a.x + a.w, b.x + b.w)
    return { x: (x0 + x1) / 2, y: (top.y + top.h + bottom.y) / 2, horizontal: false, y0: top.y + top.h, y1: bottom.y, x0: 0, x1: 0 }
  }
  return { x: (a.x + a.w / 2 + b.x + b.w / 2) / 2, y: (a.y + a.h / 2 + b.y + b.h / 2) / 2, horizontal: true, x0: 0, x1: 0, y0: 0, y1: 0 }
}

function boundsOf(rects) {
  var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i]
    x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y)
    x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h)
  }
  if (!isFinite(x0)) return { x: 0, y: 0, w: 1920, h: 1080 }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

function neighbor(items, fromAddr, dx, dy) {
  var a = null
  for (var i = 0; i < items.length; i++) if (items[i].address === fromAddr) a = items[i]
  if (!a) return items.length ? items[0].address : ""
  var ax = a.x + a.w / 2, ay = a.y + a.h / 2
  var best = "", bestScore = Infinity
  for (var j = 0; j < items.length; j++) {
    var b = items[j]
    if (b === a) continue
    var vx = b.x + b.w / 2 - ax, vy = b.y + b.h / 2 - ay
    var along = vx * dx + vy * dy
    if (along <= 1) continue
    var score = along + Math.abs(vx * dy - vy * dx) * 2.2
    if (score < bestScore) { bestScore = score; best = b.address }
  }
  return best
}

// Lua for Hyprland that makes workspace `ws` show canvas viewport `vp`:
// every window in view (from any workspace) and every window already on `ws`
// floats at (canvas - viewport). Only windows that actually change are touched.
function landingPlan(items, ws, vp, mon) {
  var view = { x: vp.x, y: vp.y, w: mon.w, h: mon.h }
  var cmds = [], moved = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (it.tab || it.special || it.fullscreen || it.pinned) continue
    var inView = intersects(it, view, 0)
    if (!inView && it.workspaceId !== ws) continue
    var w = "address:" + it.address
    var tx = Math.round(mon.x + it.x - vp.x), ty = Math.round(mon.y + it.y - vp.y)
    var tw = Math.round(it.w), th = Math.round(it.h)
    var otherWs = it.workspaceId !== ws
    var resize = otherWs || !it.floating || it.realW !== tw || it.realH !== th
    var move = resize || it.realX !== tx || it.realY !== ty
    if (!move) continue
    // Order matters: moving to a workspace re-centres the window.
    if (otherWs) cmds.push("hl.dispatch(hl.dsp.window.move({ workspace = '" + ws + "', follow = false, window = '" + w + "' }))")
    if (otherWs || !it.floating) cmds.push("hl.dispatch(hl.dsp.window.float({ action = 'enable', window = '" + w + "' }))")
    if (resize) cmds.push("hl.dispatch(hl.dsp.window.resize({ x = " + tw + ", y = " + th + ", window = '" + w + "' }))")
    cmds.push("hl.dispatch(hl.dsp.window.move({ x = " + tx + ", y = " + ty + ", window = '" + w + "' }))")
    moved.push(it.address)
  }
  return { lua: cmds.join("\n"), moved: moved }
}

function hotkeyLabel(hotkey) {
  var names = { SUPER: "Super", CTRL: "Ctrl", SHIFT: "Shift", ALT: "Alt", RALT: "Right Alt" }
  return String(hotkey || "").split("+").map(function(p) {
    p = p.trim()
    if (names[p]) return names[p]
    return p.length === 1 ? p : p.charAt(0) + p.slice(1).toLowerCase()
  }).join(" + ")
}
