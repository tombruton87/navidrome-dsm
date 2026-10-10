# Navidrome's steps for the chassis harness (chassis/tests/e2e.sh <appdir> act).
# The music folder is a few tiny MP3s made with Navidrome's own ffmpeg.
MUSIC=$E2E/music
make_music() {   # dir artist album n
  mkdir -p "$1/$2/$3"
  docker run --rm -v "$1:/m" --entrypoint sh deluan/navidrome:latest -c "for i in \$(seq 1 $4); do ffmpeg -loglevel error -f lavfi -i sine=frequency=\$((200*i)):duration=1 -metadata title=\"Song \$i\" -metadata artist=\"$2\" -metadata album=\"$3\" -metadata track=\$i -y \"/m/$2/$3/0\$i.mp3\"; done" >/dev/null 2>&1
}
app_e2e_answers() { [[ -d "$MUSIC/Artist One" ]] || make_music "$MUSIC" "Artist One" "First Album" 3; printf "ADMIN_USER='ada'\nMUSIC_DIR_B64='%s'\nTLS='off'\n" "$(printf '%s' "$MUSIC" | base64 -w0 | tr -d '=' | tr '+/' '-_')"; }
wait_for() { local i; for i in $(seq 1 "$2"); do touch "$VAR/watching"; jq -e "$1" "$VAR/status.json" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
nd_ok() { [[ "$(curl -sk -o /dev/null -w '%{http_code}' -X POST "$1/auth/login" -H 'Content-Type: application/json' -d "{\"username\":\"$2\",\"password\":\"$3\"}")" == 200 ]]; }
sub_ok() { local s=e2esalt t; t=$(printf '%s%s' "$3" "$s" | md5sum | cut -c1-32); curl -sk "$1/rest/ping?u=$2&t=$t&s=$s&v=1.16.1&c=e2e&f=json" | jq -e '."subsonic-response".status == "ok"' >/dev/null; }
app_e2e_act() {
  local fail=0 pw pw2 url="http://127.0.0.1:$PORT" sid b64
  log "navidrome"
  echo "  (ping: HTTP $(curl -s -o /dev/null -w '%{http_code}' "$url/ping"), version $(jq -r .version "$VAR/status.json"))"
  pw=$(jq -r 'select(.kind == "users") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"
  [[ ${#pw} -ge 20 ]] && echo "  ok   a one-time password was left for the window" || { echo "  FAIL no password secret"; fail=1; }
  nd_ok "$url" ada "$pw" && echo "  ok   your account signs in to the web player" || { echo "  FAIL sign-in"; fail=1; }
  sub_ok "$url" ada "$pw" && echo "  ok   …and through the Subsonic API the phone apps use" || { echo "  FAIL subsonic"; fail=1; }
  wait_for '.app.library.songs == 3 and .app.library.albums == 1' 60 && echo "  ok   the library: 3 songs, 1 album" || { echo "  FAIL library: $(jq -c '.app.library' "$VAR/status.json")"; fail=1; }
  jq -e '.app.music.files == 3 and (.app.users | map(.user) | index("dsm") and index("ada"))' "$VAR/status.json" >/dev/null && echo "  ok   3 music files in the folder; users ada and the package's dsm" || { echo "  FAIL status: $(jq -c '{music: .app.music, users: [.app.users[]?.user]}' "$VAR/status.json")"; fail=1; }
  jq -e '.app.qr | length > 100' "$VAR/status.json" >/dev/null && echo "  ok   a QR code of the address" || { echo "  FAIL no qr"; fail=1; }
  # New music: a quick scan finds it.
  make_music "$MUSIC" "Artist Two" "Second Album" 2
  request "ACTION='scan'" "FULL='0'" || fail=1
  wait_for '.app.library.songs == 5 and .app.library.albums == 2' 60 && echo "  ok   new music found by a scan: 5 songs, 2 albums" || { echo "  FAIL rescan: $(jq -c '.app.library' "$VAR/status.json")"; fail=1; }
  # Users.
  request "ACTION='useradd'" "NUSER='sam'" "ROLE='user'" || fail=1
  pw2=$(jq -r 'select(.kind == "users") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"
  sub_ok "$url" sam "$pw2" && echo "  ok   sam can listen" || { echo "  FAIL sam"; fail=1; }
  sid=$(jq -r '.app.users[] | select(.user == "sam") | .id' "$VAR/status.json"); [[ -n "$sid" ]] || wait_for '.app.users | map(.user) | index("sam")' 20; sid=$(jq -r '.app.users[] | select(.user == "sam") | .id' "$VAR/status.json")
  request "ACTION='setadmin'" "USER_ID='$sid'" "ROLE='admin'" || fail=1
  wait_for ".app.users[] | select(.user == \"sam\") | .admin == true" 20 && echo "  ok   sam made an administrator" || { echo "  FAIL setadmin"; fail=1; }
  request "ACTION='userpw'" "USER_ID='$sid'" || fail=1
  pw=$(jq -r 'select(.kind == "users") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"
  sub_ok "$url" sam "$pw" && ! sub_ok "$url" sam "$pw2" && echo "  ok   new password works, old doesn't" || { echo "  FAIL password change"; fail=1; }
  local dsmid; dsmid=$(jq -r '.app.users[] | select(.user == "dsm") | .id' "$VAR/status.json")
  request "ACTION='userdel'" "USER_ID='$dsmid'" >/dev/null && { echo "  FAIL removed the package's admin"; fail=1; } || echo "  ok   the package's administrator can't be removed from here"
  request "ACTION='userdel'" "USER_ID='$sid'" || fail=1
  sub_ok "$url" sam "$pw" && { echo "  FAIL removed user still listens"; fail=1; } || echo "  ok   removed"
  # Music folder: a missing one is refused; another real one is read from scratch.
  request "ACTION='musicdir'" "MUSIC_DIR_B64='$(printf '%s' /volume9/nope | base64 -w0 | tr -d '=' | tr '+/' '-_')'" >/dev/null && { echo "  FAIL accepted a missing folder"; fail=1; } || echo "  ok   a folder that isn't there is refused"
  [[ ! -e /volume9/nope ]] && echo "  ok   …and isn't created by asking" || { echo "  FAIL /volume9/nope was created"; fail=1; }
  make_music "$E2E/music2" "Artist Three" "Third Album" 4
  request "ACTION='musicdir'" "MUSIC_DIR_B64='$(printf '%s' "$E2E/music2" | base64 -w0 | tr -d '=' | tr '+/' '-_')'" || fail=1
  wait_for '.app.library.songs == 4 and .app.library.missing > 0 and .app.music.files == 4' 90 && echo "  ok   another folder: 4 songs (the first folder's shown as missing)" || { echo "  FAIL musicdir: $(jq -c '{l: .app.library, m: .app.music}' "$VAR/status.json")"; fail=1; }
  request "ACTION='scanevery'" "SCAN_EVERY='6h'" || fail=1
  [[ "$(docker exec navidrome-server printenv ND_SCANSCHEDULE)" == 6h ]] && echo "  ok   scans every 6 hours" || { echo "  FAIL scanevery"; fail=1; }
  request "ACTION='sharing'" "ON='1'" || fail=1
  [[ "$(docker exec navidrome-server printenv ND_ENABLESHARING)" == true ]] && echo "  ok   share links on" || { echo "  FAIL sharing"; fail=1; }
  # HTTPS through Navidrome's own TLS.
  request "ACTION='settings'" "TLS='self'" || fail=1
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/ping")" == 200 ]] && echo "  ok   HTTPS self: https answers" || { echo "  FAIL https"; fail=1; }
  jq -e '.app.users | length > 0' "$VAR/status.json" >/dev/null && echo "  ok   the window still manages users over HTTPS" || { echo "  FAIL api over https"; fail=1; }
  request "ACTION='settings'" "TLS='off'" || fail=1
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$url/ping")" == 200 ]] && echo "  ok   HTTPS off: http answers" || { echo "  FAIL http after off"; fail=1; }
  (( fail == 0 )) && echo "  navidrome: all passed" || echo "  navidrome: something FAILED"
  return $fail
}
