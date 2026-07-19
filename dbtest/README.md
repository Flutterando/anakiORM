# dbtest — ambiente de teste do Cockpit DB

Bases de dados suportadas pelo Anaki, com tabelas e seed, para testar o
painel Database / `cockpit db` / arquivos `.dbq`.

## Subir

```sh
cd dbtest && docker compose up -d
```

| Engine   | Porta | Database  | Credenciais            |
|----------|-------|-----------|------------------------|
| Postgres | 5434  | anaki_dev | anaki / anaki123       |
| MySQL    | 3307  | anaki_dev | anaki / anaki123       |
| MSSQL    | 1434  | anaki_dev | sa / Anaki!Pass123     |
| SQLite   | —     | `anaki_test.db` (neste diretório) |
| MongoDB  | 27018 | anaki_dev | anaki / anaki123       |
| Redis    | 6380  | —         | sem auth               |

As conexões pg/mysql/mssql estão registradas em `.cockpit/databases.json`.
O sqlite é auto-detectado pelo Cockpit.

> MSSQL: o cert self-signed do container exige `?trustcert=true` na URL
> da conexão (já configurado no `databases.json`).

## Queries de teste

```sh
cockpit db run dbtest/queries/sqlite.dbq
cockpit db run dbtest/queries/postgres.dbq
cockpit db run dbtest/queries/mysql.dbq
cockpit db run dbtest/queries/mssql.dbq
```
