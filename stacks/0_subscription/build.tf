module "test" {
  source = "cyber-scot/rg/azurerm"

  name       = "rg-${var.short}-${var.loc}-${var.env}-01"
  lock_level = "CanNotDelete"
  location   = local.location
  tags       = local.tags
}
