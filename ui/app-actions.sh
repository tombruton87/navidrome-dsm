# Navidrome's actions, validated by the CGI before they become a request file.
b64u() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 u id role v dir
  case "$a" in
    refreshcert) lines="ACTION='$a'" ;;
    useradd) u=$(param user "$body"); role=$(param role "$body")
      [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ && "$u" != dsm ]] || error "400 Bad Request" "A username: letters, digits, dot, dash, underscore — up to 32 (not dsm)."
      [[ "$role" =~ ^(user|admin)$ ]] || error "400 Bad Request" "Listener or administrator."
      lines="ACTION='useradd'
NUSER='$u'
ROLE='$role'" ;;
    userpw|setadmin|userdel) id=$(param id "$body"); [[ "$id" =~ ^[A-Za-z0-9]{10,40}$ ]] || error "400 Bad Request" "Pick a user."
      lines="ACTION='$a'
USER_ID='$id'"
      if [[ "$a" == setadmin ]]; then role=$(param role "$body"); [[ "$role" =~ ^(user|admin)$ ]] || error "400 Bad Request" "Listener or administrator."; lines="$lines
ROLE='$role'"; fi ;;
    scan) v=$(param full "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "Quick or full."; lines="ACTION='scan'
FULL='$v'" ;;
    musicdir) dir=$(decode "$(param dir "$body")")
      [[ "$dir" == /* && "$dir" != *..* && ${#dir} -le 300 && "$dir" =~ ^[^[:cntrl:]]+$ ]] || error "400 Bad Request" "A folder on the NAS, like /volume1/music."
      lines="ACTION='musicdir'
MUSIC_DIR_B64='$(b64u "$dir")'" ;;
    scanevery) v=$(param every "$body"); [[ "$v" =~ ^(15m|1h|6h|24h|0)$ ]] || error "400 Bad Request" "Pick how often."; lines="ACTION='scanevery'
SCAN_EVERY='$v'" ;;
    sharing) v=$(param on "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."; lines="ACTION='sharing'
ON='$v'" ;;
  esac
}
app_cgi_settings() {
  local tls; tls=$(param tls "$1")
  [[ -z "$tls" ]] && return 0
  [[ "$tls" =~ ^(dsm|self|off)$ ]] || error "400 Bad Request" "HTTPS is DSM's certificate, self-signed, or off."
  lines="$lines
TLS='$tls'"
}
