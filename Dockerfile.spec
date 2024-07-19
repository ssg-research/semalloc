FROM debian:bullseye

RUN DEBIAN_FRONTEND="noninteractive" apt-get update && apt-get -y install tzdata

# base
RUN apt-get update \
  && apt-get install -y build-essential \
      gcc \
      g++ \
      gdb \
      make \
      ninja-build \
      cmake \
      autoconf \
      automake \
      libtool \
      locales-all \
      dos2unix \
      rsync \
      tar \
      python3 \
      python3-dev \
      python3-pip \
  && apt-get clean

RUN apt-get update \
  && apt-get install -y git vim \
  && apt-get clean

RUN apt-get update \
  && apt-get install -y tar wget \
  && apt-get clean

# clang15
RUN mkdir -p /app/llvm15
RUN git clone https://github.com/llvm/llvm-project /app/llvm15

WORKDIR /app/llvm15
RUN git checkout e758b77161a7

RUN mkdir -p /app/llvm15/build
WORKDIR /app/llvm15/build
RUN cmake -DLLVM_TARGET_ARCH="X86" -DLLVM_TARGETS_TO_BUILD="ARM;X86;AArch64" \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="clang;openmp" -DLLVM_ENABLE_RTTI=ON -G "Unix Makefiles" ../llvm

RUN make -j$(nproc)
RUN cmake -DCMAKE_INSTALL_PREFIX=/app/llvm15/build -P cmake_install.cmake
RUN cmake -DCMAKE_INSTALL_PREFIX=/app/llvm15/build -P /app/llvm15/build/projects/openmp/cmake_install.cmake

# wllvm
RUN pip3 install wllvm

# parsec dependencies
RUN apt-get update \
  && apt-get install -y libx11-dev libxext-dev libxt-dev libxmu-headers x11proto-input-dev libxi-dev  pkg-config gettext libxmu-dev\
  && apt-get clean

# use bash
SHELL ["/bin/bash", "-ec"]

# spec get
RUN wget -O /app/spec.iso <<<<<<<<LINK>>>>>>>>
RUN mkdir -p /app/spec
WORKDIR /app/spec
RUN cmake -E tar xf /app/spec.iso
RUN echo yes | /app/spec/install.sh

# update spec
RUN source shrc
RUN rm /app/spec.iso

# install monitor dependency
RUN apt-get update && apt-get install -y time ruby-full curl && apt-get clean

# copy semalloc
RUN mkdir -p /app/semalloc
COPY . /app/semalloc

# copy config
RUN cp /app/semalloc/benchmark/assets/semalloc.cfg /app/spec/config
RUN cp /app/semalloc/benchmark/assets/benchmark.pm /app/spec/bin/harness
RUN cp /app/semalloc/benchmark/assets/setup_common.pl /app/spec/bin/common
WORKDIR /app/spec

# build and convert spec
RUN mkdir -p /app/semalloc/test
RUN mkdir -p /app/semalloc/test/input

WORKDIR /app/spec
RUN source shrc

RUN python3 /app/semalloc/benchmark/assets/spec_build_1.py
RUN /app/semalloc/benchmark/assets/spec_build_2.rb

# build semalloc frontend
RUN mkdir -p /app/semalloc/frontend/build
WORKDIR /app/semalloc/frontend/build

RUN LLVM_DIR=/app/llvm15/build/lib/cmake/llvm cmake ..
RUN make -j6

# build semalloc backend
RUN mkdir -p /app/semalloc/backend/build
WORKDIR /app/semalloc/backend/build
RUN LLVM_DIR=/app/llvm15/build/lib/cmake/llvm cmake -DGLIBC_OVERRIDE=ON ..
RUN make -j6

# clone memory allocators
RUN mkdir -p /app/markus
RUN mkdir -p /app/ffmalloc

RUN mkdir -p /app/markus && git clone http://github.com/SamAinsworth/MarkUs-sp2020.git /app/markus
RUN mkdir -p /app/ffmalloc && git clone http://github.com/bwickman97/ffmalloc.git /app/ffmalloc

# build them
WORKDIR /app/markus/bdwgc-markus
RUN ./autogen.sh
RUN ./configure --prefix=/app/markus --enable-redirect-malloc --enable-threads=posix --disable-gc-assertions --enable-thread-local-alloc --enable-parallel-mark --disable-munmap --enable-cplusplus --enable-large-config --disable-gc-debug 
RUN make install

WORKDIR /app/ffmalloc
RUN make

# spec output
RUN mkdir -p /app/semalloc/output/
