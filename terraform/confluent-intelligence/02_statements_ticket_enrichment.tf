# Ticket enrichment statement, per PROJECT_SPEC.md section 2.4.
# This CTAS statement auto-creates its backing topic + Schema Registry
# subject (same pattern as the sibling project's CREATE TABLE statements)
# -- no confluent_kafka_topic needed for tickets.enriched.
#
# TEMPORARY: sentiment_result is a fake placeholder (random pick among the
# same three labels app/scripts/dev_fake_producer.py already uses) instead
# of a real AI_SENTIMENT call, so the rest of the pipeline (TRIAGEAGENT,
# dashboard) can be built/tested without depending on AI_SENTIMENT's exact
# EA syntax and per-aspect return-type shape being verified first. Swap
# back to AI_SENTIMENT(text, ARRAY['urgency']) once that's confirmed
# against current docs.confluent.io.

resource "confluent_flink_statement" "ticket_enrichment" {
  statement = <<-SQL
    CREATE TABLE `tickets.enriched` AS
    SELECT
      ticket_id,
      user_id,
      text,
      urgency_self_rated,
      CASE CAST(FLOOR(RAND() * 3) AS INT)
        WHEN 0 THEN 'negative'
        WHEN 1 THEN 'neutral'
        ELSE 'positive'
      END AS sentiment_result,
      CURRENT_TIMESTAMP AS enriched_at
    FROM `tickets.raw`;
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
