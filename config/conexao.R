library(DBI)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  host = "localhost",
  port = 5432,
  dbname = "dump_hro",
  user = "postgres",
  password = "postgres"
)

dbListTables(con)