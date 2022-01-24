from aws_cdk import (
    core,
    aws_ec2,
    aws_iam,
    aws_ecr_assets
)


# https://www.sentiatechblog.com/acm-for-nitro-enclaves-how-secure-are-they
# https://github.com/aws/aws-nitro-enclaves-sdk-c/blob/main/docs/kmstool.md
class NitroWalletStack(core.Stack):

    def __init__(self, scope: core.Construct, construct_id: str, **kwargs) -> None:
        params = kwargs.pop('params')
        super().__init__(scope, construct_id, **kwargs)

        key_alias = core.CfnParameter(self, "keyid", type="String",
                                      description="The KMS key id to be "
                                                  "used as a ethereum private key")

        signing_server_image = aws_ecr_assets.DockerImageAsset(self, "EthereumSigningServerImage",
                                                               directory="./application/server"
                                                               )

        vpc = aws_ec2.Vpc(self, 'VPC',
                          nat_gateways=1,
                          subnet_configuration=[aws_ec2.SubnetConfiguration(name='public',
                                                                            subnet_type=aws_ec2.SubnetType.PUBLIC),
                                                aws_ec2.SubnetConfiguration(name='private',
                                                                            subnet_type=aws_ec2.SubnetType.PRIVATE)
                                                ],
                          enable_dns_support=True,
                          enable_dns_hostnames=True)

        kms_endpoint = aws_ec2.InterfaceVpcEndpoint(
            self, "KMSEndpoint",
            vpc=vpc,
            subnets=aws_ec2.SubnetSelection(subnet_type=aws_ec2.SubnetType.PRIVATE),
            service=aws_ec2.InterfaceVpcEndpointAwsService.KMS,
            private_dns_enabled=True
        )

        secrets_manager_endpoint = aws_ec2.InterfaceVpcEndpoint(
            self, "SecretsManagerEndpoint",
            vpc=vpc,
            subnets=aws_ec2.SubnetSelection(subnet_type=aws_ec2.SubnetType.PRIVATE),
            service=aws_ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
            private_dns_enabled=True
        )

        ssm_endpoint = aws_ec2.InterfaceVpcEndpoint(
            self, 'SSMEndpoint',
            vpc=vpc,
            subnets=aws_ec2.SubnetSelection(subnet_type=aws_ec2.SubnetType.PRIVATE),
            service=aws_ec2.InterfaceVpcEndpointAwsService.SSM,
            private_dns_enabled=True
        )

        ecr_endpoint = aws_ec2.InterfaceVpcEndpoint(
            self, 'ECREndpoint',
            vpc=vpc,
            subnets=aws_ec2.SubnetSelection(subnet_type=aws_ec2.SubnetType.PRIVATE),
            service=aws_ec2.InterfaceVpcEndpointAwsService.ECR,
            private_dns_enabled=True
        )

        subnet = vpc.private_subnets[0]
        private_sg = aws_ec2.SecurityGroup(
            self,
            "NitroWalletPrivateSG",
            vpc=vpc,
            allow_all_outbound=True,
            description="Private SG for NitroWallet EC2 instance")

        # AMI
        amzn_linux = aws_ec2.MachineImage.latest_amazon_linux(
            generation=aws_ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
        ).get_image(self)

        # Instance Role and SSM Managed Policy
        role = aws_iam.Role(self, "InstanceSSM",
                            assumed_by=aws_iam.ServicePrincipal("ec2.amazonaws.com")
                            )
        role.add_managed_policy(aws_iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonEC2RoleforSSM"))

        kms_sign_policy = aws_iam.PolicyStatement(actions=["kms:Sign"],
                                                  resources=["arn:aws:kms:{}:{}:key/{}".format(self.region,
                                                                                               self.account,
                                                                                               key_alias.to_string())],
                                                  effect=aws_iam.Effect.ALLOW
                                                  )

        role.add_to_principal_policy(kms_sign_policy)

        ec2_iam_instance_profile = aws_iam.CfnInstanceProfile(self, 'InstanceProfile_EC2',
                                                              roles=[role.role_name],
                                                              instance_profile_name="InstanceProfile_EC2")

        # network_interface = aws_ec2.CfnInstance.NetworkInterfaceProperty(
        #     device_index='0',
        #     associate_public_ip_address=True,
        #     subnet_id=subnet.subnet_id,
        #     group_set=[public_sg.security_group_id],
        # )

        network_interface = aws_ec2.CfnInstance.NetworkInterfaceProperty(
            device_index='0',
            associate_public_ip_address=False,
            subnet_id=subnet.subnet_id,
            group_set=[private_sg.security_group_id],
        )

        block_device = aws_ec2.CfnInstance.BlockDeviceMappingProperty(device_name="/dev/xvda",
                                                                      ebs=aws_ec2.CfnInstance.EbsProperty(
                                                                          delete_on_termination=False,
                                                                          volume_size=32,
                                                                          volume_type='gp2',
                                                                          encrypted=True
                                                                      ))

        # pull and build efi image
        mappings = {"__DEV_MODE__": params["deployment"],
                    "__SIGNING_SERVER_IMAGE_URI__": signing_server_image.image_uri}

        with open("./user_data/user_data.sh") as f:
            user_data_raw = core.Fn.sub(f.read(), mappings)

        instance = aws_ec2.CfnInstance(self, 'NitroEC2Instance',
                                       instance_type=aws_ec2.InstanceType("m5a.xlarge").to_string(),
                                       user_data=core.Fn.base64(user_data_raw),
                                       enclave_options=aws_ec2.CfnInstance.EnclaveOptionsProperty(enabled=True),
                                       image_id=amzn_linux.image_id,
                                       network_interfaces=[network_interface],
                                       block_device_mappings=[block_device],
                                       iam_instance_profile=ec2_iam_instance_profile.instance_profile_name
                                       )

        signing_server_image.repository.grant_pull(role)

        core.CfnOutput(
            self,
            'EC2 Instance ID',
            value=instance.ref,
            description="Nitro EC2 Instance ID"
        )
