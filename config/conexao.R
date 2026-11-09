library(DBI)
library(RPostgres)

con <- dbConnect(
  RPostgres::Postgres(),
  host = "localhost",
  port = 5432,
  dbname = "formbricks_20261020",
  user = "postgres",
  password = "postgres"
)