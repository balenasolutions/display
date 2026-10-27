# ==============================================================================
# BUILD: Weston from source
# ==============================================================================
# Debian trixie ships Weston 14.0.2, which aborts on pointer motion on
# Raspberry Pi (assert(fb) in state-propose.c, fixed upstream after 14.x).
# Only the DRM backend, GL renderer, kiosk and desktop shells and weston-debug
# are built. Runtime libraries are trixie packages.
FROM debian:13.2-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

ARG WESTON_VERSION=16.0.1
ARG WESTON_SHA256=54f889d236d73f497e7929f355ad87f03c2bbcde945bb29fbbae2a4b3050e467
ARG WESTON_URL=https://gitlab.freedesktop.org/wayland/weston/-/releases/${WESTON_VERSION}/downloads/weston-${WESTON_VERSION}.tar.xz

# Weston 16 requires wayland-protocols >= 1.46 at build time; trixie has 1.44,
# trixie-backports has a newer release.
# g++ is required by Weston's meson project declaration; no C++ is compiled
# (C++ is only used by the Perfetto tracing option, which is disabled).
RUN echo "deb http://deb.debian.org/debian trixie-backports main" \
        > /etc/apt/sources.list.d/backports.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dpkg-dev \
    g++ \
    gcc \
    libc6-dev \
    libcairo2-dev \
    libdisplay-info-dev \
    libdrm-dev \
    libegl-dev \
    libevdev-dev \
    libgbm-dev \
    libgles-dev \
    libinput-dev \
    liblcms2-dev \
    libpixman-1-dev \
    libpng-dev \
    libseat-dev \
    libudev-dev \
    libwayland-dev \
    libxkbcommon-dev \
    meson \
    ninja-build \
    pkg-config \
    wayland-protocols/trixie-backports \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSLo weston.tar.xz "${WESTON_URL}" && \
    echo "${WESTON_SHA256}  weston.tar.xz" | sha256sum -c - && \
    tar -xJf weston.tar.xz && \
    rm weston.tar.xz

# Compiler and linker flags from dpkg-buildflags with all hardening features
# enabled: fortify, stack protector, stack clash protection, full RELRO (bindnow),
# PIE, and branch protection or CET where the architecture supports them.
# https://manpages.debian.org/trixie/dpkg-dev/dpkg-buildflags.1.en.html#hardening
ENV DEB_BUILD_MAINT_OPTIONS=hardening=+all
RUN eval "$(dpkg-buildflags --export=sh)" && \
    meson setup build "weston-${WESTON_VERSION}" \
        --prefix=/usr/local \
        --libdir=lib \
        --buildtype=plain \
        --wrap-mode=nofallback \
        -Db_pie=true \
        -Dbackend-default=drm \
        -Dbackend-drm=true \
        -Dbackend-headless=false \
        -Dbackend-pipewire=false \
        -Dbackend-rdp=false \
        -Dbackend-vnc=false \
        -Dbackend-wayland=false \
        -Dbackend-x11=false \
        -Drenderer-gl=true \
        -Drenderer-vulkan=false \
        -Dxwayland=false \
        -Dsystemd=false \
        -Dshell-desktop=true \
        -Dshell-kiosk=true \
        -Dshell-ivi=false \
        -Dshell-lua=false \
        -Dcolor-management-lcms=true \
        -Dimage-jpeg=false \
        -Dimage-webp=false \
        -Dtools=debug \
        -Ddemo-clients=false \
        '-Dsimple-clients=[]' \
        -Dtests=false \
        -Ddoc=false && \
    meson compile -C build && \
    DESTDIR=/opt/weston meson install -C build --strip && \
    rm -rf /opt/weston/usr/local/include \
           /opt/weston/usr/local/lib/pkgconfig \
           /opt/weston/usr/local/share/man \
           /opt/weston/usr/local/share/pkgconfig

# ==============================================================================
# RUNTIME
# ==============================================================================
FROM debian:13.2-slim

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Runtime libraries for the Weston build, from trixie so they receive Debian
# security updates. libcairo2 and libpng16-16t64 are used by
# weston-desktop-shell (DISPLAY_UX_MODE=desktop).
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    dbus \
    gettext-base \
    libcairo2 \
    libdisplay-info2 \
    libdrm2 \
    libegl-mesa0 \
    libegl1 \
    libevdev2 \
    libgbm1 \
    libgl1-mesa-dri=25.* \
    libgles2 \
    libinput10 \
    liblcms2-2 \
    libpixman-1-0 \
    libpng16-16t64 \
    libseat1 \
    libwayland-client0 \
    libwayland-cursor0 \
    libwayland-server0 \
    libxkbcommon0 \
    udev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/weston/ /

# Fails the build if a Weston binary or module has an unresolved library.
RUN ldconfig && \
    ! ldd /usr/local/bin/weston* /usr/local/libexec/weston-* \
          /usr/local/lib/libweston-16/*.so /usr/local/lib/weston/*.so \
        | grep 'not found' && \
    weston --version

# Setup Weston
RUN mkdir -p /etc/weston/templates
COPY weston-templates/ /etc/weston/templates/
COPY weston-env-defaults.sh /etc/weston/weston-env-defaults.sh


COPY entry.sh /usr/bin/entry.sh
RUN chmod +x /usr/bin/entry.sh

CMD ["/usr/bin/entry.sh"]
