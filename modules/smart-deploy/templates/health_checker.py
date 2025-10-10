import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROJECT_NAME = "${project_name}"
ENVIRONMENT = "${environment}"

ecs_client = boto3.client('ecs')
ecr_client = boto3.client('ecr')
cloudwatch_client = boto3.client('cloudwatch')

def lambda_handler(event, context):
    
    try:
        logger.info(f"Iniciando verificação de saúde programada - Projeto: {PROJECT_NAME}, Ambiente: {ENVIRONMENT}")
        
        services = [
            "front",
            "admins-api", 
            "checkout-api",
            "members-api",
            "users-api",
            "webhooks-api"
        ]
        
        results = {}
        overall_health = True
        
        for service in services:
            logger.info(f"Verificando serviço: {service}")
            service_health = check_service_health(service)
            results[service] = service_health
            
            if not service_health.get('healthy', False):
                overall_health = False
        
        send_metrics(results, overall_health)
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'project': PROJECT_NAME,
                'environment': ENVIRONMENT,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'overall_health': overall_health,
                'services': results,
                'summary': {
                    'total_services': len(services),
                    'healthy_services': sum(1 for r in results.values() if r.get('healthy', False)),
                    'unhealthy_services': sum(1 for r in results.values() if not r.get('healthy', False))
                }
            }, indent=2)
        }
        
        logger.info(f"Verificação concluída - Status geral: {'Saudável' if overall_health else 'Problemático'}")
        return response
        
    except Exception as e:
        logger.error(f"Erro na verificação de saúde: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }

def check_service_health(service_name: str) -> Dict[str, Any]:
    
    health_result = {
        'service_name': service_name,
        'healthy': False,
        'checks': {},
        'timestamp': datetime.now(timezone.utc).isoformat()
    }
    
    try:
        ecr_check = check_ecr_image(service_name)
        health_result['checks']['ecr'] = ecr_check
        
        ecs_check = check_ecs_service(service_name)
        health_result['checks']['ecs'] = ecs_check
        
        health_result['healthy'] = ecr_check.get('exists', False) and ecs_check.get('healthy', False)
        
    except Exception as e:
        logger.error(f"Erro ao verificar serviço {service_name}: {str(e)}")
        health_result['error'] = str(e)
    
    return health_result

def check_ecr_image(service_name: str) -> Dict[str, Any]:
    
    try:
        repository_name = f"{PROJECT_NAME}/{service_name}"
        
        ecr_client.describe_repositories(repositoryNames=[repository_name])
        
        response = ecr_client.describe_images(
            repositoryName=repository_name,
            imageIds=[{'imageTag': 'latest'}]
        )
        
        if response.get('imageDetails'):
            image_detail = response['imageDetails'][0]
            return {
                'exists': True,
                'push_date': image_detail.get('imagePushedAt', '').isoformat() if image_detail.get('imagePushedAt') else '',
                'size_bytes': image_detail.get('imageSizeInBytes', 0),
                'registry_id': image_detail.get('registryId', ''),
                'repository_name': repository_name
            }
        else:
            return {'exists': False, 'repository_name': repository_name}
            
    except ecr_client.exceptions.RepositoryNotFoundException:
        return {'exists': False, 'error': 'Repository not found', 'repository_name': repository_name}
    except ecr_client.exceptions.ImageNotFoundException:
        return {'exists': False, 'error': 'Image not found', 'repository_name': repository_name}
    except Exception as e:
        return {'exists': False, 'error': str(e), 'repository_name': repository_name}

def check_ecs_service(service_name: str) -> Dict[str, Any]:
    try:
        cluster_name = f"{PROJECT_NAME}-cluster"
        ecs_service_name = f"{PROJECT_NAME}-{service_name}"
        
        cluster_response = ecs_client.describe_clusters(clusters=[cluster_name])
        if not cluster_response.get('clusters') or cluster_response['clusters'][0]['status'] != 'ACTIVE':
            return {'healthy': False, 'error': 'Cluster not active or not found'}
        
        service_response = ecs_client.describe_services(
            cluster=cluster_name,
            services=[ecs_service_name]
        )
        
        if not service_response.get('services'):
            return {'healthy': False, 'error': 'Service not found'}
        
        service = service_response['services'][0]
        running_count = service.get('runningCount', 0)
        desired_count = service.get('desiredCount', 0)
        status = service.get('status', 'UNKNOWN')
        
        tasks_response = ecs_client.list_tasks(
            cluster=cluster_name,
            serviceName=ecs_service_name,
            desiredStatus='RUNNING'
        )
        
        healthy_tasks = 0
        if tasks_response.get('taskArns'):
            tasks_detail = ecs_client.describe_tasks(
                cluster=cluster_name,
                tasks=tasks_response['taskArns']
            )
            
            for task in tasks_detail.get('tasks', []):
                if task.get('lastStatus') == 'RUNNING' and task.get('healthStatus') in ['HEALTHY', 'UNKNOWN']:
                    healthy_tasks += 1
        
        is_healthy = (
            status == 'ACTIVE' and
            running_count == desired_count and 
            desired_count > 0 and
            healthy_tasks >= desired_count
        )
        
        return {
            'healthy': is_healthy,
            'status': status,
            'running_count': running_count,
            'desired_count': desired_count,
            'healthy_tasks': healthy_tasks,
            'cluster_name': cluster_name,
            'service_name': ecs_service_name
        }
        
    except Exception as e:
        return {'healthy': False, 'error': str(e)}

def send_metrics(results: Dict[str, Dict], overall_health: bool):
    try:
        namespace = f"{PROJECT_NAME}/HealthCheck"
        timestamp = datetime.now(timezone.utc)
        
        cloudwatch_client.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': 'OverallHealth',
                    'Value': 1 if overall_health else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': ENVIRONMENT},
                        {'Name': 'Project', 'Value': PROJECT_NAME}
                    ]
                }
            ]
        )
        
        metric_data = []
        for service_name, health_data in results.items():
            metric_data.extend([
                {
                    'MetricName': 'ServiceHealth',
                    'Value': 1 if health_data.get('healthy', False) else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': ENVIRONMENT},
                        {'Name': 'Project', 'Value': PROJECT_NAME},
                        {'Name': 'Service', 'Value': service_name}
                    ]
                },
                {
                    'MetricName': 'ECRImageExists',
                    'Value': 1 if health_data.get('checks', {}).get('ecr', {}).get('exists', False) else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': ENVIRONMENT},
                        {'Name': 'Project', 'Value': PROJECT_NAME},
                        {'Name': 'Service', 'Value': service_name}
                    ]
                }
            ])
            
            ecs_data = health_data.get('checks', {}).get('ecs', {})
            if 'running_count' in ecs_data:
                metric_data.append({
                    'MetricName': 'ECSRunningTasks',
                    'Value': ecs_data['running_count'],
                    'Unit': 'Count',
                    'Timestamp': timestamp,
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': ENVIRONMENT},
                        {'Name': 'Project', 'Value': PROJECT_NAME},
                        {'Name': 'Service', 'Value': service_name}
                    ]
                })
        
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cloudwatch_client.put_metric_data(
                Namespace=namespace,
                MetricData=batch
            )
        
        logger.info(f"Métricas enviadas para CloudWatch: {len(metric_data)} métricas")
        
    except Exception as e:
        logger.error(f"Erro ao enviar métricas: {str(e)}")