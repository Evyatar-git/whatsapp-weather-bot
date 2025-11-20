import logging
from typing import Optional

import boto3

logger = logging.getLogger(__name__)

class ParameterStoreClient:
    def __init__(self, region_name: str = "us-east-1"):
        self.region_name = region_name
        self.client = boto3.client('ssm', region_name=region_name)
        self.prefix = "weather-bot"
    
    def get_parameter(self, parameter_name: str, with_decryption: bool = True) -> Optional[str]:
        """Get a parameter from AWS Parameter Store."""
        try:
            full_name = f"{self.prefix}-{parameter_name}"
            response = self.client.get_parameter(
                Name=full_name,
                WithDecryption=with_decryption
            )
            value = response.get('Parameter', {}).get('Value')
            return str(value) if value is not None else None
        except Exception as e:
            logger.error(f"Failed to get parameter {parameter_name}: {str(e)}")
            return None
    
    def get_parameters(self, parameter_names: list) -> dict:
        """Get multiple parameters from AWS Parameter Store."""
        try:
            full_names = [f"{self.prefix}-{name}" for name in parameter_names]
            response = self.client.get_parameters(
                Names=full_names,
                WithDecryption=True
            )
            
            result = {}
            for param in response['Parameters']:
                original_name = param['Name'].replace(f"{self.prefix}-", "")
                result[original_name] = param['Value']
            
            return result
        except Exception as e:
            logger.error(f"Failed to get parameters {parameter_names}: {str(e)}")
            return {}

# Global instance
parameter_store = ParameterStoreClient()
