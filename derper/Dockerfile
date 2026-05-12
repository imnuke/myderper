FROM golang:1.26-alpine AS build
ARG DERPER_REF=v1.96.5
ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn
ENV CGO_ENABLED=0
ENV GOPROXY=${GOPROXY}
ENV GOSUMDB=${GOSUMDB}
ENV GOTOOLCHAIN=auto
RUN go install tailscale.com/cmd/derper@${DERPER_REF}

FROM alpine:3.20
COPY --from=build /go/bin/derper /usr/local/bin/derper
ENTRYPOINT ["/usr/local/bin/derper"]
