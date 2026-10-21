#!/bin/sh
set -eu

list=$(mktemp)
trap 'rm -f "$list"' EXIT

timeout 30 kubectl get pods -A --field-selector=status.phase=Failed -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.metadata.ownerReferences[*].kind}{"\n"}{end}' > "$list"

while IFS="$(printf '\t')" read -r ns name kinds; do
  [ -n "${name:-}" ] || continue
  case " ${kinds:-} " in
    *" Job "* | *" DaemonSet "* | *" StatefulSet "* | *" Node "*)
      continue
      ;;
  esac
  echo "pod-reaper: $ns/$name"
  timeout 30 kubectl get pod -n "$ns" "$name" -o jsonpath='reason={.status.reason} message={.status.message}{"\n"}{range .status.containerStatuses[*]}{.name} exit={.state.terminated.exitCode} reason={.state.terminated.reason} message={.state.terminated.message}{"\n"}{end}'
  timeout 30 kubectl logs -n "$ns" "$name" --all-containers --tail=200 --prefix --timestamps || true
  timeout 30 kubectl delete pod -n "$ns" "$name" --wait=false --ignore-not-found
done < "$list"
