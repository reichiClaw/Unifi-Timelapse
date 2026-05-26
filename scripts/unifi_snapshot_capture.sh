#!/bin/sh

set -eu

INTERVAL_SECONDS="${INTERVAL_SECONDS:-900}"
OUTPUT_DIR="${OUTPUT_DIR:-/volume1/unifi-snapshots}"
FILE_PREFIX="${FILE_PREFIX:-unifi-camera}"
CAMERA_SCHEME="${CAMERA_SCHEME:-http}"
CAMERA_PATH="${CAMERA_PATH:-/snap.jpeg}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"
MAX_TIME="${MAX_TIME:-60}"
INSECURE_TLS="${INSECURE_TLS:-1}"
ONCE=0
temp_file=""

cleanup_temp_files() {
  rm -f "${temp_file:-}"
}

trap 'cleanup_temp_files' EXIT
trap 'cleanup_temp_files; exit 130' INT
trap 'cleanup_temp_files; exit 143' TERM

usage() {
  cat <<'USAGE'
Usage:
  unifi_snapshot_capture.sh [--config /path/to/config] [--once]

Captures snapshots directly from a UniFi camera and saves them to a NAS folder.
By default it runs forever and captures every 15 minutes.

Required config values:
  CAMERA_HOST          Camera hostname or IP, for example 192.168.1.50
                       Not required when CAMERA_SNAPSHOT_URL is set.

Optional config values:
  CAMERA_SNAPSHOT_URL  Full direct camera snapshot URL. Overrides CAMERA_HOST.
  CAMERA_SCHEME        http or https. Default: http
  CAMERA_PORT          Optional camera port.
  CAMERA_PATH          Snapshot path. Default: /snap.jpeg
  CAMERA_USERNAME      Optional camera username.
  CAMERA_PASSWORD      Optional camera password.
  OUTPUT_DIR           Destination folder. Default: /volume1/unifi-snapshots
  INTERVAL_SECONDS     Capture interval. Default: 900
  FILE_PREFIX          Filename prefix. Default: unifi-camera
  INSECURE_TLS         Set to 1 for self-signed camera certs. Default: 1
  CONNECT_TIMEOUT      Curl connect timeout in seconds. Default: 10
  MAX_TIME             Curl max request time in seconds. Default: 60

Example config:
  CAMERA_HOST="192.168.1.50"
  CAMERA_SCHEME="http"
  CAMERA_PATH="/snap.jpeg"
  OUTPUT_DIR="/volume1/photo/unifi"
  FILE_PREFIX="front-door"
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
  if [ -z "${CAMERA_SNAPSHOT_URL:-}" ] && [ -z "${CAMERA_HOST:-}" ]; then
    fail "CAMERA_HOST or CAMERA_SNAPSHOT_URL is required"
  fi

  if { [ -n "${CAMERA_USERNAME:-}" ] && [ -z "${CAMERA_PASSWORD:-}" ]; } ||
    { [ -z "${CAMERA_USERNAME:-}" ] && [ -n "${CAMERA_PASSWORD:-}" ]; }; then
    fail "CAMERA_USERNAME and CAMERA_PASSWORD must be set together"
  fi
}

build_snapshot_url() {
  if [ -n "${CAMERA_SNAPSHOT_URL:-}" ]; then
    printf '%s' "$CAMERA_SNAPSHOT_URL"
    return
  fi

  camera_path="$CAMERA_PATH"
  case "$camera_path" in
    /*) ;;
    *) camera_path="/$camera_path" ;;
  esac

  port_part=""
  if [ -n "${CAMERA_PORT:-}" ]; then
    port_part=":$CAMERA_PORT"
  fi

  printf '%s://%s%s%s' "$CAMERA_SCHEME" "$CAMERA_HOST" "$port_part" "$camera_path"
}

fetch_snapshot() {
  snapshot_url="$1"
  output_path="$2"

  if [ "${INSECURE_TLS:-0}" = "1" ] && [ -n "${CAMERA_USERNAME:-}" ]; then
    curl -sS -L -k \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      --anyauth \
      --user "$CAMERA_USERNAME:$CAMERA_PASSWORD" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  elif [ -n "${CAMERA_USERNAME:-}" ]; then
    curl -sS -L \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      --anyauth \
      --user "$CAMERA_USERNAME:$CAMERA_PASSWORD" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  elif [ "${INSECURE_TLS:-0}" = "1" ]; then
    curl -sS -L -k \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  else
    curl -sS -L \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  fi
}

capture_snapshot() {
  mkdir -p "$OUTPUT_DIR"

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  output_file="$OUTPUT_DIR/${FILE_PREFIX}_${timestamp}.jpg"
  temp_file="$output_file.tmp"
  snapshot_url="$(build_snapshot_url)"
  snapshot_code="$(fetch_snapshot "$snapshot_url" "$temp_file")" ||
    fail "Unable to fetch camera snapshot from $snapshot_url"

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

log "Starting direct camera snapshot capture every ${INTERVAL_SECONDS} seconds"
while :; do
  capture_snapshot
  sleep "$INTERVAL_SECONDS"
done
