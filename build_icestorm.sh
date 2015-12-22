#!/bin/bash

# This script automates the process of building Project IceStorm.
# The configuration is stored in icestorm_build.cfg

# defines if script should download and build libs - set to 0 if you want to do this step manually
ENABLE_DOWNLOAD_LIB=1

# defines if script should clone git before building - set to 0 if you want to clone manually
ENABLE_DOWNLOAD_ICESTORM=1

# defines if script should build IceStorm Project files - set to 0 if you want to build IceStorm manually
ENABLE_BUILD=1

# defines if script should copy all needed files to one directory - set to 0 if you want to prepare files manually
ENABLE_INSTALL=1

# first - load variables from the configuration file:
echo "Loading config." >&2
set -a 
source ./icestorm_build.cfg
set +a
set -e
# basic conf check
echo "Checking configuration..." >&2

# check if CC_PREFIX is properly set
if which ${CC_PREFIX}gcc >/dev/null; then
	echo Compiler prefix set as:  ${CC_PREFIX} 
else
	echo "Compiler with prefix ${CC_PREFIX} not available. Make sure to add it to your PATH environment variable."
	exit
fi

# DOWNLOAD AND BUILD LIBS
# In this step, the script will download, untar, build
# and install libraries which are required later.
if [ $ENABLE_DOWNLOAD_LIB -eq 1 ]; then
echo "Installing libs..."
	echo "Preparing directories."
	mkdir -p $ROOT_DIR/lib
	cd $ROOT_DIR/lib
	
	# download and build libusb
	echo "Downloading libusb..."
	wget $LIBUSB_URL -O libusb.archive
	echo "Unpacking libusb..."
	mkdir -p libusb
	tar -xvf libusb.archive -C ./libusb --strip-components=1
	echo "Building libusb..."
	mkdir -p libusb/build
	mkdir -p $LIBUSB_INSTALL_PATH
	cd libusb/build
	.././configure --host=arm-linux-gnueabihf --prefix=$LIBUSB_INSTALL_PATH
	make -j`nproc`
	make install	

	# download and build libftdi
	cd $ROOT_DIR/lib
	echo "Downloading libftdi..."
	wget $LIBFTDI_URL -O libftdi.archive
	echo "Unpacking libftdi..."
	mkdir -p libftdi
	tar -xvf libftdi.archive -C ./libftdi --strip-components=1
	echo "Building libftdi..."
	mkdir -p libftdi/build
	mkdir -p $LIBFTDI_INSTALL_PATH
	cd libftdi/build
	cmake -DCMAKE_INSTALL_PREFIX="${LIBFTDI_INSTALL_PATH}" -DCMAKE_CXX_COMPILER="${CC_PREFIX}g++" -DCMAKE_C_COMPILER="${CC_PREFIX}gcc" -DLIBUSB_LIBRARIES="${LIBUSB_INSTALL_PATH}/lib/libusb-1.0.so" -DLIBUSB_INCLUDE_DIR="${LIBUSB_INSTALL_PATH}/include/libusb-1.0" -DPYTHON_BINDINGS=OFF -DFTDIPP=OFF ../
	make
	make install

	# download and build libncurses
	cd $ROOT_DIR/lib
	echo "Downloading libncurses..."
	wget $LIBNCURSES_URL -O libncurses.archive
	echo "Unpacking libncurses..."
	mkdir -p libncurses
	tar -xvf libncurses.archive -C ./libncurses --strip-components=1
	mkdir -p libncurses/build
	mkdir -p $LIBNCURSES_INSTALL_PATH
	cd libncurses/build

	# prepare variables needed to build ncurses
	# those variables will aslo be used when
	# building libreadline and libtcl 
	export TARGETMACH=arm-none-linux-gnueabihf
	export BUILDMACH=`uname -m`
	export CROSS=$CC_PREFIX
	export LD=${CROSS}ld
	export AS=${CROSS}as
	export CC=${CROSS}gcc
	export CXX=${CROSS}g++

	# build libncurses
	.././configure --host=$TARGETMACH --prefix=$LIBNCURSES_INSTALL_PATH --with-shared --without-debug --without-ada --enable-overwrite
	echo "Building libncurses..."
	make -j`nproc`
	make install 

	# download and build libreadline
	cd $ROOT_DIR/lib
	echo "Downloading libreadline..."
	wget $LIBREADLINE_URL -O libreadline.archive
	wget http://lfs-matrix.net/patches/downloads/readline/readline-6.2-fixes-1.patch
	echo "Unpacking libreadline..."
	mkdir -p libreadline
	tar -xvf libreadline.archive -C ./libreadline --strip-components=1
	mv readline-6.2-fixes-1.patch ./libreadline
	cd libreadline
	mkdir -p build
	mkdir -p $LIBREADLINE_INSTALL_PATH
	patch -Np1 < ./readline-6.2-fixes-1.patch
	cd build
	.././configure --prefix=$LIBREADLINE_INSTALL_PATH --host=$TARGETMACH LDFLAGS=-L$LIBNCURSES_INSTALL_PATH/lib
	echo "Building libreadline..."
	make SHLIB_LIBS=-lncurses
	make install

	# download and build libffi
	cd $ROOT_DIR/lib
	echo "Downloading libffi..."
	wget $LIBFFI_URL -O libffi.archive
	echo "Unpacking libffi..."
	mkdir -p libffi
	tar -xvf libffi.archive -C ./libffi --strip-components=1
	mkdir -p libffi/build
	mkdir -p $LIBFFI_INSTALL_PATH
	cd libffi/build
	echo "Building libffi..."
	.././configure --host=arm-linux-gnueabihf --prefix=$LIBFFI_INSTALL_PATH
	make -j`nproc`
	make install

	# download and build libtcl
	cd $ROOT_DIR/lib
	echo "Downloading libtcl..."
	wget $LIBTCL_URL -O libtcl.archive
	echo "Unpacking libtcl..."
	mkdir -p libtcl
	tar -xvf libtcl.archive -C ./libtcl --strip-components=1
	mkdir -p libtcl/build
	mkdir -p $LIBTCL_INSTALL_PATH
	cd libtcl/build
	# little hack needed to build tcl
	export av_cv_func_strtod=yes
	export tcl_cv_strtod_buggy=1
	echo "Building libtcl..."
	../unix/./configure --host=$TARGETMACH --prefix=$LIBTCL_INSTALL_PATH
	make -j`nproc`
	make install
	echo "All libraries installed."
	cd $ROOT_DIR
