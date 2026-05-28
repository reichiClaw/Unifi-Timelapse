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
START_TIME="${START_TIME:-}"
END_TIME="${END_TIME:-}"
ACTIVE_DAYS="${ACTIVE_DAYS:-}"
LOG_FILE="${LOG_FILE:-}"
ONCE=0
temp_file=""
header_file=""

cleanup_temp_files() {
  rm -f "${temp_file:-}" "${header_file:-}"
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
  START_TIME           Optional daily start time, HH:MM.
  END_TIME             Optional daily end time, HH:MM.
  ACTIVE_DAYS          Optional days, for example mon,tue,wed,thu,fri.
                       Supports sun,mon,tue,wed,thu,fri,sat and 0-7
                       where 0 or 7 is Sunday.
  LOG_FILE             Optional log file. Default:
                       OUTPUT_DIR/unifi_snapshot_capture.log

Example config:
  CAMERA_HOST="192.168.1.50"
  CAMERA_SCHEME="http"
  CAMERA_PATH="/snap.jpeg"
  OUTPUT_DIR="/volume1/photo/unifi"
  FILE_PREFIX="front-door"
USAGE
}

log() {
  log_line="$(printf '%s %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")"
  printf '%s\n' "$log_line"

  if [ -n "${LOG_FILE:-}" ]; then
    log_dir="${LOG_FILE%/*}"
    if [ "$log_dir" = "$LOG_FILE" ]; then
      (printf '%s\n' "$log_line" >>"$LOG_FILE") 2>/dev/null || true
    elif mkdir -p "$log_dir" 2>/dev/null; then
      (printf '%s\n' "$log_line" >>"$LOG_FILE") 2>/dev/null || true
    elif [ -z "$log_dir" ]; then
      (printf '%s\n' "$log_line" >>"$LOG_FILE") 2>/dev/null || true
    fi
  fi
}

fail() {
  log "ERROR: $*"
  exit 1
}

strip_leading_zeroes() {
  stripped="$(printf '%s' "$1" | sed 's/^0*//')"
  printf '%s' "${stripped:-0}"
}

require_positive_integer() {
  name="$1"
  value="$2"

  case "$value" in
    ''|*[!0-9]*) fail "$name must be a positive integer" ;;
  esac

  if [ "$value" -le 0 ]; then
    fail "$name must be greater than 0"
  fi
}

require_non_negative_integer() {
  name="$1"
  value="$2"

  case "$value" in
    ''|*[!0-9]*) fail "$name must be 0 or 1" ;;
  esac
}

time_to_minutes() {
  value="$1"

  case "$value" in
    [0-2][0-9]:[0-5][0-9]) ;;
    *) fail "Invalid time '$value'. Use HH:MM, for example 08:30" ;;
  esac

  hours="$(strip_leading_zeroes "${value%:*}")"
  minutes="$(strip_leading_zeroes "${value#*:}")"

  if [ "$hours" -gt 23 ]; then
    fail "Invalid time '$value'. Hour must be between 00 and 23"
  fi

  printf '%s\n' "$((hours * 60 + minutes))"
}

normalize_day() {
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    sun|sunday|0|7) printf '%s' 0 ;;
    mon|monday|1) printf '%s' 1 ;;
    tue|tues|tuesday|2) printf '%s' 2 ;;
    wed|wednesday|3) printf '%s' 3 ;;
    thu|thur|thurs|thursday|4) printf '%s' 4 ;;
    fri|friday|5) printf '%s' 5 ;;
    sat|saturday|6) printf '%s' 6 ;;
    *) fail "Invalid day '$1'. Use names like mon,tue or numbers 0-7" ;;
  esac
}

