import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export class OpenImagesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ---- Tags ----
    const tags: Record<string, string> = {
      project: 'open-images',
      environment: 'production',
      owner: 'data-team',
      'cost-center': 'analytics',
    };
    Object.entries(tags).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));

    // ---- S3 Bucket (INFRA-01, INFRA-04) ----
    const bucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `open-images-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ---- Glue Database (INFRA-02) ----
    new glue.CfnDatabase(this, 'Database', {
      catalogId: this.account,
      databaseInput: {
        name: 'open_images',
        description: 'Open Images V7 annotation data in Iceberg format',
        locationUri: `s3://${bucket.bucketName}/warehouse/`,
      },
    });

    // ---- Athena Workgroup (INFRA-03) ----
    const workgroup = new athena.CfnWorkGroup(this, 'Workgroup', {
      name: 'open-images',
      description: 'Open Images query workgroup',
      state: 'ENABLED',
      recursiveDeleteOption: true,
      workGroupConfiguration: {
        bytesScannedCutoffPerQuery: 10 * 1024 * 1024 * 1024, // 10 GB
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetricsEnabled: true,
        engineVersion: {
          selectedEngineVersion: 'Athena engine version 3',
        },
        resultConfiguration: {
          outputLocation: `s3://${bucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
      },
    });

    // ---- IAM Policy (INFRA-05) ----
    const athenaAccessPolicy = new iam.ManagedPolicy(this, 'AthenaAccessPolicy', {
      managedPolicyName: 'open-images-athena-access',
      statements: [
        // S3 permissions on the bucket and its objects
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:ListBucket',
            's3:GetBucketLocation',
          ],
          resources: [
            bucket.bucketArn,
            `${bucket.bucketArn}/*`,
          ],
        }),
        // Glue catalog permissions scoped to open_images database
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'glue:GetDatabase',
            'glue:GetDatabases',
            'glue:GetTable',
            'glue:GetTables',
            'glue:GetPartition',
            'glue:GetPartitions',
            'glue:CreateTable',
            'glue:UpdateTable',
            'glue:DeleteTable',
            'glue:BatchGetPartition',
          ],
          resources: [
            this.formatArn({ service: 'glue', resource: 'catalog' }),
            this.formatArn({ service: 'glue', resource: 'database', resourceName: 'open_images' }),
            this.formatArn({ service: 'glue', resource: 'table', resourceName: 'open_images/*' }),
          ],
        }),
        // Athena permissions scoped to the workgroup
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'athena:StartQueryExecution',
            'athena:GetQueryExecution',
            'athena:GetQueryResults',
            'athena:StopQueryExecution',
            'athena:GetWorkGroup',
          ],
          resources: [
            this.formatArn({ service: 'athena', resource: 'workgroup', resourceName: workgroup.name }),
          ],
        }),
      ],
    });

    // ---- Outputs ----
    new cdk.CfnOutput(this, 'BucketName', {
      value: bucket.bucketName,
      exportName: 'open-images-bucket-name',
    });
    new cdk.CfnOutput(this, 'BucketArn', {
      value: bucket.bucketArn,
      exportName: 'open-images-bucket-arn',
    });
    new cdk.CfnOutput(this, 'DatabaseName', {
      value: 'open_images',
      exportName: 'open-images-database-name',
    });
    new cdk.CfnOutput(this, 'WorkgroupName', {
      value: 'open-images',
      exportName: 'open-images-workgroup-name',
    });
    new cdk.CfnOutput(this, 'AthenaAccessPolicyArn', {
      value: athenaAccessPolicy.managedPolicyArn,
      exportName: 'open-images-athena-policy-arn',
    });
  }
}
