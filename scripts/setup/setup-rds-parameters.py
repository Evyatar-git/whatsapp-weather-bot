#!/usr/bin/env python3
"""
RDS Database Parameters Setup Script
Creates RDS connection parameters in AWS Parameter Store
"""

import boto3
import sys
import getpass
from botocore.exceptions import ClientError

# Colors for output
class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color

def print_colored(message, color=Colors.NC):
    print(f"{color}{message}{Colors.NC}")

def get_rds_info():
    """Get RDS information from Terraform or AWS."""
    import subprocess
    import os
    
    # Try to get from Terraform
    terraform_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'terraform', 'environments', 'dev')
    
    rds_info = {
        'host': None,
        'port': '5432',
        'name': 'weatherbot',
        'username': 'postgres',
        'password': None
    }
    
    try:
        # Get RDS endpoint from Terraform
        result = subprocess.run(
            ['terraform', 'output', '-raw', 'rds_endpoint'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            rds_info['host'] = result.stdout.strip()
        
        # Get RDS port
        result = subprocess.run(
            ['terraform', 'output', '-raw', 'rds_port'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            rds_info['port'] = result.stdout.strip()
        
        # Get database name
        result = subprocess.run(
            ['terraform', 'output', '-raw', 'rds_database_name'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            rds_info['name'] = result.stdout.strip()
        
        # Get password from Terraform state
        result = subprocess.run(
            ['terraform', 'state', 'show', 'random_password.rds_password[0]'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'result' in line and '=' in line:
                    rds_info['password'] = line.split('=')[1].strip().strip('"')
    except Exception as e:
        print_colored(f"Warning: Could not get all info from Terraform: {e}", Colors.YELLOW)
    
    # If host not found, try AWS directly
    if not rds_info['host']:
        try:
            rds = boto3.client('rds', region_name='us-east-1')
            response = rds.describe_db_instances(DBInstanceIdentifier='weather-bot-db')
            db = response['DBInstances'][0]
            rds_info['host'] = db['Endpoint']['Address']
            rds_info['port'] = str(db['Endpoint']['Port'])
            rds_info['name'] = db.get('DBName', 'weatherbot')
            rds_info['username'] = db['MasterUsername']
        except Exception as e:
            print_colored(f"Error getting RDS info from AWS: {e}", Colors.RED)
            sys.exit(1)
    
    return rds_info

def create_parameter(ssm, param_name, param_value, param_type='String', description=''):
    """Create or update an SSM parameter."""
    try:
        # Check if parameter exists
        try:
            ssm.get_parameter(Name=param_name)
            print_colored(f"  Parameter exists, updating: {param_name}", Colors.YELLOW)
            overwrite = True
        except ClientError as e:
            if e.response['Error']['Code'] == 'ParameterNotFound':
                overwrite = False
            else:
                raise
        
        ssm.put_parameter(
            Name=param_name,
            Value=param_value,
            Type=param_type,
            Description=description,
            Overwrite=overwrite
        )
        print_colored(f"  ✓ {'Updated' if overwrite else 'Created'}: {param_name}", Colors.GREEN)
        return True
    except ClientError as e:
        print_colored(f"  ✗ Failed to create {param_name}: {e}", Colors.RED)
        return False

def main():
    print_colored("=== RDS Database Parameters Setup ===\n", Colors.BLUE)
    
    # Check AWS credentials
    try:
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        print_colored(f"AWS CLI configured (Account: {identity.get('Account')})\n", Colors.GREEN)
    except Exception as e:
        print_colored(f"Error: AWS CLI not configured: {e}", Colors.RED)
        sys.exit(1)
    
    # Get RDS information
    print_colored("Retrieving RDS instance details...", Colors.BLUE)
    rds_info = get_rds_info()
    
    if not rds_info['host']:
        print_colored("Error: Could not retrieve RDS endpoint", Colors.RED)
        sys.exit(1)
    
    print_colored(f"✓ RDS Endpoint: {rds_info['host']}", Colors.GREEN)
    print_colored(f"✓ RDS Port: {rds_info['port']}", Colors.GREEN)
    print_colored(f"✓ Database Name: {rds_info['name']}", Colors.GREEN)
    print_colored(f"✓ Username: {rds_info['username']}\n", Colors.GREEN)
    
    # Get password if not found
    if not rds_info['password']:
        print_colored("Password not found in Terraform state", Colors.YELLOW)
        rds_info['password'] = getpass.getpass("Enter RDS master password: ")
        if not rds_info['password']:
            print_colored("Error: Password cannot be empty", Colors.RED)
            sys.exit(1)
    else:
        print_colored("✓ Password found in Terraform state\n", Colors.GREEN)
    
    # Create SSM client
    ssm = boto3.client('ssm', region_name='us-east-1')
    
    # Create all parameters
    print_colored("Creating database parameters in Parameter Store...\n", Colors.BLUE)
    
    params = [
        ('/weather-bot/database/host', rds_info['host'], 'String', 'RDS PostgreSQL host endpoint'),
        ('/weather-bot/database/port', rds_info['port'], 'String', 'RDS PostgreSQL port'),
        ('/weather-bot/database/name', rds_info['name'], 'String', 'RDS PostgreSQL database name'),
        ('/weather-bot/database/username', rds_info['username'], 'String', 'RDS PostgreSQL master username'),
        ('/weather-bot/database/password', rds_info['password'], 'SecureString', 'RDS PostgreSQL master password'),
    ]
    
    success_count = 0
    for param_name, param_value, param_type, description in params:
        if create_parameter(ssm, param_name, param_value, param_type, description):
            success_count += 1
    
    print()
    if success_count == len(params):
        print_colored("=== All database parameters created successfully! ===\n", Colors.GREEN)
        print_colored("Summary:", Colors.BLUE)
        print_colored(f"  Host: {rds_info['host']}", Colors.NC)
        print_colored(f"  Port: {rds_info['port']}", Colors.NC)
        print_colored(f"  Database: {rds_info['name']}", Colors.NC)
        print_colored(f"  Username: {rds_info['username']}", Colors.NC)
        print_colored(f"  Password: {'*' * len(rds_info['password'])} (stored securely)\n", Colors.GREEN)
        print_colored("Next steps:", Colors.BLUE)
        print_colored("1. Deploy application to EKS using Helm", Colors.NC)
        print_colored("2. Application will automatically retrieve these parameters", Colors.NC)
        print_colored("3. Verify database connection in application logs\n", Colors.NC)
    else:
        print_colored(f"Warning: Only {success_count}/{len(params)} parameters were created", Colors.YELLOW)
        sys.exit(1)

if __name__ == '__main__':
    main()

