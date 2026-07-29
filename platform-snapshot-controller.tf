resource "kubectl_manifest" "snapshot_controller" {
  for_each  = fileset("${path.module}/manifests/snapshot-controller", "*.yaml")
  yaml_body = file("${path.module}/manifests/snapshot-controller/${each.value}")
}

resource "kubectl_manifest" "ceph_block_snapshot_class" {
  depends_on = [kubectl_manifest.snapshot_controller]
  yaml_body = yamlencode({
    apiVersion = "snapshot.storage.k8s.io/v1"
    kind       = "VolumeSnapshotClass"
    metadata = {
      name = "ceph-block-snapshot"
      labels = {
        "k10.kasten.io/is-snapshot-class" = "true"
      }
    }
    driver         = "rook-ceph.rbd.csi.ceph.com"
    deletionPolicy = "Delete"
    parameters = {
      clusterID                                         = "rook-ceph"
      "csi.storage.k8s.io/snapshotter-secret-name"      = "rook-csi-rbd-provisioner"
      "csi.storage.k8s.io/snapshotter-secret-namespace" = "rook-ceph"
    }
  })
}
