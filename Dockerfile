# syntax=docker/dockerfile:1
#
# splitpro-railway: thin wrapper around the official SplitPro image for Railway.
# It adds tini, a privilege drop to the `node` user, a bounded wait for PostgreSQL,
# and a readiness supervisor. Application code is unchanged.
#
# Base image is pinned by digest. Update SPLITPRO_IMAGE and SPLITPRO_VERSION together
# (see MAINTENANCE.md).
ARG SPLITPRO_IMAGE=docker.io/ossapps/splitpro@sha256:efaa52b30d009573c4bf70e5711d6447536914469420db58680e1e6779acde6e

FROM ${SPLITPRO_IMAGE}

ARG SPLITPRO_VERSION=2.1.5
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root
RUN apk add --no-cache tini su-exec \
    && rm -rf /var/cache/apk/*

COPY licenses/ /usr/share/licenses/splitpro-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/splitpro-railway-entrypoint

# Railway injects PORT; HOSTNAME must be 0.0.0.0 so the Railway edge can reach the listener.
ENV HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

LABEL org.opencontainers.image.title="splitpro-railway" \
      org.opencontainers.image.description="Community Railway wrapper for SplitPro (open-source Splitwise alternative). Not affiliated with OSS Apps." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/splitpro-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/splitpro-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/splitpro-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/ossapps/splitpro:v${SPLITPRO_VERSION}" \
      io.splitpro-railway.upstream.version="${SPLITPRO_VERSION}"

VOLUME ["/app/uploads"]
EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/splitpro-railway-entrypoint"]
CMD []
