from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    account_pool_size: int = 250
    match_threshold: int = 65
    admin_token: str = "change-me"
    port: int = 8000
    enable_generator: bool = True
    generator_rate: float = 0.5

    # mcp 2.x rejects any request whose Host header isn't in this list
    # (DNS-rebinding protection, on by default) -- add the public
    # deployment hostname here once known, e.g. "my-portal.fly.dev".
    mcp_allowed_hosts: str = "localhost:*,127.0.0.1:*"

    cc_bootstrap_servers: str = ""
    cc_api_key: str = ""
    cc_api_secret: str = ""
    cc_security_protocol: str = "SASL_SSL"
    cc_sasl_mechanisms: str = "PLAIN"

    cc_schema_registry_url: str = ""
    cc_schema_registry_api_key: str = ""
    cc_schema_registry_api_secret: str = ""


settings = Settings()
