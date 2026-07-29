# Required-keys list mirrors `grep -rn 'local\.images\[' hestia/*.tf` — update
# both together if a site/deployment starts or stops reading an image ref.
run "required_deployment_keys_exist" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["momus", "monke-academy-site", "vin-moe-site", "vinnel-cloud-admin", "vinnel-cloud-auth", "vinnel-cloud-site"] :
      contains(keys(output.images), k)
    ])
    error_message = "images.json is missing a key that hestia/*.tf reads via local.images[...]"
  }
}

run "image_refs_are_pinned_by_digest" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in output.images : can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+@sha256:[0-9a-f]{64}$", v))
      if !startswith(k, "//")
    ])
    error_message = "every non-comment entry in images.json must be a digest-pinned image ref (repo@sha256:<64 hex>)"
  }
}
