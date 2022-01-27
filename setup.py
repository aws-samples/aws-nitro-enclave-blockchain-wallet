import setuptools

CDK_VERSION = '1.122.0'
with open("README.md") as fp:
    long_description = fp.read()

setuptools.setup(
    name="nitro_wallet",
    version="0.0.1",

    description="An empty CDK Python app",
    long_description=long_description,
    long_description_content_type="text/markdown",

    author="author",

    package_dir={"": "nitro_wallet"},
    packages=setuptools.find_packages(where="nitro_wallet"),

    install_requires=[
        "aws-cdk.core=={}".format(CDK_VERSION),
        "aws-cdk.aws-ec2=={}".format(CDK_VERSION),
        "aws-cdk.aws-kms=={}".format(CDK_VERSION),
        "aws-cdk.aws-ecr-assets=={}".format(CDK_VERSION),
        "aws-cdk.aws-kms=={}".format(CDK_VERSION),
        "aws-cdk.aws-secretsmanager=={}".format(CDK_VERSION),
        "aws-cdk.aws-lambda=={}".format(CDK_VERSION)
    ],

    python_requires=">=3.6",

    classifiers=[
        "Development Status :: 4 - Beta",

        "Intended Audience :: Developers",

        "License :: OSI Approved :: Apache Software License",

        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",

        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",

        "Typing :: Typed",
    ],
)
