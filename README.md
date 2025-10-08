Serviço de Autenticação

Este repositório contém o código-fonte de uma função AWS Lambda responsável pela autenticação de usuários do SistemaPedidos. A função é exposta através de um API Gateway e utiliza o AWS Cognito como provedor de identidade.

A autenticação é realizada de forma "passwordless" (sem senha) a partir de um backend, onde o cliente é identificado pelo seu username único (CPF).
Arquitetura

O fluxo de autenticação segue os seguintes passos:

1.	O cliente (frontend) envia uma requisição POST /auth para o API Gateway contendo o username.
2.	O API Gateway aciona a Função Lambda.
3.	A Lambda busca o usuário no AWS Cognito usando o username fornecido.
4.	Se o usuário for encontrado, a Lambda solicita ao Cognito que gere um token JWT.
5.	O token JWT (id_token e refresh_token) é retornado ao cliente.

Pré-requisitos

Para executar este projeto localmente, você precisará ter instalado:

•	AWS CLI
•	AWS SAM CLI
•	Python 3.9+

Configuração

A função Lambda depende de duas variáveis de ambiente para se conectar ao Cognito. Elas devem ser configuradas no arquivo template.yaml:
...
Environment:
  Variables:
    USER_POOL_ID: "ID_DO_SEU_USER_POOL" 
    CLIENT_ID: "ID_DO_SEU_APP_CLIENT"
...

Deploy

O deploy desta função é automatizado via GitHub Actions.

•	Toda alteração enviada para a branch main através de um Pull Request acionará a esteira de CI/CD.
•	A Action irá automaticamente construir o pacote da aplicação (sam build) e enviá-lo para um bucket S3.
•	Uma outra esteira no repositório de infraestrutura (Terraform) é responsável por implantar a nova versão da Lambda, apontando para o artefato no S3.

API
Autenticar Usuário
•	Endpoint: POST /auth
•	Descrição: Autentica um usuário com base no seu username e retorna tokens JWT.
Corpo da Requisição (Request Body):

{
  "username": "12345678911"
}

Resposta de Sucesso (200 OK):
{
  "message": "Autenticação bem-sucedida",
  "id_token": "ey...",
  "refresh_token": "ey..."
}

Respostas de Erro:

•	400 Bad Request: Se o parâmetro username não for enviado ou se o corpo da requisição não for um JSON válido.
•	404 Not Found: Se nenhum usuário for encontrado com o username fornecido.
•	500 Internal Server Error: Para erros inesperados no servidor.
