# Create IAM roles and Policies for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name               = "Test_Lambda_Transformation_Role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
    {
        "Action": "sts:AssumeRole",
        "Principal": {
            "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
    }
 ]
}
EOF
}

resource "aws_iam_policy" "lambda_policy" {

  name        = "Lambda_Policy"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create a zip file of the python code
data "archive_file" "python_zip_code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = "${path.module}/python/hello.zip"
}

# Create the lambda function
resource "aws_lambda_function" "lambda_function" {
  filename      = "${path.module}/python/hello.zip"
  function_name = "Test_Transformation_Function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cwl_transform.lambda_handler"
  runtime       = "python3.8"
  depends_on    = [aws_iam_role_policy_attachment.lambda_role_policy]
  timeout       = 300
  description   = "Lambda function to transform data coming from CW Logs"
  tags = {
    "ManagedBy" = "Terraform"
  }
}