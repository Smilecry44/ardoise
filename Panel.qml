import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Ardoise : qui occupe la machine, en lignes qui font le total.
// Pastille dans la barre (RAM utilisée), carte façon Boxtop au clic, et une fenêtre
// centrée (graphiques, tous les processus, actions, « libère-moi ») au clic droit.
// Ce panneau est aussi le centre de données : il garde `ardoise --flux` lancé,
// tient les historiques et passe les actions à la commande ardoise.
Panel {
  id: root
  moduleName: "io.github.smilecry44.ardoise"
  ipcTarget: "io.github.smilecry44.ardoise"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // La commande `ardoise` est livrée dans le dossier du plugin (réglage `command` pour en utiliser une autre).
  readonly property string bundledCli: decodeURIComponent(String(Qt.resolvedUrl("ardoise")).replace(/^[a-z]+:\/\//, ""))
  readonly property string cli: setting("command", bundledCli)
  readonly property int historyLen: 150

  // ── langue : réglage `language` (auto | fr | en) ; auto suit la langue du système ──
  readonly property string lang: {
    var l = String(setting("language", "auto"))
    if (l === "fr" || l === "en") return l
    return String(Qt.locale().name).indexOf("fr") === 0 ? "fr" : "en"
  }
  function t(fr, en) { return lang === "fr" ? fr : en }
  // les réglages arrivent après la création : relancer le flux dans la bonne langue
  onLangChanged: if (flux.running) flux.running = false
  // nombre avec la virgule en français, le point en anglais
  function num(v, d) { var s = (Number(v) || 0).toFixed(d); return lang === "fr" ? s.replace(".", ",") : s }
  // Claude Code présent sur la machine (la commande le dit ; absent de l'info = on suppose oui)
  readonly property bool hasClaude: !info || info.has_claude !== false

  // ── état ──
  property bool windowOpen: false
  property var sys: null
  property var hw: ({})
  property var info: null
  property var procsByGroup: ({})
  property var basket: null
  property real basketTarget: 0
  property string armed: ""
  property string toast: ""
  property string sortKey: "ram"
  property string filter: "tout"           // tout | sessions | applis | calmes | fuites
  readonly property real smallLimit: 70 * 1048576
  // compteurs des filtres
  readonly property var filterCounts: {
    var g = info ? info.groups : []
    return { tout: g.length,
             sessions: g.filter(function(x) { return x.kind === "claude" }).length,
             applis: g.filter(function(x) { return x.kind !== "claude" }).length,
             calmes: g.filter(function(x) { return x.idle > 3600 }).length,
             fuites: g.filter(function(x) { return !!x.leak }).length }
  }

  // ── l'état général, en une phrase ──
  readonly property var verdict: {
    if (!sys) return { level: "ok", text: t("lecture…", "reading…"), detail: "" }
    var leaks = info ? info.groups.filter(function(g) { return !!g.leak }) : []
    var free = go(sys.available) + t(" libres", " free")
    var last = events.length ? events[events.length - 1] : null
    var lastTxt = last ? t("dernier événement : ", "last event: ") + last.text + t(" à ", " at ") + hhmm(last.t) : t("aucun événement récent", "no recent event")
    var threshold = setting("alertThreshold", 85)
    if (pct >= threshold) return { level: "crit", text: t("chargée · ", "loaded · ") + free, detail: t("la RAM dépasse ", "RAM is above ") + threshold + " % · " + lastTxt }
    if (leaks.length) return { level: "warn", text: t("à surveiller · ", "keep an eye · ") + free, detail: t("fuite probable : ", "probable leak: ") + leaks.map(function(g) { return g.name }).join(", ") }
    if (twins.length) return { level: "warn", text: t("à surveiller · ", "keep an eye · ") + free, detail: t("conversation ouverte deux fois : ", "conversation open twice: ") + twins[0].name }
    if (pct >= threshold - 15) return { level: "warn", text: t("bien remplie · ", "fairly full · ") + free, detail: lastTxt }
    return { level: "ok", text: t("tranquille · ", "calm · ") + free, detail: t("rien d'anormal · ", "nothing unusual · ") + lastTxt }
  }
  readonly property color verdictColor: verdict.level === "crit" ? warn : verdict.level === "warn" ? cFiles : "#29D398"

  // ── la suggestion de la boîte ⁷ ──
  readonly property string suggestion: {
    if (!info) return ""
    var parts = [], gain = 0
    var sleepy = sessions.filter(function(g) { return g.idle > 3600 && !(g.twins && g.twins.length) })
    if (sleepy.length) { var v = sleepy.reduce(function(a, g) { return a + g.facture }, 0); gain += v
      parts.push(sleepy.length + (sleepy.length > 1 ? t(" sessions calmes", " sessions idle") : t(" session calme", " session idle")) + t(" depuis plus d'une heure", " for over an hour")) }
    var dup = sessions.filter(function(g) { return g.twins && g.twins.length && !g.scratch_size })
    if (dup.length) { gain += dup.reduce(function(a, g) { return a + g.ram + g.zram }, 0); parts.push(dup.length + t(" conversation ouverte deux fois", " conversation open twice")) }
    var orph = orphans.reduce(function(a, o) { return a + o.cost }, 0)
    if (orph > 50 * 1048576) { gain += orph; parts.push(t("des scratchpads de sessions fermées", "scratchpads of closed sessions")) }
    var leaks = info.groups.filter(function(g) { return !!g.leak })
    if (leaks.length) parts.push(t("une fuite probable (", "a probable leak (") + leaks[0].name + ")")
    if (!parts.length) return t("Rien à signaler : rien ne dort ni ne fuit.", "All clear: nothing asleep, nothing leaking.")
    var txt = parts.join(", ")
    if (pct < 85) txt = t("Rien d'urgent. ", "Nothing urgent. ") + txt
    return txt + (gain > 100 * 1048576 ? t(" : ≈ ", ": ≈ ") + go(gain) + t(" récupérables.", " to recover.") : ".")
  }

  // derniers points d'une série, pour les mini-courbes de l'en-tête
  function spark(arr, n) { return arr.length > n ? arr.slice(arr.length - n) : arr }
  property bool sortAsc: false
  property string search: ""
  property var expanded: ({})
  signal bulleDemandee(string nom)   // affiche l'info-bulle d'un groupe (test, IPC « bulle »)
  readonly property int pct: sys ? Math.round(100 * sys.used / sys.total) : 0
  readonly property bool wantFull: opened || windowOpen

  // ── historiques ──
  property var hCpu: []
  property var hMem: []
  property var hZram: []
  property var hRx: []
  property var hTx: []
  property var hRead: []
  property var hWrite: []
  property var hGpu: []
  property var hBreak: []   // [sessions, applis, /tmp, noyau, écart] à chaque bilan
  property var hT: []       // heure de chaque relevé de 2 s
  property var hBreakT: []  // heure de chaque bilan

  // ── historique par minute (24 h, gardé sur le disque par le flux chef) ──
  property var minutes: []  // { t, cpu, used, total, rx, tx, rd, wr, gpu, parts }
  property var events: []   // { t, kind, text }
  property string range: "live"   // live (5 min) | 1h | 24h
  readonly property var rangeSpan: ({ live: 300, "1h": 3600, "24h": 86400 })

  // Valeurs d'une série pour la plage choisie, sur `cols` colonnes.
  // En direct : un point par relevé de 2 s. En 1 h / 24 h : l'axe suit le temps, chaque
  // colonne couvre une tranche égale de la plage (moyenne, ou pic pour réseau et disque) ;
  // une colonne sans relevé reprend le point précédent s'il date de moins de 2 min,
  // sinon elle reste vide (machine éteinte, shell arrêté).
  function series(key, cols) {
    if (range === "live") {
      var live = { cpu: hCpu, rx: hRx, tx: hTx, rd: hRead, wr: hWrite, gpu: hGpu, parts: hBreak }[key] || []
      return live
    }
    return buckets(key, cols).vals
  }
  // Les heures correspondant aux colonnes d'une série (pour placer les repères).
  function seriesTimes(key, cols) {
    if (range === "live") return key === "parts" ? hBreakT : hT
    return buckets(key, cols).times
  }
  function buckets(key, cols) {
    var n = Math.max(1, Math.floor(cols || 200))  // les graphiques peuvent passer une largeur non entière
    var now = Date.now() / 1000, span = rangeSpan[range], from = now - span, w = span / n
    var isParts = key === "parts", peak = key === "rx" || key === "tx" || key === "rd" || key === "wr"
    var empty = isParts ? [0, 0, 0, 0, 0] : 0
    var sums = [], counts = [], vals = [], times = []
    for (var c = 0; c < n; c++) { sums.push(isParts ? [0, 0, 0, 0, 0] : 0); counts.push(0); times.push(from + (c + 1) * w) }
    var lastBefore = null
    for (var i = 0; i < minutes.length; i++) {
      var m = minutes[i]
      if (!m || !isFinite(m.t)) continue
      if (m.t < from) { lastBefore = m; continue }
      var col = Math.max(0, Math.min(n - 1, Math.floor((m.t - from) / w)))
      if (isParts && !sums[col]) continue
      var v = isParts ? (m.parts || [0, 0, 0, 0, 0]) : (m[key] || 0)
      if (isParts) for (var k = 0; k < 5; k++) sums[col][k] += Number(v[k]) || 0
      else sums[col] = peak ? Math.max(sums[col], v) : sums[col] + v
      counts[col]++
    }
    var prev = lastBefore ? { t: lastBefore.t, v: isParts ? (lastBefore.parts || empty) : (lastBefore[key] || 0) } : null
    for (var j = 0; j < n; j++) {
      if (counts[j]) {
        var val = isParts ? sums[j].map(function(x) { return x / counts[j] }) : (peak ? sums[j] : sums[j] / counts[j])
        vals.push(val); prev = { t: times[j], v: val }
      } else if (prev && times[j] - prev.t <= Math.max(120, w)) vals.push(prev.v)
      else vals.push(empty)
    }
    return { vals: vals, times: times }
  }
  function downsample(vals, cols, peak) {
    if (!cols || vals.length <= cols) return vals
    var out = [], step = vals.length / cols
    for (var i = 0; i < cols; i++) {
      var a = Math.floor(i * step), b = Math.max(a + 1, Math.floor((i + 1) * step))
      var chunk = vals.slice(a, b)
      if (Array.isArray(chunk[0])) {
        var acc = chunk[0].map(function() { return 0 })
        chunk.forEach(function(c) { for (var k = 0; k < acc.length; k++) acc[k] += c[k] / chunk.length })
        out.push(acc)
      } else if (peak) out.push(Math.max.apply(null, chunk))
      else out.push(chunk.reduce(function(s, v) { return s + v }, 0) / chunk.length)
    }
    return out
  }
  // Les événements de la plage, du plus récent au plus ancien.
  function rangeEvents() {
    var from = Date.now() / 1000 - rangeSpan[range]
    return events.filter(function(e) { return e.t >= from }).slice().reverse()
  }
  function hhmm(t) {
    var d = new Date(t * 1000)
    return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
  }
  function eventColor(kind) {
    return kind === "open" ? cApps : kind === "close" ? cKernel : kind === "leak" ? cFiles : warn
  }

  // ── couleurs (thème Omarchy + teintes façon btop) ──
  readonly property color fg: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color warn: Commons.Color.urgent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.68)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.18)
  readonly property color cSessions: "#7aa2f7"
  readonly property color cApps: "#8fbf7f"
  readonly property color cFiles: "#e0af68"
  readonly property color cKernel: "#9a9aa8"
  readonly property color cNet: "#bb9af7"
  readonly property color cGpu: "#f7768e"
  readonly property int fs: Style.font.bodySmall
  readonly property int rowH: Math.round(fs * 1.75)

  // ── données dérivées ──
  readonly property var sessions: {
    if (!info) return []
    return info.groups.filter(function(g) { return g.kind === "claude" })
      .sort(function(a, b) { return b.facture - a.facture })
  }
  readonly property var apps: info ? info.groups.filter(function(g) { return g.kind !== "claude" }) : []
  // Lignes « sans processus » du tableau : la mémoire qui n'appartient à personne,
  // pour que le total du tableau fasse toute la RAM utilisée.
  readonly property var personneRows: {
    if (!info) return []
    var p = info.personne
    var orphans = p.orphans.reduce(function(s, o) { return s + o.cost }, 0)
    function row(id, name, v, desc) {
      return { id: "personne:" + id, kind: "personne", name: name, ram: Math.max(0, v), zram: 0, procs: 0, cpu: 0,
               idle: 0, poids_mort: 0, roots: [], twins: [], protected: true, paused: false, scratch: 0, desc: desc }
    }
    return [
      row("tmp", t("/tmp et mémoire partagée", "/tmp and shared memory"), p.files_ram + p.files_zram,
          t("Des fichiers stockés en RAM : /tmp, /dev/shm, /run.", "Files stored in RAM: /tmp, /dev/shm, /run.")
          + (hasClaude ? t(" Les scratchpads des sessions Claude en font partie (déjà comptés dans leur facture : la colonne /tmp)",
                           " Claude sessions' scratchpads are part of it (already counted in their bill: the /tmp column)") : "")
          + (orphans > 1048576 ? t(", plus ", ", plus ") + go(orphans) + t(" de scratchpads de sessions fermées, à vider depuis la carte ou « libère-moi »",
                                                                         " of scratchpads from closed sessions, to clear from the card or “free me”") : "")
          + t(". Une partie est compressée dans la zram.", ". Part of it is compressed in zram.")),
      row("noyau", t("noyau", "kernel"), p.kernel,
          t("La mémoire du noyau Linux lui-même : tables de pages, piles, caches internes non récupérables.",
            "The Linux kernel's own memory: page tables, stacks, internal caches that can't be reclaimed.")),
      row("reserve", t("réserve du noyau", "kernel reserve"), p.reserve,
          t("Ce que le noyau garde toujours libre pour ne jamais tomber en panne de mémoire. On ne peut pas la récupérer.",
            "What the kernel always keeps free so it never runs out of memory. It can't be reclaimed.")),
      row("gpu", t("prêtée au GPU", "lent to the GPU"), p.gpu,
          t("De la RAM prêtée au GPU (la carte graphique) en plus de sa VRAM (textures, tampons des fenêtres et des jeux).",
            "RAM lent to the GPU (graphics card) on top of its VRAM (textures, window and game buffers).")),
      row("ecart", t("écart non expliqué", "unexplained gap"), info.ecart,
          t("Ce que Ardoise n'arrive pas à attribuer : pilotes, cache verrouillé, mémoire que le noyau ne détaille pas. Affiché honnêtement plutôt que caché.",
            "What Ardoise can't attribute: drivers, locked cache, memory the kernel doesn't break down. Shown honestly rather than hidden."))
    ]
  }
  readonly property var separatorRow: ({ id: "sep", kind: "sep", name: "", ram: 0, zram: 0, procs: 0, cpu: 0, idle: 0,
                                         poids_mort: 0, roots: [], twins: [], protected: true, paused: false, scratch: 0 })
  readonly property var groupById: {
    var m = {}
    if (info) for (var i = 0; i < info.groups.length; i++) m[info.groups[i].id] = info.groups[i]
    for (var j = 0; j < personneRows.length; j++) m[personneRows[j].id] = personneRows[j]
    m["sep"] = separatorRow
    var t = tableGroups
    for (var k = 0; k < t.length; k++) if (t[k].kind === "petits") m[t[k].id] = t[k]
    return m
  }
  readonly property real sessionsTotal: sessions.reduce(function(s, g) { return s + g.ram + g.zram }, 0)
  readonly property real appsTotal: apps.reduce(function(s, g) { return s + g.ram + g.zram }, 0)
  readonly property real filesTotal: info ? info.personne.files_ram + info.personne.files_zram : 0
  readonly property real kernelTotal: info ? info.personne.kernel + info.personne.reserve + info.personne.gpu : 0
  readonly property real ecart: info ? Math.max(0, info.ecart) : 0
  readonly property var twins: sessions.filter(function(g) { return g.twins && g.twins.length && g.scratch_size > 0 })
  readonly property var orphans: info ? info.personne.orphans.filter(function(o) { return o.size > 1048576 }) : []

  // Lignes de la table : le cœur du PC épinglé en haut (ni trié ni filtré),
  // un séparateur, puis les groupes de processus, filtrés par la recherche et triés.
  readonly property var tableGroups: {
    if (!info) return []
    var q = search.trim().toLowerCase()
    var byGroup = procsByGroup
    var flt = filter
    var list = info.groups.filter(function(g) {
      if (flt === "sessions" && g.kind !== "claude") return false
      if (flt === "applis" && g.kind === "claude") return false
      if (flt === "calmes" && !(g.idle > 3600)) return false
      if (flt === "fuites" && !g.leak) return false
      if (q === "") return true
      if (String(g.name).toLowerCase().indexOf(q) >= 0) return true
      var ps = byGroup[g.id] || []
      for (var i = 0; i < ps.length; i++)
        if (ps[i].label.toLowerCase().indexOf(q) >= 0 || ps[i].cmd.toLowerCase().indexOf(q) >= 0 || String(ps[i].pid) === q) return true
      return false
    })
    var key = sortKey, dir = sortAsc ? 1 : -1
    function val(g) {
      if (key === "name") return String(g.name).toLowerCase()
      if (key === "procs") return g.procs
      if (key === "cpu") return g.cpu
      if (key === "tmp") return g.scratch || 0
      if (key === "idle") return g.idle
      if (key === "poids") return g.poids_mort
      if (key === "pct") return g.ram + g.zram
      return g.ram + g.zram
    }
    list.sort(function(a, b) {
      var va = val(a), vb = val(b)
      return (va < vb ? -1 : va > vb ? 1 : 0) * dir
    })
    // les petits groupes (moins de 70 Mo, ni session ni fuite) se rangent dans une seule ligne,
    // sauf pendant une recherche ou un filtre
    if (q === "" && flt === "tout") {
      var big = [], small = []
      for (var i = 0; i < list.length; i++) {
        var g = list[i]
        if (g.kind !== "claude" && !g.leak && g.ram + g.zram < smallLimit) small.push(g); else big.push(g)
      }
      if (small.length > 2) {
        var sum = function(f) { return small.reduce(function(s, x) { return s + f(x) }, 0) }
        var fold = { id: "petits", kind: "petits", name: small.length + t(" petits groupes (< ", " small groups (< ") + go(smallLimit) + ")",
                     ram: sum(function(x) { return x.ram }), zram: sum(function(x) { return x.zram }), procs: sum(function(x) { return x.procs }),
                     cpu: sum(function(x) { return x.cpu }), idle: 0, poids_mort: 0, roots: [], twins: [], protected: true, paused: false, scratch: 0,
                     desc: t("Les groupes qui pèsent moins de ", "Groups weighing less than ") + go(smallLimit)
                           + t(" chacun, rangés ici pour alléger le tableau. Un clic les déplie.", " each, folded here to lighten the table. Click to expand.") }
        list = big.concat([fold], expanded["petits"] ? small : [])
      }
    }
    return personneRows.concat([separatorRow], list)
  }

  // ── formats ──
  function go(n) {
    n = Number(n) || 0
    if (Math.abs(n) >= 1073741824) return num(n / 1073741824, 1) + t(" Go", " GB")
    if (Math.abs(n) >= 1048576) return Math.round(n / 1048576) + t(" Mo", " MB")
    return Math.round(n / 1024) + t(" Ko", " KB")
  }
  function rate(n) { return go(n) + "/s" }
  function dur(s) {
    s = Math.floor(Number(s) || 0)
    if (s >= 86400) return Math.floor(s / 86400) + t(" j ", " d ") + Math.floor(s % 86400 / 3600) + " h"
    if (s >= 3600) return Math.floor(s / 3600) + " h " + String(Math.floor(s % 3600 / 60)).padStart(2, "0")
    if (s >= 60) return Math.floor(s / 60) + " min"
    return t("actif", "active")
  }
  function pctTxt(v) { v = Number(v) || 0; return (v >= 10 ? v.toFixed(0) : num(v, 1)) + " %" }

  // ── actions ──
  function arm(key) { armed = key; disarm.restart() }
  // Clic sur un en-tête : trie par cette colonne ; un second clic inverse le sens.
  function sortBy(key) {
    if (sortKey === key) sortAsc = !sortAsc
    else { sortKey = key; sortAsc = key === "name" }
  }
  function run(args, done) {
    actProc.doneText = done || ""
    actProc.command = ["python3", root.cli].concat(args, ["--lang", root.lang])
    actProc.running = true
  }
  function toggleExpanded(id) {
    var e = Object.assign({}, expanded)
    if (e[id]) delete e[id]; else e[id] = true
    expanded = e
  }
  function liberer(n) {
    basketTarget = n
    basket = null
    liberProc.command = ["python3", root.cli, "liberer", String(n), "--lang", root.lang]
    liberProc.running = true
  }
  property bool analysing: analyseProc.running
  function analyser(raison) {
    if (analyseProc.running || !hasClaude) return
    analyseProc.command = ["python3", root.cli, "analyser", "--lang", root.lang, "--raison", raison || t("demandée depuis Ardoise", "requested from Ardoise")]
    analyseProc.running = true
    closeWindow(); close()
  }
  function openWindow() { close(); windowOpen = true }
  function closeWindow() { windowOpen = false; armed = "" }
  function toggleWindow() { windowOpen ? closeWindow() : openWindow() }
  function refresh() { if (flux.running) flux.write("tick\n") }

  function push(arr, v) {
    var a = arr.length >= historyLen ? arr.slice(arr.length - historyLen + 1) : arr.slice()
    a.push(v)
    return a
  }
  function ingest(line) {
    var d
    try { d = JSON.parse(line) } catch (e) { return }
    if (d.type === "hw") { hw = d.hw; return }
    if (d.type === "hist") { minutes = d.points; events = d.events; return }
    if (d.type === "minute") {
      var m = minutes.length > 1500 ? minutes.slice(minutes.length - 1440) : minutes.slice()
      m.push(d.point); minutes = m; return
    }
    if (d.type === "event") {
      var ev = events.length > 400 ? events.slice(events.length - 300) : events.slice()
      ev.push(d.event); events = ev; return
    }
    if (d.type === "sys") {
      sys = d
      hCpu = push(hCpu, d.cpu)
      hMem = push(hMem, 100 * d.used / d.total)
      hZram = push(hZram, d.zram.data > 0 ? 100 * d.zram.used / d.total : 0)
      hRx = push(hRx, d.net.rx)
      hTx = push(hTx, d.net.tx)
      hRead = push(hRead, d.disk.read)
      hWrite = push(hWrite, d.disk.write)
      hGpu = push(hGpu, d.gpu.busy === null ? 0 : d.gpu.busy)
      hT = push(hT, d.time)
    } else if (d.type === "full") {
      var by = {}
      if (d.procs) {
        for (var i = 0; i < d.procs.length; i++) {
          var p = d.procs[i]
          if (!by[p.group]) by[p.group] = []
          by[p.group].push(p)
        }
        for (var k in by) by[k].sort(function(a, b) { return (b.ram + b.swap) - (a.ram + a.swap) })
      }
      if (d.procs) procsByGroup = by
      info = d
      var s = 0, a = 0
      for (var j = 0; j < d.groups.length; j++) {
        var g = d.groups[j]
        if (g.kind === "claude") s += g.ram + g.zram; else a += g.ram + g.zram
      }
      hBreak = push(hBreak, [s, a, d.personne.files_ram + d.personne.files_zram,
                             d.personne.kernel + d.personne.reserve + d.personne.gpu, Math.max(0, d.ecart)])
      hBreakT = push(hBreakT, d.time)
    }
  }

  onWantFullChanged: if (flux.running) flux.write(wantFull ? "open\n" : "close\n")
  onOpenedChanged: if (!opened) armed = ""

  Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }
  Timer { id: toastTimer; interval: 6000; onTriggered: root.toast = "" }

  Process {
    id: flux
    command: ["python3", root.cli, "--flux", "--seuil", String(root.setting("alertThreshold", 85)), "--lang", root.lang]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.ingest(line) } }
    onStarted: if (root.wantFull) flux.write("open\n")
    onExited: restartFlux.start()
  }
  Timer { id: restartFlux; interval: 3000; onTriggered: flux.running = true }

  Process {
    id: actProc
    property string doneText: ""
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: function(code) {
      var err = actErr.text.trim()
      root.toast = code === 0 ? (doneText || actOut.text.trim().split("\n").pop()) : (err.split("\n").pop() || root.t("échec", "failed"))
      toastTimer.restart()
      root.basket = null
      root.refresh()
    }
  }

  Process {
    id: analyseProc
    stderr: StdioCollector { id: analyseErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.toast = analyseErr.text.trim().split("\n").pop() || root.t("l'analyse n'a pas pu s'ouvrir", "the analysis could not open"); toastTimer.restart() }
    }
  }

  Process {
    id: liberProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.basket = JSON.parse(text) } catch (e) { root.basket = null } }
    }
  }

  ShellIpc {
    target: "io.github.smilecry44.ardoise"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function openWindow(): void { root.openWindow() }
    function closeWindow(): void { root.closeWindow() }
    function toggleWindow(): void { root.toggleWindow() }
    function liberer(go: int): void { root.openWindow(); root.liberer(go) }
    function analyser(): void { root.analyser("") }
    function chercher(texte: string): void { root.openWindow(); root.search = texte }
    function vue(plage: string): void { root.range = plage === "5min" ? "live" : plage }
    function bulle(nom: string): void { root.openWindow(); root.bulleDemandee(nom) }
  }

  // ── pastille façon OmaControl : « 󰍛 CPU 14%  RAM 69%  Disk 31% » ──
  // Réglage `barStats` dans shell.json : liste parmi cpu, temp, ram, swap, disk, gpu, vram.
  readonly property var barStats: setting("barStats", ["cpu", "ram", "disk"])
  readonly property bool barAlert: !!sys && (pct >= 90 || sys.cpu >= 95)
  function statText(id) {
    if (!sys) return ""
    if (id === "cpu") return "CPU " + Math.round(sys.cpu) + "%"
    if (id === "temp") return sys.cpu_temp ? Math.round(sys.cpu_temp) + "°" : ""
    if (id === "ram") return "RAM " + pct + "%"
    if (id === "swap") return sys.zram.data > 0 ? "zram " + go(sys.zram.used) : ""
    if (id === "disk") return sys.disks.length ? "Disk " + Math.round(100 * sys.disks[0].used / sys.disks[0].total) + "%" : ""
    if (id === "gpu") return sys.gpu.busy !== null ? "GPU " + sys.gpu.busy + "%" : ""
    if (id === "vram") return sys.gpu.vram_total ? "VRAM " + Math.round(100 * sys.gpu.vram_used / sys.gpu.vram_total) + "%" : ""
    return ""
  }
  readonly property string barLabel: {
    if (!sys) return "󰍛 …"
    var parts = []
    for (var i = 0; i < barStats.length; i++) { var t = statText(barStats[i]); if (t) parts.push(t) }
    return (barAlert ? "\uf071 " : "󰍛 ") + parts.join("  ")
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    fontSize: Style.font.caption
    active: root.barAlert
    tooltipText: !root.sys ? "Ardoise" :
      "Ardoise\n"
      + "CPU " + Math.round(root.sys.cpu) + " %" + (root.sys.cpu_temp ? " · " + Math.round(root.sys.cpu_temp) + "°" : "") + "\n"
      + "RAM " + root.go(root.sys.used) + " / " + root.go(root.sys.total) + root.t(" (dispo ", " (available ") + root.go(root.sys.available) + ")\n"
      + (root.sys.zram.data > 0 ? "zram " + root.go(root.sys.zram.data) + " → " + root.go(root.sys.zram.used) + "\n" : "")
      + (root.sys.gpu.busy !== null ? "GPU " + root.sys.gpu.busy + " % · VRAM " + root.go(root.sys.gpu.vram_used) + "\n" : "")
      + root.t("\nClic : la fenêtre Ardoise", "\nClick: open the Ardoise window")
    // tous les clics ouvrent ou ferment la fenêtre centrée (la petite carte n'est plus utilisée)
    onPressed: function(b) { root.toggleWindow() }
  }

  // ── fenêtre centrée, chargée seulement quand elle est ouverte ──
  Loader {
    active: root.windowOpen
    source: Qt.resolvedUrl("Window.qml")
    onLoaded: {
      item.screenRef = button.QsWindow.window ? button.QsWindow.window.screen : null
      item.hub = root
    }
  }

  // ── carte (clic sur la pastille) ──
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: col.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        // en-tête
        Item {
          width: parent.width
          implicitHeight: head.implicitHeight
          Column {
            id: head
            spacing: Style.space(2)
            Text {
              text: "ARDOISE"
              color: root.fg
              font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true; font.letterSpacing: 3
            }
            RqText {
              color: root.dim
              text: !root.sys ? root.t("lecture…", "reading…") :
                go(root.sys.used) + " / " + go(root.sys.total) + root.t(" · dispo ", " · available ") + go(root.sys.available)
                + (root.sys.zram.data > 0 ? " · zram " + go(root.sys.zram.data) + " → " + go(root.sys.zram.used) : "")
            }
          }
          Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: root.pct + "%"
            color: root.pct >= 85 ? root.warn : root.fg
            font.family: Style.font.family; font.pixelSize: Style.font.displayLarge; font.bold: true
          }
        }

        // bilan : une barre qui fait 100 % de la RAM utilisée
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.info
          Row {
            id: stack
            width: parent.width
            height: Style.space(10)
            readonly property real used: root.info ? root.info.used : 1
            Repeater {
              model: [
                { v: root.sessionsTotal, c: root.cSessions }, { v: root.appsTotal, c: root.cApps },
                { v: root.filesTotal, c: root.cFiles }, { v: root.kernelTotal, c: root.cKernel },
                { v: root.ecart, c: root.faint }
              ]
              Rectangle { width: Math.max(0, stack.width * modelData.v / stack.used); height: stack.height; color: modelData.c; radius: 2 }
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(12)
            Repeater {
              model: [
                { t: "sessions", v: root.sessionsTotal, c: root.cSessions }, { t: root.t("applis", "apps"), v: root.appsTotal, c: root.cApps },
                { t: "/tmp", v: root.filesTotal, c: root.cFiles }, { t: root.t("noyau", "kernel"), v: root.kernelTotal, c: root.cKernel },
                { t: root.t("écart", "gap"), v: root.ecart, c: root.faint }
              ]
              Row {
                spacing: Style.space(4)
                Rectangle { width: 7; height: 7; radius: 2; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                RqText { text: modelData.t + " " + go(modelData.v); color: root.dim; font.pixelSize: Style.font.caption }
              }
            }
          }
        }

        // ¹ sessions Claude
        RqBox {
          width: parent.width
          num: "¹"; title: root.t("sessions claude", "claude sessions")
          aside: root.sessions.length + " · " + go(root.sessions.reduce(function(s, g) { return s + g.facture }, 0))
          visible: root.sessions.length > 0

          Item {
            width: parent.width; height: root.rowH
            RqText { x: 0; width: parent.width * 0.40; text: "session"; color: root.dim; font.pixelSize: Style.font.caption }
            RqText { x: parent.width * 0.40; width: parent.width * 0.17; text: root.t("facture", "bill"); color: root.dim; horizontalAlignment: Text.AlignRight; font.pixelSize: Style.font.caption }
            RqText { x: parent.width * 0.62; width: parent.width * 0.20; text: root.t("calme", "idle"); color: root.dim; font.pixelSize: Style.font.caption }
          }
          Repeater {
            model: root.sessions.slice(0, 9)
            Item {
              width: parent.width; height: root.rowH
              RqText {
                x: 0; width: parent.width * 0.40 - 6
                text: modelData.name + (modelData.twins && modelData.twins.length ? " ×2" : "")
                color: modelData.twins && modelData.twins.length ? root.warn : nameMa.containsMouse && modelData.terminal ? root.accent : root.fg
                font.underline: nameMa.containsMouse && !!modelData.terminal
                MouseArea {
                  id: nameMa
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !!modelData.terminal
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.run(["montrer", String(modelData.pid)]); root.close() }
                }
              }
              RqText {
                x: parent.width * 0.40; width: parent.width * 0.17
                text: go(modelData.facture); horizontalAlignment: Text.AlignRight
                color: modelData.scratch > 1073741824 ? root.warn : root.fg
              }
              RqText {
                x: parent.width * 0.62; width: parent.width * 0.22
                text: dur(modelData.idle)
                color: modelData.idle > 3 * 3600 ? root.cFiles : root.dim
              }
              RqAct {
                anchors.right: parent.right; height: parent.height
                hub: root; confirm: true; danger: true
                key: "fermer-" + modelData.pid; label: root.t("fermer", "close")
                onActivated: root.run(["fermer", String(modelData.pid)], modelData.name + root.t(" fermée (reprise : claude --resume)", " closed (resume: claude --resume)"))
              }
            }
          }
          RqText {
            visible: root.sessions.length > 9
            width: parent.width; height: root.rowH
            color: root.dim
            text: "+ " + (root.sessions.length - 9) + root.t(" autres · ", " more · ") + go(root.sessions.slice(9).reduce(function(s, g) { return s + g.facture }, 0))
          }
          Repeater {
            model: root.twins
            RqText {
              width: parent.width; height: root.rowH
              color: root.warn
              text: "! " + modelData.name + root.t(" et ", " and ") + modelData.twins.join(", ") + root.t(" : même conversation", ": same conversation")
            }
          }
          RqText {
            width: parent.width; height: root.rowH
            color: root.dim
            font.pixelSize: Style.font.caption
            text: root.t("facture = processus + MCP + zram + /tmp", "bill = process + MCP + zram + /tmp")
          }
        }

        // ² personne
        RqBox {
          width: parent.width
          num: "²"; title: root.t("personne", "nobody")
          aside: go(root.filesTotal + root.kernelTotal + root.ecart)
          visible: !!root.info

          Repeater {
            model: root.info ? [
              { t: root.t("fichiers en RAM (/tmp, shm)", "files in RAM (/tmp, shm)"), v: root.filesTotal, c: root.cFiles },
              { t: root.t("noyau", "kernel"), v: root.info.personne.kernel, c: root.cKernel },
              { t: root.t("réserve du noyau", "kernel reserve"), v: root.info.personne.reserve, c: root.cKernel },
              { t: root.t("prêtée au GPU", "lent to the GPU"), v: root.info.personne.gpu, c: root.cKernel },
              { t: root.t("écart non expliqué", "unexplained gap"), v: root.ecart, c: root.faint, gap: true }
            ] : []
            Item {
              width: parent.width; height: root.rowH
              RqText { width: parent.width * 0.50; text: modelData.t; color: modelData.gap ? root.dim : root.fg }
              RqText { x: parent.width * 0.50; width: parent.width * 0.17; text: go(modelData.v); horizontalAlignment: Text.AlignRight }
              RqDots {
                x: parent.width * 0.71; anchors.verticalCenter: parent.verticalCenter
                count: 14; tint: modelData.c
                frac: root.info ? modelData.v / Math.max(root.filesTotal, root.info.personne.kernel, root.info.personne.reserve, root.ecart, 1) : 0
              }
            }
          }
          Repeater {
            model: root.orphans.slice(0, 4)
            Item {
              width: parent.width; height: root.rowH
              RqText { width: parent.width * 0.50; text: root.t("  scratchpad fermé ", "  closed scratchpad ") + modelData.session.slice(0, 8); color: root.dim }
              RqText { x: parent.width * 0.50; width: parent.width * 0.17; text: go(modelData.cost); horizontalAlignment: Text.AlignRight; color: root.dim }
              RqAct {
                anchors.right: parent.right; height: parent.height
                hub: root; confirm: true
                key: "vider-" + modelData.session; label: root.t("vider", "clear")
                onActivated: root.run(["vider", modelData.session], "scratchpad " + modelData.session.slice(0, 8) + root.t(" supprimé", " deleted"))
              }
            }
          }
        }

        // ³ applis
        RqBox {
          width: parent.width
          num: "³"; title: root.t("applis", "apps")
          aside: go(root.appsTotal)
          visible: root.apps.length > 0
          Repeater {
            model: root.apps.slice(0, 7)
            Item {
              width: parent.width; height: root.rowH
              RqText { width: parent.width * 0.50; text: modelData.name + (modelData.procs > 1 ? "  ×" + modelData.procs : "") }
              RqText { x: parent.width * 0.50; width: parent.width * 0.17; text: go(modelData.ram + modelData.zram); horizontalAlignment: Text.AlignRight }
              RqDots {
                x: parent.width * 0.71; anchors.verticalCenter: parent.verticalCenter
                count: 14; tint: root.cApps
                frac: root.apps.length ? (modelData.ram + modelData.zram) / (root.apps[0].ram + root.apps[0].zram) : 0
              }
            }
          }
        }

        // ⁴ clones
        RqBox {
          width: parent.width
          num: "⁴"; title: "clones"
          aside: root.info ? go(root.info.clones.reduce(function(s, c) { return s + c.mem }, 0)) : ""
          visible: !!root.info && root.info.clones.length > 0
          Repeater {
            model: root.info ? root.info.clones.slice(0, 5) : []
            Item {
              width: parent.width; height: root.rowH
              RqText { width: parent.width * 0.50; text: modelData.count + " × " + modelData.name }
              RqText { x: parent.width * 0.50; width: parent.width * 0.17; text: go(modelData.mem); horizontalAlignment: Text.AlignRight }
              RqText { x: parent.width * 0.71; width: parent.width * 0.29; text: root.t("1 par session", "1 per session"); color: root.dim; font.pixelSize: Style.font.caption }
            }
          }
        }

        // pied
        Item {
          width: parent.width; height: root.rowH
          RqText {
            width: parent.width * 0.62
            text: root.toast !== "" ? root.toast : root.t("clic droit sur la pastille : fenêtre", "right-click the badge: window")
            color: root.toast !== "" ? root.accent : root.dim
            font.pixelSize: Style.font.caption
          }
          RqAct {
            anchors.right: parent.right; height: parent.height
            hub: root; label: root.t("⤢ ouvrir la fenêtre", "⤢ open the window")
            onActivated: root.openWindow()
          }
        }
      }
    }
  }
}
