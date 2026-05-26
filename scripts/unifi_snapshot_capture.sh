#!/bin/sh

set -eu

INTERVAL_SECONDS="${INTERVAL_SECONDS:-900}"
OUTPUT_DIR="${OUTPUT_DIR:-/volume1/unifi-snapshots}"
FILE_PREFIX="${FILE_PREFIX:-unifi-camera}"
UNIFI_SCHEME="${UNIFI_SCHEME:-https}"
UNIFI_PORT="${UNIFI_PORT:-443}"
INSECURE_TLS="${INSECURE_TLS:-1}"
ONCE=0
cookie_file=""
header_file=""
body_file=""
temp_file=""

cleanup_temp_files() {
  rm -f "${cookie_file:-}" "${header_file:-}" "${body_file:-}" "${temp_file:-}"
}

trap 'cleanup_temp_files' EXIT
trap 'cleanup_temp_files; exit 130' INT
trap 'cleanup_temp_files; exit 143' TERM

usage() {
  cat <<'USAGE'
Usage:
  unifi_snapshot_capture.sh [--config /path/to/config] [--once]

Captures snapshots from a UniFi Protect camera and saves them to a NAS folder.
By default it runs forever and captures every 15 minutes.

Required config values:
  UNIFI_HOST       UniFi Console hostname or IP, for example 192.168.1.1
  UNIFI_USERNAME   Local UniFi OS username
  UNIFI_PASSWORD   Local UniFi OS password
  CAMERA_ID        UniFi Protect camera ID

Optional config values:
  OUTPUT_DIR        Destination folder. Default: /volume1/unifi-snapshots
  INTERVAL_SECONDS  Capture interval. Default: 900
  FILE_PREFIX       Filename prefix. Default: unifi-camera
  UNIFI_SCHEME      http or https. Default: https
  UNIFI_PORT        UniFi Console port. Default: 443
  INSECURE_TLS      Set to 1 for self-signed UniFi certs. Default: 1

Example config:
  UNIFI_HOST="192.168.1.1"
  UNIFI_USERNAME="snapshot-user"
  UNIFI_PASSWORD="change-me"
  CAMERA_ID="64f000000000000000000000"
  OUTPUT_DIR="/volume1/photo/unifi"
USAGE
}

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

load_config() {
  if [ -n "${CONFIG_FILE:-}" ]; then
    [ -r "$CONFIG_FILE" ] || fail "Config file is not readable: $CONFIG_FILE"
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
}

require_config() {
  [ -n "${UNIFI_HOST:-}" ] || fail "UNIFI_HOST is required"
  [ -n "${UNIFI_USERNAME:-}" ] || fail "UNIFI_USERNAME is required"
  [ -n "${UNIFI_PASSWORD:-}" ] || fail "UNIFI_PASSWORD is required"
  [ -n "${CAMERA_ID:-}" ] || fail "CAMERA_ID is required"
}

curl_tls_flag() {
  if [ "${INSECURE_TLS:-0}" = "1" ]; then
    printf '%s' "-k"
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

capture_snapshot() {
  mkdir -p "$OUTPUT_DIR"

  tmp_dir="${TMPDIR:-/tmp}"
  cookie_file="$tmp_dir/unifi_snapshot_cookie_$$.txt"
  header_file="$tmp_dir/unifi_snapshot_headers_$$.txt"
  body_file="$tmp_dir/unifi_snapshot_login_$$.txt"

  base_url="${UNIFI_SCHEME}://${UNIFI_HOST}:${UNIFI_PORT}"
  username_json="$(json_escape "$UNIFI_USERNAME")"
  password_json="$(json_escape "$UNIFI_PASSWORD")"
  login_payload="{\"username\":\"$username_json\",\"password\":\"$password_json\",\"remember\":true}"
  tls_flag="$(curl_tls_flag)"

  login_code="$(
    curl -sS $tls_flag \
      -c "$cookie_file" \
      -D "$header_file" \
      -o "$body_file" \
      -H "Content-Type: application/json" \
      -X POST \
      --data "$login_payload" \
      -w "%{http_code}" \
      "$base_url/api/auth/login"
  )" || fail "Unable to reach UniFi login endpoint"

  case "$login_code" in
    200|204) ;;
    *) fail "UniFi login failed with HTTP $login_code" ;;
  esac

  csrf_token="$(
    awk 'tolower($1) == "x-csrf-token:" { sub(/\r$/, "", $2); print $2; exit }' "$header_file"
  )"

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  output_file="$OUTPUT_DIR/${FILE_PREFIX}_${timestamp}.jpg"
  temp_file="$output_file.tmp"
  snapshot_url="$base_url/proxy/protect/api/cameras/$CAMERA_ID/snapshot?force=true"

  if [ -n "$csrf_token" ]; then
    snapshot_code="$(
      curl -sS $tls_flag \
        -b "$cookie_file" \
        -H "x-csrf-token: $csrf_token" \
        -o "$temp_file" \
        -w "%{http_code}" \
        "$snapshot_url"
    )" || fail "Unable to fetch camera snapshot"
  else
    snapshot_code="$(
      curl -sS $tls_flag \
        -b "$cookie_file" \
        -o "$temp_file" \
        -w "%{http_code}" \
        "$snapshot_url"
    )" || fail "Unable to fetch camera snapshot"
  fi

  case "$snapshot_code" in
    200) ;;
    *)
      rm -f "$temp_file"
      fail "Snapshot request failed with HTTP $snapshot_code"
      ;;
  esac

  if [ ! -s "$temp_file" ]; then
    rm -f "$temp_file"
    fail "Snapshot response was empty"
  fi

  mv "$temp_file" "$output_file"
  log "Saved snapshot: $output_file"
  cleanup_temp_files
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      shift
      [ "$#" -gt 0 ] || fail "--config requires a file path"
      CONFIG_FILE="$1"
      ;;
    --once)
      ONCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

load_config
require_config

if [ "$ONCE" = "1" ]; then
  capture_snapshot
  exit 0
fi

log "Starting UniFi snapshot capture every ${INTERVAL_SECONDS} seconds"
while :; do
  capture_snapshot
  sleep "$INTERVAL_SECONDS"
done
