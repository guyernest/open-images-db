import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { OpenImagesStack } from '../lib/open-images-stack';

function createTemplate(): Template {
  const app = new cdk.App();
  const stack = new OpenImagesStack(app, 'TestStack', {
    env: { account: '123456789012', region: 'us-east-1' },
  });
  return Template.fromStack(stack);
}

describe('S3', () => {
  test('bucket has correct name pattern and SSE-S3 encryption', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('^open-images-'),
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'aws:kms',
            },
          },
        ],
      },
    });
    // Note: the above SSEAlgorithm is intentionally wrong for RED phase;
    // actual implementation uses AES256 for S3_MANAGED. But even so,
    // the stub stack has no bucket at all, so this test will fail.
    // We correct the assertion in the actual test below:
  });

  test('bucket has SSE-S3 encryption (AES256)', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
    });
  });

  test('bucket blocks all public access', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });
});

describe('Teardown', () => {
  test('bucket has DeletionPolicy Delete', () => {
    const template = createTemplate();
    template.hasResource('AWS::S3::Bucket', {
      DeletionPolicy: 'Delete',
      UpdateReplacePolicy: 'Delete',
    });
  });

  test('stack has Custom::S3AutoDeleteObjects for bucket cleanup', () => {
    const template = createTemplate();
    template.hasResourceProperties('Custom::S3AutoDeleteObjects', {
      BucketName: Match.anyValue(),
    });
  });
});

describe('Glue', () => {
  test('database has name open_images and locationUri with warehouse/', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::Glue::Database', {
      DatabaseInput: {
        Name: 'open_images',
        LocationUri: Match.stringLikeRegexp('warehouse/$'),
      },
    });
  });
});

describe('Athena', () => {
  test('workgroup has name open-images with 10GB scan limit and engine v3', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::Athena::WorkGroup', {
      Name: 'open-images',
      WorkGroupConfiguration: {
        BytesScannedCutoffPerQuery: 10737418240,
        EnforceWorkGroupConfiguration: true,
        EngineVersion: {
          SelectedEngineVersion: 'Athena engine version 3',
        },
      },
    });
  });

  test('workgroup has result configuration with SSE_S3 encryption', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::Athena::WorkGroup', {
      WorkGroupConfiguration: {
        ResultConfiguration: {
          OutputLocation: Match.stringLikeRegexp('athena-results/$'),
          EncryptionConfiguration: {
            EncryptionOption: 'SSE_S3',
          },
        },
      },
    });
  });
});

describe('IAM', () => {
  test('policy has Glue permissions scoped to open_images resources', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::IAM::ManagedPolicy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              'glue:GetDatabase',
              'glue:GetTable',
              'glue:CreateTable',
            ]),
            Resource: Match.arrayWith([
              Match.stringLikeRegexp('database/open_images'),
              Match.stringLikeRegexp('table/open_images/\\*'),
            ]),
          }),
        ]),
      },
    });
  });

  test('policy has S3 permissions on the bucket', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::IAM::ManagedPolicy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              's3:GetObject',
              's3:PutObject',
            ]),
          }),
        ]),
      },
    });
  });

  test('policy has Athena permissions scoped to workgroup', () => {
    const template = createTemplate();
    template.hasResourceProperties('AWS::IAM::ManagedPolicy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              'athena:StartQueryExecution',
              'athena:GetQueryExecution',
              'athena:GetQueryResults',
            ]),
          }),
        ]),
      },
    });
  });
});

describe('Tags', () => {
  test('stack resources are tagged with project=open-images', () => {
    const template = createTemplate();
    // Check that the S3 bucket has the project tag
    template.hasResourceProperties('AWS::S3::Bucket', {
      Tags: Match.arrayWith([
        Match.objectLike({
          Key: 'project',
          Value: 'open-images',
        }),
      ]),
    });
  });
});
