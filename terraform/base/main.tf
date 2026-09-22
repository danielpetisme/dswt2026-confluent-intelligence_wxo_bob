# Basic platform: one environment, one Basic Kafka cluster on AWS (RTCE,
# provisioned in the confluent-intelligence phase, is AWS-only), one
# service account + API keys the support_portal app authenticates with,
# and the one topic nothing else creates automatically (tickets.raw --
# tickets.enriched/tickets.metrics/tickets.agent-actions are created by
# Flink CTAS statements in the confluent-intelligence phase instead).

resource "confluent_environment" "main" {
  display_name = "${var.name_prefix}-env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

resource "confluent_kafka_cluster" "main" {
  display_name = "${var.name_prefix}-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = var.region

  basic {}

  environment {
    id = confluent_environment.main.id
  }
}

resource "confluent_service_account" "app" {
  display_name = "${var.name_prefix}-app"
  description  = "Service account for the support_portal app (Kafka + Schema Registry access)."
}

resource "confluent_role_binding" "app_cluster_admin" {
  principal   = "User:${confluent_service_account.app.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}

# CloudClusterAdmin on the Kafka cluster does NOT cover Schema Registry --
# confirmed live: the app's SR key got a 403 registering tickets.raw's
# schema without this. EnvironmentAdmin at the environment level is what
# actually grants Schema Registry access (same pattern the sibling
# project uses).
resource "confluent_role_binding" "app_environment_admin" {
  principal   = "User:${confluent_service_account.app.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.main.resource_name
}

resource "confluent_api_key" "app_kafka" {
  display_name = "${var.name_prefix}-app-key"
  description  = "Kafka API key for the support_portal app's embedded producer/consumer."

  owner {
    id          = confluent_service_account.app.id
    api_version = confluent_service_account.app.api_version
    kind        = confluent_service_account.app.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # The key needs the role binding in place before Confluent Cloud will
  # let it actually produce/consume against the cluster.
  depends_on = [confluent_role_binding.app_cluster_admin]
}

data "confluent_schema_registry_cluster" "main" {
  environment {
    id = confluent_environment.main.id
  }

  depends_on = [confluent_kafka_cluster.main]
}

resource "confluent_api_key" "app_schema_registry" {
  display_name = "${var.name_prefix}-sr-key"
  description  = "Schema Registry API key for the support_portal app's JSON Schema serializer/deserializer."

  owner {
    id          = confluent_service_account.app.id
    api_version = confluent_service_account.app.api_version
    kind        = confluent_service_account.app.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.main.id
    api_version = data.confluent_schema_registry_cluster.main.api_version
    kind        = data.confluent_schema_registry_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  depends_on = [confluent_role_binding.app_environment_admin]
}

resource "confluent_kafka_topic" "tickets_raw" {
  topic_name       = "tickets.raw"
  partitions_count = 2

  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }

  rest_endpoint = confluent_kafka_cluster.main.rest_endpoint

  credentials {
    key    = confluent_api_key.app_kafka.id
    secret = confluent_api_key.app_kafka.secret
  }
}
