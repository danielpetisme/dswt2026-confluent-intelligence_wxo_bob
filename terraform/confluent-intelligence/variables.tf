variable "confluent_cloud_api_key" {
  description = "Confluent Cloud organization-level API key. Same org as the platform phase; set via TF_VAR_confluent_cloud_api_key, never committed."
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud organization-level API secret. Set via TF_VAR_confluent_cloud_api_secret, never committed."
  type        = string
  sensitive   = true
}

variable "intelligence_flink_max_cfu" {
  description = "Max CFU for the Flink compute pool. A demo with the ticket enrichment/metrics statements + one Streaming Agent needs very little; the provider's own minimum/default is small."
  type        = number
  default     = 5
}

# --- Single-agent wiring (TRIAGEAGENT) -- gated because it has two
# prerequisites that don't exist until later in the build order: the
# support_portal app must be deployed publicly, and the check_status UDF
# JAR must be built (via the flink-udf skill). Leave
# intelligence_enable_agent=false to apply everything else (ticket
# enrichment/metrics statements, RTCE key) today.

variable "intelligence_enable_agent" {
  description = "Set true once app_public_url and udf_jar_path below are real, to provision the MCP connection/tools/CREATE AGENT statements."
  type        = bool
  default     = false
}

variable "app_public_url" {
  description = "Manual override for the deployed support_portal app's public URL. Normally left empty -- terraform/confluent-intelligence auto-derives this from terraform/app-hosting's `ingress_url` output via terraform_remote_state. Only set this if testing against an app hosted somewhere other than terraform/app-hosting, or if you need a value before app-hosting has been applied."
  type        = string
  default     = ""
}

variable "udf_jar_path" {
  description = "Local path to the built check_status UDF JAR. Currently unused -- the check_status_tool/function/artifact resources in 03_statements_triage_agent.tf are commented out in favor of MCP-only tools."
  type        = string
  default     = ""
}

variable "flink_udf_class_name" {
  description = "Fully-qualified Java class name of the check_status UDF inside udf_jar_path. Currently unused, see udf_jar_path."
  type        = string
  default     = ""
}

# --- AWS Bedrock connection + model (backs the TRIAGEAGENT's model) --
# gated independently of intelligence_enable_agent so the connection/CREATE
# MODEL can be stood up and verified on its own before the rest of the
# agent pipeline (which additionally needs the deployed app's public URL
# and the UDF JAR) is ready.

variable "intelligence_enable_bedrock_model" {
  description = "Set true to provision a dedicated, least-privilege IAM user + long-lived access key (bedrock:InvokeModel on Anthropic models only, see bedrock_iam.tf) plus the Bedrock connection + CREATE MODEL statement that uses it. Requires AWS_PROFILE (or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) + AWS_REGION to be set -- the same ones already used for `--stage app` -- so Terraform's aws provider can create the IAM user. Required (but not sufficient on its own) for intelligence_enable_agent = true."
  type        = bool
  default     = false
}

locals {
  agent_prereqs_met = (
    local.app_public_url != "" &&
    var.intelligence_enable_bedrock_model
  )
}

resource "terraform_data" "validate_agent_prereqs" {
  count = var.intelligence_enable_agent && !local.agent_prereqs_met ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.agent_prereqs_met
      error_message = "intelligence_enable_agent = true requires a resolvable app_public_url (apply terraform/app-hosting first, or set TF_VAR_app_public_url manually) and intelligence_enable_bedrock_model to both be set."
    }
  }
}
