pipeline {
    agent any
    environment {
        // --- 1. Credentials and Fixed Parameters ---
        // Ensure 'aws-devops-credentials' ID matches your Jenkins credential setup
        AWS_CREDS   = credentials('aws-devops-credentials') 
        
        // These are the ONLY two variables you need to manually define here 
        // (or pull from Jenkins parameters) since AMI/Region are handled dynamically/by default.
        TF_REGION   = 'eu-west-2' // CHANGE THIS to your target region (must match your key-pair region)
        TF_KEY_PAIR = 'MyAwsKeyName'    // CHANGE THIS to your actual SSH key name in AWS
        
        // --- 2. Runtime Variables ---
        INSTANCE_IPS = '' // Used to pass the list of IPs between stages
    }
    
    stages {
        stage('Checkout Code') {
            steps {
                git url: 'https://github.com/YourUsername/devops-cluster-project.git', branch: 'main'
            }
        }
        
        stage('Terraform Apply (Provision Cluster & ALB)') {
            steps {
                dir('terraform') { 
                    // Configure AWS environment variables for Terraform
                    withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDS.keyId}", "AWS_SECRET_ACCESS_KEY=${AWS_CREDS.secret}"]) {
                        sh 'terraform init' 
                        
                        // Pass ONLY the required variables (region and key_pair_name)
                        sh "terraform apply -auto-approve -var 'aws_region=${TF_REGION}' -var 'key_pair_name=${TF_KEY_PAIR}'"
                        
                        // Get the array of IPs from Terraform output and format it for Ansible
                        script {
                            def ip_array_json = sh(returnStdout: true, script: 'terraform output -json all_instance_ips').trim()
                            def ip_list = new groovy.json.JsonSlurper().parseText(ip_array_json).join(',')
                            INSTANCE_IPS = ip_list 
                            echo "ALB DNS: ${sh(returnStdout: true, script: 'terraform output -raw alb_dns_name').trim()}"
                            echo "Cluster IPs: ${INSTANCE_IPS}"
                        }
                    }
                }
            }
        }
        
        stage('Ansible Configure (Docker & Nginx Deployment)') {
            steps {
                dir('ansible') { 
                    // 1. Create a dynamic inventory file
                    sh "echo '[all_cluster_nodes]' > inventory.ini"
                    script {
                        INSTANCE_IPS.split(',').each { ip ->
                            // Use 'ec2-user' for Amazon Linux or 'ubuntu' for Ubuntu AMI
                            sh "echo '${ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/${TF_KEY_PAIR}.pem' >> inventory.ini"
                        }
                    }
                    
                    // 2. Run the Ansible playbook on the cluster
                    sh 'ansible-playbook -i inventory.ini deploy_docker.yml'
                }
            }
        }
    }
    
    // --- COST CONTROL: Terraform Destroy (Runs every time, regardless of success) ---
    post {
        always {
            stage('Terraform Destroy (Cost Control)') {
                steps {
                    echo '*** STARTING TERRAFORM DESTROY TO MINIMIZE AWS CHARGES ***'
                    dir('terraform') {
                        withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDS.keyId}", "AWS_SECRET_ACCESS_KEY=${AWS_CREDS.secret}"]) {
                            // The destroy command must pass the same variables as the apply command!
                            sh "terraform destroy -auto-approve -var 'aws_region=${TF_REGION}' -var 'key_pair_name=${TF_KEY_PAIR}'"
                        }
                    }
                }
            }
        }
    }
}