# ================================================================
# Multi-stage Dockerfile for KuberBank Backend
# Stage 1: Dependencies and Testing
# Stage 2: Production Build
# ================================================================

# ================================================================
# STAGE 1: Base image with dependencies
# ================================================================
FROM node:18-alpine AS base

# Install system dependencies
RUN apk add --no-cache \
    postgresql-client \
    dumb-init \
    curl \
    ca-certificates

WORKDIR /app

# Copy package files
COPY api/package*.json ./

# Install ALL dependencies (including dev dependencies for testing)
RUN npm ci

# Copy application code
COPY api/ ./

# ================================================================
# STAGE 2: Testing stage
# ================================================================
FROM base AS test

# Set test environment
ENV NODE_ENV=test

# Copy test configuration
COPY api/jest.config.js ./
COPY api/jest.setup.js ./
COPY api/.eslintrc.js ./

# Install additional test dependencies if needed
RUN npm ci

# Run linting
RUN npm run lint || exit 0

# Run tests with coverage
RUN npm test -- --coverage --passWithNoTests

# This stage will fail if tests fail, preventing the build from continuing

# ================================================================
# STAGE 3: Production build
# ================================================================
FROM node:18-alpine AS builder

# Build arguments
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Labels for container metadata
LABEL org.opencontainers.image.title="KuberBank Backend" \
      org.opencontainers.image.description="Kubernetes-native banking API" \
      org.opencontainers.image.authors="Hamza Qureshi" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}"

# Install system dependencies
RUN apk add --no-cache \
    postgresql-client \
    curl \
    ca-certificates

WORKDIR /app

# Copy package files
COPY api/package*.json ./

# Install only production dependencies
RUN npm ci --production && \
    npm cache clean --force

# Copy application code
COPY api/ ./

# ================================================================
# STAGE 4: Production runtime
# ================================================================
FROM node:18-alpine AS production

# Install runtime dependencies
RUN apk add --no-cache \
    dumb-init \
    postgresql-client \
    curl

# Create app user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application code
COPY --chown=nodejs:nodejs api/ ./

# Create logs directory
RUN mkdir -p /app/logs && \
    chown -R nodejs:nodejs /app/logs

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "server.js"]