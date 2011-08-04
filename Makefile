CLUTTER_MAJOR_VERSION = 1.7
CLUTTER_VERSION = 1.7.6
COGL_MAJOR_VERSION = 1.7
COGL_VERSION = 1.7.4
MX_MAJOR_VERSION = 1.3
MX_VERSION = 1.3.0
PACKAGE_VERSION = $(CLUTTER_VERSION).1
CC = i686-pc-mingw32-gcc
CLUTTER_GIT_PATCH = http://git.gnome.org/browse/clutter/patch/?id=
COGL_GIT_PATCH = http://git.gnome.org/browse/cogl/patch/?id=
BUILD_TYPE = `uname -m`-unknown-linux-gnu

LIB = WINEPREFIX="$(PWD)" wine lib.exe

CANDLE = WINEDLLOVERRIDES="msi=n" WINEPREFIX="$(PWD)" wine candle.exe
LIGHT = WINEDLLOVERRIDES="msi=n" WINEPREFIX="$(PWD)" wine light.exe

WIXOBJS = clutter.wixobj

all : clutter-$(PACKAGE_VERSION).msi

downloads/clutter-$(CLUTTER_VERSION).tar.bz2 :
	mkdir -p downloads
	wget -O $@ http://source.clutter-project.org/sources/clutter/$(CLUTTER_MAJOR_VERSION)/clutter-$(CLUTTER_VERSION).tar.bz2

downloads/mx-$(MX_VERSION).tar.bz2 :
	mkdir -p downloads
	wget -O $@ http://source.clutter-project.org/sources/mx/$(MX_MAJOR_VERSION)/mx-$(MX_VERSION).tar.bz2

downloads/cogl-$(COGL_VERSION).tar.bz2 :
	mkdir -p downloads
	wget -O $@ http://source.clutter-project.org/sources/cogl/$(COGL_MAJOR_VERSION)/cogl-$(COGL_VERSION).tar.bz2

clutter-source-stamp : downloads/clutter-$(CLUTTER_VERSION).tar.bz2
	tar -jxf $<
	if test "$(CLUTTER_VERSION)" = "1.7.6"; then \
	  ( cd clutter-$(CLUTTER_VERSION) && wget -q -O - \
	    "$(CLUTTER_GIT_PATCH)91ace65cae" \
	    | patch -p1 ); \
	fi
	touch $@

cogl-source-stamp : downloads/cogl-$(COGL_VERSION).tar.bz2
	tar -jxf $<
	if test "$(COGL_VERSION)" = "1.7.4"; then \
	  ( cd cogl-$(COGL_VERSION) \
	     && for x in d259a87602516 f7bdc92d6c397 38deb9747; do \
	       wget -q -O - \
	         "$(COGL_GIT_PATCH)$$x" \
	       | patch -f -p1; done ); \
	fi
	touch $@

mx-source-stamp : downloads/mx-$(MX_VERSION).tar.bz2
	tar -jxf $<
	( cd mx-$(MX_VERSION) \
	  && for x in \
	      0001-mx-create-image-cache-Use-GDir-instead-of-opendir.patch \
	      0002-mx-image-Conditionally-call-sysconf.patch \
	      0003-configure.ac-Add-no-undefined-to-the-libtool-flags.patch; \
	       do \
	      patch -p1 < ../"$$x" || exit 1; done )
	touch $@

deps-install-stamp : clutter-source-stamp
	DOWNLOAD_PROG=$(PWD)/download-wrapper.sh \
	ROOT_DIR=$(PWD)/deps-install \
	DOWNLOAD_DIR=$(PWD)/downloads \
	BUILD_DIR=$(PWD)/deps-build \
	clutter-$(CLUTTER_VERSION)/build/mingw/mingw-fetch-dependencies.sh
	$(LIB) /machine:i386 \
	/def:$(PWD)/deps-build/json-glib-0.12.2/json-glib/.libs/libjson-glib-1.0-0.dll.def \
	/out:$(PWD)/deps-install/lib/json-glib-1.0.lib \
	/name:libjson-glib-1.0-0.dll
	touch $@

