# Multi-stage build for KuberBank Backend
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

# Set working directory
WORKDIR /app

# Copy package files
COPY api/package*.json ./

# Install dependencies
RUN npm ci --production=false && \
    npm cache clean --force

# Copy application code
COPY api/ ./

# Run tests (optional, can be disabled for faster builds)
# RUN npm test

# Production stage
FROM node:18-alpine

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create app user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
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