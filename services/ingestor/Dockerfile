FROM golang:1.25 AS build

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go mod tidy
RUN go mod tidy
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM alpine:3.20

WORKDIR /app

RUN apk --no-cache add ca-certificates curl

COPY --from=build /app/server /app/server

EXPOSE 8080 8081 8082 8083

CMD ["/app/server"]
