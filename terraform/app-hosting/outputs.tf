output "ecr_repository_url" {
  description = "Read by deploy.py before the image exists, to build and push against a real URI."
  value       = aws_ecr_repository.app.repository_url
}

# ingress_paths' exact shape (how many entries, in what order) isn't
# confirmed from hands-on testing -- this takes the first entry as the
# app's public URL. If that's wrong once applied, print the full list
# instead (`terraform output -json` on aws_ecs_express_gateway_service.app)
# and adjust.
output "ingress_url" {
  description = "Public HTTPS URL for the deployed support_portal app."
  value       = try(aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint, null)
}

output "admin_token" {
  value     = var.app_admin_token
  sensitive = true
}
