FROM golang:1.24.5-alpine AS builder

WORKDIR /build
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags "-X github.com/truenas/truenas-csi/pkg/driver.DRIVER_VERSION=v${VERSION}" -o truenas-csi-driver cmd/main.go

FROM alpine:3.19
RUN apk add --no-cache ca-certificates nfs-utils open-iscsi e2fsprogs xfsprogs util-linux
COPY --from=builder /build/truenas-csi-driver /truenas-csi-driver
ENTRYPOINT ["/truenas-csi-driver"]
