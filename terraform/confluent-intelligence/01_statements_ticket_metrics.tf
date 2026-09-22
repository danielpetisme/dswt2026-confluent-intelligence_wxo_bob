# Ticket metrics/forecast statement, per PROJECT_SPEC.md section 2.4.
# This CTAS statement auto-creates its backing topic + Schema Registry
# subject (same pattern as the sibling project's CREATE TABLE statements)
# -- no confluent_kafka_topic needed for tickets.metrics.
#
# Reads directly from `tickets.raw`, so it has no data dependency on the
# ticket_enrichment statement and applies independently.
#
# `tickets.raw`'s own `submitted_at` column came in as VARCHAR (from the
# app's JSON Schema), which TUMBLE rejects outright. Tried adding a
# computed watermark column via ALTER TABLE ADD -- confirmed live that
# Confluent Cloud Flink already declares a system-provided watermark on
# every table by default and rejects ADD for this ("Use ALTER TABLE
# MODIFY for custom watermarks"). Simplest correct fix: use that
# system-provided time attribute directly -- Confluent Cloud Flink
# exposes it as the `$rowtime` metadata column (the Kafka record
# timestamp) -- instead of parsing `submitted_at` or touching the
# table's watermark at all.
#
# Switched from AI_FORECAST (Early Access) to ML_FORECAST (GA,
# ARIMA-based) after AI_FORECAST consistently failed with "does not
# exist" even matching its docs' exact syntax multiple ways -- the docs
# state AI_FORECAST access is gated by EA program sign-up with no
# GRANT/RBAC path, and this org isn't enrolled for it (confirmed
# per Daniel's decision to use the GA fallback this project's plan
# already anticipated as a contingency for exactly this risk).
#
# Recurring gotcha along the way: Flink/Calcite infers CHAR(n)
# (fixed-length) for string literals and for JSON_OBJECT(...)'s result,
# not STRING/VARCHAR -- both AI_FORECAST's and ML_FORECAST's config
# parameter only have a STRING overload (no MAP/CHAR overload), so every
# such expression needs an explicit CAST(... AS STRING).
#
# ML_FORECAST returns a ROW (actual_value, aic, forecast_value,
# lower_bound, rmse, timestamp, upper_bound). Tried projecting a single
# field out of it (both `alias.field` and `(alias).field`) and hit
# "Table not found" then "Incompatible types" -- rather than keep
# guessing composite-field-access syntax against a live, billed compute
# pool, keep the whole ROW as-is in the output topic instead of
# decomposing it in SQL. This is arguably better anyway: it preserves
# lower_bound/upper_bound/rmse too, not just the point forecast, which
# the dashboard can destructure client-side from the nested JSON.
resource "confluent_flink_statement" "ticket_metrics_forecast" {
  # RTCE's query tool rejects this table in its default (planner-inferred)
  # "retract" changelog mode -- confirmed live: the GROUP BY + OVER(...
  # UNBOUNDED PRECEDING) call to ML_FORECAST can revise the forecast for a
  # window_end it already emitted, so the planner conservatively marks the
  # output as retract. RTCE only supports append/upsert. Since a forecast
  # revision for the same window_end is the semantically correct case here,
  # upsert (keyed by window_end) is the right target, not forcing append.
  # This CTAS variant (PRIMARY KEY/WITH in the CREATE part, columns still
  # inferred from the SELECT) is a Confluent-confirmed pattern -- avoids
  # hand-declaring ML_FORECAST's ROW field types, which the comment above
  # already flagged as unreliable to guess.
  #
  # window_end (the key) must be the SELECT's first column -- confirmed
  # live: "Key columns must appear at the beginning of the table schema."
  statement = <<-SQL
    CREATE TABLE `tickets.metrics` (
      PRIMARY KEY (window_end) NOT ENFORCED
    ) WITH (
      'changelog.mode' = 'upsert'
    ) AS
    SELECT
      window_end,
      window_start,
      COUNT(*) AS ticket_count,
      ML_FORECAST(
        CAST(COUNT(*) AS DOUBLE),
        window_end,
        CAST(JSON_OBJECT('minTrainingSize' VALUE 10, 'enableStl' VALUE false, 'horizon' VALUE 5) AS STRING)
      ) OVER (
        ORDER BY window_end
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS forecast
    FROM TABLE(
      TUMBLE(TABLE `tickets.raw`, DESCRIPTOR($rowtime), INTERVAL '1' MINUTE)
    )
    GROUP BY window_start, window_end;
  SQL

  properties = local.flink_statement_context.properties

  compute_pool {
    id = local.flink_statement_context.compute_pool_id
  }

  principal {
    id = local.flink_statement_context.principal_id
  }

  rest_endpoint = local.flink_statement_context.rest_endpoint

  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }

  organization {
    id = local.flink_statement_context.organization_id
  }

  environment {
    id = local.environment_id
  }
}
