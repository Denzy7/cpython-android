#/bin/sh

set -e

if [[ ! -v ANDROID_NDK_ROOT ]]; then
    echo "We need ANDROID_NDK_ROOT"
    exit 1
fi

if [[ ! -v CHOST ]]; then
    echo "We need CHOST"
    exit 1
fi

rootpath=$(dirname $(realpath $0))

_architectures="aarch64 armv7a-eabi x86 x86-64"

if [[ -v ARCH ]]; then
_architectures=$ARCH
fi

PYTHON_VERSION=3.13

export ANDROID_NDK_ROOT=$(realpath "$ANDROID_NDK_ROOT")
export ANDROID_MINIMUM_PLATFORM=21
export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"

for _arch in ${_architectures}; do
    sed "s|@TRIPLE@|${_arch}|g" "$rootpath/android-configure_PKGBUILD/android-configure.sh" > android-${_arch}-configure
    chmod +x android-${_arch}-configure
done
ln -sf "$rootpath/android-environment/android-env.sh" android-env

export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-$(uname -m)/bin:$PWD:$PWD/host-python/usr/local/bin:$PATH"
export LC_ALL=C

if ! command -v "python$PYTHON_VERSION" >/dev/null 2>&1; then
    echo "We must compile host python first"
    mkdir -p build-host-python
    pushd build-host-python
    "$rootpath/cpython/configure" --prefix=/usr/local --disable-test-modules
    make -j$(nproc)
    make DESTDIR=../host-python install
    popd
fi

for _arch in ${_architectures}; do

    case "${_arch}" in
        aarch64)
            osslArch=arm64
            ;;
        armv7a-eabi)
            osslArch=arm
            ;;
        x86)
            osslArch=x86
            ;;
        x86-64)
            osslArch=x86_64
            ;;
        *)
            osslArch="unknown"
            ;;
    esac

    if [[ "$osslArch" == "unknown" ]]; then
        continue
    fi

    source android-env $_arch

    mkdir -p build-ossl-$_arch
    pushd build-ossl-$_arch
    echo "build openssl for $_arch"
    "$rootpath/openssl/Configure" --prefix="${ANDROID_PREFIX}" android-$osslArch -D__ANDROID_API__=$ANDROID_MINIMUM_PLATFORM no-docs no-tests
    make -j$(nproc)
    make DESTDIR=../output install
    popd

    echo "Build python$PYTHON_VERSION for $_arch"
    mkdir -p build-$_arch-python
    pushd build-$_arch-python
    ../android-$_arch-configure  --disable-test-modules --with-build-python --with-ensurepip=install  --with-openssl=../output/$ANDROID_EXTERNAL_LIBS/$_arch/ $rootpath/cpython
    make -j$(nproc)
    make DESTDIR=../output install
    popd
done