fi


# CLONE GIT REPOSITORIES
if [ $ENABLE_DOWNLOAD_ICESTORM -eq 1 ]; then
	echo "Cloning repositories..."
	cd $ROOT_DIR
	git clone -b ARM-cross-compile https://github.com/antmicro/yosys.git
	git clone -b ARM-cross-compile https://github.com/antmicro/icestorm.git icestorm-tools
	git clone -b ARM-cross-compile https://github.com/antmicro/arachne-pnr.git
	git clone -b ARM-cross-compile https://github.com/antmicro/abc-lib.git
fi

# BUILD THE ICESTORM PROJECT
# First the script performs some checks. We need to make sure
# that all libraries are available and the root directory is
# properly set
if [ $ENABLE_BUILD -eq 1 ]; then

echo "Building IceStorm Project..."

# check if ROOT_DIR contains icestorm, yosys, arachne-pnr and abc
DIRS_TO_CHECK="icestorm-tools yosys arachne-pnr abc-lib"
set -- $DIRS_TO_CHECK
echo "Checking if $ROOT_DIR is valid root directory."
for i in "$@"
do
	if [ ! -d $ROOT_DIR/$i ]; then
		echo "Directory $i does not exist. Are you sure you have downloaded all the files and set ROOT_DIR properly?"
		exit
	fi
done

# check if library's paths are set properly
temp_variable_array=(LIBUSB_INSTALL_PATH LIBFTDI_INSTALL_PATH LIBNCURSES_INSTALL_PATH LIBREADLINE_INSTALL_PATH LIBFFI_INSTALL_PATH LIBTCL_INSTALL_PATH)

for i in ${temp_variable_array[@]}
do
	if [ ! -d  ${!i} ]; then
		echo "Directory ${!i} does not exist. Check if INSTALL_PATHs in icestorm_build.cfg are set properly."
		exit
	fi
done

# BUILD ICESTORM TOOLS PROPER

# BUILD ICESTORM
echo "Building icepack..."
cd $ROOT_DIR/icestorm-tools/icepack
make -j`nproc`

echo "Building icebox..."
cd $ROOT_DIR/icestorm-tools/icebox
make -j`nproc`

echo "Building icemulti..."
cd $ROOT_DIR/icestorm-tools/icemulti
make -j`nproc`

echo "Building iceprog..."
cd $ROOT_DIR/icestorm-tools/iceprog
make -j`nproc`

# BUILD ARACHNE-PNR
echo "Building arachne-pnr..."
cd $ROOT_DIR/arachne-pnr/
make -j1

# BUILD LIBABC
echo "Building libabc..."
cd $ROOT_DIR/abc-lib
make -j`nproc`

# BUILD YOSYS
echo "Building yosys..."
cd $ROOT_DIR/yosys
make -j`nproc`
fi

# INSTALL
# In this step all files required by the IceStorm Project
# are copied to $INSTALLATION_PATH.
if [ $ENABLE_INSTALL -eq 1 ]; then
	echo "Installing the files to $INSTALLATION_PATH"
	cd $ROOT_DIR
	mkdir -p $INSTALLATION_PATH/bin
	mkdir -p $INSTALLATION_PATH/lib
	mkdir -p $INSTALLATION_PATH/share/yosys
	mkdir -p $INSTALLATION_PATH/share/arachne-pnr
	echo "Copying the binaries..."
	cd $INSTALLATION_PATH/bin
	cp $ROOT_DIR/icestorm-tools/icepack/icepack ./
	cp $ROOT_DIR/icestorm-tools/icemulti/icemulti ./
	cp $ROOT_DIR/icestorm-tools/iceprog/iceprog ./
	cp $ROOT_DIR/arachne-pnr/bin/arachne-pnr-arm ./arachne-pnr
	cp $ROOT_DIR/yosys/yosys-* ./
	cp $ROOT_DIR/yosys/yosys ./
	echo "Copying the data..."
	cd $INSTALLATION_PATH/share/yosys
	cp -r $ROOT_DIR/yosys/share/* ./
	cd $INSTALLATION_PATH/share/arachne-pnr
	cp -r $ROOT_DIR/arachne-pnr/share/arachne-pnr/* ./
	echo "Copying the libraries..."
	cd $INSTALLATION_PATH/lib
	cp $LIBUSB_INSTALL_PATH/lib/libusb* ./
	cp $LIBFTDI_INSTALL_PATH/lib/libftdi1* ./
	cp $LIBNCURSES_INSTALL_PATH/lib/lib* ./
	cp $LIBREADLINE_INSTALL_PATH/lib/lib* ./
	cp $LIBFFI_INSTALL_PATH/lib/*.so* ./
	cp $LIBTCL_INSTALL_PATH/lib/lib* ./
fi
