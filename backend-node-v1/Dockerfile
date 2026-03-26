FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
RUN chown -R node:node /app
USER node
ENV PORT=18080
EXPOSE 18080
CMD ["npm", "start"]
