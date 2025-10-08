# src/handler.py
import boto3
import os
import json

# Inicializa o cliente do Cognito fora do handler para reutilização de conexão
cognito_client = boto3.client('cognito-idp')

# Pega as variáveis de ambiente definidas no template.yaml
# Isso é mais seguro do que colocar valores fixos no código
USER_POOL_ID = os.environ['USER_POOL_ID']
CLIENT_ID = os.environ['CLIENT_ID']

def auth_by_cpf(event, context):
    """
    Handler principal da Lambda. Recebe um evento do API Gateway,
    procura um usuário pelo CPF no Cognito e retorna um JWT.
    """
    try:
        # O corpo da requisição vem como uma string, então precisamos convertê-lo para um dicionário Python
        body = json.loads(event.get('body', '{}'))
        name = body.get('name')

        # 1. Validação de entrada: Garante que o CPF foi enviado
        if not name:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Parâmetro "name" é obrigatório'})
            }

        # 2. Etapa A: Encontrar o usuário pelo atributo custom:cpf
        # Simula o comando `aws cognito-idp list-users --filter ...`
        response = cognito_client.list_users(
            UserPoolId=USER_POOL_ID,
            Filter=f"name = \"{name}\""
        )

        if not response['Users']:
            return {
                'statusCode': 404,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Cliente não encontrado'})
            }

        # Pega o nome de usuário interno do Cognito, que é necessário para a próxima etapa
        username = response['Users'][0]['name']

        # 3. Etapa B: Iniciar a autenticação e gerar o token (JWT)
        # Simula o comando `aws cognito-idp admin-initiate-auth ...`
        auth_response = cognito_client.admin_initiate_auth(
            UserPoolId=USER_POOL_ID,
            ClientId=CLIENT_ID,
            AuthFlow='ADMIN_NO_SRP_AUTH',
            AuthParameters={
                'USERNAME': username
            }
        )

        # 4. Retornar o token JWT para o cliente
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': 'Autenticação bem-sucedida',
                'id_token': auth_response['AuthenticationResult']['IdToken'],
                'refresh_token': auth_response['AuthenticationResult']['RefreshToken']
            })
        }

    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Corpo da requisição em formato JSON inválido'})
        }
    except Exception as e:
        # Captura de erro genérica para evitar vazar detalhes de implementação
        print(f"Erro inesperado: {e}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Erro interno no servidor'})
        }