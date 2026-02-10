#!/bin/bash

###############################################################################
# AWS Port Configuration Script for mldl Environment
# This script configures ports for the Flask scheduler application on AWS EC2
###############################################################################

# Default configuration
DEFAULT_PORT=5000
GUNICORN_PORT=8000
NGINX_PORT=80
HTTPS_PORT=443

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_warning "This script should be run as root for firewall configuration"
        print_info "Run with: sudo $0"
        return 1
    fi
    return 0
}

# Function to open port in UFW firewall
open_ufw_port() {
    local port=$1
    local protocol=${2:-tcp}
    
    if command -v ufw &> /dev/null; then
        print_info "Opening port $port/$protocol in UFW firewall..."
        ufw allow $port/$protocol
        if [ $? -eq 0 ]; then
            print_info "Port $port/$protocol opened successfully in UFW"
        else
            print_error "Failed to open port $port/$protocol in UFW"
            return 1
        fi
    else
        print_warning "UFW is not installed. Skipping UFW configuration."
    fi
}

# Function to open port in firewalld
open_firewalld_port() {
    local port=$1
    local protocol=${2:-tcp}
    
    if command -v firewall-cmd &> /dev/null; then
        print_info "Opening port $port/$protocol in firewalld..."
        firewall-cmd --permanent --add-port=$port/$protocol
        firewall-cmd --reload
        if [ $? -eq 0 ]; then
            print_info "Port $port/$protocol opened successfully in firewalld"
        else
            print_error "Failed to open port $port/$protocol in firewalld"
            return 1
        fi
    else
        print_warning "firewalld is not installed. Skipping firewalld configuration."
    fi
}

# Function to open port in iptables
open_iptables_port() {
    local port=$1
    local protocol=${2:-tcp}
    
    if command -v iptables &> /dev/null; then
        print_info "Opening port $port/$protocol in iptables..."
        iptables -A INPUT -p $protocol --dport $port -j ACCEPT
        
        # Save iptables rules (method varies by system)
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save
        elif [ -f /etc/init.d/iptables-persistent ]; then
            /etc/init.d/iptables-persistent save
        else
            print_warning "Could not save iptables rules permanently"
        fi
        
        print_info "Port $port/$protocol opened successfully in iptables"
    else
        print_warning "iptables is not installed. Skipping iptables configuration."
    fi
}

