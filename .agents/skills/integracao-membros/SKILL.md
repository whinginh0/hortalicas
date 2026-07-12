---
name: integracao-membros
description: Instâncias de integração de área de membros, bancos de dados Supabase, e-mails do Brevo, e-mails transacionais de compra e webhooks de checkout.
---

# Skill de Integração da Área de Membros

Esta skill guia o agente no processo de configuração e integração de novas áreas de membros conectadas ao banco de dados Supabase, envios de e-mails transacionais altamente estruturados com Brevo, e tratamento de webhooks completos de checkout (com suporte a Order Bumps).

---

## 1. Banco de Dados: Supabase

Para cada projeto, deve ser criada uma tabela de usuários para liberar o acesso via e-mail.

### Estrutura da Tabela `usuarios`
- **Nome da Tabela**: `usuarios`
- **RLS (Row Level Security)**: Habilitado. Adicione uma política de leitura pública (`Select`) anon para permitir que o formulário de login pesquise se o e-mail inserido possui acesso.
- **Colunas**:
  - `id` (int8 ou uuid): Chave primária.
  - `created_at` (timestamptz): Padrão `now()`.
  - `nome` (text): Nome completo do comprador.
  - `email` (text): E-mail do comprador (Unique e indexado em lowercase).
  - `plano` (text): Nome identificador do plano comprado (ex: `basico`, `completo`, `completo_orderbump`).
  - `status` (text): Estado da compra (ex: `approved`, `refunded`, `pending`).

---

## 2. Webhook de Integração (Checkout -> Supabase)

Quando uma compra é aprovada, a plataforma de checkout envia um POST HTTP para o endpoint do webhook. O webhook deve tratar compras normais e compras que contêm **Order Bump**.

### Payload Recebido do Checkout (Exemplo Completo com Order Bump)
```json
{
  "event": "order.approved",
  "status": "approved",
  "purchase": {
    "id": "pay_9875189234",
    "total_amount": 37.90
  },
  "customer": {
    "name": "João da Silva",
    "email": "joaosilva@email.com"
  },
  "product": {
    "id": "prod_1",
    "name": "+150 Pragas e Doenças em Hortaliças Ilustradas",
    "plan": {
      "name": "Plano Completo"
    }
  },
  "order_bumps": [
    {
      "id": "bump_1",
      "name": "100 Defensivos e Produtos para Hortaliças Ilustrados",
      "amount": 10.00
    }
  ]
}
```

### Lógica do Webhook
1. **Identificação do Plano**: 
   - Analisa o `product.plan.name` para identificar se é Básico ou Completo.
   - Verifica se a lista `order_bumps` não está vazia. Se contiver o item do order bump, atualiza o nome do plano para incluir a marcação do order bump (ex: `completo_orderbump`).
2. **Upsert no Banco**:
   - Insere ou atualiza o comprador na tabela `usuarios`:
     ```sql
     INSERT INTO usuarios (nome, email, plano, status)
     VALUES ('João da Silva', 'joaosilva@email.com', 'completo_orderbump', 'approved')
     ON CONFLICT (email)
     DO UPDATE SET plano = EXCLUDED.plano, status = EXCLUDED.status;
     ```
3. **Disparo do E-mail Transacional**:
   - Prepara e envia os parâmetros dinâmicos para a API do Brevo.

---

## 3. Configuração do E-mail de Acesso no Brevo (Sendinblue)

- **API Endpoint**: `https://api.brevo.com/v3/smtp/email`
- **Headers**:
  - `api-key`: `SUA_CHAVE_API_BREVO`
  - `content-type`: `application/json`

### Payload JSON de Envio para a API do Brevo
```json
{
  "sender": {
    "name": "Hortaliças Ilustradas",
    "email": "contato@hortalicas.com"
  },
  "to": [
    {
      "email": "joaosilva@email.com",
      "name": "João da Silva"
    }
  ],
  "subject": "Seu acesso ao Material Ilustrado foi liberado!",
  "htmlContent": "HTML_CONTENT_AQUI",
  "params": {
    "NOME": "João da Silva",
    "EMAIL": "joaosilva@email.com",
    "PLANO": "Plano Completo",
    "COMPROU_ORDERBUMP": true,
    "NOME_ORDERBUMP": "100 Defensivos e Produtos para Hortaliças Ilustrados",
    "LINK_MEMBROS": "https://areademembros.hortalicas.com/login.html"
  }
}
```

