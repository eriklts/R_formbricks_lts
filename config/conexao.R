library(DBI)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  host = "179.124.146.8",
  port = 5432,
  dbname = "formbricks",
  user = "postgres",
  password = "postgres"
)

dbListTables(con)
