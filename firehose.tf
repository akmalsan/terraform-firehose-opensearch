# Create S3 bucket for data delivery
resource "aws_s3_bucket" "bucket" {
  bucket        = "firehose-test-delivery"
  force_destroy = true

  tags = var.tags
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"
}

# Create role and policies for Firehose
resource "aws_iam_role" "firehose_role" {
  name = "firehose_test_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "firehose_s3" {
  name   = "Firehose_S3"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject"
        ],
        "Resource": [
            "${aws_s3_bucket.bucket.arn}",
            "${aws_s3_bucket.bucket.arn}/*"
        ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:ap-southeast-1:${var.log_recipient_ID}:log-group:${aws_cloudwatch_log_group.firehose_group.name}:log-stream:*"
      ]
    },
    {
            "Effect": "Allow",
            "Action": [
                "es:ESHttpPost",
                "es:ESHttpPut",
                "es:DescribeDomain",    
                "es:DescribeDomains",
                "es:DescribeDomainConfig"
            ],
            "Resource": [
                "${aws_elasticsearch_domain.opensearch.arn}",
                "${aws_elasticsearch_domain.opensearch.arn}/*"
            ]
        },
        {        
            "Effect": "Allow",
            "Action": [
                "es:ESHttpGet"
            ],
            "Resource": [
                "${aws_elasticsearch_domain.opensearch.arn}/_all/_settings",
                "${aws_elasticsearch_domain.opensearch.arn}/_cluster/stats",
                "${aws_elasticsearch_domain.opensearch.arn}/index-name*/_mapping/superstore",
                "${aws_elasticsearch_domain.opensearch.arn}/_nodes",
                "${aws_elasticsearch_domain.opensearch.arn}/_nodes/stats",
                "${aws_elasticsearch_domain.opensearch.arn}/_nodes/*/stats",
                "${aws_elasticsearch_domain.opensearch.arn}/_stats",
                "${aws_elasticsearch_domain.opensearch.arn}/index-name*/_stats"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
              "lambda:InvokeFunction",
              "lambda:GetFunctionConfiguration"
            ],
            "Resource": [
              "${aws_lambda_function.lambda_function.arn}:*"
            ]
        }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "firehose_s3" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_s3.arn
}

# Create CloudWatch Log Group and Stream for Firehose logging
resource "aws_cloudwatch_log_group" "firehose_group" {
  name = "/aws/kinesisfirehose/test-delivery-stream"

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose_stream" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_group.name
}

# Create Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "test_stream" {
  name        = "kinesis-firehose-opensearch-test-stream"
  destination = "elasticsearch"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn
    buffer_interval = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_group.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_stream.name
    }
  }

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.opensearch.arn
    role_arn = aws_iam_role.firehose_role.arn
    index_name = "test"
    buffering_interval = 60
    s3_backup_mode = "AllDocuments"
  }

  tags = var.tags
}

# Create role and policies for cross account data transfer to Firehose
resource "aws_iam_role" "cwl_to_kinesis" {
  name = "CWLtoKinesis"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "logs.ap-southeast-1.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringLike": {
                    "aws:SourceArn": [
                        "arn:aws:logs:ap-southeast-1:${var.log_sender_ID}:*",
                        "arn:aws:logs:ap-southeast-1:${var.log_recipient_ID}:*"
                    ]
                }
            }
        }
    ]
}
EOF
}

resource "aws_iam_policy" "firehose_cwl" {
  name   = "CWLPermissions"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement":[
      {
        "Effect":"Allow",
        "Action":["firehose:*"],
        "Resource":["arn:aws:firehose:ap-southeast-1:${var.log_recipient_ID}:*"]
      }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "firehose_CWL" {
  role       = aws_iam_role.cwl_to_kinesis.name
  policy_arn = aws_iam_policy.firehose_cwl.arn
}

# Create Log Destination
resource "aws_cloudwatch_log_destination" "destination" {
  name       = "test-destination"
  role_arn   = aws_iam_role.cwl_to_kinesis.arn
  target_arn = aws_kinesis_firehose_delivery_stream.test_stream.arn
}

data "aws_iam_policy_document" "destination" {
  statement {
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = [
        var.log_sender_ID,
      ]
    }
    actions = [
      "logs:PutSubscriptionFilter"
    ]
    resources = [
      aws_cloudwatch_log_destination.destination.arn,
    ]
  }
}

resource "aws_cloudwatch_log_destination_policy" "destination" {
  destination_name = aws_cloudwatch_log_destination.destination.name
  access_policy    = data.aws_iam_policy_document.destination.json
}