# Use a slim official Node.js runtime as the base image.
# Alpine keeps the image small and fast to pull in CI/CD and on ECS.
FROM node:20-alpine

# Set working directory inside the container.
WORKDIR /app

# Copy dependency manifest first so Docker can cache npm install
# when only application code changes.
COPY package.json ./

# Install production dependencies only (no devDependencies).
RUN npm install --omit=dev

# Copy application source code.
COPY app/ ./app/

# wget is used by the ECS container health check in infra/task-definition.json.
RUN apk add --no-cache wget && chown -R node:node /app

# Document which port the app listens on (Express default: 3000).
EXPOSE 3000

# Run as non-root user for better security in production.
USER node

# Start the application.
CMD ["npm", "start"]
