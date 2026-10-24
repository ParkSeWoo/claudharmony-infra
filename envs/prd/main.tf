variable "services" {
  type = any
}

variable "images" {
  type = map(string)
}

module "stack" {
  source = "../../modules/stack"

  environment   = "prd"
  public_port   = 80
  enable_tunnel = true
  services      = var.services
  images        = var.images
}

output "stack" {
  value = module.stack
}
