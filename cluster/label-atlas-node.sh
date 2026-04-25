#!/bin/bash
# Label the Mac Mini 2018 node for GPU and storage workloads
kubectl label node atlas node-role.kubernetes.io/gpu=true
kubectl label node atlas node-role.kubernetes.io/storage=true
