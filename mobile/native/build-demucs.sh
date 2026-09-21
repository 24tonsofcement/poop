#!/usr/bin/env bash
set -euo pipefail
source_dir="$RUNNER_TEMP/demucs-src"
git clone --recursive https://github.com/sevagh/demucs.cpp.git "$source_dir"
git -C "$source_dir" checkout f1206e9adeea103aef4a636b9e62297cf1f8e34e
git -C "$source_dir" submodule update --init --recursive
for abi in arm64-v8a x86_64; do
  build_dir="$RUNNER_TEMP/demucs-$abi"
  cmake -S mobile/native/demucs -B "$build_dir" -G Ninja \
    -DDEMUCS_SOURCE="$source_dir" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/27.2.12479018/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static
  cmake --build "$build_dir" -j2
  mkdir -p "android/build/native-libs/$abi"
  cp "$build_dir/libpulse_demucs.so" "android/build/native-libs/$abi/"
done
mkdir -p android/build/native-assets
curl --fail --retry 3 -L -o android/build/native-assets/htdemucs-6s-f16.bin \
 https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/main/ggml-model-htdemucs-6s-f16.bin
echo '09704f4ceae204e56e77d5eefd6ac71d7275be81fd507e6913371d59abcee856  android/build/native-assets/htdemucs-6s-f16.bin' | sha256sum --check
# Fail rather than package an HTML error or an incomplete model.
test "$(stat -c%s android/build/native-assets/htdemucs-6s-f16.bin)" -gt 40000000
mkdir -p android/build/native-assets/licenses
cp "$source_dir/LICENSE" android/build/native-assets/licenses/demucs-cpp.txt
