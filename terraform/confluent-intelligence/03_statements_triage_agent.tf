# Single TRIAGEAGENT (PROJECT_SPEC.md section 2.5, simplified from four
# chained agents to one -- Confluent Streaming Agents has no native
# agent-to-agent handoff/branching primitive, confirmed during planning).
#
# Two independent gates:
#   - var.intelligence_enable_bedrock_model provisions just the Bedrock connection +
#     CREATE MODEL below, so that piece can be stood up and verified on
#     its own.
#   - var.intelligence_enable_agent provisions the rest of the pipeline (UDF, MCP
#     connection, tools, CREATE AGENT, run_triage_agent) and additionally
#     requires enable_bedrock_model = true plus the deployed app's public
#     URL and the check_status UDF JAR.
#
# IMPORTANT -- everything in this file is more speculative than the rest
# of this Terraform and MUST be re-verified against
# registry.terraform.io/providers/confluentinc/confluent/latest/docs and
# docs.confluent.io before applying with enable_agent = true:
#   - The installed provider (2.86.0) has NO confluent_flink_agent or
#     confluent_flink_tool resource type (checked via `terraform
#     providers schema -json`) -- CREATE TOOL/CREATE AGENT/CREATE
#     FUNCTION are run as raw SQL via confluent_flink_statement.
#   - A native confluent_flink_connection resource DOES exist, but its
#     schema (type/endpoint/credentials/api_key/username/password/aws_*)
#     has no field for the 'transport-type' WITH-option the MCP
#     connection needs -- so CREATE CONNECTION is also raw SQL here
#     rather than that native resource, deliberately.
#   - The confluent-artifact:// URI format in CREATE FUNCTION below is
#     an educated guess at the reference syntax, not a confirmed one.
#   - AI_RUN_AGENT's exact lateral-join column shape is not confirmed.
#   - The Bedrock connection/model below follows the pattern from
#     github.com/confluentinc/demo-confluent-intelligence-f1
#     (terraform/aws/main.tf's bedrock_textgen_connection + llm_textgen_model).
#     The reference repo defaults to us-east-1 and uses the `us.` cross-
#     region inference profile; this project defaults to eu-west-1, so the
#     model ID below uses the `eu.` inference profile instead -- confirmed
#     live via `aws bedrock list-inference-profiles` + a direct
#     bedrock-runtime invoke-model call against this account/region. If
#     var.region ever changes, re-check which inference profile prefix
#     applies. CREATE MODEL's exact syntax is still otherwise unconfirmed
#     against current docs.confluent.io.

resource "confluent_flink_connection" "bedrock_textgen_connection" {
  count = var.intelligence_enable_bedrock_model ? 1 : 0

  # Unlike other display_names in this project, confluent_flink_connection
  # rejects underscores ("name needs to contain lowercase alphanumeric
  # characters and hyphens only") -- confirmed live -- so name_prefix (which
  # allows underscores, e.g. "dpetisme_dswt2026") needs sanitizing here.
  display_name = "${replace(local.name_prefix, "_", "-")}-triage-agent-llm-connection"
  type         = "BEDROCK"
  endpoint     = "https://bedrock-runtime.${local.region}.amazonaws.com/model/eu.anthropic.claude-sonnet-4-5-20250929-v1:0/invoke"

  aws_access_key = aws_iam_access_key.bedrock_invoker[0].id
  aws_secret_key = aws_iam_access_key.bedrock_invoker[0].secret
  # No aws_session_token: bedrock_iam.tf creates a permanent IAM user
  # key, not an STS token -- there's no temporary-credential case to
  # support.

  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [time_sleep.bedrock_iam_propagation]
}

resource "confluent_flink_statement" "create_triage_agent_model" {
  count = var.intelligence_enable_bedrock_model ? 1 : 0

  statement = <<-SQL
    CREATE MODEL `triage_agent_model`
    INPUT (prompt STRING)
    OUTPUT (response STRING)
    WITH (
      'provider' = 'bedrock',
      'task' = 'text_generation',
      'bedrock.connection' = '${confluent_flink_connection.bedrock_textgen_connection[0].display_name}',
      'bedrock.params.max_tokens' = '50000'
    );
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [confluent_flink_connection.bedrock_textgen_connection]
}

# Commented out along with check_status_tool below -- the streaming agent
# relies only on the MCP tools for now, and no UDF JAR has been built
# (var.udf_jar_path/flink_udf_class_name are unset).
# resource "confluent_flink_artifact" "check_status_udf" {
#   count = var.intelligence_enable_agent ? 1 : 0
#
#   display_name     = "${local.name_prefix}-check-status-udf"
#   cloud            = "AWS"
#   region           = local.region
#   artifact_file    = var.udf_jar_path
#   content_format   = "JAR"
#   runtime_language = "JAVA"
#
#   environment {
#     id = local.environment_id
#   }
# }
#
# resource "confluent_flink_statement" "create_check_status_function" {
#   count = var.intelligence_enable_agent ? 1 : 0
#
#   statement = <<-SQL
#     CREATE FUNCTION check_status
#     AS '${var.flink_udf_class_name}'
#     USING JAR 'confluent-artifact://${confluent_flink_artifact.check_status_udf[0].id}';
#   SQL
#
#   properties = local.flink_statement_context.properties
#   compute_pool { id = local.flink_statement_context.compute_pool_id }
#   principal { id = local.flink_statement_context.principal_id }
#   rest_endpoint = local.flink_statement_context.rest_endpoint
#   credentials {
#     key    = local.flink_statement_context.api_key
#     secret = local.flink_statement_context.api_secret
#   }
#   organization { id = local.flink_statement_context.organization_id }
#   environment { id = local.environment_id }
# }

