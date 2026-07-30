# Lab overlay: official slim base + npm correction release when GHCR has no matching tag.
# npm latest (2026.7.1-2) has no ghcr.io/openclaw/openclaw:2026.7.1-2* image (verified 2026-07-30).
# Rebuild when bumping openclaw_npm_version / openclaw_base_image in defaults/main.yml.
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:2026.7.1-slim
ARG OPENCLAW_NPM_VERSION=2026.7.1-2

FROM node:24-bookworm-slim AS pkg
ARG OPENCLAW_NPM_VERSION
WORKDIR /tmp
RUN npm pack "openclaw@${OPENCLAW_NPM_VERSION}" \
  && tar -xzf openclaw-*.tgz \
  && npm pack "@openclaw/ai@${OPENCLAW_NPM_VERSION}" \
  && mkdir -p /out/ai \
  && tar -xzf openclaw-ai-*.tgz -C /out/ai --strip-components=1 \
  && mv package /out/openclaw

FROM ${OPENCLAW_BASE_IMAGE}
USER root
COPY --from=pkg /out/openclaw/dist /app/dist
COPY --from=pkg /out/openclaw/package.json /app/package.json
COPY --from=pkg /out/openclaw/openclaw.mjs /app/openclaw.mjs
COPY --from=pkg /out/openclaw/npm-shrinkwrap.json /app/npm-shrinkwrap.json
COPY --from=pkg /out/openclaw/CHANGELOG.md /app/CHANGELOG.md
# Keep bundled @openclaw/ai in sync with the correction release (only dep bump in 2026.7.1-2).
COPY --from=pkg /out/ai/ /app/node_modules/@openclaw/ai/
RUN chown -R node:node /app
USER node
WORKDIR /app
