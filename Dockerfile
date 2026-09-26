# llama-ROCmFPX Builder
# Builds the latest ArtomYuan/llama.cpp-rocm fork with ROCm/HIP support
# and outputs the llama-server binary.

ARG ROCM_VERSION=7.2.1
ARG UBUNTU_VERSION=24.04

FROM docker.io/rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-complete AS build

ARG AMDGPU_TARGETS="gfx908;gfx90a;gfx942;gfx1030;gfx1100;gfx1101;gfx1102;gfx1151;gfx1150;gfx1200;gfx1201"

SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    curl \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone the latest upstream source
RUN git clone https://github.com/ArtomYuan/llama.cpp-rocm.git . \
    && git log -1 --format="%H %s"

# Build with HIP
RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" \
        -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_SERVER=ON \
    && cmake --build build --config Release -j$(nproc) --target llama-server

# Minimal runtime image
FROM ubuntu:${UBUNTU_VERSION} AS runtime

RUN apt-get update && apt-get install -y \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/bin/llama-server /usr/local/bin/llama-server

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV OUTPUT_DIR=/output

ENTRYPOINT ["/entrypoint.sh"]