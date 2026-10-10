    echo "ADMIN_USER='$(printf '%s' "${wizard_admin_user:-admin}" | tr -cd 'A-Za-z0-9._-' | head -c 32)'"
    echo "MUSIC_DIR_B64='$(printf '%s' "${wizard_music_dir:-/volume1/music}" | base64 | tr -d '\n=' | tr '+/' '-_')'"
    echo "TLS='$(if [ "${wizard_tls_dsm:-false}" = true ]; then echo dsm; elif [ "${wizard_tls_self:-false}" = true ]; then echo self; else echo off; fi)'"