cogl-install-stamp : cogl-source-stamp clutter-source-stamp deps-install-stamp
	cd cogl-$(COGL_VERSION) && \
	  ./configure --host="i686-pc-mingw32" \
	  --target="i686-pc-mingw32" \
	  --build="$(BUILD_TYPE)" \
	  --disable-glx \
	  --enable-wgl \
	  --prefix="$(PWD)/cogl-install" \
	  CFLAGS="-O2 -mms-bitfields" \
	  PKG_CONFIG="$(PWD)/deps-build/run-pkg-config.sh"
	make -C cogl-$(COGL_VERSION) all install
	$(LIB) /machine:i386 \
	/def:cogl-$(COGL_VERSION)/cogl/.libs/libcogl-2.dll.def \
	/out:$(PWD)/cogl-install/lib/cogl.lib \
	/name:libcogl-2.dll
	$(LIB) /machine:i386 \
	/def:cogl-$(COGL_VERSION)/cogl-pango/.libs/libcogl-pango-0.dll.def \
	/out:$(PWD)/cogl-install/lib/cogl-pango.lib \
	/name:libcogl-pango-0.dll
	touch $@

clutter-install-stamp : clutter-source-stamp deps-install-stamp cogl-install-stamp
	cd clutter-$(CLUTTER_VERSION) && \
	  ./configure --host="i686-pc-mingw32" \
	  --target="i686-pc-mingw32" \
	  --build="$(BUILD_TYPE)" \
	  --with-flavour=win32 \
	  --prefix="$(PWD)/clutter-install" \
	  CFLAGS="-O2 -mms-bitfields" \
	  PKG_CONFIG="$(PWD)/deps-build/run-pkg-config.sh" \
	  PKG_CONFIG_PATH="$(PWD)/cogl-install/lib/pkgconfig"
	make -C clutter-$(CLUTTER_VERSION) all install
	$(LIB) /machine:i386 \
	/def:clutter-$(CLUTTER_VERSION)/clutter/.libs/libclutter-win32-1.0-0.dll.def \
	/out:$(PWD)/clutter-install/lib/clutter-win32-1.0.lib \
	/name:libclutter-win32-1.0-0.dll
	touch $@

mx-install-stamp : mx-source-stamp clutter-install-stamp
	cd mx-$(MX_VERSION) && \
	  gnome-autogen.sh --host="i686-pc-mingw32" \
	  --target="i686-pc-mingw32" \
	  --build="$(BUILD_TYPE)" \
	  --disable-gtk-widgets \
	  --with-winsys=none \
	  --prefix="$(PWD)/mx-install" \
	  CFLAGS="-O2 -mms-bitfields" \
	  PKG_CONFIG="$(PWD)/deps-build/run-pkg-config.sh" \
	  PKG_CONFIG_PATH="$(PWD)/cogl-install/lib/pkgconfig:$(PWD)/clutter-install/lib/pkgconfig"
	make -C mx-$(MX_VERSION) all install
	$(LIB) /machine:i386 \
	/def:mx-$(MX_VERSION)/mx/.libs/libmx-1.0-2.dll.def \
	/out:$(PWD)/mx-install/lib/mx-1.0.lib \
	/name:libmx-1.0-2.dll
	touch $@

fixprefix.exe : fixprefix.c
	$(CC) -Wall -O2 -o $@ $<

clutter.wxs : generate-msi.pl deps-install-stamp cogl-install-stamp clutter-install-stamp mx-install-stamp clutter.wxs.in
	perl generate-msi.pl \
	--packageversion="$(PACKAGE_VERSION)" \
	"Clutter dependencies:deps-install" \
	"Cogl:cogl-install" \
	"Clutter:clutter-install" \
	"Mx:mx-install" \
	> $@

%.wixobj : %.wxs
	$(CANDLE) $<

clutter-$(PACKAGE_VERSION).msi : $(WIXOBJS) fixprefix.exe
	rm -rf cab-cache
	mkdir -p cab-cache
	$(LIGHT) -cc cab-cache -out $@ $(WIXOBJS)
	@cabextract -p -F TestFileA 'cab-cache/#clutter.cab' > test-result-a
	@cabextract -p -F TestFileB 'cab-cache/#clutter.cab' > test-result-b
	@if cmp -s test-result-{a,b}; then \
	  echo; \
	  echo "***ERROR***"; \
	  echo; \
	  echo "You have hit a bug where light.exe is combining files that "; \
	  echo "have the same size. The resulting .msi will not work. If "; \
	  echo "you are using WiX 3.5 under Wine you may want to try "; \
	  echo "3.0 instead."; \
	  echo; \
	  rm -f "$@"; \
	  exit 1; \
	fi

.PHONY : all
