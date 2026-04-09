# ============================================================================ #
# Copyright (c) 2022 - 2026 NVIDIA Corporation & Affiliates.                   #
# All rights reserved.                                                         #
#                                                                              #
# This source code and the accompanying materials are made available under     #
# the terms of the Apache License 2.0 which accompanies this distribution.     #
# ============================================================================ #

# This file contains additional CUDA-Q development dependencies.
# The image installs cuQuantum, cuTensor, and the CUDA packages defined by the
# cuda_packages build argument.
#
# Usage:
# Must be built from the repo root with:
#   docker build -t ghcr.io/nvidia/cuda-quantum-devdeps:ext -f docker/build/devcontainer.Dockerfile .

ARG cuda_version=12.6
ARG base_image=ghcr.io/nvidia/cuda-quantum-devdeps:gcc11-main
FROM $base_image
SHELL ["/bin/bash", "-c"]
ARG cuda_version
ENV CUDA_VERSION=${cuda_version}

# When a dialogue box would be needed during install, assume default configurations.
# Set here to avoid setting it for all install commands. 
# Given as arg to make sure that this value is only set during build but not in the launched container.
ARG DEBIAN_FRONTEND=noninteractive
RUN apt update && apt-get install -y --no-install-recommends ca-certificates wget build-essential \
    && apt-get upgrade -y libc-bin libcap2 \
    && apt-get autoremove -y --purge && apt-get clean && rm -rf /var/lib/apt/lists/* 

# We need to remove the preinstalled cuda keyring as this will conflict when installing even non-cuda packages.
# When cuda packages are installed below, the keyring will be reinstalled.
RUN rm -f /etc/apt/sources.list.d/cuda.list

# Install Mellanox OFED runtime dependencies.

RUN apt-get update && apt-get install -y --no-install-recommends gnupg \
    && wget -qO - "https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox" | apt-key add - \
    && mkdir -p /etc/apt/sources.list.d && wget -q -nc --no-check-certificate -P /etc/apt/sources.list.d "https://linux.mellanox.com/public/repo/mlnx_ofed/5.3-1.0.0.1/ubuntu20.04/mellanox_mlnx_ofed.list" \
    && apt-get update -y && apt-get install -y --no-install-recommends \
        ibverbs-providers ibverbs-utils \
        libibmad5 libibumad3 libibverbs1 librdmacm1 \
    && rm /etc/apt/trusted.gpg && rm /etc/apt/sources.list.d/mellanox_mlnx_ofed.list \
    && apt-get remove -y gnupg \
    && apt-get autoremove -y --purge && apt-get clean && rm -rf /var/lib/apt/lists/* 

# Install CUDA

ARG cuda_packages="cuda-cudart cuda-nvrtc cuda-compiler libcublas libcublas-dev libcurand-dev libcusolver libcusparse-dev libnvjitlink cuda-nvml-dev"
RUN if [ -n "$cuda_packages" ]; then \
        # Filter out libnvjitlink if CUDA version is less than 12
        if [ $(echo $CUDA_VERSION | cut -d "." -f1) -lt 12 ]; then \
            cuda_packages=$(echo "$cuda_packages" | tr ' ' '\n' | grep -v "libnvjitlink" | tr '\n' ' ' | sed 's/ *$//'); \
        fi \
        && arch_folder=$([ "$(uname -m)" == "aarch64" ] && echo sbsa || echo x86_64) \
        && cuda_packages=$(echo "$cuda_packages" | tr ' ' '\n' | xargs -I {} echo {}-$(echo ${CUDA_VERSION} | cut -d. -f1-2 | tr . -)) \
        && wget -q "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/$arch_folder/cuda-keyring_1.1-1_all.deb" \
        && dpkg -i cuda-keyring_1.1-1_all.deb \
        && apt-get update && apt-get install -y --no-install-recommends --allow-change-held-packages $cuda_packages \
        && rm cuda-keyring_1.1-1_all.deb \
        && apt-get autoremove -y --purge && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# The installation of CUDA above creates files that will be injected upon launching the container
# with the --gpu=all flag. This creates issues upon container launch. We hence remove these files.
# As long as the container is launched with the --gpu=all flag, the GPUs remain accessible and CUDA
# is fully functional. See also https://github.com/NVIDIA/nvidia-docker/issues/1699.
RUN if [ -z "$CUDA_ROOT" ]; then \
        rm -rf \
        /usr/lib/$(uname -m)-linux-gnu/libcuda.so* \
        /usr/lib/$(uname -m)-linux-gnu/libnvcuvid.so* \
        /usr/lib/$(uname -m)-linux-gnu/libnvidia-*.so* \
        /usr/lib/firmware \
        /usr/local/cuda/compat/lib; \
    fi

ENV CUDA_INSTALL_PREFIX="/usr/local/cuda-${CUDA_VERSION}"
ENV CUDA_HOME="$CUDA_INSTALL_PREFIX"
ENV CUDA_ROOT="$CUDA_INSTALL_PREFIX"
ENV CUDA_PATH="$CUDA_INSTALL_PREFIX"
ENV PATH="${CUDA_INSTALL_PREFIX}/lib64/:${CUDA_INSTALL_PREFIX}/bin:${PATH}"
# TODO: Eliminate the need for this
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install cuQuantum dependencies, including cuTensor.
# Install cupy version 13.4.1
# Note: for docker images, we fixed the cuquantum version (with `==`) to avoid unintentional upgrades.
# e.g., API marked as deprecated in a minor version upgrade may break build.
# For Python pip installations, we allow minor version upgrades with `~=`, assuming the API is stable.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* && \
    if [ "$(echo $CUDA_VERSION | cut -d . -f1)" = "13" ]; then \
        cupy_version=13.6.0; \
    else \
        cupy_version=13.4.1; \
    fi && \
    python3 -m pip install --break-system-packages cupy-cuda$(echo $CUDA_VERSION | cut -d . -f1)x==${cupy_version} cuquantum-cu$(echo $CUDA_VERSION | cut -d . -f1)==26.1.0 && \
    if [ "$(python3 --version | grep -o [0-9\.]* | cut -d . -f -2)" != "3.12" ]; then \
        echo "expecting Python version 3.12"; \
    fi

ARG CUQUANTUM_INSTALL_PREFIX=/usr/local/lib/python3.12/dist-packages/cuquantum
ENV CUQUANTUM_INSTALL_PREFIX="$CUQUANTUM_INSTALL_PREFIX"
ENV CUQUANTUM_ROOT="$CUQUANTUM_INSTALL_PREFIX"
ENV CUQUANTUM_PATH="$CUQUANTUM_INSTALL_PREFIX"
ENV LD_LIBRARY_PATH="$CUQUANTUM_INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"
ENV CPATH="$CUQUANTUM_INSTALL_PREFIX/include:$CPATH"

ARG CUTENSOR_INSTALL_PREFIX=/usr/local/lib/python3.12/dist-packages/cutensor
ENV CUTENSOR_INSTALL_PREFIX="$CUTENSOR_INSTALL_PREFIX"
ENV CUTENSOR_ROOT="$CUTENSOR_INSTALL_PREFIX"
ENV LD_LIBRARY_PATH="$CUTENSOR_INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"
ENV CPATH="$CUTENSOR_INSTALL_PREFIX/include:$CPATH"
