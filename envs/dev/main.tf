variable "services" {
  type = any
}

variable "images" {
  type = map(string)
}

module "stack" {
  source = "../../modules/stack"

  environment   = "dev"
  public_port   = 8081
  enable_tunnel = true
  services      = var.services
  images        = var.images
}

output "stack" {
  value = module.stack
}
