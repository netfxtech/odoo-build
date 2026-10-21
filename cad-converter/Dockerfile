# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm

ARG TARGETARCH
ARG ODA_URL=https://www.opendesign.com/guestfiles/get?filename=ODAFileConverter_QT6_lnxX64_11dll.deb
# Official DEB: ODA File Converter 27.9.0.0, amd64. A changed download fails
# checksum verification; review and update this pin before changing versions.
ARG ODA_SHA256=12f5e14c55c35176062f63e242d5390f732722213dd685fa3cd44a6555384cd0

RUN test "${TARGETARCH}" = amd64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl xvfb xauth libgl1 libopengl0 libegl1 libglib2.0-0 \
       libfontconfig1 libfreetype6 libdbus-1-3 libx11-6 libx11-xcb1 \
       libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
       libxcb-render-util0 libxcb-util1 libxcb-xinerama0 libxcb-xkb1 \
       libxkbcommon-x11-0 libxrender1 libxi6 \
    && curl --fail --silent --show-error --location --retry 2 \
       "${ODA_URL}" --output /tmp/oda.deb \
    && echo "${ODA_SHA256}  /tmp/oda.deb" | sha256sum --check --strict \
    && test "$(dpkg-deb -f /tmp/oda.deb Architecture)" = amd64 \
    && apt-get install -y --no-install-recommends /tmp/oda.deb \
    && chmod 0755 /usr/bin/ODAFileConverter \
    && if [ ! -e /usr/lib/x86_64-linux-gnu/libxcb-util.so.0 ]; then \
         ln -s libxcb-util.so.1 /usr/lib/x86_64-linux-gnu/libxcb-util.so.0; \
       fi \
    && rm -rf /var/lib/apt/lists/* /tmp/oda.deb

WORKDIR /app
COPY server.py /app/server.py
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOME=/tmp
USER 10001:10001
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz', timeout=3)"
CMD ["python", "/app/server.py"]
