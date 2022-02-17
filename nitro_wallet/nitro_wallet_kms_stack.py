from aws_cdk import (
    core,
    aws_iam,
    aws_kms
)


class NitroWalletKMSStack(core.Stack):

    def __init__(self, scope: core.Construct, construct_id: str, **kwargs) -> None:
        # todo dev/prod missing
        params = kwargs.pop('params')
        super().__init__(scope, construct_id, **kwargs)

        # aws_instance_role_arn
        aws_instance_role_arn = core.CfnParameter(self, "InstanceRoleARN",
                                                  type="String",
                                                  description="")

        # todo defaults to 0000...for debug mode
        # todo if dev enable debug mode???
        enclave_image_pcr0 = core.CfnParameter(self, "EIPPCR0",
                                               type="String",
                                               description="",
                                               default="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

        lambda_role_arn = core.CfnParameter(self, "LambdaRoleARN",
                                            type="String",
                                            description="")

        nitro_enclave_policy = aws_iam.PolicyDocument(
            statements=[aws_iam.PolicyStatement(
                sid="Enable decrypt from enclave",
                actions=["kms:Decrypt"],
                principals=[aws_iam.ArnPrincipal(aws_instance_role_arn.value_as_string)],
                resources=["*"],
                conditions={
                    "StringEqualsIgnoreCase": {
                        "kms:RecipientAttestation:ImageSha384": enclave_image_pcr0.value_as_string
                    }}
            ),
                aws_iam.PolicyStatement(
                    sid="Enable encrypt from lambda",
                    actions=["kms:*"],
                    principals=[aws_iam.ArnPrincipal(lambda_role_arn.value_as_string)],
                    resources=["*"]
                )
            ]
        )

        encryption_key = aws_kms.Key(self, "EncryptionKey",
                                     policy=nitro_enclave_policy)

        core.CfnOutput(self, "KMS KeyID",
                       value=encryption_key.key_id,
                       description="KMS KeyID")