# Function to configure AWS Security Group (requires AWS CLI)
configure_aws_security_group() {
    local port=$1
    local protocol=${2:-tcp}
    local sg_id=$3
    local description=${4:-"Port $port for mldl scheduler application"}
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        print_info "Visit: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        return 1
    fi
    
    if [ -z "$sg_id" ]; then
        # Try to get security group ID from instance metadata
        print_info "Attempting to retrieve security group ID from instance metadata..."
        sg_id=$(aws ec2 describe-instances \
            --instance-ids $(ec2-metadata --instance-id | cut -d " " -f 2) \
            --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
            --output text 2>/dev/null)
        
        if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
            print_error "Could not determine security group ID"
            print_info "Please provide security group ID as parameter"
            return 1
        fi
    fi
    
    print_info "Configuring AWS Security Group: $sg_id"
    print_info "Adding inbound rule for port $port/$protocol..."
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr 0.0.0.0/0 \
        --description "$description" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_info "AWS Security Group rule added successfully"
    else
        print_warning "Security group rule may already exist or failed to add"
        print_info "Checking existing rules..."
        aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions[?ToPort==\`$port\`]"
    fi
}

# Function to check if port is already in use
check_port_in_use() {
    local port=$1
    
    if netstat -tuln | grep -q ":$port "; then
        print_warning "Port $port is already in use"
        print_info "Current process using port $port:"
        netstat -tulnp | grep ":$port "
        return 1
    else
        print_info "Port $port is available"
        return 0
    fi
}

# Function to open all required ports
open_all_ports() {
    local sg_id=$1
    
    print_info "=========================================="
    print_info "Configuring ports for mldl Flask Scheduler"
    print_info "=========================================="
    
    # Array of ports to configure: port:protocol:description
    local ports=(
        "$DEFAULT_PORT:tcp:Flask development server"
        "$GUNICORN_PORT:tcp:Gunicorn production server"
        "$NGINX_PORT:tcp:Nginx HTTP"
        "$HTTPS_PORT:tcp:Nginx HTTPS"
    )
    
    for port_config in "${ports[@]}"; do
        IFS=':' read -r port protocol description <<< "$port_config"
        
        print_info ""
        print_info "Configuring port $port ($description)..."
        
        # Check if port is in use
        check_port_in_use "$port"
        
        # Configure local firewall
        if check_root; then
            open_ufw_port "$port" "$protocol"
            open_firewalld_port "$port" "$protocol"
            open_iptables_port "$port" "$protocol"
        fi
        
        # Configure AWS Security Group if sg_id is provided
        if [ -n "$sg_id" ]; then
            configure_aws_security_group "$port" "$protocol" "$sg_id" "$description"
        fi
    done
    
    print_info ""
    print_info "=========================================="
    print_info "Port configuration completed!"
    print_info "=========================================="
}

# Function to configure a custom port
configure_custom_port() {
    local port=$1
    local protocol=${2:-tcp}
    local sg_id=$3
    local description=${4:-"Custom port $port"}
    
    print_info "Configuring custom port $port/$protocol..."
    
    # Check if port is in use
    check_port_in_use "$port"
    
    # Configure local firewall
    if check_root; then
        open_ufw_port "$port" "$protocol"
        open_firewalld_port "$port" "$protocol"
        open_iptables_port "$port" "$protocol"
    fi
    
    # Configure AWS Security Group if sg_id is provided
    if [ -n "$sg_id" ]; then
        configure_aws_security_group "$port" "$protocol" "$sg_id" "$description"
    fi
    
    print_info "Custom port $port configured successfully"
}

# Function to display current open ports
show_open_ports() {
    print_info "Current listening ports:"
    if command -v netstat &> /dev/null; then
        netstat -tuln | grep LISTEN
    elif command -v ss &> /dev/null; then
        ss -tuln | grep LISTEN
    else
        print_error "Neither netstat nor ss command found"
    fi
}

# Function to show security group rules
show_security_group_rules() {
    local sg_id=$1
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        return 1
    fi
    
    if [ -z "$sg_id" ]; then
        print_info "Attempting to retrieve security group ID from instance metadata..."
        sg_id=$(aws ec2 describe-instances \
            --instance-ids $(ec2-metadata --instance-id | cut -d " " -f 2) \
            --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
            --output text 2>/dev/null)
    fi
    
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
        print_error "Could not determine security group ID"
        return 1
    fi
    
    print_info "Security Group Rules for $sg_id:"
    aws ec2 describe-security-groups --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description]' \
        --output table
}

# Main function to parse arguments and execute
main() {
    case "$1" in
        "all")
            open_all_ports "$2"
            ;;
        "custom")
            if [ -z "$2" ]; then
                print_error "Port number required for custom configuration"
                print_info "Usage: $0 custom <port> [protocol] [security-group-id] [description]"
                exit 1
            fi
            configure_custom_port "$2" "$3" "$4" "$5"
            ;;
        "show")
            show_open_ports
            ;;
        "sg-show")
            show_security_group_rules "$2"
            ;;
        "help"|"--help"|"-h")
            cat << EOF
AWS Port Configuration Script for mldl Environment

Usage: $0 <command> [arguments]

Commands:
    all [security-group-id]              Configure all default ports for the scheduler
    custom <port> [protocol] [sg-id] [description]  Configure a custom port
    show                                 Show currently open ports on the system
    sg-show [security-group-id]         Show AWS Security Group rules
    help                                 Show this help message

Examples:
    # Configure all default ports
    sudo $0 all

    # Configure all default ports with AWS Security Group
    sudo $0 all sg-0123456789abcdef

    # Configure a custom port 8080
    sudo $0 custom 8080

    # Configure custom port with AWS Security Group
    sudo $0 custom 8080 tcp sg-0123456789abcdef "Custom app port"

    # Show open ports
    $0 show

    # Show AWS Security Group rules
    $0 sg-show sg-0123456789abcdef

Default Ports:
    5000  - Flask development server
    8000  - Gunicorn production server
    80    - Nginx HTTP
    443   - Nginx HTTPS

Note:
    - Run with sudo for local firewall configuration
    - AWS CLI must be configured for security group management
    - Ensure you have proper AWS IAM permissions

EOF
            ;;
        *)
            print_error "Unknown command: $1"
            print_info "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -eq 0 ]; then
        print_error "No command provided"
        print_info "Run '$0 help' for usage information"
        exit 1
    fi
    main "$@"
fi
