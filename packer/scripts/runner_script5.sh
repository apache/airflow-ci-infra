echo "Pre-loading commonly used docker images from S3"
set -eux -o pipefail
aws s3 cp s3://airflow-ci-assets/pre-baked-images.tar.gz - | docker load