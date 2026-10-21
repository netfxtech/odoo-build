# This stage is also embedded in aws:~/docker/odoo-build/Dockerfile.
# Build with the same Debian variant as the Odoo runtime for ABI compatibility.
ARG PYTHON_VERSION=3.12-slim
ARG OS_VARIANT=bookworm
FROM python:${PYTHON_VERSION}-${OS_VARIANT} AS libredwg-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/libredwg
RUN curl -fsSL --retry 3 https://ftp.gnu.org/gnu/libredwg/libredwg-0.14.tar.gz -o source.tar.gz \
    && echo 'cb6ee0b078c6d9e0f09d66f1feac33ba6342df88ae544e9f9335fab475218351  source.tar.gz' | sha256sum -c - \
    && tar -xzf source.tar.gz --strip-components=1 \
    && ./configure CFLAGS='-O1' --disable-shared --enable-static --disable-bindings --disable-docs --disable-json \
    && make -j1 -C src \
    && make -j1 -C programs dwg2dxf \
    && install -D -m 0755 programs/dwg2dxf /out/usr/local/bin/dwg2dxf \
    && strip /out/usr/local/bin/dwg2dxf \
    && install -D -m 0644 COPYING /out/usr/local/share/licenses/libredwg/COPYING \
    && /out/usr/local/bin/dwg2dxf --version

FROM python:${PYTHON_VERSION}-${OS_VARIANT} AS libredwg-runtime
COPY --from=libredwg-builder /out/usr/local/ /usr/local/
RUN dwg2dxf --version
