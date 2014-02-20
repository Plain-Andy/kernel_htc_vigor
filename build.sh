#!/bin/bash -e

msg() {
    echo
    echo ==== $* ====
    echo
}

# -----------------------

CROSS_COMPILE=$ARM_EABI_TOOLCHAIN/arm-eabi-

LOCAL_BUILD_DIR=$OUT

TARGET_DIR=$OUT

SYSTEM_PARTITION=$(grep -r "/system" $ANDROID_BUILD_TOP/$TARGET_RECOVERY_FSTAB | sed 's\/system.*\\' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

DEFCONFIG=$TARGET_KERNEL_CONFIG

FLASH_BOOT=$(grep -r "/boot" $ANDROID_BUILD_TOP/$TARGET_RECOVERY_FSTAB | sed 's\/boot.*\\' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

PHONE="$PRODUCT_MANUFACTURER $PRODUCT_MODEL"

DATE=$(date +%Y-%m-%d)

# ----

VERSION=$TARGET_PRODUCT-kernel-$DATE

# ----

BANNER=`cat <<EOF
ui_print("$VERSION");
ui_print("for");
ui_print("$PHONE");
EOF`

TOOLS_DIR=$TARGET_KERNEL_SOURCE

# -----------------------

ZIP=$TARGET_DIR/$VERSION.zip
UPDATE_ROOT=$LOCAL_BUILD_DIR/update
KEYS=$ANDROID_BUILD_TOP/build/target/product/security
CERT=$KEYS/testkey.x509.pem
KEY=$KEYS/testkey.pk8
GLOBAL=$LOCAL_BUILD_DIR/global
POSTBOOT=$LOCAL_BUILD_DIR/postboot
VIDEOFIX=$LOCAL_BUILD_DIR/videofix
ZIMAGE=arch/arm/boot/zImage

msg Building: $VERSION
echo "   Defconfig:       $DEFCONFIG"
echo "   Local build dir: $LOCAL_BUILD_DIR"
echo "   Target dir:      $TARGET_DIR"
echo "   Tools dir:       $TOOLS_DIR"
echo
echo "   Target system partition: $SYSTEM_PARTITION"
echo

if [ -e $CERT -a -e $KEY ]
then
    msg Reusing existing $CERT and $KEY
else
    msg Regenerating keys, pleae enter the required information.

    (
	#mkdir -p $KEYS
	cd $KEYS
	openssl genrsa -out key.pem 1024 && \
	openssl req -new -key key.pem -out request.pem && \
	openssl x509 -req -days 9999 -in request.pem -signkey key.pem -out certificate.pem && \
	openssl pkcs8 -topk8 -outform DER -in key.pem -inform PEM -out key.pk8 -nocrypt
    )
fi

if [ -e $UPDATE_ROOT ]
then
    rm -rf $UPDATE_ROOT
fi

if [ -e $LOCAL_BUILD_DIR/update.zip ]
then
    rm -f $LOCAL_BUILD_DIR/update.zip
fi

cd $TOOLS_DIR

if [ ! -e $LOCAL_BUILD_DIR/kernel ]
then
make $DEFCONFIG

perl -pi -e 's/(CONFIG_LOCALVERSION="[^"]*)/\1-'"$VERSION"'"/' .config

make -j$(cat /proc/cpuinfo | grep "^processor" | wc -l) ARCH=arm CROSS_COMPILE="$CROSS_COMPILE"

msg Kernel built successfully, building $ZIP
else
msg Using pre-built kernel, building $ZIP
fi

mkdir -p $UPDATE_ROOT/system/lib/modules

if [ ! -e $LOCAL_BUILD_DIR/kernel ]
then
find . -name '*.ko' -exec cp {} $UPDATE_ROOT/system/lib/modules/ \;
else
cp $OUT/system/lib/modules/* $UPDATE_ROOT/system/lib/modules/*
fi

mkdir -p $UPDATE_ROOT/META-INF/com/google/android
cp ./update-binary $UPDATE_ROOT/META-INF/com/google/android

if [ ! -e $LOCAL_BUILD_DIR/kernel ]
then
SUM=`sha1sum $ZIMAGE | cut --delimiter=' ' -f 1`
else
SUM=`sha1sum $LOCAL_BUILD_DIR/kernel | cut --delimiter=' ' -f 1`
fi

(
    cat <<EOF
$BANNER
EOF
  sed -e "s|@@SYSTEM_PARTITION@@|$SYSTEM_PARTITION|" \
      -e "s|@@FLASH_BOOT@@|$FLASH_BOOT|" \
      -e "s|@@SUM@@|$SUM|" \
      < ./updater-script
) > $UPDATE_ROOT/META-INF/com/google/android/updater-script

mkdir -p $UPDATE_ROOT/kernel
if [ -e $LOCAL_BUILD_DIR/kernel ]
then
cp $LOCAL_BUILD_DIR/kernel $UPDATE_ROOT/kernel/zImage
else
cp ./$ZIMAGE $UPDATE_ROOT/kernel
fi
cp ./AnyKernel/* $UPDATE_ROOT/kernel

(
    cd $UPDATE_ROOT
    zip -r ../update.zip .
)
java -jar ./signapk.jar $CERT $KEY $LOCAL_BUILD_DIR/update.zip $ZIP
if [ ! -e $LOCAL_BUILD_DIR/kernel ]
then
make mrproper
fi
rm -rf $UPDATE_ROOT
rm -f $LOCAL_BUILD_DIR/update.zip
msg COMPLETE
cd $ANDROID_BUILD_TOP
