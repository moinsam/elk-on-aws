# Deploy ELK Stack to Amazon ECS


## Introduction
In this article we will discuss how we self-deployed [ELK Stack](https://www.elastic.co/what-is/elk-stack) on [Amazon ECS](https://aws.amazon.com/ecs/) by using [AWS Cloud Formation](https://aws.amazon.com/cloudformation/) to help us create the required resources.

There are many other possibilities to use the **ELK Stack** in your environment, from deploying it manually to your **preferred servers** to using one of the available cloud solutions like [AWS Elasticsearch Service](https://aws.amazon.com/elasticsearch-service/) or [Elastic Cloud](https://www.elastic.co/cloud/).

I believe, that there is no one option better than the other, but you may choose the one that fits you. Several factors which can help you decide which method to choose may be:

- Amount of time you want to spend setting up, deploying, upgrading and managing the cluster;
- Amount of resources you will need (e.g. CPU or Storage);
- Amount of money you are ready to spent (cloud solutions may be very easy to setup & manage, but they may become expansive when you require a lot of resources);
- The license type you are ready to submit to;
- Also, of course, **confidentiality** of your data;

We are submitted to using AWS for production but also everything we do should be “easily expatriated” to other hosting service. Based on this and other factors, we choose to deploy our **ELK Stack** to **AWS EC2 instances**.

## Stacks

**AWS Cloud Formation** supports creating and linking multiple stacks in order to build the infrastructure. Therefore, we have separated everything we create in the following parts:

1. Amazon ECR Repository: [ecr](https://github.com/KetekSoftware/elk-on-aws/tree/main/ecr);
2. Amazon ECS Cluster (+ Auto Scaling Group, Security Groups etc.): [ecs](https://github.com/KetekSoftware/elk-on-aws/tree/main/ecs);
3. Elasticsearch-bootstrap [elasticsearch-bootstrap](https://github.com/KetekSoftware/elk-on-aws/tree/main/elasticsearch-bootstrap);
4. Elasticsearch [elasticsearch](https://github.com/KetekSoftware/elk-on-aws/tree/main/elasticsearch);
5. Kibana [kibana](https://github.com/KetekSoftware/elk-on-aws/tree/main/kibana);
6. Logstash [logstash](https://github.com/KetekSoftware/elk-on-aws/tree/main/logstash);

For each of the above point a different YAML which describes an AWS Cloud Formation Stack will be deployed in the exact order.

## Deploying

Usually for each stack we have the following files:

- **service.yaml** – the resources to be created on **AWS** through this stack;
- **service.params.json** – value of the parameters required by the stack;
- **services.deploy.sh** – creates / updates the stack on **AWS** by using [AWS CLI](https://aws.amazon.com/cli/);
- **(optional) Dockerfile** – describes the image which will be uploaded to **Amazon ECR** and used to startup Amazon ECS service;
- **(optional) files** – other files required by the service which will be copied to image while building it;
- **(optional) service-build.sh** – builds up the image using the **Dockerfile** and pushes it to **Amazon ECR** in order to be used by **service.yaml**;

### 1. Amazon ECR Repositories

This stack is the simplest one and we only run it once to create the resources.

We are creating 3 repositories:

- **ESRepository** : *AWSAccountId.dkr.ecr.us-west-2.amazonaws.com/elastic/es*
- **KibanaRepository** : *AWSAccountId.dkr.ecr.us-west-2.amazonaws.com/elastic/kibana*
- **LogstashRepository** : *AWSAccountId.dkr.ecr.us-west-2.amazonaws.com/elastic/logstash*

The stack requires 2 parameters: **AWSAccountId** and **AWSECRAdminUser** in order to specify the principal/owner of the repositories which are found into `elastic-ecr.params.json`:

```json
[
  {
    "ParameterKey": "AWSAccountId", 
    "ParameterValue": "THE_AWS_ACCOUNT_ID"
  }, 
  {
    "ParameterKey": "AWSECRAdminUser", 
    "ParameterValue": "USER"
  }
]
```

Update the parameter values with your data, re-check the `elastic-ecr.yaml` file (the complete files are in the repository):

```yaml
AWSTemplateFormatVersion: 2010-09-09
Parameters:
  ...
Resources:
  ESRepository:
    Type: 'AWS::ECR::Repository'
    Properties:
      RepositoryName: elastic/es
      RepositoryPolicyText:
        Version: 2008-10-17
        Statement:
          - Sid: AllowPushPull
            Effect: Allow
            Principal:
              AWS:
                - !Join
                  - ''
                  - - 'arn:aws:iam::'
                    - !Ref AWSAccountId
                    - ':user/'
                    - !Ref AWSECRAdminUser
            Action:
              ...
  KibanaRepository:
    ...
  LogstashRepository:
    ...
Outputs:
  ...
```

Now update the stack name as you wish in the `elastic-ecr.deploy.sh` file:

```shell
STACK_NAME=elastic-ecr

if ! aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
  aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://elastic-ecr.yaml --parameters file://elastic-ecr.params.json
else
  aws cloudformation update-stack --stack-name $STACK_NAME --template-body file://elastic-ecr.yaml --parameters file://elastic-ecr.params.json
fi
```

Before running any **AWS CLI** command, make sure you authenticate. For more information, please check the [configuring **AWS CLI** page](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html):

Finally, run the bash script to start the stack:

```shell
./elastic-ecr.deploy.sh
```

Watch the [AWS Cloud Formation Console](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-using-console.html) that your stack successfully run and all resources are created.

![AWS Cloud Formation Console](https://content.screencast.com/users/DanielGherasim/folders/Capture/media/a3bed390-0bbf-4f1b-96a1-cafc6d5a9bd7/LWR_Recording.png)

### 2. Amazon ECS Cluster

We have prepared **Amazon ECR** repositories to push **Elasticsearch**, **Kibana** and **Logstash** images to on the previous step. Now, we will prepare the **Amazon ECS cluster** where we will deploy the images.

Please note we are talking about 2 clusters in this article which are totally different: one is the **Amazon ECS Cluster** which works as our docker images **orchestration tool**, the other is the **Elasticsearch Cluster** which will be formed of multiple Elasticsearch instances deployed on different servers.

The stack requires 7 parameters:

- **KeyName** – name of the key uploaded to AWS that will be used for protecting the EC2 instances;
- **VpcId** – the Id of the VPC inside your AWS accounts that will be used for instances;
- **SubnetId** – list of subnets inside the VPC that can be used to launch instances on;
- **MaxSize** – the maximum size of instances in the Auto Scaling Group;
- **MinSize** – the minimum size of instances on the Auto Scaling Group;
- **DesiredCapacity** – the desired number of instances in the Auto Scaling Group;
- **InstanceType** – the type of instances to launch (e.g. t3.xlarge).

Update the parameters with the correct values in the `elastic-ecs.params.json` file.

We are going to launch a 2 nodes Elasticsearch cluster, therefore we are going to set MinSize, MaxSize and DesiredCapacity to 2.

Check the `elastic-ecs.yaml` file for all the resources that are going to be created:

```yaml
...
Resources:
  Cluster:
    Type: 'AWS::ECS::Cluster'
  SecurityGroup:
    ...
  SecurityGroupSSHinbound:
    ...
  SecurityGroupALLPorts:
    ...
  CloudwatchLogsGroup:
    ...
  EC2Role:
    ...
  AutoScalingGroup:
    ...
  LaunchConfiguration:
    ...
  ServiceRole:
    ...
  AutoscalingRole:
    ...
  EC2InstanceProfile:
    ...
Outputs:
  ...
```

Make sure you update the `elastic-esc.yaml` file as you prefer.

We are using the latest [Amazon Linux 2 ECS Optimized AMI](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html) currently, and we are launching 2 **c5a.large** instances with **50GB** each.

If you specify a different space for instances, make sure you also update the instance’s **UserData** to tell docker the amount of space available:

```shell
...
# Set Docker daemon options
cloud-init-per once docker_options echo 'OPTIONS="${!OPTIONS} --storage-opt dm.basesize=50G"' >> /etc/sysconfig/docker
...
```

Another important part is the **Elasticsearch tag** we are defining for the EC2 instances:

```yaml
AutoScalingGroup4:
  ...
  Properties:
    ...
    Tags:
      ...
      - Key: ElasticSearch
        Value: es
      ...
```

You will also find out the same value inside the `elasticsearch.yml` file where we tell the **Elasticsearch** cluster which uses the **discovery-ec2** plugin at what **EC2** instances to look for Elasticsearch nodes in order to attach them the cluster.

Also, we tell **EC2** instances to what **ECS Cluster** to connect through the following configuration:

```yaml
...
  LaunchConfiguration:
    Type: 'AWS::AutoScaling::LaunchConfiguration'
    Properties:
      ...
      UserData:
        Fn::Base64:
          Fn::Sub:
            - |
              ...
              # Set the ECS agent configuration options
              echo ECS_CLUSTER=${ClusterName} >> /etc/ecs/ecs.config
              echo ECS_RESERVED_MEMORY=256 >> /etc/ecs/ecs.config
              ...
            - ClusterName: !Ref Cluster
...
```

Finally, launch the stack by running the `elastic-ecs.deploy.sh` bash script:

```shell
./elastic-ecs.deploy.sh
```

Now, keep an eye on the **AWS Cloud Formation Console** that the stack is successfully created.

After that, check **AWS Amazon ECS Console** that the cluster exists and the **EC2 Instances** are ready to accept containers on them.

![Elastic ECS Cluster](https://content.screencast.com/users/DanielGherasim/folders/Capture/media/de526ad7-6b16-409c-9b19-f8a2a5fdcc56/LWR_Recording.png)

### 3. Elasticsearch-bootstrap

Now our **Amazon ECS Cluster** is ready to accept services and launch them on the existing instances.

You may wonder why there is an **Elasticsearch-bootstrap** service and not just the **Elasticsearch** service.

Well, that’s because **Elasticsearch Cluster** needs to elect a master node by **NAME** the first time it is started. Since we do not provide names for our **Elasticsearch Nodes**, we need to first start an instance of **Elasticsearch** with a name and tell it to select itself as the master node.

> It’s the only way at this moment I can start a cluster for the first time.

After launching the other **Elasticsearch Nodes** on step 4, we can safely remove this service.

First thing first we need the Dockerfile which will push our **Elasticsearch** image to **Amazon ECR**.

```shell
ARG ES_VERSION
FROM docker.elastic.co/elasticsearch/elasticsearch-oss:${ES_VERSION}
ENV REGION us-west-2
USER root
COPY --chown=elasticsearch:elasticsearch elasticsearch.yml /usr/share/elasticsearch/config/
COPY --chown=elasticsearch:elasticsearch ssl/esnode-key.pem /usr/share/elasticsearch/config/
COPY --chown=elasticsearch:elasticsearch ssl/esnode.pem /usr/share/elasticsearch/config/
COPY --chown=elasticsearch:elasticsearch ssl/kirk-key.pem /usr/share/elasticsearch/config/
COPY --chown=elasticsearch:elasticsearch ssl/kirk.pem /usr/share/elasticsearch/config/
COPY --chown=elasticsearch:elasticsearch ssl/root-ca.pem /usr/share/elasticsearch/config/
USER elasticsearch
WORKDIR /usr/share/elasticsearch
RUN bin/elasticsearch-plugin install -b discovery-ec2 && bin/elasticsearch-plugin install -b repository-s3 && sed -e '/^-Xm/s/^/#/g' -i /usr/share/elasticsearch/config/jvm.options
RUN bin/elasticsearch-plugin install -b https://d3g5vo6xdbdb9a.cloudfront.net/downloads/elasticsearch-plugins/opendistro-security/opendistro_security-1.12.0.0.zip
RUN bin/elasticsearch-plugin install -b https://d3g5vo6xdbdb9a.cloudfront.net/downloads/elasticsearch-plugins/opendistro-sql/opendistro_sql-1.12.0.0.zip
RUN echo "********" | bin/elasticsearch-keystore create -v
RUN echo "********" | bin/elasticsearch-keystore add s3.client.default.access_key
RUN echo "********" | bin/elasticsearch-keystore add s3.client.default.secret_key.
USER root
COPY --chown=elasticsearch:elasticsearch opendistro/internal_users.yml /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/
USER elasticsearch
```

As you can see, we’re using the **OSS** version of Elasticsearch (last one which was still on Apache2.0 is 7.10.0) along with the corresponding **Open Distro Security** and **Open Distro SQL** plugins from Amazon.

We are also copying some local files where we keep configuration for this Elasticsearch node and for the plugins:

- `opendistro/internal_users.yml`
- `ssl/*.pem`
- `elasticsearch.yml`

The piece of configuration which makes the difference between this **Elasticsearch-bootstrap** service and the **Elasticsearch** service is in `elasticsearch.yml` on the following 2 lines:

```yaml
cluster:
  ...
  initial_master_nodes:
  - election_node
node:
  name: election_node
```

Other important configurations will be explained when we will deploy the **Elasticsearch** service.

Before building and pushing the image to **Amazon ECR Docker Repository**, make sure you login to it:

```shell
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin THE_AWS_ACCOUNT_ID.dkr.ecr.ap-northeast-1.amazonaws.com
```

Now we use the following bash script to build the image and push it to the **ESRepository**:

```shell
#!/bin/bash
AWS_ACCOUNT_ID=THE_AWS_ACCOUNT_ID
AWS_DEFAULT_REGION=us-west-2
REPO_NAME=elastic/es
ES_VERSION=7.10.0
MAGE_TAG=7.1.1-bootstrap
eval $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email | sed 's|https://||')
docker build --build-arg ES_VERSION=$ES_VERSION -t $REPO_NAME:$ES_VERSION_TAG .
docker tag $REPO_NAME:$ES_VERSION_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$ES_VERSION_TAG
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$ES_VERSION_TAG
```

You should see now inside the **Amazon ECR Repository Console** the new image is uploaded.

Now that we have the image, we are ready to deploy the **Elasticserach-bootstrap** service. For that, we have the `elastic-es-bootstrap.yaml` file which will create the following resources:

```yaml
...
Resources:
  Service:
    Type: 'AWS::ECS::Service'
    ...
  TaskDefinition:
    Type: 'AWS::ECS::TaskDefinition'
    ...
  ...
...
```

As you can see, we are not going to create any Application Load Balancer or Target Group for this service since we are going to remove it anyway.

Now, we use `elastic-es-bootstrap.deploy.sh` file to start the stack:

```shell
#!/bin/bash
STACK_NAME=elastic-es-bootstrap

if ! aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
    aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://elastic-es-bootstrap.yaml --parameters file://elastic-es-bootstrap.params.json --capabilities CAPABILITY_IAM
else
    aws cloudformation update-stack --stack-name $STACK_NAME --template-body file://elastic-es-bootstrap.yaml --parameters file://elastic-es-bootstrap.params.json --capabilities CAPABILITY_IAM
fi
```

Name the stack as you wish and run the bash script:

```shell
./elastic-es-bootstrap.deploy.sh
```

At this moment, we need to wait for the stack to create the service inside **Amazon ECS Cluster** and the orchestration tool should place one container to one of the instances.

This step could take a while since the docker image needs to be downloaded to the instance.

You can check the **Amazon ECS Console** for the new service called **elastic-es-bootstrap-Service-CODE** and under the **Events** tab wait until it says:

```
service elastic-es-bootstrap-Service-CODE has reached a steady state.
```

If that happens, it means the **Elasticsearch-bootstrap** instance has been successfully launched at one of the instance.

At this point, I am going to check if the cluster is really up by doing the next steps:

- Connect to the **EC2 Instance** where **Elasticsearch-bootstrap** service has started the container;
- Check that container is up and running: `sudo docker ps -a`;
- Check cluster state: `curl -XGET "http://localhost:9200/_cat/health" -u username:password -k`
- You should see `yellow` state which is fine because we currently have just one node in the cluster.

If everything is fine, now we are ready for the next step.

### 4. Elasticsearch

Next we are going to deploy the **Elasticsearch** service which is going to start new nodes that will join the existing cluster already started at step 3.

The `Dockerfile` is identical with the Elasticsearch-boostrap service, but in the `es-build.sh` file we have `ES_VERSION_TAG=7.10.0` and not `ES_VERSION_TAG=7.1.1-bootstrap`:

```shell
#!/bin/bash
AWS_ACCOUNT_ID=THE_AWS_ACCOUNT_ID
AWS_DEFAULT_REGION=us-west-2
REPO_NAME=elastic-es
ES_VERSION=7.10.0
ES_VERSION_TAG=7.10.0
eval $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email | sed 's|https://||')
docker build --build-arg ES_VERSION=$ES_VERSION -t $REPO_NAME:$ES_VERSION_TAG .
docker tag $REPO_NAME:$ES_VERSION_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$ES_VERSION_TAG
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$ES_VERSION_TAG
```

Another difference is in the `elasticsearch.yml` file. We now do not specify any `cluster.initial_master_nodes` and no `node.name`. The rest of the configuration file is identical.

Now let’s discuss some parts of `elasticsearch.yml` file.

```yaml
cluster:
  name: elastic
  routing.allocation.awareness.attributes: aws_availability_zone
  routing.allocation.disk.threshold_enabled: false
  max_shards_per_node: 5100
```

As you can see, the `cluster.name` is important because the node will only join the cluster with the same name.

```yaml
node:
  data: true
  master: true
  max_local_storage_nodes: 1
```

We can also change configuration through environment variables which has a higher precedence.

All our **Elasticsearch** nodes are both data and master nodes.

```yaml
network:
  host: 0.0.0.0
  publish_host: _ec2:privateIp_
transport:
  publish_host: _ec2:privateIp_
```

Here we link the node with the private ip of the **EC2** instance.

```yaml
discovery:
  seed_providers: ec2
ec2:
  tag.ElasticSearch: es
  endpoint: ec2.${REGION}.amazonaws.com
  host_type: private_ip
  any_group: true
...
s3:
  client.default.endpoint: s3.${REGION}.amazonaws.com
```

As said when creating the **Auto Scaling Group** at step 2, the value of the `tag` parameter given to the **EC2** instances is important, since the discovery plugin will only search for **Elasticsearch** nodes installed on those **EC2** instances. If it found an **Elasticsearch** instance at port **9200** and the `cluster.name` is identical, the node **joins** the cluster.

The rest of the configurations are to configure the cluster for our needs and to configure the **Open Distro Plugins**.

We will now build and push the image to **Amazon ECR**:

```shell
./es-build.sh
```

Now we will update the `elastic-es.params.json` file:
```json
[
    {
        "ParameterKey": "AWSAccountId",
        "ParameterValue": "THE_AWS_ACCOUNT_ID"
    },
    {
        "ParameterKey": "SubnetId",
        "ParameterValue": "subnet-1,subnet-2,subnet-3"
    },
    {
        "ParameterKey": "BaseStackName",
        "ParameterValue": "elastic-ecs"
    },
    {
        "ParameterKey": "ESVersion",
        "ParameterValue": "7.10.0"
    },
    {
        "ParameterKey": "ESInstanceCount",
        "ParameterValue": "1"
    }
]
```


As you can see, we will only tell the service to start just 1 instance of **Elasticsearch**. We will increase it to 2 after we remove the **Elasticsearch-bootstrap** service.

Besides, the same resource created by the **Elasticsearch-bootstrap** service, this stack will also create an **Application Load Balancer** with specific **Listeners** and **Target Groups** since we will want to be able to externally access the cluster’s API:

```yaml
...
Resources:
    Service:
      ...
    TaskDefinition:
      ...
    SecurityGroup:
      ...
    AccessForLBToHosts:
      ...
    ESLB:
      ...
    ESLBListener:
      ...
    ESLBListenerRule:
      ...
    ESTG:
      ...
...
```

The following script starts the new service:

```shell
#!/bin/bash
STACK_NAME=elastic-es

if ! aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
  aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://elastic-es.yaml --parameters file://elastic-es.params.json --capabilities CAPABILITY_IAM
else
  aws cloudformation update-stack --stack-name $STACK_NAME --template-body file://elastic-es.yaml --parameters file://elastic-es.params.json --capabilities CAPABILITY_IAM
fi
```

We run it and wait for the service to start a new **Elasticsearch** node which should join the existing **Elasticsearch Cluster**.

```shell
./elastic-es.deploy.sh
```

At this moment, when we run again `curl -XGET "https://localhost:9200/_cat/health" -u username:password -k` we should see a green state of the cluster and 2 nodes in service.

The next step is to turn off the initial master node, started by the **Elasticsearch-bootstrap** service.

We will vote it for exclusion:

```shell
# Vote first node for exclusion by name:
curl -XPOST "http://localhost:9200/_cluster/voting_config_exclusions?node_names=election_node" -u username:password
```

Now we will simply remove the **elastic-es-boostrap** stack from the **AWS Cloud Formation Stack** which will remove the service from the **Amazon ECS** cluster and turn off the **Elasticsearch-bootstrap** node.

Next, we will increase **ESInstanceCount** to 2 in the `elastic-es.params.json` and re-run the command to update the stack:

```shell
./elastic-es.deploy.sh
```

Finally, we should see 2 nodes in service in the **Elasticsearch Cluster** and it’s state should turn back **green**.

```shell
curl -XGET "https://localhost:9200/_cat/health" -u username:password -k
curl -XGET "https://localhost:9200/_cat/nodes" -u username:password -k
```

At this point, the **Elasticsearch Cluster** is ready to ingest data.

### 5. Kibana
   Next we are going to launch a Kibana UI instance and connect it with the Elasticsearch Cluster.

The Dockerfile for creating the needed image is:

ARG KIBANA_VERSION
FROM docker.elastic.co/kibana/kibana-oss:${KIBANA_VERSION}
ENV REGION us-west-2
USER root
COPY --chown=kibana:kibana kibana.yml /usr/share/kibana/config/
COPY --chown=kibana:kibana ssl/esnode-key.pem /usr/share/kibana/config/
COPY --chown=kibana:kibana ssl/esnode.pem /usr/share/kibana/config/
COPY --chown=kibana:kibana ssl/root-ca.pem /usr/share/kibana/config/
USER kibana
WORKDIR /usr/share/kibana
RUN bin/kibana-plugin install https://d3g5vo6xdbdb9a.cloudfront.net/downloads/kibana-plugins/opendistro-security/opendistroSecurityKibana-1.12.0.0.zip
We will now use the following kibana-build.sh bash script to build and pus the image:

#!/bin/bash
AWS_ACCOUNT_ID=THE_AWS_ACCOUNT_ID
AWS_DEFAULT_REGION=us-west-2
REPO_NAME=elastic/kibana
KIBANA_VERSION=7.10.0
eval $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email | sed 's|https://||')
docker build --build-arg KIBANA_VERSION=$KIBANA_VERSION -t $REPO_NAME:$KIBANA_VERSION .
docker tag $REPO_NAME:$KIBANA_VERSION $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$KIBANA_VERSION
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$REPO_NAME:$KIBANA_VERSION
Run it:

./kibana-build.sh
The kibana.yml file contains some required configurations for setting up Kibana. Also, inside the ssl folder we find the same certificate used when launching Elasticsearch nodes .

The most important configurations are elasticsearch.hosts, elasticsearch.username and elasticsearch.password. But, we will set those through Environment Variables inside the Task Definition when we launch the containers.

In elastic-kibana.params.json we define the following parameters:

AWSAccountId – The Id of the AWS Account;
SubnetId – Subnet Ids to launch the Load Balancer in;
BaseStackName – The name of the based ECS stack – used to optain it’s outputs and link this to it’s resources;
KibanaVersion – The version of the Kibana image which is actually the tag of the image in Amazon ECR;
KibanaInstanceCount – Number of Kibana instances you want;
ESStackName – The name of the Elasticsearch stack to link with it’s resources.
Inside the elastic-kibana.yaml file, we define the ELASTICSEARCH_HOSTS environment variable to assign to the containers.

...
TaskDefinition:
Type: 'AWS::ECS::TaskDefinition'
Properties:
...
ContainerDefinitions:
...
Environment:
- Name: ELASTICSEARCH_HOSTS
  Value: "https://private_ip_of_one_EC2_instance:9200/"
  ...
  You can provide a private IP of one of the EC2 instances where Elasticserach is installed, or you can setup private DNS inside your VPC and map that DNS to the private IP.

Now launch the stack:

#!/bin/bash
STACK_NAME=elastic-kibana

if ! aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://elastic-kibana.yaml --parameters file://elastic-kibana.params.json --capabilities CAPABILITY_IAM
else
aws cloudformation update-stack --stack-name $STACK_NAME --template-body file://elastic-kibana.yaml --parameters file://elastic-kibana.params.json --capabilities CAPABILITY_IAM
fi
Run:

./elastic-kibana.deploy.sh
When the service is up and running, you should be able to access Kibana through the Application Load Balancer public DNS. You may setup your own DNS and map it to the load balancer.

6. Logstash
   Launching Logstash on the Amazon ECS cluster is similar with launching Kibana. Only that Logstash will not have any Load Balancer but just the Service and the Task Definition.

Make sure you define the proper logstash.conf file in the pipeline/logstash.conf file. In our case we are processing logs from several Application Load Balancers which pushes their logs on S3. Therefore, S3 Pluin of LogStash is used.

input {
s3 {
region => "us-west-2"
access_key_id => "ACCESS_KEY"
secret_access_key => "SECRET_KEY"
bucket => "bucket_name"
interval => 360
prefix => "AWSLogs/AWS_ACCOUNT_ID/elasticloadbalancing/us-west-2"
exclude_pattern => "/(.+)not-included-file(.+)/"
type => "s3_alb"
sincedb_path => "/usr/share/logstash/sincedbs/s3_alb"
}
}

filter {
grok {
match => ["message",
'%{NOTSPACE:request_type} %{TIMESTAMP_ISO8601:response_timestamp} %{NOTSPACE:alb_name} %{NOTSPACE:client} %{NOTSPACE:target} %{NOTSPACE:request_processing_time:float} %{NOTSPACE:target_processing_time:float} %{NOTSPACE:response_processing_time:float} %{NOTSPACE:elb_status_code} %{NOTSPACE:target_status_code} %{NOTSPACE:received_bytes:float} %{NOTSPACE:sent_bytes:float} %{QUOTEDSTRING:request} %{QUOTEDSTRING:user_agent} %{NOTSPACE:ssl_cipher} %{NOTSPACE:ssl_protocol} %{NOTSPACE:target_group_arn} %{QUOTEDSTRING:trace_id} "%{DATA:domain_name}" "%{DATA:chosen_cert_arn}" %{NUMBER:matched_rule_priority:int} %{TIMESTAMP_ISO8601:request_creation_time} "%{DATA:actions_executed}" "%{DATA:redirect_url}"( "%{DATA:error_reason}")?'
]
}

	mutate {
		add_field => { "loadbalancer_log" => "%{message}" }
		remove_field => ["message"]
	}

	mutate {
		remove_field => ["actions_executed", "redirect_url", "chosen_cert_arn", "domain_name", "error_reason", "matched_rule_priority", "target_group_arn", "ssl_cipher", "ssl_protocol" ]
	}

	date {
		match  => [ "response_timestamp", ISO8601 ]
	}
	
	mutate {
		gsub => [
			"request", '"', "",
			"trace_id", '"', "",
			"user_agent", '"', ""
		]
	}

	if [target] {
		grok {
			match => ["target", "(%{IPORHOST:target_ip})?(:)?(%{INT:target_port})?"]
		}
		mutate {
			remove_field => ["target" ]
		}
	}

	if [request] {
		grok {
			match => ["request", "(%{NOTSPACE:http_method})? (%{NOTSPACE:http_uri})? (%{NOTSPACE:http_version})?"]
		}
		mutate {
			remove_field => ["request", "http_version" ]
		}
	}		

	if [http_uri] {
		grok {
			match => ["http_uri", "(%{WORD:protocol})?(://)?(%{IPORHOST:domain})?(:)?(%{INT:http_port})?(%{GREEDYDATA:request_uri})?"]
		}
		mutate {
			remove_field => ["http_uri" ]
		}
	}

	if [client] {
		grok {
			match => ["client", "(%{IPORHOST:client_ip})?"]
		}
		mutate {
			remove_field => ["client" ]
		}
	}

	if [trace_id] {
		grok {
			match => [ "trace_id", "(Self=%{NOTSPACE:trace_id_self})?(;)?Root=%{NOTSPACE:trace_id_root}" ]
		}
		mutate {
			remove_field => ["trace_id" ]
		}
	}

	mutate {
		add_field => { "[@metadata][domain]" => "%{domain}" }
		add_field => { "[@metadata][alb_name]" => "%{alb_name}" }

		remove_field => ["type", "tags" ]
	}
}

output {
if [@metadata][domain] =~ /^.*example1\.domain.*$/ or [@metadata][alb_name] =~ /^.*alb1-name.*$/   {
elasticsearch {
hosts => ["https://private_ip_or_private_DNS:9200"]
index => "example1.domain.lb-%{+YYYY.MM}"
retry_on_conflict => 5
user => "user"
password => "password"
ssl => true
ssl_certificate_verification => false
cacert => "/usr/share/logstash/config/root-ca.pem"
ilm_enabled => false
}
}
else if [@metadata][domain] =~ /^.*example2\.domain.*$/ or [@metadata][alb_name] =~ /^.*alb2-name.*$/ {
elasticsearch {
hosts => ["https://private_ip_or_private_DNS:9200"]
index => "example2.domain.lb-%{+YYYY.MM}"
retry_on_conflict => 5
user => "user"
password => "password"
ssl => true
ssl_certificate_verification => false
cacert => "/usr/share/logstash/config/root-ca.pem"
ilm_enabled => false
}
}
else  {
elasticsearch {
hosts => ["https://private_ip_or_private_DNS:9200"]
index => "unknown.domain.lb-%{+YYYY.MM}"
retry_on_conflict => 5
user => "user"
password => "password"
ssl => true
ssl_certificate_verification => false
cacert => "/usr/share/logstash/config/root-ca.pem"
ilm_enabled => false
}
}
}
Since we do not want duplicates if we restart Logstash and processing the logs into Elasticsearch, we use the sincedb_path => "/usr/share/logstash/sincedbs/s3_alb" file to keep track of the last date of the last processed file.

The Dockerfile for our Lostash is this one:

ARG LOGSTASH_VERSION
FROM docker.elastic.co/logstash/logstash-oss:${LOGSTASH_VERSION}
USER root
RUN rm -rf /usr/share/logstash/pipeline/
RUN rm -rf /usr/share/logstash/sincedbs/
COPY --chown=logstash:logstash pipeline/ /usr/share/logstash/pipeline/
COPY --chown=logstash:logstash sincedbs/ /usr/share/logstash/sincedbs/
COPY --chown=logstash:logstash ssl/root-ca.pem /usr/share/logstash/config/
COPY --chown=logstash:logstash config/logstash.yml /usr/share/logstash/config/

USER logstash
We build and push it to Amazon ECR:

./logstash-build.sh
Finally, we launch the stack which will launch the service:

./elastic-logstash.deploy.sh
Conclusion
I have explained part of what we did to launch the ELK Stack to Amazon ECS.

There might pe points I’ve missed, therefore, doing this requires good knowledge of the ECS Service and the ELK Stack.

Published files on GitHub do not contain sensitive information or in most cases it is censored.

Make sure you check everything and feel free to add your personal touch based on your needs.