active_days_match_today() {
  [ -n "$ACTIVE_DAYS" ] || return 0

  schedule_day="$1"
  old_ifs="$IFS"
  IFS=', '
  for day in $ACTIVE_DAYS; do
    [ -n "$day" ] || continue
    normalized_day="$(normalize_day "$day")"
    if [ "$normalized_day" = "$schedule_day" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"

  return 1
}

active_time_window_match_minutes() {
  now_minutes="$1"

  [ -n "$START_TIME" ] || return 0

  start_minutes="$(time_to_minutes "$START_TIME")"
  end_minutes="$(time_to_minutes "$END_TIME")"

  if [ "$start_minutes" -le "$end_minutes" ]; then
    [ "$now_minutes" -ge "$start_minutes" ] && [ "$now_minutes" -le "$end_minutes" ]
    return
  fi

  [ "$now_minutes" -ge "$start_minutes" ] || [ "$now_minutes" -le "$end_minutes" ]
}

schedule_day_for_window() {
  today="$1"
  now_minutes="$2"

  [ -n "$START_TIME" ] || {
    printf '%s' "$today"
    return
  }

  start_minutes="$(time_to_minutes "$START_TIME")"
  end_minutes="$(time_to_minutes "$END_TIME")"

  if [ "$start_minutes" -gt "$end_minutes" ] && [ "$now_minutes" -le "$end_minutes" ]; then
    printf '%s' "$(((today + 6) % 7))"
    return
  fi

  printf '%s' "$today"
}

schedule_allows_capture() {
  now_minutes="$(time_to_minutes "$(date '+%H:%M')")"
  today="$(date '+%w')"
  schedule_day="$(schedule_day_for_window "$today" "$now_minutes")"

  if ! active_days_match_today "$schedule_day"; then
    log "Skipping snapshot: schedule day $schedule_day is not in ACTIVE_DAYS=$ACTIVE_DAYS"
    return 1
  fi

  if ! active_time_window_match_minutes "$now_minutes"; then
    log "Skipping snapshot: current time is outside START_TIME=$START_TIME END_TIME=$END_TIME"
    return 1
  fi

  return 0
}

load_config() {
  if [ -n "${CONFIG_FILE:-}" ]; then
    [ -r "$CONFIG_FILE" ] || fail "Config file is not readable: $CONFIG_FILE"
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
}

set_default_log_file() {
  if [ -z "${LOG_FILE:-}" ]; then
    LOG_FILE="$OUTPUT_DIR/unifi_snapshot_capture.log"
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

  require_positive_integer "INTERVAL_SECONDS" "$INTERVAL_SECONDS"
  require_positive_integer "CONNECT_TIMEOUT" "$CONNECT_TIMEOUT"
  require_positive_integer "MAX_TIME" "$MAX_TIME"

  if [ -n "${CAMERA_PORT:-}" ]; then
    require_positive_integer "CAMERA_PORT" "$CAMERA_PORT"
    if [ "$CAMERA_PORT" -gt 65535 ]; then
      fail "CAMERA_PORT must be between 1 and 65535"
    fi
  fi

  require_non_negative_integer "INSECURE_TLS" "$INSECURE_TLS"
  if [ "$INSECURE_TLS" -ne 0 ] && [ "$INSECURE_TLS" -ne 1 ]; then
    fail "INSECURE_TLS must be 0 or 1"
  fi

  if { [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; } ||
    { [ -z "$START_TIME" ] && [ -n "$END_TIME" ]; }; then
    fail "START_TIME and END_TIME must be set together"
  fi

  if [ -n "$START_TIME" ]; then
    time_to_minutes "$START_TIME" >/dev/null
    time_to_minutes "$END_TIME" >/dev/null
  fi

  if [ -n "$ACTIVE_DAYS" ]; then
    old_ifs="$IFS"
    IFS=', '
    for day in $ACTIVE_DAYS; do
      [ -n "$day" ] || continue
      normalize_day "$day" >/dev/null
    done
    IFS="$old_ifs"
  fi
}

capture_error() {
  log "ERROR: $*"
  cleanup_temp_files
  return 1
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
  header_path="$3"

  if [ "${INSECURE_TLS:-0}" = "1" ] && [ -n "${CAMERA_USERNAME:-}" ]; then
    curl -sS -L -k \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      --anyauth \
      --user "$CAMERA_USERNAME:$CAMERA_PASSWORD" \
      -D "$header_path" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  elif [ -n "${CAMERA_USERNAME:-}" ]; then
    curl -sS -L \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      --anyauth \
      --user "$CAMERA_USERNAME:$CAMERA_PASSWORD" \
      -D "$header_path" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  elif [ "${INSECURE_TLS:-0}" = "1" ]; then
    curl -sS -L -k \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -D "$header_path" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  else
    curl -sS -L \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -D "$header_path" \
      -o "$output_path" \
      -w "%{http_code}" \
      "$snapshot_url"
  fi
}

content_type_is_image() {
  content_type="$1"

  case "$(printf '%s' "$content_type" | tr '[:upper:]' '[:lower:]')" in
    image/*) return 0 ;;
    *) return 1 ;;
  esac
}

file_has_image_signature() {
  image_type="$(
    od -An -tx1 -N12 "$1" 2>/dev/null |
      tr -d ' \n'
  )"

  case "$image_type" in
    ffd8ff*) return 0 ;;                 # JPEG
    89504e470d0a1a0a*) return 0 ;;       # PNG
    474946383761*|474946383961*) return 0 ;; # GIF
    52494646????????57454250*) return 0 ;;   # WebP
    *) return 1 ;;
  esac
}

capture_snapshot() {
  schedule_allows_capture || return 0

  mkdir -p "$OUTPUT_DIR" || {
    capture_error "Unable to create output directory: $OUTPUT_DIR"
    return 1
  }

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  output_file="$OUTPUT_DIR/${FILE_PREFIX}_${timestamp}.jpg"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/unifi_snapshot_capture.XXXXXX")" || {
    capture_error "Unable to create temporary snapshot file"
    return 1
  }
  header_file="$(mktemp "${TMPDIR:-/tmp}/unifi_snapshot_headers.XXXXXX")" || {
    capture_error "Unable to create temporary header file"
    return 1
  }
  snapshot_url="$(build_snapshot_url)"
  snapshot_code="$(fetch_snapshot "$snapshot_url" "$temp_file" "$header_file")" || {
    capture_error "Unable to fetch camera snapshot from $snapshot_url"
    return 1
  }

  case "$snapshot_code" in
    200) ;;
    *)
      capture_error "Snapshot request failed with HTTP $snapshot_code"
      return 1
      ;;
  esac

  if [ ! -s "$temp_file" ]; then
    capture_error "Snapshot response was empty"
    return 1
  fi

  content_type="$(
    awk 'tolower($0) ~ /^content-type:/ {
      sub(/\r$/, "", $0)
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      value = $0
    } END { print value }' "$header_file"
  )"
  if ! content_type_is_image "$content_type"; then
    capture_error "Snapshot response was not an image Content-Type: ${content_type:-missing}"
    return 1
  fi

  if ! file_has_image_signature "$temp_file"; then
    capture_error "Snapshot response body did not look like an image"
    return 1
  fi

  mv "$temp_file" "$output_file" || {
    capture_error "Unable to save snapshot to $output_file"
    return 1
  }
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
set_default_log_file
require_config

if [ "$ONCE" = "1" ]; then
  capture_snapshot
  exit 0
fi

log "Starting direct camera snapshot capture every ${INTERVAL_SECONDS} seconds"
while :; do
  if ! capture_snapshot; then
    log "Snapshot attempt failed; continuing loop"
  fi
  sleep "$INTERVAL_SECONDS"
done
