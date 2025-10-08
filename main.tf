# Variável para a região da AWS
terraform {
  backend "s3" {
    # Exemplo de valores
    bucket = "spoo-ent9-backend"  # <-- NOME DO SEU "COFRE"
    key    = "gateway-lambda/terraform.tfstate" # <-- ENDEREÇO DO ARQUIVO DENTRO DO COFRE
    region = "us-east-1"
  }
}

variable "aws_region" {
  description = "A região da AWS onde os recursos serão criados."
  type        = string
  default     = "us-east-1"
}

# Variável para o nome do bucket S3, que será passada pelo pipeline
variable "lambda_code_bucket" {
  description = "O nome do bucket S3 que armazena os pacotes de deploy da Lambda."
  type        = string
}

provider "aws" {
  region = var.aws_region
}

# --- 1. AWS Cognito ---

resource "aws_cognito_user_pool" "main" {
  # --- ALTERAÇÃO APLICADA AQUI ---
  # Alterando o nome para forçar a recriação do User Pool
  name = "Sistema PedidosUserPool"

  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }

  alias_attributes = ["email"]
  # Schema Mínimo: Apenas o essencial para o seu fluxo de autenticação
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = false

#    string_attribute_constraints {
#      min_length = 11
#      max_length = 11
#    }
  }


}



resource "aws_cognito_user_pool_client" "main" {
  # --- ALTERAÇÃO APLICADA AQUI ---
  # Alterando o nome para forçar a recriação do App Client
  name                          = "SistemaPedidosAppClient"
  user_pool_id                  = aws_cognito_user_pool.main.id
  generate_secret               = false
  explicit_auth_flows           = ["ADMIN_NO_SRP_AUTH"]
  prevent_user_existence_errors = "ENABLED"

  # Omitindo os atributos para que o Cognito use o padrão.
}

# --- 2. IAM ROLE E POLÍTICA PARA A LAMBDA ---

resource "aws_iam_role" "lambda_auth_role" {
  name = "lambda-auth-cpf-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
    }],
  })
}

resource "aws_iam_policy" "lambda_auth_policy" {
  name   = "lambda-auth-cpf-policy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action   = ["cognito-idp:ListUsers", "cognito-idp:AdminInitiateAuth"],
        Effect   = "Allow",
        Resource = aws_cognito_user_pool.main.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_auth_attach" {
  role       = aws_iam_role.lambda_auth_role.name
  policy_arn = aws_iam_policy.lambda_auth_policy.arn
}

# --- 3. LAMBDA FUNCTION ---

resource "aws_lambda_function" "auth_cpf_lambda" {
  function_name = "auth-by-cpf"
  role          = aws_iam_role.lambda_auth_role.arn
  handler       = "handler.auth_by_cpf"
  runtime       = "python3.9"

  s3_bucket        = var.lambda_code_bucket
  s3_key           = "auth-by-cpf/deployment_package.zip"
  source_code_hash = filebase64sha256("deployment_package.zip")

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      CLIENT_ID    = aws_cognito_user_pool_client.main.id
    }
  }
  timeout = 30
}

# --- 4. API GATEWAY ---

resource "aws_api_gateway_rest_api" "api" {
  name = "SistemaPedidos-API-v2"
}

resource "aws_api_gateway_resource" "auth_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "auth_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.auth_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.auth_resource.id
  http_method             = aws_api_gateway_method.auth_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth_cpf_lambda.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayToInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${aws_api_gateway_method.auth_method.http_method}${aws_api_gateway_resource.auth_resource.path}"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.auth_resource.id,
      aws_api_gateway_method.auth_method.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_lambda_function.auth_cpf_lambda.source_code_hash,
    ]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "v1"
}

# --- OUTPUTS FINAIS ---
output "api_endpoint_url" {
  description = "A URL base para invocar a API de autenticação"
  value       = aws_api_gateway_stage.api_stage.invoke_url
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "user_pool_arn" {
  description = "O ARN do Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}
