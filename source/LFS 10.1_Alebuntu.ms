.\" 0.-Preparativos para comenzar con LFS

su
echo $LFS
export LFS=/mnt/lfs
echo $LFS

case $(uname -m) in
 x86_64) mkdir -pv $LFS/lib64 ;;
esac

mkdir -v $LFS/tools

groupadd lfs 
useradd -s /bin/bash -g lfs -m -k /dev/null lfs

passwd lfs
usuario

chown -v lfs $LFS/{usr,lib,var,etc,bin,sbin,tools}
case $(uname -m) in
 x86_64) chown -v lfs $LFS/lib64 ;;
esac

chown -v lfs $LFS/sources
su - lfs

cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat > ~/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
EOF
source ~/.bash_profile

echo $LFS
echo $LC_ALL
echo $LFS_TGT
echo $PATH

.\" 1.-Compilación cruzada de herramientas temporales.

echo $LFS
echo $LC_ALL
echo $LFS_TGT
echo $PATH

cd $LFS/sources

//1.1.-Binutils paso 1

tar -xf binutils-2.36.1.tar.xz
cd binutils-2.36.1
mkdir -v build 
cd build
../configure --prefix=$LFS/tools \
 --with-sysroot=$LFS \
 --target=$LFS_TGT \
 --disable-nls \
 --disable-werror
make
make install
cd ../..
rm -rf binutils-2.36.1

.\" 1.2.-GCC paso 1

tar -xf gcc-10.2.0.tar.xz
cd gcc-10.2.0
tar -xf ../mpfr-4.1.0.tar.xz
mv -v mpfr-4.1.0 mpfr
tar -xf ../gmp-6.2.1.tar.xz
mv -v gmp-6.2.1 gmp
tar -xf ../mpc-1.2.1.tar.gz
mv -v mpc-1.2.1 mpc
case $(uname -m) in
 x86_64)
 sed -e '/m64=/s/lib64/lib/' \
 -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build 
cd build
../configure \
 --target=$LFS_TGT \
 --prefix=$LFS/tools \
 --with-glibc-version=2.11 \
 --with-sysroot=$LFS \
 --with-newlib \
 --without-headers \
 --enable-initfini-array \
 --disable-nls \
 --disable-shared \
 --disable-multilib \
 --disable-decimal-float \
 --disable-threads \
 --disable-libatomic \
 --disable-libgomp \
 --disable-libquadmath \
 --disable-libssp \
 --disable-libvtv \
 --disable-libstdcxx \
 --enable-languages=c,c++
