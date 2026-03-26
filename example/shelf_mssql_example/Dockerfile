# ── Stage 1: Build Rust native library ──
FROM rust:1.83-slim-bookworm AS rust-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY rust/ ./rust/

RUN cd rust && cargo build --release --features mssql
RUN cp rust/target/release/libanaki_native.so /build/libanaki_mssql.so

# ── Stage 2: Build Dart AOT executable ──
FROM dart:3.10 AS dart-builder

WORKDIR /app

# Copy packages
COPY packages/anaki_orm/ packages/anaki_orm/
COPY packages/anaki_mssql/ packages/anaki_mssql/
COPY example/shelf_mssql_example/ example/shelf_mssql_example/

# Place native lib where the driver can find it
COPY --from=rust-builder /build/libanaki_mssql.so \
     packages/anaki_mssql/native_libs/libanaki_mssql-linux-x64.so

# Resolve dependencies
RUN cd packages/anaki_orm && dart pub get
RUN cd packages/anaki_mssql && dart pub get
RUN cd example/shelf_mssql_example && dart pub get

# AOT compile
RUN cd example/shelf_mssql_example && \
    dart compile exe bin/server.dart -o /app/server

# ── Stage 3: Minimal production image ──
FROM debian:bookworm-slim AS production

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && rm -rf /var/lib/apt/lists/*

RUN useradd -r -s /bin/false appuser

WORKDIR /app

# Copy AOT binary + native lib
COPY --from=dart-builder /app/server ./server
COPY --from=rust-builder /build/libanaki_mssql.so ./libanaki_mssql.so

# Ensure the native lib is findable
ENV LD_LIBRARY_PATH=/app

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

CMD ["./server"]
