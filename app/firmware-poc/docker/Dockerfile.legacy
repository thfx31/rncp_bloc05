# =============================================================================
# build-legacy-ubuntu18
#
# Represents the legacy build environment used in production:
#   - Ubuntu 18.04 (Bionic) — EOL but still used for old toolchains
#   - gcc-7 (legacy compiler required by old firmware projects)
#   - arm-linux-gnueabi cross-compiler
#   - Simulator binary for CI validation
#
# In production this environment was a dedicated workstation or Jenkins node
# running natively on Ubuntu 18.04. This image eliminates that dependency.
# =============================================================================

FROM ubuntu:18.04

LABEL maintainer="poc-ci@example.com"
LABEL description="Legacy build environment — Ubuntu 18.04 + gcc-7"
LABEL version="1.0.0"

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-7 \
        g++-7 \
        make \
        cmake \
        binutils \
        file \
        git \
        ca-certificates \
        # ARM cross-compiler (represents the embedded toolchain)
        gcc-arm-linux-gnueabi \
        binutils-arm-linux-gnueabi \
        # Minimal runtime utilities
        curl \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set gcc-7 as default gcc
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 70 \
 && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 70

# Copy and compile the simulator
COPY simulator/simulator.c /opt/simulator/simulator.c

RUN gcc -Wall -O2 -o /usr/local/bin/simulator /opt/simulator/simulator.c \
 && chmod +x /usr/local/bin/simulator \
 && rm -rf /opt/simulator

# Build directory — firmware sources will be mounted/copied here
WORKDIR /workspace

# Verify installation
RUN gcc --version \
 && arm-linux-gnueabi-gcc --version \
 && simulator --help 2>&1 || true

CMD ["/bin/bash"]