FROM alpine:latest

RUN apk add --no-cache bash gettext

WORKDIR /generator

COPY generate.sh /usr/local/bin/generate-config
RUN chmod +x /usr/local/bin/generate-config

ENTRYPOINT ["generate-config"]
