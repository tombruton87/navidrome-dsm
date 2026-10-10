# Navidrome's hooks for the chassis core (sourced by run-core.sh). The core
# gives: say, env_get/env_set, rand, compose, in_volume, cname, svc_up,
# leave_secret, fresh, now, qr_png_b64, MSG, VAR, APP, LOG, PKG_NAME,
# PKG_TITLE, and the tls_* helpers (chassis tls.sh).
#
# Navidrome's own API does the work: your account is made through its
# first-run endpoint; the window then acts through an administrator of the
# package's own ("dsm", password in the root-only settings file), and scans
# through the Subsonic API the phone apps use. Your password is never stored.

ND=""
PKG_ADMIN=dsm
JWT_FILE=""

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    ADMIN_USER|NUSER) [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ && "$2" != "$PKG_ADMIN" ]] ;;
    MUSIC_DIR_B64) [[ "$2" =~ ^[A-Za-z0-9_-]+$ ]] && (( ${#2} <= 700 )) ;;
    USER_ID)  [[ "$2" =~ ^[A-Za-z0-9]{10,40}$ ]] ;;
    ROLE)     [[ "$2" =~ ^(user|admin)$ ]] ;;
    FULL)     [[ "$2" =~ ^[01]$ ]] ;;
    SCAN_EVERY) [[ "$2" =~ ^(15m|1h|6h|24h|0)$ ]] ;;
    TLS)      [[ "$2" =~ ^(dsm|self|off)$ ]] ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ talking to Navidrome
