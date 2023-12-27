# Rudimentary Dockerfile
FROM registry.gitlab.steamos.cloud/steamrt/scout/sdk

# Use the later binutils
RUN cp /usr/lib/binutils-2.30/bin/* /usr/bin/

# Scout finally has GCC 12 :D
# We also need nasm for libvpx
RUN apt-get install -y \
    gcc-12-monolithic \
    nano \
    nasm \
    binutils-2.30-dev \
    libconfig8-dev \
    libedit-dev \
    install-info

# Scout has update-alternatives specified for gcc/g++, we need to use something higher than 100
RUN update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120

# Auto-config update-alternatives to update gcc version
RUN update-alternatives --auto g++
RUN update-alternatives --auto gcc

# Temporary build directory for CMake
RUN mkdir /cmake_build

# Download, build, and install CMake 3.28.1
RUN cd /cmake_build && wget https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1.tar.gz
RUN cd /cmake_build && tar xf cmake-3.28.1.tar.gz
RUN cd /cmake_build/cmake-3.28.1 && mkdir build && cd build && cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr && ninja && ninja install

# Build a new version of Git from source, the version in the scout runtime is ANCIENT (1.7.9.5)
RUN mkdir /git_build && \
    cd /git_build && \
    wget https://github.com/git/git/archive/refs/tags/v2.43.0.tar.gz && \
    tar xf v2.43.0.tar.gz && \
    cd git-2.43.0 && \
    make configure && \
    ./configure --prefix=/usr && \
    make all -j8 && \
    make install

# Get LLVM 7 source and build it for bootstrapping with old ldc2
RUN mkdir /llvm7 && cd /llvm7 && git clone https://github.com/llvm/llvm-project.git --recurse -b release/7.x
RUN cd /llvm7/llvm-project && \
    mkdir build && \
    cd build && \
    cmake ../llvm -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/llvm7/install -DLLVM_INCLUDE_TESTS=OFF && \
    ninja && ninja install

# Clone ldc2 ltsmaster, used for bootstrapping to compile newer versions of ldc2
RUN mkdir /ldc_build && \
    cd /ldc_build && \
    git clone https://github.com/ldc-developers/ldc.git ldc-lts --recurse -b ltsmaster

# Build and install to our prefix
RUN cd /ldc_build/ldc-lts && \
    mkdir build && cd build && \
    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ldc_build/install/ltsmaster -DMULTILIB=ON -DLLVM_ROOT_DIR=/llvm7/install && \
    ninja && ninja install

# Clone the 1.20.x release of ldc2, not the latest, but we need to compile this first in order to compile the latest version.
# This is incredibly convoluted, but also mildly hilarious.
RUN cd /ldc_build && \
    git clone https://github.com/ldc-developers/ldc.git ldc-1.20 --recurse -b release-1.20.x

# Build and install to our prefix
RUN cd /ldc_build/ldc-1.20 && \
    mkdir build && cd build && \
    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ldc_build/install/1.20.x -DD_COMPILER=/ldc_build/install/ltsmaster/bin/ldmd2 -DMULTILIB=ON -DLLVM_ROOT_DIR=/llvm7/install && \
    ninja && ninja install

# Get LLVM 16 source, build, and install (for ldc2 v1.35.0)
# Do this last, so when we upgrade later, the docker/podman build cache will save us from having to redo EVERYTHING
RUN mkdir /llvm16 && cd /llvm16 && git clone https://github.com/llvm/llvm-project.git --recurse -b release/16.x
RUN cd /llvm16/llvm-project && \
    mkdir build && \
    cd build && \
    cmake ../llvm -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DLLVM_INCLUDE_TESTS=OFF && \
    ninja && ninja install

# Clone 1.35.0 release of ldc2. This is the latest currently. The 1.36 beta is out, so we may update soon.
RUN cd /ldc_build && \
    git clone https://github.com/ldc-developers/ldc.git ldc-1.35.0 --recurse -b v1.35.0

# Build and install the latest version of ldc2 :D
RUN cd /ldc_build/ldc-1.35.0 && \
    mkdir build && cd build && \
    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release =DCMAKE_INSTALL_PREFIX=/usr -DD_COMPILER=/ldc_build/install/1.20.x/bin/ldmd2 -DMULTILIB=ON && \
    ninja && ninja install

# Temporary build directory for D tools (needed for rdmd)
RUN mkdir /dlang_tools_build

# Clone the tools repo
RUN cd /dlang_tools_build && git clone https://github.com/dlang/tools.git --recurse -b v2.106.0

# Build and "install" rdmd
RUN cd /dlang_tools_build/tools && \
    ldc2 rdmd.d -O2 -of=/usr/bin/rdmd

# Temporary build directory for dub
RUN mkdir /dub_build

# Clone dub
RUN cd /dub_build && git clone https://github.com/dlang/dub.git --recurse -b v1.33.0

# Build dub
RUN cd /dub_build/dub && DMD=ldmd2 ./build.d

# Install dub
RUN cp /dub_build/dub/bin/dub /usr/bin/dub

# Remove our temporary building directories
RUN rm -rf /cmake_build
RUN rm -rf /git_build
RUN rm -rf /ldc_build
RUN rm -rf /llvm7
RUN rm -rf /llvm16
RUN rm -rf /dlang_tools_build
RUN rm -rf /dub_build
