#!/bin/bash

###############################################################################
# AWS Security Group Management Script for mldl Environment
# This script manages AWS Security Groups for the scheduler application
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Function to check AWS CLI installation
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        print_info "Install AWS CLI from: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured"
        print_info "Run 'aws configure' to set up your credentials"
        return 1
    fi
    
    print_info "AWS CLI is configured correctly"
    return 0
}

# Function to get instance ID
get_instance_id() {
    if command -v ec2-metadata &> /dev/null; then
        ec2-metadata --instance-id | cut -d " " -f 2
    else
        # Try using IMDSv2
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
            curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
        else
            # Fallback to IMDSv1
            curl http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
        fi
    fi
}

# Function to get security group ID from instance
get_security_group_id() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        instance_id=$(get_instance_id)
    fi
    
    if [ -z "$instance_id" ]; then
        print_error "Could not determine instance ID"
        return 1
    fi
    
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text 2>/dev/null
}

# Function to create a new security group
create_security_group() {
    local sg_name=$1
    local description=$2
    local vpc_id=$3
    
    if [ -z "$sg_name" ]; then
        print_error "Security group name is required"
        return 1
    fi
    
    if [ -z "$description" ]; then
        description="Security group for mldl scheduler application"
    fi
    
    # Get VPC ID if not provided
    if [ -z "$vpc_id" ]; then
        print_info "Retrieving default VPC ID..."
        vpc_id=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
        
        if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
            print_error "Could not determine VPC ID"
            print_info "Please provide VPC ID as parameter"
            return 1
        fi
    fi
    
    print_info "Creating security group: $sg_name in VPC: $vpc_id"
    
    sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text)
    
    if [ $? -eq 0 ] && [ -n "$sg_id" ]; then
        print_info "Security group created successfully: $sg_id"
        
        # Add tags
        aws ec2 create-tags \
            --resources "$sg_id" \
            --tags Key=Name,Value="$sg_name" Key=Environment,Value=mldl Key=Application,Value=scheduler
        
        echo "$sg_id"
        return 0
    else
        print_error "Failed to create security group"
        return 1
    fi
}

# Function to add inbound rule
add_inbound_rule() {
    local sg_id=$1
    local port=$2
    local protocol=${3:-tcp}
    local cidr=${4:-0.0.0.0/0}
    local description=${5:-"Port $port access"}
    
    if [ -z "$sg_id" ] || [ -z "$port" ]; then
        print_error "Security group ID and port are required"
        return 1
    fi
    
    print_info "Adding inbound rule: $port/$protocol from $cidr to $sg_id"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions IpProtocol="$protocol",FromPort="$port",ToPort="$port",IpRanges="[{CidrIp=$cidr,Description=\"$description\"}]" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_info "Inbound rule added successfully"
        return 0
    else
        print_warning "Rule may already exist or failed to add"
        return 1
    fi
}

# Function to remove inbound rule
remove_inbound_rule() {
    local sg_id=$1
    local port=$2
    local protocol=${3:-tcp}
    local cidr=${4:-0.0.0.0/0}
    
    if [ -z "$sg_id" ] || [ -z "$port" ]; then
        print_error "Security group ID and port are required"
        return 1
    fi
    
    print_info "Removing inbound rule: $port/$protocol from $cidr in $sg_id"
    
    aws ec2 revoke-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions IpProtocol="$protocol",FromPort="$port",ToPort="$port",IpRanges="[{CidrIp=$cidr}]" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_info "Inbound rule removed successfully"
        return 0
    else
        print_error "Failed to remove inbound rule"
        return 1
    fi
}

# Function to list all rules in a security group
list_security_group_rules() {
    local sg_id=$1
    
    if [ -z "$sg_id" ]; then
        sg_id=$(get_security_group_id)
    fi
    
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
        print_error "Could not determine security group ID"
        return 1
    fi
    
    print_info "Security Group Rules for: $sg_id"
    echo ""
    
    # Get security group details
    aws ec2 describe-security-groups --group-ids "$sg_id" \
        --query 'SecurityGroups[0].[GroupName,Description,VpcId]' \
        --output table
    
    echo ""
    print_info "Inbound Rules:"
    aws ec2 describe-security-groups --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description]' \
        --output table
    
    echo ""
    print_info "Outbound Rules:"
    aws ec2 describe-security-groups --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description]' \
        --output table
}

