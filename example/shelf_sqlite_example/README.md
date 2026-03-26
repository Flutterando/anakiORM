# Shelf + SQLite Example

A simple REST API using [Shelf](https://pub.dev/packages/shelf) and [AnakiORM](../../packages/anaki_orm/) with the [SQLite driver](../../packages/anaki_sqlite/).

## Prerequisites

1. **Dart SDK** >= 3.10.0
2. **Rust** toolchain (for building the native library)

## Setup

### 1. Build the native SQLite library

```bash
# From the monorepo root
./scripts/build_native.sh sqlite --local
```

### 2. Install dependencies

```bash
dart pub get
```

### 3. Run the server

```bash
dart run bin/server.dart
```

The server starts at `http://localhost:8080`.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/todos` | List all todos |
| `GET` | `/todos/:id` | Get a todo by ID |
| `POST` | `/todos` | Create a new todo |
| `PUT` | `/todos/:id` | Update a todo |
| `DELETE` | `/todos/:id` | Delete a todo |

## Examples

### Create a todo

```bash
curl -X POST http://localhost:8080/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "description": "Milk, eggs, bread"}'
```

### List all todos

```bash
curl http://localhost:8080/todos
```

### Update a todo

```bash
curl -X PUT http://localhost:8080/todos/1 \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "description": "Milk, eggs, bread, butter", "completed": true}'
```

### Delete a todo

```bash
curl -X DELETE http://localhost:8080/todos/1
```
