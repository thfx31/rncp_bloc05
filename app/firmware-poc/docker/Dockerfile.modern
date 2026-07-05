# =============================================================================
# build-modern-ubuntu22
#
# Represents the modern build environment for new firmware projects:
#   - Ubuntu 22.04 (Jammy) — LTS, actively maintained
#   - gcc-12 (modern compiler with enhanced warnings and hardening)
#   - arm-linux-gnueabihf cross-compiler (hard-float ABI, Cortex-A targets)
#   - Simulator binary for CI validation
# =============================================================================

FROM ubuntu:22.04

LABEL maintainer="poc-ci@example.com"
LABEL description="Modern build environment — Ubuntu 22.04 + gcc-12"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-12 \
        g++-12 \
        make \
        cmake \
        binutils \
        file \
        git \
        ca-certificates \
        # ARM cross-compiler (hard-float, for Cortex-A/Cortex-M with FPU)
        gcc-arm-linux-gnueabihf \
        binutils-arm-linux-gnueabihf \
        # Static analysis helpers
        cppcheck \
        # Minimal utilities
        curl \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set gcc-12 as default
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 \
 && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120

# Copy and compile the simulator
COPY simulator/simulator.c /opt/simulator/simulator.c

RUN gcc -Wall -O2 -o /usr/local/bin/simulator /opt/simulator/simulator.c \
 && chmod +x /usr/local/bin/simulator \
 && rm -rf /opt/simulator

WORKDIR /workspace

# Verify installation
RUN gcc --version \
 && arm-linux-gnueabihf-gcc --version \
 && simulator --help 2>&1 || true

CMD ["/bin/bash"]