FROM rust:1.85-slim AS builder
WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
RUN cargo build --release
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/recygo-backend /usr/local/bin/recygo-backend
EXPOSE 8080
CMD ["recygo-backend"]
