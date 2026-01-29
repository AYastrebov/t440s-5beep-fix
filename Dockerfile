FROM ubuntu:22.04

LABEL maintainer="T440s BIOS Fix Project"
LABEL description="Docker image with all tools for T440s 5-Beep BIOS fix"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system packages
RUN apt-get update && apt-get install -y \
    p7zip-full \
    wget \
    perl \
    flashrom \
    build-essential \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Build ifdtool from coreboot source
RUN git clone --depth 1 https://review.coreboot.org/coreboot.git /tmp/coreboot \
    && cd /tmp/coreboot/util/ifdtool \
    && make && cp ifdtool /usr/local/bin/ \
    && rm -rf /tmp/coreboot

# Download and install UEFIExtract
RUN wget -q https://github.com/LongSoft/UEFITool/releases/download/A68/UEFIExtract_NE_A68_linux_x86_64.zip \
    && unzip UEFIExtract_NE_A68_linux_x86_64.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/UEFIExtract \
    && rm UEFIExtract_NE_A68_linux_x86_64.zip

# Copy scripts
COPY prepare_bios.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/prepare_bios.sh

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