# Function to setup default scheduler ports
setup_scheduler_ports() {
    local sg_id=$1
    local cidr=${2:-0.0.0.0/0}
    
    if [ -z "$sg_id" ]; then
        print_error "Security group ID is required"
        return 1
    fi
    
    print_info "Setting up scheduler application ports in security group: $sg_id"
    
    # Array of ports: port:protocol:description
    local ports=(
        "5000:tcp:Flask development server"
        "8000:tcp:Gunicorn production server"
        "80:tcp:HTTP access"
        "443:tcp:HTTPS access"
        "22:tcp:SSH access"
    )
    
    for port_config in "${ports[@]}"; do
        IFS=':' read -r port protocol description <<< "$port_config"
        add_inbound_rule "$sg_id" "$port" "$protocol" "$cidr" "$description"
    done
    
    print_info "Scheduler ports setup completed"
}

# Function to restrict access to specific IP
restrict_to_ip() {
    local sg_id=$1
    local port=$2
    local ip_address=$3
    
    if [ -z "$sg_id" ] || [ -z "$port" ] || [ -z "$ip_address" ]; then
        print_error "Security group ID, port, and IP address are required"
        return 1
    fi
    
    # Add /32 if not specified
    if [[ ! "$ip_address" =~ "/" ]]; then
        ip_address="$ip_address/32"
    fi
    
    print_info "Restricting port $port to IP: $ip_address"
    
    # Remove existing rules for all IPs
    remove_inbound_rule "$sg_id" "$port" "tcp" "0.0.0.0/0"
    
    # Add rule for specific IP
    add_inbound_rule "$sg_id" "$port" "tcp" "$ip_address" "Restricted access from $ip_address"
}

# Function to get current public IP
get_public_ip() {
    local ip=$(curl -s http://checkip.amazonaws.com/)
    if [ -n "$ip" ]; then
        print_info "Your current public IP: $ip"
        echo "$ip"
    else
        print_error "Could not determine public IP"
        return 1
    fi
}

# Main function
main() {
    case "$1" in
        "create")
            create_security_group "$2" "$3" "$4"
            ;;
        "add")
            add_inbound_rule "$2" "$3" "$4" "$5" "$6"
            ;;
        "remove")
            remove_inbound_rule "$2" "$3" "$4" "$5"
            ;;
        "list")
            list_security_group_rules "$2"
            ;;
        "setup")
            setup_scheduler_ports "$2" "$3"
            ;;
        "restrict")
            restrict_to_ip "$2" "$3" "$4"
            ;;
        "get-id")
            sg_id=$(get_security_group_id "$2")
            if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
                print_info "Security Group ID: $sg_id"
                echo "$sg_id"
            else
                print_error "Could not retrieve security group ID"
                exit 1
            fi
            ;;
        "my-ip")
            get_public_ip
            ;;
        "help"|"--help"|"-h")
            cat << EOF
AWS Security Group Management Script for mldl Environment

Usage: $0 <command> [arguments]

Commands:
    create <name> [description] [vpc-id]
        Create a new security group
        
    add <sg-id> <port> [protocol] [cidr] [description]
        Add an inbound rule to security group
        Default: protocol=tcp, cidr=0.0.0.0/0
        
    remove <sg-id> <port> [protocol] [cidr]
        Remove an inbound rule from security group
        
    list [sg-id]
        List all rules in a security group
        If sg-id not provided, tries to get from current instance
        
    setup <sg-id> [cidr]
        Setup all default scheduler ports in security group
        Default cidr: 0.0.0.0/0
        
    restrict <sg-id> <port> <ip-address>
        Restrict port access to specific IP address
        
    get-id [instance-id]
        Get security group ID from instance
        If instance-id not provided, uses current instance
        
    my-ip
        Get your current public IP address
        
    help
        Show this help message

Examples:
    # Create a new security group
    $0 create "mldl-scheduler-sg" "Security group for scheduler"
    
    # Add a rule to allow port 8000 from anywhere
    $0 add sg-0123456789abcdef 8000
    
    # Add a rule to allow port 22 from specific IP
    $0 add sg-0123456789abcdef 22 tcp 203.0.113.0/24 "SSH from office"
    
    # Setup all scheduler ports
    $0 setup sg-0123456789abcdef
    
    # List all rules
    $0 list sg-0123456789abcdef
    
    # Restrict SSH to your IP
    $0 restrict sg-0123456789abcdef 22 203.0.113.1
    
    # Get security group ID from current instance
    $0 get-id
    
    # Get your public IP
    $0 my-ip

Note:
    - AWS CLI must be installed and configured
    - Proper IAM permissions are required for security group operations
    - Use 'aws configure' to set up credentials

EOF
            ;;
        *)
            if ! check_aws_cli; then
                exit 1
            fi
            print_error "Unknown command: $1"
            print_info "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if ! check_aws_cli && [ "$1" != "help" ] && [ "$1" != "--help" ] && [ "$1" != "-h" ]; then
        exit 1
    fi
    
    if [ $# -eq 0 ]; then
        print_error "No command provided"
        print_info "Run '$0 help' for usage information"
        exit 1
    fi
    
    main "$@"
fi
