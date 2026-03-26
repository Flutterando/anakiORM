# Docker AOT Deployment

Guide for deploying AnakiORM applications with AOT (Ahead-of-Time) compilation in Docker.

## Prerequisites

- Docker installed
- Rust toolchain (for building native libraries)
- Dart SDK >= 3.10.0

## Strategy

AOT compilation produces a single native executable. The Rust native library (`.so`) must be available alongside the executable at runtime.

## Dockerfile (Multi-stage)

```dockerfile
# ──────────────────────────────────────────────
# Stage 1: Build the Rust native library
# ──────────────────────────────────────────────
FROM rust:1.83-slim AS rust-builder

WORKDIR /build

# Copy the single Rust crate
COPY rust/ ./

# Build for Linux x64 with the sqlite feature
RUN cargo build --release --target x86_64-unknown-linux-gnu --features sqlite

# The output will be at:
# /build/target/x86_64-unknown-linux-gnu/release/libanaki_native.so

# ──────────────────────────────────────────────
# Stage 2: Build the Dart AOT executable
# ──────────────────────────────────────────────
FROM dart:stable AS dart-builder

WORKDIR /app

# Copy all Dart source
COPY . .

# Get dependencies
RUN cd example/shelf_sqlite_example && dart pub get

# AOT compile
RUN cd example/shelf_sqlite_example && dart compile exe bin/server.dart -o /app/server

# ──────────────────────────────────────────────
# Stage 3: Runtime (minimal image)
# ──────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the AOT-compiled Dart executable
COPY --from=dart-builder /app/server ./server

# Copy the native library next to the executable (renamed for the Dart driver)
COPY --from=rust-builder /build/target/x86_64-unknown-linux-gnu/release/libanaki_native.so ./libanaki_sqlite.so

# Ensure the native library is findable
ENV LD_LIBRARY_PATH=/app

EXPOSE 8080

CMD ["./server"]
```

## Build & Run

```bash
# Build the Docker image
docker build -t my-anaki-app .

# Run the container
docker run -p 8080:8080 my-anaki-app
```

## Using Pre-built Binaries

If you've already built the native libraries with `build_native.sh`, you can simplify the Dockerfile by skipping the Rust build stage:

```dockerfile
FROM dart:stable AS dart-builder

WORKDIR /app
COPY . .
RUN cd example/shelf_sqlite_example && dart pub get
RUN cd example/shelf_sqlite_example && dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY --from=dart-builder /app/server ./server
# Copy the pre-built Linux x64 binary
COPY packages/anaki_sqlite/native_libs/libanaki_sqlite-linux-x64.so ./libanaki_sqlite.so

ENV LD_LIBRARY_PATH=/app
EXPOSE 8080
CMD ["./server"]
```

## Tips

- **For Linux ARM (e.g., AWS Graviton):** Replace `x86_64-unknown-linux-gnu` with `aarch64-unknown-linux-gnu` in the Rust build stage.
- **For multiple databases:** Build the crate with multiple features (`--features sqlite,postgres`) and copy each output to `/app/`, renaming accordingly.
- **Image size:** The runtime image is ~70MB (Debian slim + Dart AOT binary + native lib).
- **Health check:** Add `HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1` if you implement a health endpoint.
