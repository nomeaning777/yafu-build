ARG YAFU_COMMIT_ID=4d517d613b2569465d02668fd5db85334599226e
ARG YSIEVE_COMMIT_ID=e7c5ffd75350174007345f809ae50d9642149c8f
ARG YTOOLS_COMMIT_ID=6d6e97af2fa93144d51bd676040477313b9023dd
ARG GMP_VERSION=6.3.0
ARG GMP_ECM_COMMIT_ID=4101450b1c3eefa49b544f09fa93e5045f4cd580
ARG CC=gcc-12
ARG MSIEVE_REVISION=1050

#
# Download gmp. Dedicated stage is for caching the downloads.
#
FROM ubuntu:22.04 as download-gmp

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl zstd tar && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG GMP_VERSION

WORKDIR /data
RUN curl --fail -L https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.zst -O && \
    mkdir gmp && \
    cd gmp && \
    tar -I zstd -xf ../gmp-${GMP_VERSION}.tar.zst --strip-components=1


#
# Download yafu.
#
FROM ubuntu:22.04 as download-yafu

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG YAFU_COMMIT_ID

WORKDIR /data
RUN git clone https://github.com/bbuhrow/yafu.git && \
    cd yafu && \
    git checkout ${YAFU_COMMIT_ID}


#
# Download ysieve.
#
FROM ubuntu:22.04 as download-ysieve

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG YSIEVE_COMMIT_ID

WORKDIR /data

RUN git clone https://github.com/bbuhrow/ysieve.git && \
    cd ysieve && \
    git checkout ${YSIEVE_COMMIT_ID}


#
# Download ytools.
#
FROM ubuntu:22.04 as download-ytools

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG YTOOLS_COMMIT_ID

WORKDIR /data

RUN git clone https://github.com/bbuhrow/ytools.git && \
    cd ytools && \
    git checkout ${YTOOLS_COMMIT_ID}


#
# Download gmp-ecm.
#
FROM ubuntu:22.04 as download-gmp-ecm

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG GMP_ECM_COMMIT_ID

WORKDIR /data

RUN git clone https://gitlab.inria.fr/zimmerma/ecm.git && \
    cd ecm && \
    git checkout ${GMP_ECM_COMMIT_ID}


#
# Download msieve.
#
FROM ubuntu:22.04 as download-msieve

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates subversion && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG MSIEVE_REVISION

WORKDIR /data

RUN svn checkout -r ${MSIEVE_REVISION} https://svn.code.sf.net/p/msieve/code/trunk msieve


#
# Download ggnfs
#
FROM ubuntu:22.04 as download-ggnfs

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /data

RUN git clone https://github.com/MersenneForum/ggnfs.git


# Builder base image. This is the base image for all the other builder images.
#
FROM ubuntu:22.04 as builder-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libz-dev m4 autoconf gcc-12 autotools-dev automake libtool && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


#
# Build gmp
#
FROM builder-base as build-gmp

ARG CC

COPY --from=download-gmp /data/gmp /src/gmp
WORKDIR /src/gmp

RUN <<EOS
set -e
./configure --enable-fat --prefix=/opt/gmp CC=${CC}
make -j
make check
make install
EOS


#
# Build gmp-ecm
#
FROM builder-base as build-gmp-ecm

COPY --from=download-gmp-ecm /data/ecm /src/ecm
COPY --from=build-gmp /opt/gmp /opt/gmp

ARG CC
WORKDIR /src/ecm
RUN autoreconf -i
RUN ./configure --with-gmp=/opt/gmp --prefix=/opt/ecm CC=${CC}
RUN make -j
RUN make -j check
RUN make install

#
# Build msieve
#
FROM builder-base as build-msieve

COPY --from=download-msieve /data/msieve /src/msieve

COPY --from=build-gmp-ecm /opt/ecm /opt/ecm
COPY --from=build-gmp /opt/gmp /opt/gmp

RUN <<EOS
set -e

cp -r /opt/ecm/* /usr/local/
cp -r /opt/gmp/* /usr/local/
EOS

ARG CC
WORKDIR /src/msieve
RUN make -j all ECM=1 CC=${CC}

#
# Build yafu
#
FROM builder-base as build-yafu

COPY --from=download-yafu /data/yafu /src/yafu
COPY --from=download-ysieve /data/ysieve /src/ysieve
COPY --from=download-ytools /data/ytools /src/ytools
COPY --from=build-msieve /src/msieve /src/msieve

COPY --from=build-gmp /opt/gmp /opt/gmp
COPY --from=build-gmp-ecm /opt/ecm /opt/ecm

RUN <<EOS
set -e

cp -r /opt/ecm/* /usr/local/
cp -r /opt/gmp/* /usr/local/
ldconfig
EOS

ARG CC

WORKDIR /src/ytools
RUN make -j CC=${CC}

WORKDIR /src/ysieve
RUN make -j CC=${CC}

WORKDIR /src/yafu 
COPY Makefile.patch /tmp/Makefile.patch
RUN patch Makefile /tmp/Makefile.patch
RUN make -j yafu NFS=1 USE_SSE41=1 USE_AVX2=1 USE_BMI2=1 SKYLAKE=0 ICELAKE=0 CC=${CC}

#
# Build ggnfs
#
FROM builder-base as build-ggnfs

COPY --from=download-ggnfs /data/ggnfs /src/ggnfs
COPY --from=build-gmp /opt/gmp /opt/gmp

RUN <<EOS
set -e

cp -r /opt/gmp/* /usr/local/
ldconfig
EOS

WORKDIR /src/ggnfs

RUN <<EOS
set -e
cd src/experimental/lasieve4_64/athlon64
make liblasieve.a
make liblasieveI11.a
make liblasieveI12.a
make liblasieveI13.a
make liblasieveI14.a
make liblasieveI15.a
make liblasieveI16.a
cp *.a ..
cd ..
ln -s athlon64 asm
make
EOS

FROM ubuntu:22.04

# Install gmp and gmp-ecm
COPY --from=build-gmp /opt/gmp/lib/* /usr/local/lib/
COPY --from=build-gmp-ecm /opt/ecm/lib/* /usr/local/lib/

RUN ldconfig

# Install yafu
WORKDIR /yafu
COPY --from=build-yafu /src/yafu/yafu ./

# Install ggnfs
COPY --from=build-ggnfs /src/ggnfs/src/experimental/lasieve4_64/gnfs-lasieve4I*e ./

ENTRYPOINT [ "/yafu/yafu" ]
