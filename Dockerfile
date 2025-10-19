# SPDX-License-Identifier: Apache-2.0
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# Make sure Dockerfile doesn't succeed if there are errors.
RUN ["/bin/sh", "-c", "/bin/bash", "-o", "pipefail", "-c"]

# Set apt install to not be interactive for some packages that require it.
ENV DEBIAN_FRONTEND=noninteractive

# Set oneAPI library environment variable
ENV LD_LIBRARY_PATH=/opt/intel/oneapi/redist/lib:/opt/intel/oneapi/redist/lib/intel64:$LD_LIBRARY_PATH

# Install certificate authorities to get access to secure connections to other places for downloads and other packages.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends --fix-missing \
    ca-certificates \
    fonts-noto \
    git \
    gnupg2 \
    gpg-agent \
    software-properties-common \
    unzip \
    wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add and prepare Intel Graphics driver index. This is dependent on being able to pass your GPU with a working driver on the host side where the image will run.
# hadolint ignore=DL4006
# Install the Intel graphics GPG public key  
RUN wget --progress=dot:giga -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
   | gpg --dearmor | tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null && \
   echo 'deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main' \
   | tee /etc/apt/sources.list.d/oneAPI.list
RUN wget --progress=dot:giga -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
    gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
RUN echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble unified" | \
    tee /etc/apt/sources.list.d/intel-gpu-noble.list

# Sets versions of Level-Zero, OpenCL and memory allocator chosen.
ARG CMPLR_COMMON_VER=2025.0
ARG DPCPP_VER=2025.0.4-1519
ARG LIBZE_VER=1.20.2.0-1098~24.04
ARG OCLOC_VER=25.05.32567.18-1099~24.04

# Install Level-Zero and OpenCL backends.
RUN apt-get update && \
    apt-get install -y --no-install-recommends --fix-missing \
    clinfo \
    intel-gsc \
    intel-oneapi-common-vars \
    intel-oneapi-dpcpp-cpp-${CMPLR_COMMON_VER}=${DPCPP_VER} \
    intel-oneapi-compiler-shared-common-${CMPLR_COMMON_VER}=${DPCPP_VER} \
    intel-oneapi-runtime-dpcpp-cpp=${DPCPP_VER} \
    intel-opencl-icd=${OCLOC_VER} \
    libze-intel-gpu1=${OCLOC_VER} \
    libze-dev=${LIBZE_VER} && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Make sure everything is up to date.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends --fix-missing && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf  /var/lib/apt/lists/*

# Install Python and other associated packages from PPA since default is 3.10
ARG PYTHON=python3.12
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends --fix-missing \
    ${PYTHON} \
    ${PYTHON}-dev \
    lib${PYTHON} \
    python3-pip \
    ${PYTHON}-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the startup script to the /bin/ folder and make executable.
COPY startup.sh /bin/
RUN chmod 755 /bin/startup.sh

# Volumes that can be used by the image when making containers.
VOLUME [ "/deps2" ]
VOLUME [ "/ComfyUI" ]
VOLUME [ "/models" ]
VOLUME [ "/root/.cache/huggingface" ]

# Setup location of Python virtual environment
ENV VENVDir=/deps2/venv

# Enable Level Zero system management
# See https://spec.oneapi.io/level-zero/latest/sysman/PROG.html
ENV ZES_ENABLE_SYSMAN=1

# Force 100% available VRAM size for compute-runtime.
# See https://github.com/intel/compute-runtime/issues/586
ENV NEOReadDebugKeys=1
ENV ClDeviceGlobalMemSizeAvailablePercent=100

# Enable double precision emulation. Turned off by default to enable attention slicing to address the 4GB single allocation limit with Intel Xe GPUs and lower.
# See https://github.com/intel/compute-runtime/blob/master/opencl/doc/FAQ.md#feature-double-precision-emulation-fp64
#ENV OverrideDefaultFP64Settings=1
#ENV IGC_EnableDPEmulation=1

# Enable SYCL variables for cache reuse and single threaded mode.
# See https://github.com/intel/llvm/blob/sycl/sycl/doc/EnvironmentVariables.md
ENV SYCL_CACHE_PERSISTENT=1
ENV SYCL_PI_LEVEL_ZERO_SINGLE_THREAD_MODE=1

# Setting to turn on for Intel Xe GPUs that do not have XMX cores which include any iGPUs from Intel Ice Lake to Meteor Lake.
#ENV BIGDL_LLM_XMX_DISABLED=1

# Linux only setting that speeds up compute workload submissions allowing them to run concurrently on a single hardware queue. Turned off by default since
# this was only introduced recently with the Xe graphics driver you need to turn on by default manually and development focus has been on using this feature
# with Data Center GPU Max Series. Only also seems to benefit LLMs mostly when Intel encourages turning it on on Intel Arc cards. Also need kernel 6.2 or up.
# See https://www.intel.com/content/www/us/en/developer/articles/guide/level-zero-immediate-command-lists.html
#ENV SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1

# Set to false if CPU is to be used to launch ComfyUI. XPU is default.
ARG UseXPU=true
ENV UseXPU=${UseXPU}

# Set to true if ipexrun is to be used to launch ComfyUI. Off by default.
ARG UseIPEXRUN=false
ENV UseIPEXRUN=${UseIPEXRUN}

# Set to the arguments you want to pass to ipexrun.
# Example for CPU: --multi-task-manager 'taskset' --memory-allocator ${ALLOCATOR}
# Example for XPU: --convert-fp64-to-fp32
ARG IPEXRUNArgs=""
ENV IPEXRUNArgs=${IPEXRUNArgs}

# Pass in ComfyUI arguments as an environment variable so it can be used in startup_nightly.sh which passes it on.
ARG ComfyArgs=""
ENV ComfyArgs=${ComfyArgs}

# Set location and entrypoint of the image to the ComfyUI directory and the startup script.
WORKDIR /ComfyUI
ENTRYPOINT [ "startup.sh" ]
