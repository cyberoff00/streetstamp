FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
ENV PORT=18080
EXPOSE 18080
CMD ["npm", "start"]