b64d() { local s=${1//-/+}; s=${s//_//}; while (( ${#s} % 4 )); do s="$s="; done; printf '%s' "$s" | base64 -d 2>/dev/null; }
env_set_q() { local v=${2//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\$\$}; env_set "$1" "\"$v\""; }
env_get_q() { local v; v=$(env_get "$1"); v=${v#\"}; v=${v%\"}; v=${v//\$\$/\$}; v=${v//\\\"/\"}; printf '%s' "${v//\\\\/\\}"; }
scheme() { [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]] && echo https || echo http; }
nd_url() { echo "$(scheme)://127.0.0.1:$(env_get HTTP_PORT)"; }
strong_password() { echo "$(rand 5)-$(rand 5)-$(rand 5)-$(rand 5)"; }
nd_login() {   # → a token for the package's administrator, kept a few hours
  local tok; [[ -s "$JWT_FILE" ]] && fresh "$JWT_FILE" 7200 && { cat "$JWT_FILE"; return 0; }
  tok=$(curl -sk --max-time 15 -X POST "$(nd_url)/auth/login" -H 'Content-Type: application/json' \
        -d "$(jq -cn --arg u "$PKG_ADMIN" --arg p "$(env_get_q DSM_PASS)" '{username: $u, password: $p}')" 2>/dev/null | jq -r '.token // empty')
  [[ -n "$tok" ]] || return 1
  printf '%s' "$tok" > "$JWT_FILE"; chmod 600 "$JWT_FILE"; printf '%s' "$tok"
}
nd_api() {   # method path [json] → body (HTTP code in ND_CODE)
  local tok out; tok=$(nd_login) || { ND_CODE=0; return 1; }
  out=$(curl -sk --max-time 30 -X "$1" "$(nd_url)/api/$2" -H "x-nd-authorization: Bearer $tok" -H 'Content-Type: application/json' ${3:+-d "$3"} -w '\n%{http_code}' 2>/dev/null)
  ND_CODE=${out##*$'\n'}; out=${out%$'\n'*}
  [[ "$ND_CODE" == 401 ]] && { rm -f "$JWT_FILE"; }
  printf '%s' "$out"; [[ "$ND_CODE" =~ ^2 ]]
}
nd_count() { curl -sk --max-time 15 -o /dev/null -D - "$(nd_url)/api/$1?_start=0&_end=1&missing=${2:-false}" -H "x-nd-authorization: Bearer $(nd_login)" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1) == "x-total-count" {print $2}'; }
subsonic() {   # method [params] → JSON body, as the package's administrator (Subsonic token auth, like the phone apps)
  local salt t; salt=$(rand 12); t=$(printf '%s%s' "$(env_get_q DSM_PASS)" "$salt" | md5sum | cut -c1-32)
  curl -sk --max-time 30 "$(nd_url)/rest/$1?u=$PKG_ADMIN&t=$t&s=$salt&v=1.16.1&c=dsm-package&f=json${2:+&$2}" 2>/dev/null
}
# --mount, not -v: -v would quietly create a folder that isn't there.
music_check() {   # path → number of music files Navidrome would see (via the Docker daemon, which sees the NAS's own folders)
  docker run --rm --mount "type=bind,source=$1,target=/m,readonly" --entrypoint sh "$PKG_NAME-setup:local" -c \
    'find /m -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.wma" -o -iname "*.aiff" -o -iname "*.dsf" \) 2>/dev/null | wc -l' 2>/dev/null
}
music_dir_ok() { [[ "$1" == /* && "$1" != *..* && "$1" != *[,\"$'\n']* && ${#1} -le 300 ]] && docker run --rm --mount "type=bind,source=$1,target=/m,readonly" --entrypoint sh "$PKG_NAME-setup:local" -c 'test -d /m' 2>/dev/null; }
music_src() {   # what compose mounts at /music: the folder, or an empty placeholder in this share while it's missing
  if music_dir_ok "$(env_get_q MUSIC_DIR)"; then env_set_q MUSIC_SRC "$(env_get_q MUSIC_DIR)"
  else mkdir -p "$APP/no-music-yet"; env_set MUSIC_SRC ./no-music-yet; return 1; fi
}

# ------------------------------------------------------------ lifecycle hooks
app_first_env() {
  env_set ND_IMAGE deluan/navidrome:latest
  env_set ADMIN_USER "${ADMIN_USER:-admin}"; env_set DSM_USER "$PKG_ADMIN"; env_set_q DSM_PASS "$(strong_password)"
  local dir; dir=$(b64d "${MUSIC_DIR_B64:-}"); env_set_q MUSIC_DIR "${dir:-/volume1/music}"
  env_set SCAN_EVERY 1h; env_set SHARING false; env_set TLS "${TLS:-off}"
  tls_fix_scheme || true
  touch "$VAR/.needs-users"
}
app_load_env() { ND=$(cname server); JWT_FILE="$VAR/.nd-jwt"; }
app_before_up() {
  [[ -n "$(env_get TLS)" ]] || env_set TLS off
  music_src || say "✗ the music folder $(env_get_q MUSIC_DIR) isn't there — Navidrome starts with an empty library until it is (Music folder tab)"
  setup_tls || say "✗ HTTPS couldn't be set up: $MSG"
}
setup_tls() {
  tls_fix_scheme || true
  tls_prepare data || return 1
  if [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]]; then env_set TLS_CERT /data/tls/fullchain.pem; env_set TLS_KEY /data/tls/privkey.pem
  else env_set TLS_CERT ""; env_set TLS_KEY ""; fi
  qr_png_b64 "$(env_get APP_URL)" > "$VAR/qr.b64.tmp" && mv "$VAR/qr.b64.tmp" "$VAR/qr.b64"
}
app_health() { [[ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$(nd_url)/ping" 2>/dev/null)" == 200 ]]; }
app_version() { docker exec "$ND" /app/navidrome --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | head -n 1; }
app_after_up() { make_users 60; }
make_users() {   # [tries] — the first time: your account (Navidrome's first-run endpoint), then the package's own administrator
  [[ -f "$VAR/.needs-users" ]] || return 0
  local i pw user out tok; user=$(env_get ADMIN_USER)
  for i in $(seq 1 "${1:-1}"); do app_health && break; sleep 2; done
  app_health || { say "Navidrome isn't answering yet — your account is made when it does"; return 0; }
  pw=$(strong_password)
  out=$(curl -sk --max-time 15 -X POST "$(nd_url)/auth/createAdmin" -H 'Content-Type: application/json' -d "$(jq -cn --arg u "$user" --arg p "$pw" '{username: $u, password: $p}')" 2>/dev/null)
  tok=$(jq -r '.token // empty' <<< "$out" 2>/dev/null)
  if [[ -n "$tok" ]]; then
    leave_secret "Navidrome ($user)" "$pw" users; say "first start: your Navidrome account $user was made; the password is shown once in the window"
    curl -sk --max-time 15 -X POST "$(nd_url)/api/user" -H "x-nd-authorization: Bearer $tok" -H 'Content-Type: application/json' \
      -d "$(jq -cn --arg u "$PKG_ADMIN" --arg p "$(env_get_q DSM_PASS)" '{userName: $u, name: "DSM package (keep this one)", password: $p, isAdmin: true}')" -o /dev/null 2>/dev/null
  else say "Navidrome already has users — the package didn't make one ($(head -c 120 <<< "$out"))"; fi
  if nd_login >/dev/null; then rm -f "$VAR/.needs-users"; subsonic startScan >/dev/null; say "the package's administrator (dsm) is ready; a first scan started"
  else say "✗ the package's administrator couldn't sign in to Navidrome — the window can't manage users until it can"; fi
}

# ------------------------------------------------------------ what the window shows
app_status() {
  svc_up server || { echo '{"up": false}'; return 0; }
  local users scan artists albums songs missing
  users=$(nd_api GET "user?_sort=userName&_order=ASC" 2>/dev/null | jq -c 'map({id, user: .userName, name, admin: .isAdmin, last_access: .lastAccessAt, last_login: .lastLoginAt})' 2>/dev/null)
  scan=$(subsonic getScanStatus | jq -c '."subsonic-response".scanStatus // null' 2>/dev/null)
  artists=$(nd_count artist); albums=$(nd_count album); songs=$(nd_count song); missing=$(nd_count song true)   # missing: no longer in the folder (kept for their plays and ratings)
  [[ -s "$VAR/qr.b64" ]] || qr_png_b64 "$(env_get APP_URL)" > "$VAR/qr.b64"
  [[ -s "$VAR/cert.json" ]] || tls_info data
  if ! fresh "$VAR/.music-files" 21600; then music_check "$(env_get_q MUSIC_DIR)" | tr -cd '0-9' > "$VAR/.music-files"; fi
  jq -n -c --argjson users "${users:-[]}" --argjson scan "${scan:-null}" --arg artists "${artists:-0}" --arg albums "${albums:-0}" --arg songs "${songs:-0}" --arg missing "${missing:-0}" \
     --arg url "$(env_get APP_URL)" --arg admin "$(env_get ADMIN_USER)" --arg pkg "$PKG_ADMIN" --arg dir "$(env_get_q MUSIC_DIR)" --arg files "$(cat "$VAR/.music-files" 2>/dev/null)" \
     --arg every "$(env_get SCAN_EVERY)" --arg sharing "$(env_get SHARING)" --arg qr "$(cat "$VAR/qr.b64" 2>/dev/null)" \
     --arg tls "$(env_get TLS)" --arg tls_source "$(env_get TLS_SOURCE)" --argjson cert "$(cat "$VAR/cert.json" 2>/dev/null || echo null)" \
     '{up: true, url: $url, admin_user: $admin, pkg_admin: $pkg, users: $users, scan: $scan,
       library: {artists: ($artists | tonumber? // 0), albums: ($albums | tonumber? // 0), songs: ($songs | tonumber? // 0), missing: ($missing | tonumber? // 0)},
       music: {dir: $dir, files: ($files | tonumber? // null), every: $every}, sharing: ($sharing == "true"), qr: $qr,
       tls: {mode: $tls, source: $tls_source, cert: $cert}}' 2>/dev/null || echo '{"up": true}'
}

# ------------------------------------------------------------ settings, logs, storage, backups, report
app_settings() { [[ -n "${TLS:-}" ]] && env_set TLS "$TLS"; setup_tls || return 1; rm -f "$JWT_FILE"; return 0; }
app_tick() {
  make_users 1
  # The music folder turned up after Navidrome started on the placeholder: mount it and read it (checked every 10 minutes).
  if [[ "$(env_get MUSIC_SRC)" == ./no-music-yet ]] && ! fresh "$VAR/.music-wait" 600; then
    touch "$VAR/.music-wait"
    if music_src; then say "the music folder $(env_get_q MUSIC_DIR) is there now — Navidrome is reading it"; rm -f "$VAR/.music-files"
      compose up -d >> "$LOG" 2>&1 && wait_ready 120 && subsonic startScan "fullScan=true" >/dev/null || true; fi
  fi
  fresh "$VAR/.cert-check" 86400 && return 0; touch "$VAR/.cert-check"
  tls_refresh_dsm data
  [[ "$CERT_REFRESH" == changed ]] && { docker restart "$ND" >> "$LOG" 2>&1 || true; }
  return 0
}
app_logs() { :; }
app_storage() {
  in_volume data ro -- 'cd /vol && for d in navidrome.db cache artwork; do [ -e "$d" ] && printf "%s\t%s\n" "$d" "$(du -sm "$d" 2>/dev/null | cut -f1)"; done; true' </dev/null 2>/dev/null \
    | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber? // 0)}) | from_entries' 2>/dev/null || echo "{}"
}
app_backup() {   # dir — a consistent copy of the database and Navidrome's other data (not the music, not the caches)
  in_volume data rw -- 'sqlite3 /vol/navidrome.db ".backup /tmp/navidrome.db" && cat /tmp/navidrome.db' > "$1/navidrome.db" 2>>"$LOG" </dev/null && [[ -s "$1/navidrome.db" ]] || { say "✗ the database copy didn't finish"; return 1; }
  in_volume data ro -- 'tar -C /vol -czf - --exclude=./navidrome.db --exclude="./navidrome.db-*" --exclude=./cache .' > "$1/files.tar.gz" 2>>"$LOG" </dev/null && tar -tzf "$1/files.tar.gz" >/dev/null 2>&1 || { say "✗ the files didn't tar"; return 1; }
}
app_restore() {
  [[ -s "$1/navidrome.db" && -f "$1/files.tar.gz" ]] || { MSG="That backup has no database copy or files."; return 1; }
  in_volume data rw -- 'find /vol -mindepth 1 -delete && tar -C /vol -xzf -' < "$1/files.tar.gz" 2>>"$LOG" || { MSG="The files didn't unpack."; return 1; }
  in_volume data rw -- 'cat > /vol/navidrome.db' < "$1/navidrome.db" 2>>"$LOG" || { MSG="The database didn't copy back."; return 1; }
  rm -f "$JWT_FILE"
}
app_report() {
  echo "== library"; echo "artists $(nd_count artist), albums $(nd_count album), songs $(nd_count song), missing $(nd_count song true)"
  echo "music folder: $(env_get_q MUSIC_DIR) ($(cat "$VAR/.music-files" 2>/dev/null) music files)"; subsonic getScanStatus | jq -c '."subsonic-response".scanStatus' 2>/dev/null
  echo; echo "== users"; nd_api GET user 2>/dev/null | jq -r '.[] | .userName + "  " + (if .isAdmin then "admin" else "user" end) + "  last access " + (.lastAccessAt // "never")'
  echo; echo "== settings: scan every $(env_get SCAN_EVERY), sharing $(env_get SHARING), HTTPS $(env_get TLS) (in use: $(env_get TLS_SOURCE))"
  :
}

# ------------------------------------------------------------ actions
app_act() {   # action (request vars are set)
  local pw user out dir n
  case "$1" in
    useradd)
      pw=$(strong_password)
      out=$(nd_api POST user "$(jq -cn --arg u "$NUSER" --arg p "$pw" --argjson a "$([[ "${ROLE:-user}" == admin ]] && echo true || echo false)" '{userName: $u, name: $u, password: $p, isAdmin: $a}')") \
        || { MSG="Navidrome didn't add $NUSER (HTTP $ND_CODE): $(jq -r '.error // .message // empty' <<< "$out" 2>/dev/null | head -c 160)"; return 1; }
      leave_secret "Navidrome ($NUSER)" "$pw" users; MSG="$NUSER was added — the password is shown once, below." ;;
    userpw|setadmin|userdel)
      user=$(nd_api GET "user/$USER_ID") || { MSG="There's no such user."; return 1; }
      [[ "$(jq -r .userName <<< "$user")" == "$PKG_ADMIN" ]] && { MSG="That's the package's own administrator — leave it be."; return 1; }
      case "$1" in
        userpw) pw=$(strong_password)
          nd_api PUT "user/$USER_ID" "$(jq -c --arg p "$pw" '. + {password: $p}' <<< "$user")" >/dev/null || { MSG="Navidrome didn't take it (HTTP $ND_CODE)."; return 1; }
          leave_secret "Navidrome ($(jq -r .userName <<< "$user"))" "$pw" users; MSG="A new password for $(jq -r .userName <<< "$user") is ready — it's shown once, below. Their phone apps need it too." ;;
        setadmin)
          nd_api PUT "user/$USER_ID" "$(jq -c --argjson a "$([[ "${ROLE:-user}" == admin ]] && echo true || echo false)" '. + {isAdmin: $a}' <<< "$user")" >/dev/null || { MSG="Navidrome didn't take it (HTTP $ND_CODE)."; return 1; }
          MSG="$(jq -r .userName <<< "$user") is $([[ "${ROLE:-user}" == admin ]] && echo "now an administrator" || echo "no longer an administrator")." ;;
        userdel)
          [[ "$(jq -r .userName <<< "$user")" == "$(env_get ADMIN_USER)" ]] && { MSG="That's your own account — remove it in Navidrome itself if you really mean to."; return 1; }
          nd_api DELETE "user/$USER_ID" >/dev/null || { MSG="Navidrome didn't remove it (HTTP $ND_CODE)."; return 1; }
          MSG="$(jq -r .userName <<< "$user") was removed." ;;
      esac ;;
    scan)
      out=$(subsonic startScan "$([[ "${FULL:-0}" == 1 ]] && echo fullScan=true)")
      jq -e '."subsonic-response".status == "ok"' <<< "$out" >/dev/null 2>&1 && MSG="Navidrome is $([[ "${FULL:-0}" == 1 ]] && echo "reading the whole library again" || echo "looking for new and changed music")." \
        || { MSG="The scan didn't start: $(jq -r '."subsonic-response".error.message // empty' <<< "$out" 2>/dev/null)"; return 1; } ;;
    musicdir)
      dir=$(b64d "${MUSIC_DIR_B64:-}")
      music_dir_ok "$dir" || { MSG="There's no folder $dir on this Synology (it looks like /volume1/music)."; return 1; }
      n=$(music_check "$dir" | tr -cd '0-9')
      env_set_q MUSIC_DIR "$dir"; music_src; echo "${n:-0}" > "$VAR/.music-files"
      compose up -d >> "$LOG" 2>&1 && wait_ready 120 || { MSG="Navidrome didn't come back — see the log."; return 1; }
      subsonic startScan "fullScan=true" >/dev/null
      MSG="Navidrome now plays $dir (${n:-0} music files) — it's reading them now." ;;
    scanevery)
      env_set SCAN_EVERY "$SCAN_EVERY"
      compose up -d >> "$LOG" 2>&1 && wait_ready 120 || { MSG="Navidrome didn't come back — see the log."; return 1; }
      MSG=$([[ "$SCAN_EVERY" == 0 ]] && echo "Scheduled scans are off; Navidrome still notices changes as they happen, and Scan now works." || echo "Navidrome looks for new music every $SCAN_EVERY (and notices changes as they happen).") ;;
    sharing)
      env_set SHARING "$([[ "${ON:-0}" == 1 ]] && echo true || echo false)"
      compose up -d >> "$LOG" 2>&1 && wait_ready 120 || { MSG="Navidrome didn't come back — see the log."; return 1; }
      MSG="Share links are $([[ "${ON:-0}" == 1 ]] && echo "on: anyone with a link can listen to what it shares" || echo off)." ;;
    refreshcert)
      case "$(env_get TLS)" in
        dsm) rm -f "$VAR/.cert-check"; tls_refresh_dsm data
             case "$CERT_REFRESH" in changed) docker restart "$ND" >> "$LOG" 2>&1; wait_ready 120; MSG="DSM's certificate was read again and Navidrome restarted with it." ;; same) MSG="DSM's certificate hasn't changed; Navidrome already has it." ;; *) MSG="DSM's certificate wasn't found on this system — see the log."; return 1 ;; esac ;;
        self) in_volume data rw -- 'rm -f /vol/tls/source' </dev/null 2>/dev/null; setup_tls || return 1; docker restart "$ND" >> "$LOG" 2>&1; wait_ready 120; MSG="A new self-signed certificate was made; browsers and apps will ask once more." ;;
        *) MSG="HTTPS is off here — there's no certificate to refresh."; return 1 ;;
      esac ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
}
