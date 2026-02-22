FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy source files
COPY *.js ./

# Create uploads directory
RUN mkdir -p uploads/models uploads/scenes uploads/avatars uploads/thumbnails

EXPOSE 3001

CMD ["node", "server.js"]
