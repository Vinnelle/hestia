# Gemma

module "gemma" {
  source = "./bots/gemma"

  depends_on = [module.platform_core, module.gitlab]

  image                     = local.images["gemma"]
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  llm_base_url              = module.llm.base_url
  llm_model                 = module.llm.model
  llm_api_key               = module.llm.api_key
  search_url                = module.searxng.url
}
