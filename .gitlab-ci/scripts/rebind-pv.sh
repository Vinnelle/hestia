#!/bin/sh
set -eu

usage() {
  echo "usage: $0 --from NS/PVC --to NS/PVC [--workload NS/KIND/NAME] [--restore]" >&2
  exit 2
}

from=""; to=""; workload=""; restore=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) from="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --workload) workload="$2"; shift 2 ;;
    --restore) restore=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$from" ] && [ -n "$to" ] || usage

src_ns=${from%%/*}; src_pvc=${from#*/}
dst_ns=${to%%/*};   dst_pvc=${to#*/}

if [ "$restore" -eq 1 ]; then
  pv=$(kubectl get pvc "$dst_pvc" -n "$dst_ns" -o jsonpath='{.spec.volumeName}')
  kubectl patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
  echo "$pv reclaim policy restored to Delete"
  exit 0
fi

pv=$(kubectl get pvc "$src_pvc" -n "$src_ns" -o jsonpath='{.spec.volumeName}')
[ -n "$pv" ] || { echo "$from is not bound to a PV" >&2; exit 1; }
echo "$from is bound to $pv"

kubectl patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

if [ -n "$workload" ]; then
  wl_ns=$(echo "$workload" | cut -d/ -f1)
  wl_kind=$(echo "$workload" | cut -d/ -f2)
  wl_name=$(echo "$workload" | cut -d/ -f3)
  sel=$(kubectl get "$wl_kind/$wl_name" -n "$wl_ns" \
    -o jsonpath='{range .spec.selector.matchLabels}{@}{end}' \
    | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
  kubectl scale "$wl_kind/$wl_name" -n "$wl_ns" --replicas=0
  kubectl wait --for=delete pod -n "$wl_ns" -l "$sel" --timeout=300s
fi

kubectl delete pvc "$src_pvc" -n "$src_ns" --wait=true
kubectl patch pv "$pv" --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl patch pv "$pv" -p "{\"spec\":{\"claimRef\":{\"apiVersion\":\"v1\",\"kind\":\"PersistentVolumeClaim\",\"namespace\":\"$dst_ns\",\"name\":\"$dst_pvc\"}}}"

kubectl get pv "$pv" -o jsonpath='{.metadata.name}{"  "}{.status.phase}{"  claim="}{.spec.claimRef.namespace}{"/"}{.spec.claimRef.name}{"  policy="}{.spec.persistentVolumeReclaimPolicy}{"\n"}' 
echo "$pv reserved for $to -- run the cutover apply, then re-run with --restore"
