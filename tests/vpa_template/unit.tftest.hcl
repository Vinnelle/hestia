# Guards the 2026-08-03 bug: `updateMode` was rendered at spec.updateMode, which
# is not a field on the VerticalPodAutoscaler CRD — the API server pruned it and
# every VPA silently defaulted to Recreate. See gaia/CLAUDE.md's platform-vpa.tf
# section. Nothing else fails when this regresses, so this assert is the check.
run "update_mode_is_nested_under_update_policy" {
  command = plan

  assert {
    condition     = try(output.rendered.spec.updatePolicy.updateMode, null) == "Initial"
    error_message = "update_mode must render at spec.updatePolicy.updateMode — the API server prunes spec.updateMode and defaults to Recreate"
  }

  assert {
    condition     = !contains(keys(output.rendered.spec), "updateMode")
    error_message = "spec.updateMode is not a VerticalPodAutoscaler field and is silently dropped by the API server"
  }
}

run "container_policy_renders_memory_bounds" {
  command = plan

  assert {
    condition = alltrue([
      length(output.rendered.spec.resourcePolicy.containerPolicies) == 1,
      output.rendered.spec.resourcePolicy.containerPolicies[0].containerName == "example",
      output.rendered.spec.resourcePolicy.containerPolicies[0].controlledResources == ["memory"],
      output.rendered.spec.resourcePolicy.containerPolicies[0].minAllowed.memory == "1Gi",
      output.rendered.spec.resourcePolicy.containerPolicies[0].maxAllowed.memory == "2Gi",
    ])
    error_message = "container_policies must render one policy bounding memory requests between min_memory and max_memory"
  }
}
