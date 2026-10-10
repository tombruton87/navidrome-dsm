// Navidrome's tabs on the chassis window: Library, Phones, Users, and the HTTPS part of Site address.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var EVERY = { "15m": "every 15 minutes", "1h": "every hour", "6h": "every 6 hours", "24h": "once a day", "0": "only when asked" };
  function ndUrl(st) { return ((st.app || {}).url || "").replace(/\/$/, ""); }
  function touched(id) { ["input", "change"].forEach(function (e) { $(id).addEventListener(e, function () { $(id).dataset.touched = "1"; }); }); }
  function quiet(id, v) { if (!$(id).dataset.touched) $(id).value = v == null ? "" : v; }
  function iso(s) { var t = s ? Date.parse(s) / 1000 : 0; return t > 0 ? t : 0; }

  // ---------------------------------------------------------------- Library
  ["lb-every", "lb-dir"].forEach(touched);
  P.register("library", {
    render: function (st) {
      var a = st.app || {}, l = a.library || {}, sc = a.scan || {}, m = a.music || {}, t = $("lb-tiles");
      document.querySelectorAll(".nd-link").forEach(function (x) { x.href = ndUrl(st) || "#"; });
      P.clear(t); P.tile(t, String(l.artists || 0), "artists"); P.tile(t, String(l.albums || 0), "albums"); P.tile(t, String(l.songs || 0), "songs");
      $("lb-scan").textContent = sc.scanning ? "Scanning now — " + (sc.count || 0) + " songs so far." : (iso(sc.lastScan) ? "Last scan " + P.ago(iso(sc.lastScan)) + (sc.scanType ? " (" + sc.scanType + ")" : "") + ". " : "Not scanned yet. ") + "Looking for new music " + (EVERY[m.every] || m.every || "every hour") + ".";
      quiet("lb-every", m.every || "1h"); quiet("lb-dir", m.dir || "");
      $("lb-files").textContent = (m.files == null ? "" : m.files + " music files in " + m.dir + ".")
        + (l.missing ? " " + l.missing + " song" + (l.missing === 1 ? " is" : "s are") + " no longer in the folder: Navidrome keeps their plays and ratings in case they come back (remove them in Navidrome → Missing files)." : "");
      var s = $("lb-share"), b = $("lb-share-btn"); P.clear(s); P.clear(b);
      s.appendChild(a.sharing ? P.chip("on", "ok") : P.chip("off", ""));
      b.appendChild(P.btn(a.sharing ? "Turn off" : "Turn on", "", function () { P.act("sharing", { on: a.sharing ? 0 : 1 }); }));
    },
    tiles: function (t, st) { var l = (st.app || {}).library || {}; P.tile(t, String(l.songs || 0), "songs"); }
  });
  $("lb-scan-now").onclick = function () { P.act("scan", { full: 0 }); };
  $("lb-scan-full").onclick = function () { P.act("scan", { full: 1 }, "Read every file again? On a big library this takes a while; quick scans already find new music."); };
  $("lb-every-save").onclick = function () { P.act("scanevery", { every: $("lb-every").value }).then(function () { $("lb-every").dataset.touched = ""; }); };
  $("lb-dir-save").onclick = function () { P.act("musicdir", { dir: $("lb-dir").value.trim() }, "Play the music in " + $("lb-dir").value.trim() + "? Navidrome reads it again from scratch.").then(function () { $("lb-dir").dataset.touched = ""; }); };

  // ---------------------------------------------------------------- Phones
  P.register("phones", {
    render: function (st) {
      var a = st.app || {};
      if (a.qr && $("ph-qr").dataset.qr !== a.qr) { $("ph-qr").src = "data:image/png;base64," + a.qr; $("ph-qr").dataset.qr = a.qr; }
      $("ph-url").textContent = a.url || "";
      $("ph-reach").textContent = /^https?:\/\/(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.)/.test(a.url || "")
        ? "An address on your own network: apps play at home. For anywhere else, give Navidrome an address reachable from outside on the Site address tab."
        : "Apps can reach this from anywhere it resolves.";
    }
  });

  // ---------------------------------------------------------------- Users
  P.register("users", {
    render: function (st) {
      var a = st.app || {}, users = a.users || [], tb = $("users");
      var sig = JSON.stringify(users) + "|" + P.busy + "|" + P.role; if (tb.dataset.sig === sig) return; tb.dataset.sig = sig; P.clear(tb);
      users.forEach(function (u) {
        var pkg = u.user === a.pkg_admin, mine = u.user === a.admin_user, who = P.el("div"), acts = P.el("span", null, "row");
        who.appendChild(P.el("b", u.user)); if (pkg) who.appendChild(P.el("div", "the package's own administrator", "muted small")); else if (mine) who.appendChild(P.el("div", "you", "muted small"));
        if (!pkg) {
          acts.appendChild(P.btn("New password", "", function () { P.act("userpw", { id: u.id }, "Make a new password for " + u.user + "? Their apps need it too."); }));
          if (!mine) acts.appendChild(u.admin ? P.btn("Listener only", "", function () { P.act("setadmin", { id: u.id, role: "user" }); }) : P.btn("Make admin", "", function () { P.act("setadmin", { id: u.id, role: "admin" }, "Make " + u.user + " an administrator?"); }));
          if (!mine) acts.appendChild(P.btn("Remove", "danger", function () { P.act("userdel", { id: u.id }, "Remove " + u.user + "? Their playlists and favourites go too."); }));
        }
        var tr = P.row(tb, [P.cell(who), u.admin ? P.chip("administrator", "ok") : P.chip("listener", ""), iso(u.last_access) ? P.ago(iso(u.last_access)) : "never", P.cell(acts, "n")]);
        if (pkg) tr.className = "muted-row";
      });
    }
  });
  P.register("secretNote", function (s) { return s.kind === "users" ? "Use it in Navidrome and in the music apps, then keep it in your password manager." : ""; });
  $("nu-add").onclick = function () { P.act("useradd", { user: $("nu-name").value.trim(), role: $("nu-role").value }).then(function () { $("nu-name").value = ""; }); };

  // ---------------------------------------------------------------- Site address: HTTPS
  P.register("site", {
    fill: function (st) { var t = (st.app && st.app.tls) || {}; $("set-tls").value = t.mode || "off"; },
    values: function () { return { tls: $("set-tls").value }; },
    render: function (st) {
      var t = (st.app && st.app.tls) || {}, c = t.cert, tb = $("tls-info"), note = $("tls-note"), acts = $("tls-actions"); P.clear(tb); P.clear(acts);
      $("tls-card").hidden = !t.mode || t.mode === "off";
      if (!t.mode || t.mode === "off") return;
      if (!c) { P.kv(tb, "Certificate", "none yet — it's made or read when Navidrome starts"); note.textContent = ""; return; }
      P.kv(tb, "From", t.source === "dsm" ? "DSM (the system default certificate)" : "the package (self-signed)");
      P.kv(tb, "Issued to", c.subject || "–"); P.kv(tb, "Issued by", c.self_signed ? "itself (self-signed)" : (c.issuer || "–"));
      P.kv(tb, "Expires", (c.expires || "–") + (typeof c.days_left === "number" ? " (" + (c.days_left < 0 ? "expired" : c.days_left + " days") + ")" : ""));
      if (c.names) P.kv(tb, "Names", c.names.replace(/,/g, ", "));
      note.textContent = t.mode === "dsm" && t.source === "self" ? "DSM's certificate wasn't found on this system, so a self-signed one is in use."
        : c.self_signed ? "Self-signed: browsers warn once; most music apps won't accept it. Use a trusted certificate (Let's Encrypt in DSM, made the system default) or DSM's reverse proxy with a domain."
        : "Browsers and apps trust this certificate as long as they reach Navidrome by one of its names.";
      acts.appendChild(P.btn(t.mode === "dsm" ? "Read DSM's certificate again" : "Make a new self-signed certificate", "", function () { P.act("refreshcert", {}, t.mode === "dsm" ? null : "Make a new self-signed certificate?"); }));
    }
  });
  $("set-tls").addEventListener("change", function () { $("set-url").dataset.touched = "1"; var u = $("set-url").value.trim(); if ($("set-tls").value !== "off" && /^http:\/\//.test(u)) $("set-url").value = "https://" + u.slice(7); });

  // ---------------------------------------------------------------- Storage
  P.register("storage", { render: function (app, st, box) {
    P.clear(box); var c = P.el("div", null, "card"); c.appendChild(P.el("h2", "Inside the data volume")); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["Library database (navidrome.db)", app["navidrome.db"]], ["Cover art", app.artwork], ["Transcoding and image cache", app.cache]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); });
    c.appendChild(P.el("p", "Your music isn't in here: it stays in your shared folder.", "muted small")); box.appendChild(c);
  } });
})(window.Panel);
