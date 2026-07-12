---
name: integracao-membros
description: Instâncias de integração de área de membros, bancos de dados Supabase, e-mails do Brevo, e-mails transacionais de compra e webhooks de checkout.
---

# Skill de Integração da Área de Membros

Esta skill guia o agente no processo de configuração e integração de novas áreas de membros conectadas ao banco de dados Supabase, envios de e-mails transacionais altamente estruturados com Brevo, e tratamento de webhooks de checkout da **GGCheckout**.

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
  - `status` (text): Estado da compra (ex: `approved`, `paid`, `refunded`).

---

## 2. Webhook de Integração (GGCheckout -> Supabase)

Quando uma compra é aprovada, a **GGCheckout** envia um POST HTTP para o endpoint do seu webhook contendo o JSON abaixo. O webhook deve identificar o plano principal e verificar se há **Order Bump** na lista de `products`.

### Payload Recebido da GGCheckout
```json
{
  "event": "pix.paid",
  "createdAt": "2024-01-15T10:30:00Z",
  "customer": {
    "name": "Joao Silva",
    "email": "joao@email.com",
    "document": "12345678901",
    "phone": "5511999999999",
    "ip": "177.45.23.100"
  },
  "payment": {
    "id": "29cce702-5e7e-40da-93b0-aaa19acab32e",
    "method": "pix.paid",
    "paymentMethod": "pix",
    "gateway": "pagouai",
    "status": "paid",
    "amount": 97.00,
    "pixCode": "00020126580014BR.GOV.BCB.PIX..."
  },
  "product": {
    "id": "YbfsgK1Fgm0LzUsFglrn",
    "type": "main",
    "title": "Meu Produto Digital"
  },
  "products": [
    {
      "id": "YbfsgK1Fgm0LzUsFglrn",
      "type": "main",
      "title": "Meu Produto Digital"
    },
    {
      "id": "bump_abc123",
      "type": "orderbump",
      "title": "E-book Bonus",
      "price": 2700
    }
  ],
  "webhook": {
    "id": "webhook_xyz789",
    "businessId": "woYVFMp2mOOJnU0Mrbn8AlhhpmD2",
    "events": ["pix.paid", "pix.generated"]
  },
  "utm_source": "facebook",
  "utm_medium": "cpc",
  "utm_campaign": "minha-campanha",
  "utm_content": null,
  "utm_term": null,
  "customerIp": "177.45.23.100"
}
```

### Lógica de Mapeamento no Webhook
1. **Verificação de Evento**:
   - Responda apenas a eventos que representem sucesso no pagamento (ex: `pix.paid`, `card.paid`, `ticket.paid`, ou quando `payment.status === "paid"`).
2. **Nome e E-mail do Cliente**:
   - Extraídos de `customer.name` e `customer.email`.
3. **Mapeamento de Planos e Order Bump**:
   - O plano principal padrão é baseado no `product.title`.
   - O webhook deve iterar pelo array `products`. Se encontrar algum item onde `type === "orderbump"`, o script de integração deve:
     - Definir uma flag/parâmetro `comprou_orderbump = true`.
     - Guardar o nome do order bump (campo `title`, ex: `"E-book Bonus"`).
     - Alterar a coluna `plano` no Supabase para refletir que o usuário levou o produto com o order bump (ex: `completo_orderbump`).
4. **Inserção no Banco (Supabase)**:
   - Faz um `upsert` baseado no e-mail:
     ```sql
     INSERT INTO usuarios (nome, email, plano, status)
     VALUES ('Joao Silva', 'joao@email.com', 'completo_orderbump', 'paid')
     ON CONFLICT (email)
     DO UPDATE SET plano = EXCLUDED.plano, status = EXCLUDED.status;
     ```
5. **Envio da API do Brevo**:
   - Dispara a requisição POST de e-mail transacional.

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
    "name": "[NOME_DO_SEU_PROJETO_OU_PRODUTO]",
    "email": "[EMAIL_DE_CONTATO_E_SUPORTE]"
  },
  "to": [
    {
      "email": "joao@email.com",
      "name": "Joao Silva"
    }
  ],
  "subject": "Seu acesso ao [NOME_DO_PRODUTO_OU_MATERIAL] foi liberado!",
  "htmlContent": "HTML_CONTENT_AQUI",
  "params": {
    "NOME": "Joao Silva",
    "EMAIL": "joao@email.com",
    "PLANO": "Plano Completo",
    "COMPROU_ORDERBUMP": true,
    "NOME_ORDERBUMP": "E-book Bonus",
    "LINK_MEMBROS": "[LINK_DA_SUA_AREA_DE_MEMBROS]"
  }
}
```

### Template HTML do E-mail Transacional
O template HTML enviado na chave `htmlContent` deve seguir o seguinte layout estruturado:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0; }
        .wrapper { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; }
        .header { text-align: center; margin-bottom: 24px; }
        .important-notice { background-color: [COR_AVISO_IMPORTANTE_FUNDO]; border-left: 4px solid [COR_AVISO_IMPORTANTE_BORDA]; color: [COR_AVISO_IMPORTANTE_TEXTO]; padding: 15px; border-radius: 4px; margin-bottom: 24px; font-size: 0.9rem; }
        .plan-box { background-color: [COR_CAIXA_PLANO_FUNDO]; border: 1px solid [COR_CAIXA_PLANO_BORDA]; border-radius: 6px; padding: 15px; margin-bottom: 24px; }
        .plan-title { font-weight: bold; color: [COR_CAIXA_PLANO_TEXTO]; }
        .bump-card { background: linear-gradient(135deg, [COR_CARD_BUMP_FUNDO_1], [COR_CARD_BUMP_FUNDO_2]); border: 2px dashed [COR_CARD_BUMP_BORDA]; border-radius: 8px; padding: 15px; margin-bottom: 24px; text-align: center; }
        .bump-title { font-weight: bold; color: [COR_CARD_BUMP_TEXTO]; font-size: 0.95rem; }
        .cta-button { display: inline-block; background-color: [COR_BOTAO_CTA_FUNDO]; color: [COR_BOTAO_CTA_TEXTO] !important; font-weight: bold; text-decoration: none; padding: 14px 28px; border-radius: 30px; margin: 15px 0; text-align: center; }
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

        <!-- CARD DO ORDER BUMP CASO TENHA COMPRADO -->
        {% if params.COMPROU_ORDERBUMP %}
        <div class="bump-card">
            <span class="bump-title">🎉 Parabéns pelo Upgrade!</span>
            <p style="margin: 5px 0 0 0; font-size: 0.85rem; color: [COR_CARD_BUMP_TEXTO];">
                Identificamos que você também garantiu o produto adicional: <br>
                <strong>{{params.NOME_ORDERBUMP}}</strong>.<br>
                Ele já foi liberado e está disponível na sua área de membros!
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
