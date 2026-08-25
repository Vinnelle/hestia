# Required-keys list mirrors `grep -rn 'images\[' hestia/main.tf` — update both
# together if a site/deployment starts or stops reading an image ref. The keys
# come from the three per-domain maps merged in locals.tf.
run "required_deployment_keys_exist" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["monke-academy-site", "vin-moe-site", "vinnel-cloud-admin", "vinnel-cloud-auth", "vinnel-cloud-shell", "vinnel-cloud-site"] :
      contains(keys(output.images), k)
    ])
    error_message = "a *-images.json map is missing a key that main.tf passes via local.images[...]"
  }
}

run "image_refs_are_pinned_by_digest" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in output.images : can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+@sha256:[0-9a-f]{64}$", v))
      if !startswith(k, "//")
    ])
    error_message = "every non-comment entry in the *-images.json maps must be a digest-pinned image ref (repo@sha256:<64 hex>)"
  }
}
