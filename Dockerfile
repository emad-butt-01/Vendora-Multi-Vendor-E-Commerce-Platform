# syntax=docker/dockerfile:1.6
#
# Multi-stage build for the Vendora monorepo.
#
#   Stage 1 (build) — installs ALL workspace deps so Vite + Tailwind are
#                     available, then builds client/dist.
#   Stage 2 (runtime) — node:18-alpine with only the server's runtime deps,
#                       the built SPA, and the server source.
#
# `docker-compose up` (see docker-compose.yml) is the intended entry point;
# this file is also usable standalone:
#   docker build -t vendora .
#   docker run -p 5000:5000 --env-file server/.env vendora

# ---- Stage 1: build the client ----
FROM node:18-alpine AS build
WORKDIR /repo

# Copy manifests first so the npm-install layer caches across source edits.
COPY package.json package-lock.json ./
COPY client/package.json ./client/
COPY server/package.json ./server/
COPY shared/package.json ./shared/

RUN npm ci

# Now the source. Build the client only — the server runs from source via
# Node's native ESM support, no transpile step needed.
COPY . .
RUN npm run build:client


# ---- Stage 2: production runtime ----
FROM node:18-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=5000
# Tells server/src/app.js to mount client/dist as static + SPA fallback.
ENV SERVE_CLIENT=1

# Drop privileges. node:alpine ships a `node` user — use it.
USER node

# Server runs from source — copy the workspace manifests + the server +
# the built client. We re-install deps here with --omit=dev to drop Vite,
# Tailwind, vitest, etc. that the runtime doesn't need.
COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node server/package.json ./server/
COPY --chown=node:node shared/package.json ./shared/
COPY --chown=node:node client/package.json ./client/

RUN npm ci --omit=dev --workspaces --include-workspace-root \
    && npm cache clean --force

COPY --chown=node:node server ./server
COPY --chown=node:node shared ./shared
COPY --chown=node:node --from=build /repo/client/dist ./client/dist

EXPOSE 5000
CMD ["node", "server/src/server.js"]
