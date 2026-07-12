---
name: integracao-membros
description: Instâncias de integração de área de membros, bancos de dados Supabase, e-mails do Brevo, e-mails transacionais de compra e webhooks de checkout.
---

# Skill de Integração da Área de Membros

Esta skill guia o agente no processo de configuração e integração de novas áreas de membros conectadas ao banco de dados Supabase, envios de e-mails transacionais com Brevo, e webhooks de plataformas de checkout (ex: GGCheckout, Kiwify, etc.).

---

## 1. Banco de Dados: Supabase

Para cada projeto, deve ser criada uma tabela de usuários para liberar o acesso via e-mail.

### Estrutura da Tabela `usuarios`
- **Nome da Tabela**: `usuarios`
- **RLS (Row Level Security)**: Habilitado. Adicione uma política de leitura pública (`Select`) anon para permitir que o formulário de login pesquise o e-mail cadastrado.
- **Colunas**:
  - `id` (int8 ou uuid): Chave primária.
  - `created_at` (timestamptz): Padrão `now()`.
  - `nome` (text): Nome completo do comprador.
  - `email` (text): E-mail do comprador (Unique e indexado).
  - `plano` (text): Nome do plano comprado (ex: `basico`, `completo`, `completo_orderbump`).
  - `status` (text): Estado da compra (ex: `approved`, `refunded`, `pending`).

---

## 2. Webhook de Integração (Checkout -> Supabase)

Quando uma compra é realizada, a plataforma de checkout envia um POST para um webhook (geralmente uma API Route ou um fluxo do Make/n8n) para inserir ou atualizar o usuário no Supabase.

### Payload Esperado (Exemplo)
```json
{
  "event": "order.approved",
  "customer": {
    "name": "Nome do Cliente",
    "email": "cliente@email.com"
  },
  "product": {
    "plan_name": "completo"
  },
  "status": "approved"
}
```

### Lógica do Webhook
1. Recebe o evento de compra aprovada.
2. Faz um `upsert` na tabela `usuarios` do Supabase usando o `email` como chave exclusiva:
   - Se o usuário não existe, insere seu `nome`, `email`, `plano` e define `status = 'approved'`.
   - Se o usuário já existe, atualiza o campo `plano` (ex: upgrade para plano completo) e `status`.
3. Dispara a API do Brevo para enviar o e-mail de acesso.

---

## 3. E-mail de Acesso: Brevo (Sendinblue)

Após a inserção no banco de dados, um e-mail transacional é enviado ao cliente usando um template personalizado do Brevo.

### Configuração do Brevo
- **API Endpoint**: `https://api.brevo.com/v3/smtp/email`
- **Headers**:
  - `api-key`: `SUA_CHAVE_API_BREVO`
  - `content-type`: `application/json`

### Template de E-mail Recomendado
```html
<p>Olá, {{params.NOME}}!</p>
<p>Seu acesso ao <strong>Material Ilustrado</strong> foi liberado com sucesso!</p>
<p>Para acessar sua Área de Membros, clique no link abaixo e entre usando o seu e-mail de compra ({{params.EMAIL}}):</p>
<p><a href="{{params.LINK_MEMBROS}}" style="padding: 10px 20px; background-color: #4caf50; color: white; text-decoration: none; border-radius: 5px;">Acessar Área de Membros</a></p>
<p>Qualquer dúvida, responda a este e-mail.</p>
```

---

## 4. Integração do Frontend (Login & Dashboard)

Ao configurar o template de frontend da área de membros:
1. No arquivo `login.html`, configure o objeto `PAGE_CONFIG` com a `supabaseUrl` e a `supabaseKey` (Anon public key) corretas do projeto.
2. O arquivo `login.html` buscará o e-mail digitado na tabela `usuarios` e redirecionará para `dashboard.html` passando os parâmetros via URL:
   `dashboard.html?email=email@email.com&name=Nome&plano=completo`
3. O `dashboard.html` salva a sessão no `localStorage` e exibe apenas os guias correspondentes ao plano do usuário.
