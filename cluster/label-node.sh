#!/bin/bash
kubectl label node hyperion node-role.kubernetes.io/gpu=true
kubectl label node hyperion node-role.kubernetes.io/storage=true
