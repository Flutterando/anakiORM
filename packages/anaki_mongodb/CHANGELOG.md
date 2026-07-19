# Changelog

## 0.1.0

- Initial release: MongoDB document client (`AnakiMongoDb`/`MongoCollection`) over the AnakiORM native Rust connector.
- find/findOne/findPaged, insert/update/replace/delete, countDocuments, aggregate, distinct, indexes, `runCommand` escape hatch.
- Real multi-document transactions via ClientSession (requires a replica set).
- `ObjectId` value class and automatic extended-JSON codec (`{"$oid"}`/`{"$date"}` ↔ `ObjectId`/`DateTime`).