make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
 `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h
cd ..
rm -rf gcc-10.2.0

.\" 1.3.-Linux 

tar -xvf linux-5.10.17.tar.xz
cd linux-5.10.17 
make mrproper
make headers
find usr/include -name '.*' -delete
rm usr/include/Makefile
cp -rv usr/include $LFS/usr
cd ..
rm -rf linux-5.10.17

.\" 1.4.-Glibc

tar -xvf glibc-2.33.tar.xz
cd glibc-2.33
case $(uname -m) in
 i?86) ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
 ;;
 x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
 ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
 ;;
esac
patch -Np1 -i ../glibc-2.33-fhs-1.patch 
mkdir -v build
cd build
../configure \
 --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(../scripts/config.guess) \
 --enable-kernel=3.2 \
 --with-headers=$LFS/usr/include \
 libc_cv_slibdir=/lib
make
make DESTDIR=$LFS install
echo 'int main(){}' > dummy.c
$LFS_TGT-gcc dummy.c
readelf -l a.out | grep '/ld-linux'
rm -v dummy.c a.out
$LFS/tools/libexec/gcc/$LFS_TGT/10.2.0/install-tools/mkheaders
cd ../..
rm -rf glibc-2.33

.\" 1.5.-Libstdc++ paso 1

tar -xvf gcc-10.2.0.tar.xz
cd gcc-10.2.0/
mkdir -v build
cd build
../libstdc++-v3/configure \
 --host=$LFS_TGT \
 --build=$(../config.guess) \
 --prefix=/usr \
 --disable-multilib \
 --disable-nls \
 --disable-libstdcxx-pch \
 --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/10.2.0
make
make DESTDIR=$LFS install
cd ../..
rm -rf gcc-10.2.0

.\" 1.6.-M4

tar -xvf m4-1.4.18.tar.xz
cd m4-1.4.18
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rf m4-1.4.18

.\" 1.7.-Ncurses

tar -xvf ncurses-6.2.tar.gz
cd ncurses-6.2
sed -i s/mawk// configure
mkdir build
pushd build
 ../configure
 make -C include
 make -C progs tic
popd
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(./config.guess) \
 --mandir=/usr/share/man \
 --with-manpage-format=normal \
 --with-shared \
 --without-debug \
 --without-ada \
 --without-normal \
 --enable-widec
make
make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
echo "INPUT(-lncursesw)" > $LFS/usr/lib/libncurses.so
mv -v $LFS/usr/lib/libncursesw.so.6* $LFS/lib
ln -sfv ../../lib/$(readlink $LFS/usr/lib/libncursesw.so) $LFS/usr/lib/libncursesw.so
cd ..
rm -rf ncurses-6.2

.\" 1.8.-Bash

tar -xvf bash-5.1.tar.gz
cd bash-5.1
./configure --prefix=/usr \
 --build=$(support/config.guess) \
 --host=$LFS_TGT \
 --without-bash-malloc
make
make DESTDIR=$LFS install
mv $LFS/usr/bin/bash $LFS/bin/bash 
ln -sv bash $LFS/bin/sh
cd ..
rm -rf bash-5.1

.\" 1.9.-Coreutils

tar -xvf coreutils-8.32.tar.xz
cd coreutils-8.32
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess) \
 --enable-install-program=hostname \
 --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo} $LFS/bin
mv -v $LFS/usr/bin/{false,ln,ls,mkdir,mknod,mv,pwd,rm} $LFS/bin
mv -v $LFS/usr/bin/{rmdir,stty,sync,true,uname} $LFS/bin
mv -v $LFS/usr/bin/{head,nice,sleep,touch} $LFS/bin
mv -v $LFS/usr/bin/chroot $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'
cd ..
rm -rf coreutils-8.32

.\" 1.10.-Diffutils

tar -xvf diffutils-3.7.tar.xz 
cd diffutils-3.7
./configure --prefix=/usr --host=$LFS_TGT 
make
make DESTDIR=$LFS install
cd ..
rm -rf diffutils-3.7

.\" 1.11.-File

tar -xvf file-5.39.tar.gz
cd file-5.39
mkdir build
pushd build
 ../configure --disable-bzlib \
 --disable-libseccomp \
 --disable-xzlib \
 --disable-zlib
 make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
cd ..
rm -rf file-5.39

tar -xvf findutils-4.8.0.tar.xz 
cd findutils-4.8.0
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/find $LFS/bin
sed -i 's|find:=${BINDIR}|find:=/bin|' $LFS/usr/bin/updatedb
cd ..
rm -rf findutils-4.8.0

.\" 1.13.-Gawk

tar -xvf gawk-5.1.0.tar.xz
cd gawk-5.1.0
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(./config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rf gawk-5.1.0

.\" 1.14.-Grep

tar -xvf grep-3.6.tar.xz 
cd grep-3.6
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --bindir=/bin
make
make DESTDIR=$LFS install
cd ..
rm -rf grep-3.6

.\" 1.15.-Gzip

tar -xvf gzip-1.10.tar.xz 
cd gzip-1.10
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/gzip $LFS/bin
cd ..
rm -rf gzip-1.10

.\" 1.16.-Make

tar -xvf make-4.3.tar.gz
cd make-4.3
./configure --prefix=/usr \
 --without-guile \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rf make-4.3

.\" 1.17.-Patch

tar -xvf patch-2.7.6.tar.xz
cd patch-2.7.6
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess)
make  
make DESTDIR=$LFS install
cd ..
rm -rf patch-2.7.6

.\" 1.18.-Sed

tar -xvf sed-4.8.tar.xz
cd sed-4.8
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --bindir=/bin
make
make DESTDIR=$LFS install
cd ..
rm -rf sed-4.8

.\" 1.19.-Tar

tar -xvf tar-1.34.tar.xz
cd tar-1.34
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess) \
 --bindir=/bin
make
make DESTDIR=$LFS install
cd ..
rm -rf tar-1.34

.\" 1.20.-Xz

tar -xvf xz-5.2.5.tar.xz
cd xz-5.2.5
./configure --prefix=/usr \
 --host=$LFS_TGT \
 --build=$(build-aux/config.guess) \
 --disable-static \
 --docdir=/usr/share/doc/xz-5.2.5
make 
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/{lzma,unlzma,lzcat,xz,unxz,xzcat} $LFS/bin
mv -v $LFS/usr/lib/liblzma.so.* $LFS/lib
ln -svf ../../lib/$(readlink $LFS/usr/lib/liblzma.so) $LFS/usr/lib/liblzma.so
cd ..
rm -rf xz-5.2.5

.\" 1.21.-Binutils paso 2

tar -xvf binutils-2.36.1.tar.xz
cd binutils-2.36.1
mkdir -v build
cd build
../configure \
 --prefix=/usr \
 --build=$(../config.guess) \
 --host=$LFS_TGT \
 --disable-nls \
 --enable-shared \
 --disable-werror \
 --enable-64-bit-bfd
make
make DESTDIR=$LFS install
install -vm755 libctf/.libs/libctf.so.0.0.0 $LFS/usr/lib
cd ../..
rm -rf binutils-2.36.1

.\" 1.22.-GCC paso 2

tar -xvf gcc-10.2.0.tar.xz
cd gcc-10.2.0/
tar -xf ../mpfr-4.1.0.tar.xz
mv -v mpfr-4.1.0 mpfr
tar -xf ../gmp-6.2.1.tar.xz
mv -v gmp-6.2.1 gmp
tar -xf ../mpc-1.2.1.tar.gz
mv -v mpc-1.2.1 mpc
case $(uname -m) in
 x86_64)
 sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build
cd build
mkdir -pv $LFS_TGT/libgcc
ln -s ../../../libgcc/gthr-posix.h $LFS_TGT/libgcc/gthr-default.h
../configure \
 --build=$(../config.guess) \
 --host=$LFS_TGT \
 --prefix=/usr \
 CC_FOR_TARGET=$LFS_TGT-gcc \
 --with-build-sysroot=$LFS \
 --enable-initfini-array \
 --disable-nls \
 --disable-multilib \
 --disable-decimal-float \
 --disable-libatomic \
 --disable-libgomp \
 --disable-libquadmath \
 --disable-libssp \
 --disable-libvtv \
 --disable-libstdcxx \
 --enable-languages=c,c++
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cd ../..
rm -rf gcc-10.2.0

.\" 2.-Instalando el básico sistema de software
.\" 2.1.- Introducción

su root

.\" 2.2.-Cambiando de propietario

chown -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
case $(uname -m) in
 x86_64) chown -R root:root $LFS/lib64 ;;
esac

.\" 2.3.-Preparación de sistemas de archivos de kernel virtual

mkdir -pv $LFS/{dev,proc,sys,run}

.\" 2.3.1.-Creación de los nodos principales de los dispositivos

mknod -m 600 $LFS/dev/console c 5 1
mknod -m 666 $LFS/dev/null c 1 3

.\" 2.3.2.-Montaje y incorporación de /dev

mount -v --bind /dev $LFS/dev

//2.3.3.-Montaje del sistemas de archivos del kernel virtual

mount -v --bind /dev/pts $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run

if [ -h $LFS/dev/shm ]; then
 mkdir -pv $LFS/$(readlink $LFS/dev/shm)
fi

.\" 2.4.-Entrando en el enjaulado chroot

chroot "$LFS" /usr/bin/env -i \
 HOME=/root \
 TERM="$TERM" \
 PS1='(lfs chroot) \u:\w\$ ' \
 PATH=/bin:/usr/bin:/sbin:/usr/sbin \
 /bin/bash --login +h

.\" 2.5.-Creando estructura en el sistema de archivos lfs

mkdir -pv /{boot,home,mnt,opt,srv} 
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{bin,include,lib,sbin,src}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

.\" 2.6.-Creando los ficheros y enlaces necesarios

ln -sv /proc/self/mounts /etc/mtab

echo "127.0.0.1 localhost $(hostname)" > /etc/hosts

cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
nogroup:x:99:
users:x:999:
EOF

echo "tester:x:$(ls -n $(tty) | cut -d" " -f3):101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester

exec /bin/bash --login +h

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664 /var/log/lastlog
chmod -v 600 /var/log/btmp

cd sources

.\" 2.7.-Libstdc++ paso 2

tar -xvf gcc-10.2.0.tar.xz

cd gcc-10.2.0/

ln -s gthr-posix.h libgcc/gthr-default.h

mkdir -v build

cd build

CXXFLAGS="-g -O2 -D_GNU_SOURCE" \
 --prefix=/usr \
 --disable-multilib \
 --disable-nls \
 --host=$(uname -m)-lfs-linux-gnu \
 --disable-libstdcxx-pch

make

make install

cd ../..

rm -rf gcc-10.2.0

.\" 2.8.-Gettext

tar -xvf gettext-0.21.tar.xz
cd gettext-0.21
./configure --disable-shared

make

cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin

cd ..

rm -rf gettext-0.21

.\" 2.9.-Bison

tar -xvf bison-3.7.5.tar.xz
cd bison-3.7.5
./configure --prefix=/usr \
 --docdir=/usr/share/doc/bison-3.7.5

make
make install

cd ..

rm -rf bison-3.7.5

.\" 2.10.-Perl

tar -xvf perl-5.32.1.tar.xz
cd perl-5.32.1

sh Configure -des \
 -Dprefix=/usr \
 -Dvendorprefix=/usr \
 -Dprivlib=/usr/lib/perl5/5.32/core_perl \
 -Darchlib=/usr/lib/perl5/5.32/core_perl \
 -Dsitelib=/usr/lib/perl5/5.32/site_perl \
 -Dsitearch=/usr/lib/perl5/5.32/site_perl \
 -Dvendorlib=/usr/lib/perl5/5.32/vendor_perl \
 -Dvendorarch=/usr/lib/perl5/5.32/vendor_perl

make
make install

cd ..
rm -rf perl-5.32.1

.\" 2.11.-Python

tar -xvf Python-3.9.2.tar.xz
cd Python-3.9.2

./configure --prefix=/usr \
 --enable-shared \
 --without-ensurepip

make
make install

cd ..
rm -rf Python-3.9.2

.\" 2.12.- Texinfo

tar -xvf texinfo-6.7.tar.xz
cd texinfo-6.7

./configure --prefix=/usr

make
make install

cd ..

rm -rf texinfo-6.7

.\" 2.13.-Util-linux

tar -xvf util-linux-2.36.2.tar.xz
cd util-linux-2.36.2

mkdir -pv /var/lib/hwclock

./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
 --docdir=/usr/share/doc/util-linux-2.36.2 \
 --disable-chfn-chsh \
 --disable-login \
 --disable-nologin \
 --disable-su \
 --disable-setpriv \
 --disable-runuser \
 --disable-pylibmount \
 --disable-static \
 --without-python \
 runstatedir=/run

make
make install

cd ..

rm -rf util-linux-2.36.2

.\" 2.14.- Limpieza y Guardado del Sistema Temporal

find /usr/{lib,libexec} -name \*.la -delete 
rm -rf /usr/share/{info,man,doc}/* 
exit
umount $LFS/dev{/pts,}
umount $LFS/{sys,proc,run}

.\" 2.14.1 Stripping

strip --strip-debug $LFS/usr/lib/*
strip --strip-unneeded $LFS/usr/{,s}bin/*
strip --strip-unneeded $LFS/tools/bin/*

.\" 3. Construyendo el sistema LFS
.\" 3.1.- Pasos previos