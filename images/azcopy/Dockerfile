ARG AZCOPY_VERSION='10.32.3'
ARG GO_VERSION='1.26'
ARG ALPINE_VERSION='3.23'
ARG TARGETARCH

FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} as build
ENV GOARCH=$TARGETARCH \
    GOOS=linux
WORKDIR /azcopy
ARG AZCOPY_VERSION
RUN apk add --no-cache build-base
RUN wget "https://github.com/Azure/azure-storage-azcopy/archive/v${AZCOPY_VERSION}.tar.gz" -O src.tgz \
    || wget "https://github.com/Azure/azure-storage-azcopy/archive/${AZCOPY_VERSION}.tar.gz" -O src.tgz
RUN tar xf src.tgz --strip 1 \
 && go build -o azcopy \
 && ./azcopy --version

FROM alpine:${ALPINE_VERSION} as release
ARG AZCOPY_VERSION
COPY --from=build /azcopy/azcopy /usr/local/bin
WORKDIR /WORKDIR
CMD [ "azcopy" ]