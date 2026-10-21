# Optional ODA DWG converter for ARM Odoo

The default AWS build uses local ARM64 LibreDWG; see
[the native build instructions](../libredwg/README.md). This separate service
is optional for drawings whose LibreDWG preview is incomplete.

The AWS Odoo image runs on ARM64. ODA's Linux converter is an x86-64 binary,
so it runs in this separate container on an **x86-64 Linux host**. ARM Odoo
sends the DWG to that private service, receives DXF, and renders the preview
locally. DXF, STEP and STL continue to render on the Odoo worker.

The Dockerfile installs ODA File Converter 27.9.0.0, `xvfb`, `xauth` and the
required Qt/OpenGL libraries. The official DEB download is verified against
a pinned SHA-256. If ODA changes the download, the build fails rather than
silently installing another version. Review the vendor download and update
the pin before changing versions.

Official resources:

- [ODA converter download and installation](https://www.opendesign.com/guestfiles/oda_file_converter)
- [ezdxf's ODA integration](https://ezdxf.readthedocs.io/en/stable/addons/odafc.html)

## Prepared AWS files

The deployment copy is in `aws:~/docker/odoo-build/cad-converter/`. It is a
staging copy for transfer to the chosen x86-64 host. No converter service is
started by placing these files there, and the main ARM Odoo Dockerfile does
not install ODA or Xvfb.

`aws:~/docker/odoo-build/requirements.txt` uses `ezdxf==1.4.4` and
`cadquery==2.8.0`. CadQuery 2.8 uses OpenCascade wheels available for Linux
ARM64; the earlier CadQuery 2.6.1 pin did not have compatible ARM wheels.
Pillow is supplied by the existing Odoo requirements.

## Deploy when an x86-64 host is available

1. Copy this directory to the x86-64 host. From a workstation with both SSH
   aliases configured, replace `converter-host` with the selected alias:

   ```sh
   ssh converter-host 'mkdir -p ~/docker'
   scp -3 -r aws:~/docker/odoo-build/cad-converter converter-host:~/docker/
   ```

2. On the x86-64 host, create a token file without printing the token:

   ```sh
   cd ~/docker/cad-converter
   python3 - <<'PY'
   import os, secrets
   with os.fdopen(os.open('.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
       output.write('CAD_CONVERTER_TOKEN=' + secrets.token_hex(32) + '\n')
       output.write('CAD_BIND_ADDRESS=127.0.0.1\n')
   PY
   ```

   Change `CAD_BIND_ADDRESS` to that host's private interface IP when enabling
   cross-host access. Allow TCP 8090 only from the Odoo host in the private
   network. For traffic across an untrusted network, put an HTTPS reverse proxy
   in front of this service and use its HTTPS URL in Odoo. The supplied Compose
   file binds only to localhost until you change the address.

3. Build and start the service when deployment is authorized:

   ```sh
   docker compose config --quiet
   docker compose build
   docker compose up -d
   curl --fail http://127.0.0.1:8090/healthz
   ```

   When bound only to a private IP, use that private IP for the health check.
   The service is limited to two concurrent conversions, 15 MiB input,
   32 MiB DXF output and a 25-second conversion timeout. The container runs
   as an unprivileged user with a read-only root filesystem, temporary scratch
   storage, no additional capabilities and memory/CPU/process limits.

4. Copy `odoo-cad.env.example` to the ARM Odoo deployment as `odoo-cad.env`,
   restrict it to mode `0600`, and set:

   ```text
   TAP_CAD_CONVERTER_URL=http://PRIVATE_X86_HOST:8090
   TAP_CAD_CONVERTER_TOKEN=<same token from the converter .env>
   ```

   Pass this file through the existing Odoo Compose service's `env_file`
   configuration or your existing deployment secret mechanism. These are
   runtime variables; do not add the token as a Docker build argument or
   commit it. The URL is the service base URL, without `/convert/dwg`.

5. Deploy the matching `tap_odoo_base` changes, rebuild the ARM Odoo image
   with its updated requirements, and recreate the Odoo containers to load
   the runtime environment. Upgrade the preview modules as needed. Those
   deployment operations are not performed by preparing these files.

6. Open a DWG in Documents and in the standard attachment viewer. Verify
   the preview and original download. An unavailable converter displays
   the download fallback; the shared token is never exposed to the browser.

## Validation

The x86 image was built and a real DXF → DWG → DXF round trip passed in a
one-off container with the same filesystem/user/resource restrictions. That
check did not run an HTTP listener or publish a port. Isolated tests cover
authentication, input limits, busy/failure handling, timeout cleanup, the
Odoo request and rejection of redirects. CadQuery 2.8.0 passed the existing
DXF/STEP/STL reader suite. ARM wheel resolution is checked separately; no
running AWS container is modified by these tests.
