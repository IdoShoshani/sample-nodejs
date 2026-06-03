# syntax=docker/dockerfile:1
#
# Layout follows the official Node.js Docker best practices:
#   https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md
#
# - Build stage installs production dependencies with npm.
# - Runtime stage starts from a minimal alpine base and copies *only* the node
#   binary in. No npm / yarn / corepack ship in the final image — this is the
#   "Smaller images without npm/yarn" pattern from the doc, and replaces the
#   prior `rm -rf /usr/local/lib/node_modules/npm` hack.
# - dumb-init runs as PID 1 so SIGTERM/SIGINT reach the Node process directly.
#   Kubernetes rolling updates and `docker stop` both rely on this to drain
#   gracefully; without it, Node ignores SIGTERM as PID 1 and waits for the
#   grace-period kill.

ARG NODE_IMAGE=node:22-alpine
ARG ALPINE_VERSION=3.21

# ---- deps: install production node_modules ----------------------------------
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- runtime: minimal alpine + just the node binary + dumb-init -------------
FROM alpine:${ALPINE_VERSION} AS runtime
ENV NODE_ENV=production
WORKDIR /app

# libstdc++ is the only shared lib the node binary needs beyond what alpine
# already ships; dumb-init is the init wrapper for PID 1.
RUN apk add --no-cache libstdc++ dumb-init \
  && addgroup -g 1000 node \
  && adduser  -u 1000 -G node -s /bin/sh -D node \
  && chown node:node /app

# Copy the node binary out of the official image; npm/yarn/corepack stay behind.
COPY --from=deps /usr/local/bin/node /usr/local/bin/node
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY            --chown=node:node package.json app.js ./

USER node
EXPOSE 8080
# Docker-level health mirrors the K8s livenessProbe.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/live || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "app.js"]