### Template HTML do E-mail Transacional
O template HTML enviado na chave `htmlContent` (ou configurado no painel do Brevo) deve seguir estritamente o seguinte layout visual e de conteúdo:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0; }
        .wrapper { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; }
        .header { text-align: center; margin-bottom: 24px; }
        .important-notice { background-color: #ffebee; border-left: 4px solid #d32f2f; color: #c62828; padding: 15px; border-radius: 4px; margin-bottom: 24px; font-size: 0.9rem; }
        .plan-box { background-color: #f1f8e9; border: 1px solid #c8e6c9; border-radius: 6px; padding: 15px; margin-bottom: 24px; }
        .plan-title { font-weight: bold; color: #1b5e20; }
        .bump-card { background: linear-gradient(135deg, #fff9c4, #fff59d); border: 2px dashed #fbc02d; border-radius: 8px; padding: 15px; margin-bottom: 24px; text-align: center; }
        .bump-title { font-weight: bold; color: #f57f17; font-size: 0.95rem; }
        .cta-button { display: inline-block; background-color: #4caf50; color: #ffffff !important; font-weight: bold; text-decoration: none; padding: 14px 28px; border-radius: 30px; margin: 15px 0; text-align: center; }
        .raw-link { font-size: 0.8rem; color: #757575; word-break: break-all; margin-top: 10px; }
        .footer { font-size: 0.75rem; color: #9e9e9e; text-align: center; margin-top: 30px; border-top: 1px solid #e0e0e0; padding-top: 15px; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="header">
            <h2>Acesso Liberado! 🚀</h2>
        </div>

        <!-- AVISO IMPORTANTE -->
        <div class="important-notice">
            <strong>⚠️ AVISO IMPORTANTE:</strong> Se você não encontrar este e-mail na sua Caixa de Entrada principal, verifique a aba de <strong>Promoções, Spam ou Lixo Eletrônico</strong>. Mova este e-mail para a Entrada principal para garantir que continue recebendo atualizações futuras.
        </div>

        <p>Olá, <strong>{{params.NOME}}</strong>!</p>
        <p>Parabéns pela aquisição! Seu acesso ao nosso material foi processado e já está totalmente liberado no sistema.</p>

        <!-- DETALHES DO PLANO -->
        <div class="plan-box">
            <span class="plan-title">Seu Plano Ativo:</span>
            <p style="margin: 5px 0 0 0; font-size: 1.1rem; font-weight: bold;">{{params.PLANO}}</p>
        </div>

        <!-- CARD CONSTITUTIVO CASO TENHA COMPRADO ORDER BUMP -->
        {% if params.COMPROU_ORDERBUMP %}
        <div class="bump-card">
            <span class="bump-title">🎉 Parabéns pelo Upgrade!</span>
            <p style="margin: 5px 0 0 0; font-size: 0.85rem; color: #5d4037;">
                Você também garantiu acesso ao guia extra: <br>
                <strong>{{params.NOME_ORDERBUMP}}</strong>.
            </p>
        </div>
        {% endif %}

        <p>Para entrar no seu painel de estudos, clique no botão verde abaixo e faça login inserindo o seu e-mail cadastrado (<strong>{{params.EMAIL}}</strong>):</p>

        <!-- BOTÃO DE LOGIN -->
        <div style="text-align: center;">
            <a href="{{params.LINK_MEMBROS}}" class="cta-button">ACESSAR ÁREA DE MEMBROS</a>
        </div>

        <!-- LINK COMPLETO / EXTENSO EMBAIXO -->
        <p style="margin-top: 20px; margin-bottom: 5px; font-size: 0.85rem; font-weight: bold; color: #616161;">Caso o botão acima não funcione, copie e cole o endereço abaixo no seu navegador:</p>
        <div class="raw-link">
            {{params.LINK_MEMBROS}}
        </div>

        <div class="footer">
            <p>Ambiente seguro de aprendizagem. Se precisar de ajuda, responda a este e-mail.</p>
        </div>
    </div>
</body>
</html>
```

---

## 4. Integração do Frontend (Login & Dashboard)

Ao configurar o template de frontend da área de membros:
1. No arquivo `login.html`, configure o objeto `PAGE_CONFIG` com a `supabaseUrl` e a `supabaseKey` (Anon public key) corretas do projeto.
2. O arquivo `login.html` buscará o e-mail digitado na tabela `usuarios` e redirecionará para `dashboard.html` passando os parâmetros via URL:
   `dashboard.html?email=email@email.com&name=Nome&plano=completo`
3. O `dashboard.html` salva a sessão no `localStorage` e exibe apenas os guias correspondentes ao plano do usuário.
