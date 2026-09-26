# llama-ROCmFPX Builder — charlie12345/ROCmFPX (Vulkan backend)
# Builds llama-server/llama-cli/llama-quantize from the canonical upstream fork
# and outputs the binaries via a shared volume for llama-swap.
#
# WHY VULKAN: the Unraid host has no ROCm userspace (/opt/rocm* empty) and the
# existing llama-swap stack uses the Vulkan backend. Vulkan runs on the exposed
# /dev/dri path and was the fastest decode backend in upstream's own tests.
# This is a VULKAN-ONLY build: the build stage ships no ROCm SDK (HIP compilation
# needs hipcc), and the host has no ROCm runtime anyway. If you later add a ROCm
# runtime to the host you'd switch the build base to a rocm/dev image and flip
# GGML_HIP=ON with CMAKE_HIP_ARCHITECTURES=gfx1201.

ARG UBUNTU_VERSION=24.04

# Build stage: needs cmake + Vulkan toolchain (glslang/glslc for shader compile).
# ROCm dev image NOT used — keep the toolchain lean; Vulkan needs no ROCm SDK.
FROM ubuntu:${UBUNTU_VERSION} AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates curl \
      libvulkan-dev glslang-tools libglm-dev ninja-build \
      glslc libshaderc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone the canonical upstream fork (main branch), not a downstream re-pack.
RUN git clone https://github.com/charlie12345/ROCmFPX.git llama.cpp \
    && cd llama.cpp && git checkout main \
    && git log -1 --format="%H %s"

WORKDIR /src/llama.cpp

# Match upstream's own build-rocmfp4.sh flags (Vulkan on, server on).
# gfx1201 = RX 9070 / 9070 XT. Vulkan-only build: the build stage has no ROCm
# SDK (HIP compilation needs hipcc), and the host runs Vulkan — enable Vulkan,
# leave HIP off entirely.
RUN cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_VULKAN=ON \
      -DGGML_HIP=OFF \
      -DGGML_CUDA=OFF \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_WEBUI=OFF \
      -DLLAMA_USE_PREBUILT_WEBUI=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DGGML_BUILD_TESTS=OFF \
      -DCMAKE_BUILD_PARALLEL_LEVEL=$(nproc) \
    && cmake --build build --config Release --target llama-server llama-cli llama-quantize -j $(nproc)

# Runtime image: Vulkan loader + mesa radeon driver for /dev/dri.
FROM ubuntu:${UBUNTU_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      libvulkan1 libgl1-mesa-dri mesa-vulkan-drivers libgomp1 libstdc++6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=build /src/llama.cpp/build/bin/llama-cli     /usr/local/bin/llama-cli
COPY --from=build /src/llama.cpp/build/bin/llama-quantize /usr/local/bin/llama-quantize

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV OUTPUT_DIR=/output

ENTRYPOINT ["/entrypoint.sh"]