#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/emr-create-cluster.sh [options]

Create an AWS EMR cluster using project defaults. You can override any value
with flags or environment variables (see below).

Options:
  -n, --name NAME                Cluster name (default: P11-cluster)
  -r, --region REGION            AWS region (default: eu-west-3)
  -l, --log-uri URI              S3 log URI
  -b, --bootstrap-path URI       S3 bootstrap script path
  -s, --subnet-id ID             Subnet ID for the cluster
  -k, --key-name NAME            EC2 key pair name
  -h, --help                     Show this help message

Environment variables override defaults as well:
  CLUSTER_NAME, REGION, LOG_URI, BOOTSTRAP_PATH, SUBNET_ID, KEY_NAME,
  SERVICE_ROLE_ARN, INSTANCE_PROFILE, EMR_MASTER_SG, EMR_SLAVE_SG,
  ROOT_VOLUME_SIZE, IDLE_TIMEOUT, RELEASE_LABEL

Examples:
  scripts/emr-create-cluster.sh --name "P11-cluster" --subnet-id "subnet-xxxx"
  REGION=eu-west-3 CLUSTER_NAME=P11-cluster scripts/emr-create-cluster.sh
USAGE
}

CLUSTER_NAME=${CLUSTER_NAME:-"P11-cluster"}
REGION=${REGION:-"eu-west-3"}
LOG_URI=${LOG_URI:-"s3://p11-fruits-710002907257-eu-west-3/logs/emr"}
BOOTSTRAP_PATH=${BOOTSTRAP_PATH:-"s3://p11-fruits-710002907257-eu-west-3/bootstrap/bootstrap.sh"}
SUBNET_ID=${SUBNET_ID:-"subnet-058e45c7ad2c9cb30"}
KEY_NAME=${KEY_NAME:-"p11-emr-paris"}
SERVICE_ROLE_ARN=${SERVICE_ROLE_ARN:-"arn:aws:iam::710002907257:role/service-role/AmazonEMR-ServiceRole-20260120T135907"}
INSTANCE_PROFILE=${INSTANCE_PROFILE:-"AmazonEMR-InstanceProfile-20260120T135851"}
EMR_MASTER_SG=${EMR_MASTER_SG:-"sg-0b6273a3b7b2f2e5e"}
EMR_SLAVE_SG=${EMR_SLAVE_SG:-"sg-0d1833ed3eb4fba0f"}
ROOT_VOLUME_SIZE=${ROOT_VOLUME_SIZE:-"100"}
IDLE_TIMEOUT=${IDLE_TIMEOUT:-"3600"}
RELEASE_LABEL=${RELEASE_LABEL:-"emr-7.12.0"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -l|--log-uri)
      LOG_URI="$2"
      shift 2
      ;;
    -b|--bootstrap-path)
      BOOTSTRAP_PATH="$2"
      shift 2
      ;;
    -s|--subnet-id)
      SUBNET_ID="$2"
      shift 2
      ;;
    -k|--key-name)
      KEY_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

ec2_attributes=$(cat <<JSON
{"InstanceProfile":"${INSTANCE_PROFILE}","EmrManagedMasterSecurityGroup":"${EMR_MASTER_SG}","EmrManagedSlaveSecurityGroup":"${EMR_SLAVE_SG}","KeyName":"${KEY_NAME}","AdditionalMasterSecurityGroups":[],"AdditionalSlaveSecurityGroups":[],"SubnetIds":["${SUBNET_ID}"]}
JSON
)

instance_groups=$(cat <<'JSON'
[
  {
    "InstanceCount": 1,
    "InstanceGroupType": "CORE",
    "Name": "Unité principale",
    "InstanceType": "m5.xlarge",
    "EbsConfiguration": {
      "EbsBlockDeviceConfigs": [
        {
          "VolumeSpecification": {
            "VolumeType": "gp2",
            "SizeInGB": 32
          },
          "VolumesPerInstance": 2
        }
      ]
    }
  },
  {
    "InstanceCount": 1,
    "InstanceGroupType": "MASTER",
    "Name": "Primaire",
    "InstanceType": "m5.xlarge",
    "EbsConfiguration": {
      "EbsBlockDeviceConfigs": [
        {
          "VolumeSpecification": {
            "VolumeType": "gp2",
            "SizeInGB": 32
          },
          "VolumesPerInstance": 2
        }
      ]
    }
  }
]
JSON
)

bootstrap_actions=$(cat <<JSON
[{"Args":[],"Name":"bootstrap","Path":"${BOOTSTRAP_PATH}"}]
JSON
)

auto_termination=$(cat <<JSON
{"IdleTimeout":${IDLE_TIMEOUT}}
JSON
)

aws emr create-cluster \
  --name "${CLUSTER_NAME}" \
  --log-uri "${LOG_URI}" \
  --release-label "${RELEASE_LABEL}" \
  --service-role "${SERVICE_ROLE_ARN}" \
  --unhealthy-node-replacement \
  --ec2-attributes "${ec2_attributes}" \
  --tags 'P11=' 'for-use-with-amazon-emr-managed-policies=true' \
  --applications Name=Hadoop Name=JupyterEnterpriseGateway Name=JupyterHub Name=Spark \
  --instance-groups "${instance_groups}" \
  --bootstrap-actions "${bootstrap_actions}" \
  --scale-down-behavior "TERMINATE_AT_TASK_COMPLETION" \
  --ebs-root-volume-size "${ROOT_VOLUME_SIZE}" \
  --auto-termination-policy "${auto_termination}" \
  --region "${REGION}"
