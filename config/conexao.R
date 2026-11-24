library(DBI)
library(RPostgres)

db_config <- list(
  host = "localhost",
  port = 5432,
  dbname = "formbricks_20261124",
  user = "postgres",
  password = "postgres"
)

con <- dbConnect(
  RPostgres::Postgres(),
  host = db_config$host,
  port = db_config$port,
  dbname = db_config$dbname,
  user = db_config$user,
  password = db_config$password

)