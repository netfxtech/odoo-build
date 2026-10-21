# Native ARM64 DWG previews

The supplied `aws-build.patch` adds the `libredwg-builder` stage from this
directory to AWS's `~/docker/odoo-build/Dockerfile`. It builds LibreDWG 0.14
for the image's native architecture using the same Debian variant as Odoo,
links LibreDWG statically into `dwg2dxf`,
and copies the converter and GPL-3.0-or-later license into the base image.
The GNU source tarball is verified with a pinned SHA-256. Build tools and
source files stay in the separate stage.

The patch is already applied on AWS. For a fresh build checkout, apply it from
the Odoo build directory after copying it there:

```sh
patch --dry-run -p1 < aws-build.patch
patch -p1 < aws-build.patch
```

The source build uses one compiler process and `-O1` to reduce peak memory.

The Python requirements remain `ezdxf==1.4.4` and `cadquery==2.8.0`; Odoo
already supplies Pillow. LibreDWG has no requirements.txt entry. No Xvfb or
converter service is required for this route.

After rebuilding and deploying the Odoo image through the usual deployment
process, verify `dwg2dxf --version` inside the Odoo container. Upgrade
`tap_odoo_base` and `tap_documents` and reload the browser. Preparing these
changes does not rebuild or restart the production image.

## Isolated build and conversion check

The standalone Dockerfile uses the same build stage and can be tested without
building Odoo or starting a service:

```sh
DOCKER_BUILDKIT=0 docker build --memory=1536m --memory-swap=1536m \
  --cpu-period=100000 --cpu-quota=100000 -t tap-libredwg-test:0.14 .
docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges --memory 2g --pids-limit 64 \
  --user 1000:1000 --tmpfs /tmp:rw,noexec,nosuid,size=64m,mode=1777 \
  -v "$PWD/example.dwg:/input/example.dwg:ro" tap-libredwg-test:0.14 \
  dwg2dxf -v0 -o /tmp/example.dxf /input/example.dwg
```

The preview worker runs conversion in a disposable directory with a 25-second
timeout and suppresses converter output. The existing worker CPU, memory,
file-size and process-group limits also apply. DXF output is limited to 32 MiB.

The pinned stage was built on both x86-64 and native AWS ARM64 with the limits
above. Real R2000 and ACAD2018 DWGs converted successfully in isolated containers
on both architectures. The actual preview subprocess also rendered both files
as SVG on the development host, preserving the modern fixture's line and circle.
Twenty isolated renderer/protocol tests passed. Full Odoo integration tests
remain blocked by the checkout's unrelated `odoo.tests.suite._logger` import
failure; these checks do not claim production Documents browser validation.

LibreDWG reads all DWG versions, but some advanced objects can be skipped.
Compare previews of representative real drawings before deciding whether ODA
is needed. The existing [ODA service](../cad-converter/README.md) remains an
optional alternative. Configuring `TAP_CAD_CONVERTER_URL` and
`TAP_CAD_CONVERTER_TOKEN` explicitly selects that service; with no URL, the
worker uses local `dwg2dxf`, or local ODA if `dwg2dxf` is absent.

Sources: [GNU LibreDWG](https://github.com/LibreDWG/libredwg),
[Linux ARM64 packages](https://formulae.brew.sh/formula/libredwg), and
[official source release](https://ftp.gnu.org/gnu/libredwg/).
