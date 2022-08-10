#!/bin/sh

. ./ci/zinc/linux_base.sh

OLD_ZIG="$DEPS_LOCAL/bin/zig"
TARGET="${ARCH}-linux-musl"
MCPU="baseline"

# Make the `zig version` number consistent.
# This will affect the cmake command below.
git config core.abbrev 9

echo "building stage3-debug with zig version $($OLD_ZIG version)"

# Override the cache directories so that we don't clobber with the release
# testing script which is running concurrently and in the same directory.
# Normally we want processes to cooperate, but in this case we want them isolated.
export ZIG_LOCAL_CACHE_DIR="$(pwd)/zig-cache-local-debug"
export ZIG_GLOBAL_CACHE_DIR="$(pwd)/zig-cache-global-debug"

export CC="$OLD_ZIG cc -target $TARGET -mcpu=$MCPU"
export CXX="$OLD_ZIG c++ -target $TARGET -mcpu=$MCPU"

mkdir build-debug
cd build-debug
cmake .. \
  -DCMAKE_INSTALL_PREFIX="$DEBUG_STAGING" \
  -DCMAKE_PREFIX_PATH="$DEPS_LOCAL" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DZIG_TARGET_TRIPLE="$TARGET" \
  -DZIG_TARGET_MCPU="$MCPU" \
  -DZIG_STATIC=ON \
  -GNinja

# Now cmake will use zig as the C/C++ compiler. We reset the environment variables
# so that installation and testing do not get affected by them.
unset CC
unset CXX

ninja install

# Here we rebuild zig but this time using the Zig binary we just now produced to
# build zig1.o rather than relying on the one built with stage0. See
# https://github.com/ziglang/zig/issues/6830 for more details.
cmake .. -DZIG_EXECUTABLE="$DEBUG_STAGING/bin/zig"
ninja install

cd $WORKSPACE

"$DEBUG_STAGING/bin/zig" build -p stage3 -Denable-stage1 -Dstatic-llvm -Dtarget=native-native-musl --search-prefix "$DEPS_LOCAL"

# simultaneously test building self-hosted without LLVM and with 32-bit arm
stage3/bin/zig build -Dtarget=arm-linux-musleabihf

echo "Looking for non-conforming code formatting..."
echo "Formatting errors can be fixed by running 'zig fmt' on the files printed here."
stage3/bin/zig fmt --check . --exclude test/cases/

stage3/bin/zig build test \
  -fqemu \
  -fwasmtime \
  -Dstatic-llvm \
  -Dtarget=native-native-musl \
  --search-prefix "$DEPS_LOCAL"

# Explicit exit helps show last command duration.
exit
