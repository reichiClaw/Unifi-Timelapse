# Unifi-Timelapse

This repository contains a Synology-friendly shell script for saving a snapshot
from a UniFi Protect camera every 15 minutes.

## Files

- `scripts/unifi_snapshot_capture.sh` - logs in to UniFi Protect, fetches a
  camera JPEG snapshot, and saves it to a NAS folder with a timestamped name.

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
   UNIFI_HOST="192.168.1.1"
   UNIFI_USERNAME="snapshot-user"
   UNIFI_PASSWORD="change-me"
   CAMERA_ID="64f000000000000000000000"
   OUTPUT_DIR="/volume1/photo/unifi"
   FILE_PREFIX="front-door"
   ```

   Use a local UniFi OS user with the least permissions needed for Protect.
   The `CAMERA_ID` can be found in the UniFi Protect web app URL when you open a
   camera, or via the Protect API.

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

- `UNIFI_HOST` - UniFi Console hostname or IP address.
- `UNIFI_USERNAME` - local UniFi OS username.
- `UNIFI_PASSWORD` - local UniFi OS password.
- `CAMERA_ID` - UniFi Protect camera ID.

Optional values:

- `OUTPUT_DIR` - destination folder. Default: `/volume1/unifi-snapshots`.
- `INTERVAL_SECONDS` - capture interval for loop mode. Default: `900`.
- `FILE_PREFIX` - filename prefix. Default: `unifi-camera`.
- `UNIFI_SCHEME` - `https` or `http`. Default: `https`.
- `UNIFI_PORT` - UniFi Console port. Default: `443`.
- `INSECURE_TLS` - set to `1` for UniFi self-signed certificates. Default: `1`.
