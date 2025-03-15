#!/bin/bash

XMODULESMAC=~/mnt/router/tmp/xmodules-mac
XMODULESLINUX=/home/b1/Desktop/ui.vision-xmodules-linux-v202101NEWCV

if [ $# != 1 ]
then
    echo Usage:
    echo $0 "app|rpm|pkg"
    exit 1
fi

set -e
trap "echo build.sh failed; exit 1" ERR

cd `dirname $0`
VERSION=`grep VERSION nmhost/nmhost.cc | grep define | awk -F'"' '{print $2}'`
SOURCE="$PWD/nmhost"
case "$1" in
    deb)
        echo "deb is not supported anymore"
        ;;
    app|rpm)
        rm -rf /tmp/uivision-xmodules /tmp/kcmd
        mkdir -p /tmp/uivision-xmodules/usr/{xmodules,lib} /tmp/kcmd /tmp/uivision-xmodules/usr/bin/platforms
        cp $XMODULESLINUX/* /tmp/uivision-xmodules/usr/xmodules
        cp "$SOURCE/com.github.teamdocs.kcmd.json" /tmp/uivision-xmodules/usr/lib
        cp "$SOURCE/firefox/com.github.teamdocs.kcmd.json" /tmp/uivision-xmodules/usr/lib/com.github.teamdocs.kcmd.ff.json
        if [ "$1" = "app" ]
        then
            cp /usr/lib/x86_64-linux-gnu/qt5/plugins/platforms/libqxcb.so /tmp/uivision-xmodules/usr/bin/platforms
        else
            cp /usr/lib64/qt5/plugins/platforms/libqxcb.so /tmp/uivision-xmodules/usr/bin/platforms
        fi
        chmod 755 /tmp/uivision-xmodules/usr/xmodules/*.sh /tmp/uivision-xmodules/usr/xmodules/kantu-*-host
        chmod 644 /tmp/uivision-xmodules/usr/xmodules/*.json /tmp/uivision-xmodules/usr/xmodules/*.txt
        cd /tmp/kcmd
        cmake "$SOURCE" -DCMAKE_BUILD_TYPE=Release
        make
        cp nmhost "$SOURCE/../appimage/run.sh" "$SOURCE/../appimage/runshutter.sh" /tmp/uivision-xmodules/usr/bin
        cd /tmp
        ARCH=x86_64 "$SOURCE/../appimage/linuxdeploy-x86_64.AppImage" --appdir uivision-xmodules\
            --desktop-file "$SOURCE/../appimage/uivision-xmodules.desktop" --icon-file "$SOURCE/../appimage/uivision-xmodules.png"\
            --library uivision-xmodules/usr/bin/platforms/libqxcb.so --output appimage
        ;;
    pkg)
        SOURCE="$PWD/nmhost"
        rm -rf /tmp/kcmd
        mkdir /tmp/kcmd
        cp -R macos-installer-builder tss/tss /tmp/kcmd
        chmod 755 /tmp/kcmd/tss
        rm /tmp/kcmd/macos-installer-builder/macOS-x64/application/README
        mkdir /tmp/kcmd/macos-installer-builder/macOS-x64/application/xmodules
        cp $XMODULESMAC/* /tmp/kcmd/macos-installer-builder/macOS-x64/application/xmodules
        cd /tmp/kcmd
        mkdir build
        cd build
        cmake "$SOURCE" -DCMAKE_MACOSX_BUNDLE=1 -DCMAKE_BUILD_TYPE=Release -DVERSION=${VERSION}
        make
        macdeployqt nmhost.app
        awk '/<dict>/{print;print "\t<key>LSUIElement</key>";print "\t<string>1</string>";next}{print}' nmhost.app/Contents/Info.plist >\
            /tmp/Info.plist
        cp /tmp/Info.plist nmhost.app/Contents/Info.plist
        cp ../tss nmhost.app/Contents/MacOS
        cp -R nmhost.app ../macos-installer-builder/macOS-x64/application/
        cd ../macos-installer-builder/macOS-x64/
        echo n | bash build-macos-x64.sh uivision-xmodules ${VERSION}
        ;;
esac