resource "confluent_flink_statement" "create_mcp_connection" {
  count = var.intelligence_enable_agent ? 1 : 0

  # The support_portal app's MCP mount has no auth of its own (see
  # app/support_portal/main.py -- only a Host-header allowlist), but
  # Confluent Cloud's mcp_server connection type requires some credential
  # to be set regardless. 'api-key' here is a placeholder the app never
  # checks.
  #
  # IF NOT EXISTS matters here: destroying this confluent_flink_statement
  # resource only deletes the Terraform-tracked *statement*, it does not
  # run DROP CONNECTION against the Flink catalog -- confirmed live (a
  # taint-triggered replace failed with "Connection portal_mcp_connection
  # already exists in catalog" until the orphaned object was dropped by
  # hand). Without IF NOT EXISTS, any future taint/replace of this
  # resource fails the same way.
  statement = <<-SQL
    CREATE CONNECTION IF NOT EXISTS portal_mcp_connection WITH (
      'type' = 'mcp_server',
      'endpoint' = '${local.app_public_url}/mcp',
      'transport-type' = 'STREAMABLE_HTTP',
      'api-key' = 'unused-app-has-no-mcp-auth'
    );
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }
}

resource "confluent_flink_statement" "create_search_known_issues_tool" {
  count = var.intelligence_enable_agent ? 1 : 0

  statement = <<-SQL
    CREATE TOOL search_known_issues_tool USING CONNECTION portal_mcp_connection
    WITH ('type' = 'mcp', 'allowed_tools' = 'search_known_issues');
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [confluent_flink_statement.create_mcp_connection]
}

resource "confluent_flink_statement" "create_get_account_context_tool" {
  count = var.intelligence_enable_agent ? 1 : 0

  statement = <<-SQL
    CREATE TOOL get_account_context_tool USING CONNECTION portal_mcp_connection
    WITH ('type' = 'mcp', 'allowed_tools' = 'get_account_context');
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [confluent_flink_statement.create_mcp_connection]
}

# Commented out for now -- the streaming agent should rely only on the
# MCP tools (search_known_issues_tool, get_account_context_tool), not
# this function-backed tool.
# resource "confluent_flink_statement" "create_check_status_tool" {
#   count = var.intelligence_enable_agent ? 1 : 0
#
#   statement = <<-SQL
#     CREATE TOOL check_status_tool
#     USING FUNCTION check_status
#     WITH ('type' = 'function', 'description' = 'Get current service status/incidents');
#   SQL
#
#   properties = local.flink_statement_context.properties
#   compute_pool { id = local.flink_statement_context.compute_pool_id }
#   principal { id = local.flink_statement_context.principal_id }
#   rest_endpoint = local.flink_statement_context.rest_endpoint
#   credentials {
#     key    = local.flink_statement_context.api_key
#     secret = local.flink_statement_context.api_secret
#   }
#   organization { id = local.flink_statement_context.organization_id }
#   environment { id = local.environment_id }
#
#   depends_on = [confluent_flink_statement.create_check_status_function]
# }

resource "confluent_flink_statement" "create_triage_agent" {
  count = var.intelligence_enable_agent ? 1 : 0

  statement = <<-SQL
    CREATE AGENT triage_agent
      USING MODEL `triage_agent_model`
      USING PROMPT 'You are a support triage agent for an e-commerce
        platform. For each ticket: first call search_known_issues with
        the ticket text; then call get_account_context passing the
        service from step 1 as service_hint; then decide whether to
        auto-resolve (known issue matched above threshold) or escalate,
        and produce that decision with a short message.'
      USING TOOLS search_known_issues_tool, get_account_context_tool
      WITH ('max_iterations' = '10', 'max_consecutive_failures' = '3');
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [
    confluent_flink_statement.create_search_known_issues_tool,
    confluent_flink_statement.create_get_account_context_tool,
    confluent_flink_statement.create_triage_agent_model,
  ]
}

resource "confluent_flink_statement" "run_triage_agent" {
  count = var.intelligence_enable_agent ? 1 : 0

  # Calcite rejects `AS result` + `SELECT result.*` here ("SQL parse
  # failed ... encountered 'result'", confirmed live). docs.confluent.io's
  # own AI_RUN_AGENT examples use an unaliased LATERAL TABLE with a bare
  # `SELECT *` instead, so this matches that confirmed pattern rather
  # than guessing at AI_RUN_AGENT's exact output column names.
  statement = <<-SQL
    CREATE TABLE `tickets.agent-actions` AS
    SELECT *
    FROM `tickets.enriched`,
    LATERAL TABLE(AI_RUN_AGENT('triage_agent', `tickets.enriched`.text, `tickets.enriched`.ticket_id));
  SQL

  properties = local.flink_statement_context.properties
  compute_pool { id = local.flink_statement_context.compute_pool_id }
  principal { id = local.flink_statement_context.principal_id }
  rest_endpoint = local.flink_statement_context.rest_endpoint
  credentials {
    key    = local.flink_statement_context.api_key
    secret = local.flink_statement_context.api_secret
  }
  organization { id = local.flink_statement_context.organization_id }
  environment { id = local.environment_id }

  depends_on = [confluent_flink_statement.create_triage_agent]
}
