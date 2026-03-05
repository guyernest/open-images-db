#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { OpenImagesStack } from '../lib/open-images-stack';

const app = new cdk.App();
new OpenImagesStack(app, 'OpenImagesStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
