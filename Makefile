FW_URL		:= https://github.com/raspberrypi/firmware/archive/fcf8d2f7639ad8d0330db9c8db9b71bd33eaaa28.tar.gz

EFI_BUILD	:= RELEASE
EFI_ARCH	:= AARCH64
EFI_TOOLCHAIN	:= GCC5
EFI_TIMEOUT	:= 3
EFI_FLAGS	:= --pcd=PcdPlatformBootTimeOut=$(EFI_TIMEOUT)
EFI_DSC		:= edk2-platforms/Platform/RaspberryPi/RPi3/RPi3.dsc
EFI_FD		:= Build/RPi3/$(EFI_BUILD)_$(EFI_TOOLCHAIN)/FV/RPI_EFI.fd

IPXE_CROSS	:= aarch64-linux-gnu-
IPXE_SRC	:= ipxe/src
IPXE_TGT	:= bin-arm64-efi/rpi.efi
IPXE_EFI	:= $(IPXE_SRC)/$(IPXE_TGT)

SDCARD_MB	:= 32
export MTOOLSRC	:= mtoolsrc

SHELL		:= /bin/bash

all : sdcard sdcard.img sdcard.zip

submodules :
	git submodule update --init --recursive

firmware :
	if [ ! -e firmware ] ; then \
		wget -O firmware-tmp.tar.gz $(FW_URL) && \
		mkdir -p firmware && \
		tar xf firmware-tmp.tar.gz --strip-components=1 -C firmware && \
		rm firmware-tmp.tar.gz ; \
	fi

efi : $(EFI_FD)

efi-basetools : submodules
	$(MAKE) -C edk2/BaseTools

$(EFI_FD) : submodules efi-basetools
	. ./edksetup.sh && \
	build -b $(EFI_BUILD) -a $(EFI_ARCH) -t $(EFI_TOOLCHAIN) \
		-p $(EFI_DSC) $(EFI_FLAGS)

ipxe : $(IPXE_EFI)

$(IPXE_EFI) : submodules
	$(MAKE) -C $(IPXE_SRC) CROSS=$(IPXE_CROSS) CONFIG=rpi $(IPXE_TGT)

sdcard : firmware efi ipxe
	$(RM) -rf sdcard
	mkdir -p sdcard
	cp -r $(sort $(filter-out firmware/boot/kernel%,$(wildcard firmware/boot/*))) \
		sdcard/
	cp config.txt $(EFI_FD) edk2/License.txt sdcard/
	mkdir -p sdcard/efi/boot
	cp $(IPXE_EFI) sdcard/efi/boot/bootaa64.efi
	cp ipxe/COPYING* sdcard/

sdcard.img : sdcard
	truncate -s $(SDCARD_MB)M $@
	mpartition -I -c -b 32 -s 32 -h 64 -t $(SDCARD_MB) -a "z:"
	mformat -v "piPXE" "z:"
	mcopy -s sdcard/* "z:"

sdcard.zip : sdcard
	$(RM) -f $@
	( pushd $< ; zip -q -r ../$@ * ; popd )

update:
	git submodule foreach git pull origin master

tag :
	git tag v`git show -s --format='%ad' --date=short | tr -d -`

.PHONY : submodules firmware efi efi-basetools $(EFI_FD) ipxe $(IPXE_EFI) \
	 sdcard sdcard.img

clean :
	$(RM) -rf firmware Build sdcard sdcard.img sdcard.zip
	if [ -d $(IPXE_SRC) ] ; then $(MAKE) -C $(IPXE_SRC) clean ; fi
