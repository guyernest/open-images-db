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
  const template = createTemplate();

  test('bucket has correct name pattern and SSE-S3 encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('^open-images-'),
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
  const template = createTemplate();

  test('bucket has DeletionPolicy Delete', () => {
    template.hasResource('AWS::S3::Bucket', {
      DeletionPolicy: 'Delete',
      UpdateReplacePolicy: 'Delete',
    });
  });

  test('stack has Custom::S3AutoDeleteObjects for bucket cleanup', () => {
    template.hasResourceProperties('Custom::S3AutoDeleteObjects', {
      BucketName: Match.anyValue(),
    });
  });
});

describe('Glue', () => {
  const template = createTemplate();

  test('database has name open_images and locationUri with warehouse/', () => {
    template.hasResourceProperties('AWS::Glue::Database', {
      DatabaseInput: {
        Name: 'open_images',
        LocationUri: Match.objectLike({
          'Fn::Join': Match.arrayWith([
            Match.arrayWith([
              Match.stringLikeRegexp('warehouse/'),
            ]),
          ]),
        }),
      },
    });
  });
});

describe('Athena', () => {
  const template = createTemplate();

  test('workgroup has name open-images with 10GB scan limit and engine v3', () => {
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
    template.hasResourceProperties('AWS::Athena::WorkGroup', {
      WorkGroupConfiguration: {
        ResultConfiguration: {
          OutputLocation: Match.objectLike({
            'Fn::Join': Match.arrayWith([
              Match.arrayWith([
                Match.stringLikeRegexp('athena-results/'),
              ]),
            ]),
          }),
          EncryptionConfiguration: {
            EncryptionOption: 'SSE_S3',
          },
        },
      },
    });
  });
});

describe('IAM', () => {
  const template = createTemplate();

  test('policy has Glue permissions scoped to open_images resources', () => {
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
              Match.objectLike({
                'Fn::Join': Match.arrayWith([
                  Match.arrayWith([
                    Match.stringLikeRegexp('database/open_images'),
                  ]),
                ]),
              }),
              Match.objectLike({
                'Fn::Join': Match.arrayWith([
                  Match.arrayWith([
                    Match.stringLikeRegexp('table/open_images/\\*'),
                  ]),
                ]),
              }),
            ]),
          }),
        ]),
      },
    });
  });

  test('policy has S3 permissions on the bucket', () => {
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
  const template = createTemplate();

  test('stack resources are tagged with project=open-images', () => {
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
