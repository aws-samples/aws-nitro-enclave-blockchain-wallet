from aws_cdk import (
    core,
    aws_ec2,
    aws_iam
)

# todo provide new key pair
key_name = 'us_dev'

with open("./user_data/user_data.sh") as f:
    user_data = f.read()


# https://www.sentiatechblog.com/acm-for-nitro-enclaves-how-secure-are-they
# https://github.com/aws/aws-nitro-enclaves-sdk-c/blob/main/docs/kmstool.md
class NitroWalletStack(core.Stack):

    def __init__(self, scope: core.Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        key_alias = core.CfnParameter(self, "keyid", type="String",
                                      description="The KMS key id to be "
                                                  "used as a ethereum private key")

        # VPC
        vpc = aws_ec2.Vpc(self, 'VPC',
                          nat_gateways=0,
                          subnet_configuration=[aws_ec2.SubnetConfiguration(name='public',
                                                                            subnet_type=aws_ec2.SubnetType.PUBLIC)])

        subnet = vpc.public_subnets[0]

        # ssh access for ec2 instance
        public_sg = aws_ec2.SecurityGroup(
            self,
            "SSH_SG",
            vpc=vpc,
            allow_all_outbound=True,
            description="SG for SSH access to amb client EC2 instance")

        public_sg.add_ingress_rule(aws_ec2.Peer.any_ipv4(),
                                   connection=aws_ec2.Port.tcp(22),
                                   description="ssh")

        # AMI
        amzn_linux = aws_ec2.MachineImage.latest_amazon_linux(
            generation=aws_ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
        ).get_image(self)

        # Instance Role and SSM Managed Policy
        role = aws_iam.Role(self, "InstanceSSM",
                            assumed_by=aws_iam.ServicePrincipal("ec2.amazonaws.com"),
                            role_name='testrole')
        role.add_managed_policy(aws_iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonEC2RoleforSSM"))

        kms_sign_policy = aws_iam.PolicyStatement(actions=["kms:Sign"],
                                                  resources=["arn:aws:kms:{}:{}:key/{}".format(kwargs['env'].region,
                                                                                               kwargs['env'].account,
                                                                                               key_alias.to_string())],
                                                  effect=aws_iam.Effect.ALLOW
                                                  )

        role.add_to_principal_policy(kms_sign_policy)

        ec2_iam_instance_profile = aws_iam.CfnInstanceProfile(self, 'InstanceProfile_EC2',
                                                              roles=[role.role_name],
                                                              instance_profile_name="InstanceProfile_EC2")

        network_interface = aws_ec2.CfnInstance.NetworkInterfaceProperty(
            device_index='0',
            associate_public_ip_address=True,
            subnet_id=subnet.subnet_id,
            group_set=[public_sg.security_group_id],
        )

        block_device = aws_ec2.CfnInstance.BlockDeviceMappingProperty(device_name="/dev/xvda",
                                                                      ebs=aws_ec2.CfnInstance.EbsProperty(
                                                                          delete_on_termination=False,
                                                                          volume_size=32,
                                                                          volume_type='gp2',
                                                                          encrypted=True
                                                                      ))

        instance = aws_ec2.CfnInstance(self, 'NitroEC2Instance',
                                       instance_type=aws_ec2.InstanceType("m5a.xlarge").to_string(),
                                       user_data=core.Fn.base64(user_data),
                                       key_name=key_name,
                                       enclave_options=aws_ec2.CfnInstance.EnclaveOptionsProperty(enabled=True),
                                       image_id=amzn_linux.image_id,
                                       network_interfaces=[network_interface],
                                       block_device_mappings=[block_device],
                                       iam_instance_profile=ec2_iam_instance_profile.instance_profile_name
                                       )

        public_dns = 'na - make sure the subnet has public IP assignment turned on'
        if instance.attr_public_dns_name:
            public_dns = instance.attr_public_dns_name

        core.CfnOutput(
            self,
            'EC2PublicDNS',
            value=public_dns,
            description="Public DNS address of the EC2 instance",
            export_name='EC2PublicDNS')
