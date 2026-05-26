# Unifi-Timelapse

This repository contains a Synology-friendly shell script for saving a snapshot
directly from a UniFi camera every 15 minutes.

## Files

- `scripts/unifi_snapshot_capture.sh` - fetches a JPEG snapshot directly from
  the camera IP or snapshot URL and saves it to a NAS folder with a timestamped
  name.

## Synology setup

1. Copy the script to your NAS, for example:

   ```sh
   /volume1/scripts/unifi_snapshot_capture.sh
   ```

2. Make it executable:

   ```sh
   chmod +x /volume1/scripts/unifi_snapshot_capture.sh
   ```

3. Create a config file, for example
   `/volume1/scripts/unifi_snapshot_capture.conf`:

   ```sh
   CAMERA_HOST="192.168.1.50"
   CAMERA_SCHEME="http"
   CAMERA_PATH="/snap.jpeg"
   OUTPUT_DIR="/volume1/photo/unifi"
   FILE_PREFIX="front-door"
   ```

   This accesses the camera directly, not the UNVR or UniFi Protect Console. If
   your camera uses a different snapshot endpoint, set `CAMERA_SNAPSHOT_URL`
   instead, for example:

   ```sh
   CAMERA_SNAPSHOT_URL="http://192.168.1.50/snap.jpeg"
   OUTPUT_DIR="/volume1/photo/unifi"
   FILE_PREFIX="front-door"
   ```

   If your camera requires login credentials, add:

   ```sh
   CAMERA_USERNAME="ubnt"
   CAMERA_PASSWORD="change-me"
   ```

4. Test one capture:

   ```sh
   /volume1/scripts/unifi_snapshot_capture.sh \
     --config /volume1/scripts/unifi_snapshot_capture.conf \
     --once
   ```

5. Run it every 15 minutes using one of these options.

   Option A: let the script loop forever:

   ```sh
   /volume1/scripts/unifi_snapshot_capture.sh \
     --config /volume1/scripts/unifi_snapshot_capture.conf
   ```

   Option B: use Synology DSM Task Scheduler:

   - DSM > Control Panel > Task Scheduler > Create > Scheduled Task > User-defined script
   - Schedule: every 15 minutes
   - User-defined script:

     ```sh
     /volume1/scripts/unifi_snapshot_capture.sh \
       --config /volume1/scripts/unifi_snapshot_capture.conf \
       --once
     ```

## Configuration

Required values:

- `CAMERA_HOST` - camera hostname or IP address. Not required when
  `CAMERA_SNAPSHOT_URL` is set.

Optional values:

- `CAMERA_SNAPSHOT_URL` - full direct snapshot URL. Overrides `CAMERA_HOST`.
- `CAMERA_SCHEME` - `http` or `https`. Default: `http`.
- `CAMERA_PORT` - optional camera port.
- `CAMERA_PATH` - snapshot path. Default: `/snap.jpeg`.
- `CAMERA_USERNAME` - optional camera username.
- `CAMERA_PASSWORD` - optional camera password.
- `OUTPUT_DIR` - destination folder. Default: `/volume1/unifi-snapshots`.
- `INTERVAL_SECONDS` - capture interval for loop mode. Default: `900`.
- `FILE_PREFIX` - filename prefix. Default: `unifi-camera`.
- `INSECURE_TLS` - set to `1` for self-signed camera certificates. Default: `1`.
- `CONNECT_TIMEOUT` - curl connect timeout in seconds. Default: `10`.
- `MAX_TIME` - curl max request time in seconds. Default: `60`.
