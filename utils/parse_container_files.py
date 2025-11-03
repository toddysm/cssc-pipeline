import os
import yaml

def list_files_in_directory(directory):
    file_list = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            file_path = os.path.join(root, file)
            file_list.append(file_path)
    return file_list

def is_dockerfile(filename):
    try:
        with open(filename, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#'):
                    return line.startswith('FROM ')
    except FileNotFoundError:
        return False

def is_docker_compose_file(filename):
    try:
        with open(filename, 'r') as file:
            compose_data = yaml.safe_load(file)
            return 'services' in compose_data
    except (FileNotFoundError, yaml.YAMLError):
        return False

def is_helm_chart(directory):
    chart_yaml_path = os.path.join(directory, 'Chart.yaml')
    return os.path.exists(chart_yaml_path)

def find_values_yaml_files(directory):
    values_yaml_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file == "values.yaml":
                values_yaml_files.append(os.path.join(root, file))
    return values_yaml_files

def has_kubernetes_deployments(directory):
    deployment_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(('.yaml', '.yml', '.json')) and "deployment" in file.lower():
                deployment_files.append(os.path.join(root, file))
    return deployment_files

def is_valid_kubernetes_deployment(file_path):
    try:
        with open(file_path, 'r') as file:
            manifest = yaml.safe_load(file)
            if manifest is not None:
                # Check if the manifest contains a Kubernetes Deployment kind.
                if manifest.get('kind', '') == 'Deployment':
                    return True
    except (FileNotFoundError, yaml.YAMLError):
        return False

def find_container_images(deployment_file):
    try:
        with open(deployment_file, 'r') as file:
            deployment_data = yaml.safe_load(file)
            if 'spec' in deployment_data and 'template' in deployment_data['spec'] \
                and 'spec' in deployment_data['spec']['template'] \
                and 'containers' in deployment_data['spec']['template']['spec']:
                containers = deployment_data['spec']['template']['spec']['containers']
                image_references = [container['image'] for container in containers]
                return image_references
            else:
                return []
    except (FileNotFoundError, yaml.YAMLError):
        return []

# Replace 'your_directory_path' with the path of the directory you want to search in.
directory_path = '/Users/toddysm/Documents/Development/cssc-pipeline'
if os.path.exists(directory_path):
    files = list_files_in_directory(directory_path)
    for file in files:
        print(file)
else:
    print("Directory not found.")
