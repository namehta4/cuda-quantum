# ============================================================================ #
# Copyright (c) 2022 - 2026 NVIDIA Corporation & Affiliates.                   #
# All rights reserved.                                                         #
#                                                                              #
# This source code and the accompanying materials are made available under     #
# the terms of the Apache License 2.0 which accompanies this distribution.     #
# ============================================================================ #

ARG base_image=redhat/ubi8:8.10

# [CUDA-Q Installation]
FROM ${base_image}
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

ARG base_image
ARG libcdev_package
ARG cudart_version
ARG cuda_distribution

## [Runtime dependencies]
ADD docker/test/installer/runtime_dependencies.sh /runtime_dependencies.sh
RUN export LIBCDEV_PACKAGE=${libcdev_package} && \
    export CUDART_VERSION=${cudart_version} && \
    export CUDA_DISTRIBUTION=${cuda_distribution} && \
    export VALIDATION_PACKAGES="cmake make git" && \
    . /runtime_dependencies.sh ${base_image} && \
    # working around the fact that the installation of the dependencies includes
    # setting some environment variables that are expected to be persistent on
    # on the host system but would not persistent across docker commands
    env | egrep "^(PATH=|MANPATH=|INFOPATH=|PCP_DIR=|LD_LIBRARY_PATH=|PKG_CONFIG_PATH=)" \
        >> /etc/environment

## [MPI Installation]
RUN dnf install -y --nobest --setopt=install_weak_deps=False mpich mpich-devel \
    && ln -s /usr/lib64/mpich/bin/mpiexec /bin/mpiexec

# Create new user `cudaq` with admin rights to confirm installation steps.
RUN useradd cudaq && mkdir -p /etc/sudoers.d && \
    echo 'cudaq ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/020_cudaq
RUN mkdir -p /home/cudaq && chown -R cudaq /home/cudaq
USER cudaq
WORKDIR /home/cudaq

## [Install]
ARG cuda_quantum_installer='out/install_cuda_quantum*'
ADD "${cuda_quantum_installer}" .
RUN source /etc/environment && \
    echo "Installing CUDA-Q..." && \
    ## [>CUDAQuantumInstall]
    MPI_PATH=/usr/lib64/mpich \
    sudo -E bash install_cuda_quantum*.$(uname -m) --accept && . /etc/profile
    ## [<CUDAQuantumInstall]
RUN . /etc/profile && nvq++ --help

## [ADD tools for validation]
ADD scripts/validate_installation.sh /home/cudaq/validate.sh
ADD scripts/test_cmake_find_package.sh /home/cudaq/test_cmake_find_package.sh
ADD scripts/configure_build.sh /home/cudaq/configure_build.sh
ADD docker/test/installer/mpi_cuda_check.cpp /home/cudaq/mpi_cuda_check.cpp
ADD docs/sphinx/examples/cpp /home/cudaq/examples
ADD docs/sphinx/applications/cpp /home/cudaq/applications
ADD docs/sphinx/targets/cpp /home/cudaq/targets

# Wheel to check side-by-side installation of Python and C++ support
ARG cuda_quantum_wheel='cuda_quantum_*.whl'
ADD "${cuda_quantum_wheel}" /home/cudaq
ADD python/tests /home/cudaq/python

ENTRYPOINT ["bash", "-l"]

