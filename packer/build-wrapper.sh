#!/bin/bash
#
# Wraps the build process for validations, etc
#

# TODO: validate environment variables before execution

REPOSITORY_URL="https://github.com/hail-is/hail.git"

# date is appended to ami_name to prevent collision with public AMIs
if [ -z "$TRAILING_DATE" ]; then
    TRAILING_DATE=true
fi

usage(){
cat <<EOF

  usage: build-wrapper.sh [ARGUMENTS]

    --hail-bucket      [Your S3 Bucket Name] - REQUIRED
    --roda-bucket      [RODA S3 Bucket Name] - REQUIRED
    --subnet-id        [Subnet ID]           - REQUIRED
    --subnet-type      [Subnet Type]         - REQUIRED.  public or private
    --vpc-id           [VPC ID]              - REQUIRED
    --hail-version     [Number Version]      - OPTIONAL.  If omitted, master branch will be used.
    --htslib-version   [HTSLIB Version]      - OPTIONAL.  If omitted, develop branch will be used.
    --samtools-version [Samtools Version]    - OPTIONAL.  If omitted, master branch will be used.
    --vep-version      [Number Version]      - OPTIONAL.  If omitted, VEP will not be included.

    Example:

   build-wrapper.sh --hail-bucket your-quickstart-s3-bucket-name \\
                    --roda-bucket hail-vep-pipeline \\
                    --subnet-id subnet-99999999 \\
                    --subnet-type private \\
                    --vpc-id vpc-99999999 \\
                    --hail-version 0.2.34 \\
                    --htslib-version 1.10.2 \\
                    --samtools-version 1.10 \\
                    --vep-version 99

EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --help)
            usage
            shift
            exit 0
            ;;
        --hail-version)
            HAIL_VERSION="$2"
            shift
            shift
            ;;
        --htslib-version)
            HTSLIB_VERSION="$2"
            shift
            shift
            ;;
        --samtools-version)
            SAMTOOLS_VERSION="$2"
            shift
            shift
            ;;
        --vep-version)
            VEP_VERSION="$2"
            shift
            shift
            ;;
        --roda-bucket)
            RODA_BUCKET="$2"
            shift
            shift
            ;;
        --vpc-id)
            VPC_ID="$2"
            shift
            shift
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift
            shift
            ;;
        --subnet-type)
            SUBNET_TYPE="$2"
            shift
            shift
            ;;
        --no-trailing-date)
            TRAILING_DATE=false
            shift
            shift
            ;;
    esac
done

DATE=$(date +%Y%m%d)
HAIL_NAME_VERSION="$HAIL_VERSION"  # Used by AMI name

if [ -z "$HAIL_VERSION" ]; then
    HAIL_VERSION=$(git ls-remote "$REPOSITORY_URL" refs/heads/master | awk '{print $1}')
    echo "HAIL_VERSION env var unset.  Setting to HEAD of master branch: $HAIL_VERSION"
    HAIL_NAME_VERSION=master-$(echo "$HAIL_VERSION" | cut -c1-7)
fi

if [ -z "$VEP_VERSION" ] || [ "$VEP_VERSION" == "" ]; then
    VEP_VERSION="none"
else
    # Add vep version to AMI name if enabled
    HAIL_NAME_VERSION="$HAIL_NAME_VERSION-vep-$VEP_VERSION"
fi

if [ "$TRAILING_DATE" = true ]; then
    HAIL_NAME_VERSION="$HAIL_NAME_VERSION-$DATE"
fi

if [ "$SUBNET_TYPE" == "public" ]; then
    ASSOCIATE_PUBLIC_IP_ADDRESS="true"
    SSH_INTERFACE="public_ip"
elif [ "$SUBNET_TYPE" == "private" ]; then
    ASSOCIATE_PUBLIC_IP_ADDRESS="false"
    SSH_INTERFACE="private_ip"
else
    echo "Invalid subnet type.  Valid types are public or private."
    exit 1
fi

export AWS_MAX_ATTEMPTS=600  # Builds time out with default value
packer build --var hail_name_version="$HAIL_NAME_VERSION" \
             --var hail_version="$HAIL_VERSION" \
             --var roda_bucket="$RODA_BUCKET" \
             --var htslib_version="$HTSLIB_VERSION" \
             --var samtools_version="$SAMTOOLS_VERSION" \
             --var subnet_id="$SUBNET_ID" \
             --var associate_public_ip_address="$ASSOCIATE_PUBLIC_IP_ADDRESS" \
             --var ssh_interface="$SSH_INTERFACE" \
             --var vep_version="$VEP_VERSION" \
             --var vpc_id="$VPC_ID" \
             --var-file=build.vars \
             amazon-linux.json
