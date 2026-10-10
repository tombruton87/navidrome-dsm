# Navidrome's CGI checks (sourced by chassis/tests/test-api.sh).
expect "useradd good" 202 "$(post "$me" useradd 'action=useradd&user=sam&role=user')"; request_is "useradd request" "ACTION='useradd'
NUSER='sam'
ROLE='user'
BY='$me'"
expect "useradd dsm refused" 400 "$(post "$me" useradd 'action=useradd&user=dsm&role=user')"
expect "musicdir spaces" 202 "$(post "$me" musicdir 'action=musicdir&dir=%2Fvolume1%2FMy%20Music')"; grep -q "^MUSIC_DIR_B64='L3ZvbHVtZTEvTXkgTXVzaWM'$" "$CHASSIS_VAR/request" && { (( pass++ )); echo "  ok   a folder with spaces travels base64url"; } || { (( fail++ )); echo "  FAIL musicdir request: $(tr '\n' ' ' < "$CHASSIS_VAR/request")"; }; rm -f "$CHASSIS_VAR/request"
expect "musicdir relative" 400 "$(post "$me" musicdir 'action=musicdir&dir=music')"
expect "musicdir dots" 400 "$(post "$me" musicdir 'action=musicdir&dir=%2Fvolume1%2F..%2Fetc')"
expect "scanevery bad" 400 "$(post "$me" scanevery 'action=scanevery&every=1s')"
