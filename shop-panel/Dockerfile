# Сборка панели магазина (React+Vite) для прод-стека.
# Финальная стадия — alpine с готовым dist; контейнер одноразовый:
# при запуске копирует dist в volume, который раздаёт Caddy (см. docker-compose.prod.yml).
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# API/WS URL зашиваются в бандл на этапе сборки (vite import.meta.env).
ARG VITE_API_URL
ARG VITE_WS_URL
ENV VITE_API_URL=${VITE_API_URL} \
    VITE_WS_URL=${VITE_WS_URL}

RUN npm run build

FROM alpine:3.20
COPY --from=build /app/dist /panel
# /dist — точка монтирования volume panel_dist из compose
CMD ["sh", "-c", "cp -rf /panel/. /dist/"]
